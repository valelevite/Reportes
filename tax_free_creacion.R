# =============================================================================
# TAX FREE — armado del consolidado mensual desde los CSV por tienda
# Reemplaza correr Tax_free_creacion_v2.Rmd a mano antes de los reportes de ventas.
# `crear_tax_free(mes)` lee los CSV de ese mes, escribe el .xlsx y DEVUELVE el
# dataframe ya tipado (fechas y montos parseados) para usarlo sin re-leer.
# =============================================================================

library(tidyverse)
library(openxlsx)

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
        TotalGrossAmount  = parse_number(TotalGrossAmount,  locale = locale(decimal_mark = ",", grouping_mark = ".")),
        TotalRefundAmount = parse_number(TotalRefundAmount, locale = locale(decimal_mark = ",", grouping_mark = "."))
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
