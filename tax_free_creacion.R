# =============================================================================
# TAX FREE — armado del consolidado mensual desde los CSV por tienda
# Reemplaza correr Tax_free_creacion_v2.Rmd a mano antes de los reportes de ventas.
# `crear_tax_free(mes)` lee los CSV de ese mes, escribe el .xlsx y DEVUELVE el
# dataframe ya tipado (fechas y montos parseados) para usarlo sin re-leer.
# =============================================================================

library(tidyverse)
library(openxlsx)

# El nombre de la tienda sale del nombre del archivo y no siempre coincide con el de
# Odoo. Sin esto, "Guemes" no matchea con "Güemes" en el right_join de la tabla de Tax
# free y la tienda queda como una fila suelta, con el importe de Tax free y el resto en
# blanco.
TIENDAS_TAX_FREE <- c("Guemes"     = "Güemes",
                      "San Telmo2" = "San Telmo 2")

# Los CSV de Global Blue vienen a veces en formato argentino ("72.960,00") y a veces en
# estadounidense ("118,930.00"), y cambia de mes a mes sin aviso: leerlos siempre con un
# locale fijo hacía que los importes salieran divididos por mil. Ningún archivo mezcla los
# dos formatos, pero como todos los importes traen exactamente 2 decimales, el último
# separador es SIEMPRE el decimal y los anteriores son de miles. Con eso se parsea bien
# sin depender de con qué locale se exportó el archivo.
parsear_monto <- function(x) {
  original <- trimws(as.character(x))
  limpio   <- gsub("[^0-9.,-]", "", original)
  con_dec  <- grepl("[.,][0-9]{2}$", limpio)
  entero   <- gsub("[.,]", "", ifelse(con_dec, sub("[.,][0-9]{2}$", "", limpio), limpio))
  decimal  <- ifelse(con_dec, sub("^.*[.,]([0-9]{2})$", "\\1", limpio), "00")
  monto    <- suppressWarnings(as.numeric(paste0(entero, ".", decimal)))
  monto[is.na(original) | !grepl("[0-9]", limpio)] <- NA_real_
  monto
}

crear_tax_free <- function(mes,
                           ruta_csv      = "Tax free/Tax free para armar",
                           ruta_xlsx     = "Tax free/Tax free armado",
                           escribir_xlsx = TRUE) {

  mes_arch <- str_replace(mes, "-", "_")
  archivos <- list.files(ruta_csv, pattern = paste0(mes_arch, "\\.csv$"),
                         full.names = TRUE)

  if (length(archivos) == 0)
    stop("Tax free: no hay CSV para ", mes, " en '", ruta_csv,
         "' (busqué *", mes_arch, ".csv). Descargá los CSV del mes antes de correr el reporte.")

  Tax_free <- map(archivos, function(archivo) {

    tienda <- basename(archivo) |>
      str_remove(paste0("[ _]", mes_arch, "\\.csv$"))
    if (tienda %in% names(TIENDAS_TAX_FREE))
      tienda <- unname(TIENDAS_TAX_FREE[tienda])

    read_csv(archivo, show_col_types = FALSE,
             col_types = cols(TotalGrossAmount         = "c",
                              TotalRefundAmount        = "c",
                              TouristCountryNumIsoCode = "c",
                              InvoiceNumber            = "c")) |>
      mutate(Tienda = tienda, .before = 1) |>
      select(-DocumentIdentifier, -DeskID) |>
      mutate(IssuingTime = as.character(IssuingDate)) |>
      mutate(
        IssuingDate       = str_extract(WeekdayName, "[\\d/]+$") |> as.Date(format = "%d/%m/%Y"),
        WeekdayName       = str_extract(WeekdayName, "^[^,]+"),
        TotalGrossAmount  = parsear_monto(TotalGrossAmount),
        TotalRefundAmount = parsear_monto(TotalRefundAmount)
      ) |>
      rename(TouristCountry = TouristCountryNumIsoCode) |>
      select(Tienda, WeekdayName, IssuingDate, IssuedStatus, IssuingTime,
             TFSStatus, TouristCountry, InvoiceNumber,
             TotalGrossAmount, TotalRefundAmount)

  }) |>
    bind_rows()

  if (escribir_xlsx) {
    if (!dir.exists(ruta_xlsx)) dir.create(ruta_xlsx, recursive = TRUE)
    salida <- file.path(ruta_xlsx, paste0("Tax free_", mes, ".xlsx"))
    ok <- tryCatch({ write.xlsx(Tax_free, salida); TRUE },
                   error = function(e) {
                     warning("Tax free: no se pudo escribir ", salida,
                             " (¿abierto en Excel?): ", conditionMessage(e))
                     FALSE
                   })
    if (ok) message("Tax free: escrito ", salida, " (", nrow(Tax_free),
                    " filas, ", length(archivos), " tiendas)")
  }

  Tax_free
}
