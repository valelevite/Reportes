# =============================================================================
# HORAS TRABAJADAS A PARTIR DE "PREMIOS TIENDAS"
# Reemplaza la carga manual de horas x vendedora y tienda para el reporte Presupuestos.
# =============================================================================

#reviso los message(), 
#pego el .xlsx generado debajo de la última fila de tabla x hora
#cargo Vacaciones y Observaciones si hace falta
#La búsqueda de las vendedoras en cada tienda las toma en el rango: "Horas Personal" y "Total de Horas:".
#si viene mal alguna de esas etiquetas pueden quedar mal asignadas las vendedoras


library(tidyverse)
library(openxlsx)

# ---- 1. Parámetros -----------------------------------------------------------

ruta_sueldos    <- "Reporte_gastos/Sueldos"
archivo_premios <- file.path(ruta_sueldos, "PREMIOS TIENDAS 2026.xlsx")
archivo_horas   <- file.path(ruta_sueldos, "Horas trabajadas Tiendas desde 2025-09.xlsx")

hoja_premios <- "07-2026"   # hoja del mes a procesar (MM-AAAA)
periodo      <- as.Date(paste0(substr(hoja_premios, 4, 7), "-",
                              substr(hoja_premios, 1, 2), "-01"))

# Orden exacto de columnas de la hoja "tabla x hora"
tiendas_cols <- c("Florida", "Güemes", "Güemes 2", "AS Güemes", "Recoleta",
                  "San Telmo", "San Telmo 2", "French", "AS San Telmo", "El Solar")

# Bloque "Facturación ..." de PREMIOS -> columna de la tabla de horas.
# NA = bloque conocido pero sin tienda asociada (no se carga).
mapa_tiendas <- tribble(
  ~bloque,                                    ~tienda,
  "facturacion san telmo (accesories)",       "AS San Telmo",
  "facturacion san telmo 1 (lucero)",         "San Telmo",
  "facturacion san telmo (lucero)",           "San Telmo",
  "facturacion recoleta (lucero)",            "Recoleta",
  "facturacion solar de french (lucero)",     "French",
  "facturacion de florida (lucero)",          "Florida",
  "facturacion san telmo 2 (lucero)",         "San Telmo 2",
  "facturacion guemes (lucero)",              "Güemes",
  "facturacion lu el solar (joyeria)",        "El Solar",
  "facturacion el solar (lucero)",            "El Solar",
  "facturacion as guemes g13 (chalinas)",     "AS Güemes",
  "facturacion lu guemes 2 (joyeria)",        "Güemes 2",
  "facturacion todo bijou",                   NA_character_
)

# ---- 2. Helpers --------------------------------------------------------------

# Normaliza para comparar: sin tildes, sin puntuación, minúsculas,
# tokens ordenados alfabéticamente ("Robbio Lara" == "Lara Robbio").
normalizar_nombre <- function(x) {
  x %>%
    iconv(to = "ASCII//TRANSLIT") %>%
    str_replace_all("[^A-Za-z ]", " ") %>%
    str_to_lower() %>%
    str_split(" +") %>%
    map_chr(~ paste(sort(.x[.x != ""]), collapse = " "))
}

# Normaliza los títulos de bloque (deja tildes fuera, colapsa espacios dobles)
normalizar_bloque <- function(x) {
  x %>%
    iconv(to = "ASCII//TRANSLIT") %>%
    str_to_lower() %>%
    str_replace_all("\u00a0", " ") %>%
    str_squish()
}

# ---- 3. Tablas de referencia (del archivo de horas) --------------------------

horas_hist <- read.xlsx(archivo_horas, sheet = "tabla x hora",
                        detectDates = TRUE, sep.names = " ") %>%
  as_tibble() %>%
  mutate(Periodo = as.Date(Periodo))

# Nombre canónico = el más reciente que figura en la tabla de horas para cada legajo
canonico <- horas_hist %>%
  filter(!is.na(Empleado)) %>%
  arrange(Empleado, Periodo) %>%
  group_by(Empleado) %>%
  summarise(Nombre = last(Nombre), .groups = "drop")

alias <- read.xlsx(archivo_horas, sheet = "alias") %>%
  as_tibble() %>%
  filter(!is.na(Empleado)) %>%
  transmute(clave = normalizar_nombre(Nombre_premios),
            Empleado = as.numeric(Empleado))

# Diccionario final: primero el match automático, después los alias manuales
diccionario <- bind_rows(
  canonico %>% transmute(clave = normalizar_nombre(Nombre), Empleado),
  alias
) %>%
  distinct(clave, .keep_all = TRUE)

# ---- 4. Parseo de la hoja de PREMIOS -----------------------------------------

crudo <- read.xlsx(archivo_premios, sheet = hoja_premios,
                   colNames = FALSE, skipEmptyRows = FALSE, cols = 1:2) %>%
  as_tibble() %>%
  set_names("etiqueta", "horas") %>%
  mutate(
    etiqueta = str_squish(str_replace_all(as.character(etiqueta), "\u00a0", " ")),
    etiqueta = na_if(etiqueta, ""),
    horas    = suppressWarnings(as.numeric(horas)),
    marca    = case_when(
      str_starts(normalizar_bloque(etiqueta), "facturacion")     ~ "inicio_bloque",
      str_starts(normalizar_bloque(etiqueta), "horas personal")  ~ "inicio_horas",
      str_starts(normalizar_bloque(etiqueta), "total de horas")  ~ "fin_horas",
      TRUE                                                       ~ NA_character_
    )
  ) %>%
  mutate(bloque = normalizar_bloque(if_else(marca == "inicio_bloque",
                                            etiqueta, NA_character_))) %>%
  fill(bloque, .direction = "down") %>%
  mutate(en_bloque = cumsum(coalesce(marca == "inicio_horas", FALSE)) >
                     cumsum(coalesce(marca == "fin_horas", FALSE)))

# Control 1: bloques de facturación desconocidos
bloques_desconocidos <- setdiff(na.omit(unique(crudo$bloque)), mapa_tiendas$bloque)
if (length(bloques_desconocidos) > 0) {
  message("\n*** BLOQUES DE FACTURACIÓN NO MAPEADOS (", hoja_premios, ") ***")
  walk(bloques_desconocidos, ~ message("  - ", .x))
  message("  Agregalos a `mapa_tiendas` o quedan fuera de la tabla.\n")
}

detalle <- crudo %>%
  filter(en_bloque, is.na(marca), !is.na(etiqueta), !is.na(horas), horas > 0) %>%
  left_join(mapa_tiendas, by = "bloque") %>%
  filter(!is.na(tienda)) %>%
  transmute(tienda, nombre_premios = etiqueta, horas)

# Control 2: la suma parseada contra la fila "Total de Horas:" de cada bloque
totales_declarados <- crudo %>%
  filter(marca == "fin_horas") %>%
  select(bloque, total_declarado = horas)

descuadres <- crudo %>%
  filter(en_bloque, is.na(marca), !is.na(etiqueta), !is.na(horas), horas > 0) %>%
  group_by(bloque) %>%
  summarise(total_parseado = sum(horas), .groups = "drop") %>%
  left_join(totales_declarados, by = "bloque") %>%
  filter(!is.na(total_declarado), abs(total_parseado - total_declarado) > 0.01)

if (nrow(descuadres) > 0) {
  message("\n*** DESCUADRES CONTRA 'Total de Horas:' (", hoja_premios, ") ***")
  pwalk(descuadres, function(bloque, total_parseado, total_declarado, ...)
    message("  - ", bloque, ": leí ", total_parseado,
            " y el Excel declara ", total_declarado))
  message("")
}

# ---- 5. Asignación del número de empleado ------------------------------------

detalle <- detalle %>%
  mutate(clave = normalizar_nombre(nombre_premios)) %>%
  left_join(diccionario, by = "clave")

# Control 3: vendedoras sin número (nuevas o con el nombre muy distinto)
sin_numero <- detalle %>%
  filter(is.na(Empleado)) %>%
  group_by(nombre_premios, clave) %>%
  summarise(tiendas = paste(unique(tienda), collapse = ", "),
            horas   = sum(horas), .groups = "drop")

if (nrow(sin_numero) > 0) {
  message("\n*** VENDEDORAS SIN NÚMERO DE EMPLEADO (", hoja_premios, ") ***")
  pwalk(sin_numero, function(nombre_premios, clave, tiendas, horas) {
    d   <- utils::adist(clave, diccionario$clave) / pmax(nchar(clave), nchar(diccionario$clave))
    sug <- canonico$Nombre[match(diccionario$Empleado[which.min(d)], canonico$Empleado)]
    message("  - '", nombre_premios, "' (", tiendas, ", ", horas, " hs)",
            if (min(d) < 0.35) paste0("  ->  ¿es '", sug, "'?") else
              "  ->  sin candidato parecido, ¿es nueva?")
  })
  message("  Si es un alias: agregala a la hoja 'alias' del archivo de horas.")
  message("  Si es nueva: asignale legajo y agregala a 'vendedora-tienda' y a 'alias'.\n")
}

# ---- 6. Armado de la tabla final ---------------------------------------------

horas_nuevo <- detalle %>%
  filter(!is.na(Empleado)) %>%
  group_by(Empleado, tienda) %>%
  summarise(horas = sum(horas), .groups = "drop") %>%
  pivot_wider(names_from = tienda, values_from = horas) %>%
  left_join(canonico, by = "Empleado") %>%
  mutate(Periodo = periodo, Vacaciones = NA_real_, Observaciones = NA_character_)

# Garantiza que estén las 10 columnas de tienda aunque el mes no tenga datos
faltantes <- setdiff(tiendas_cols, names(horas_nuevo))
horas_nuevo[faltantes] <- NA_real_

horas_nuevo <- horas_nuevo %>%
  mutate(HORAS = rowSums(across(all_of(c(tiendas_cols, "Vacaciones"))), na.rm = TRUE)) %>%
  select(Periodo, Empleado, Nombre, all_of(tiendas_cols),
         Vacaciones, HORAS, Observaciones) %>%
  arrange(Empleado)

# Control 4: el período ya está cargado en el histórico
periodo_ya_cargado <- periodo %in% horas_hist$Periodo

if (periodo_ya_cargado) {
  message("\n*** El período ", format(periodo, "%Y-%m"), " ya está en 'tabla x hora' (",
          sum(horas_hist$Periodo == periodo), " filas).\n",
          "    El .xlsx del mes se regenera igual, pero para el .rds manda el maestro,\n",
          "    así no se pierden las correcciones que hayas hecho a mano.\n")
}

# Control 5: filas del maestro donde HORAS no coincide con la suma de la fila
inconsistentes <- horas_hist %>%
  mutate(suma = rowSums(across(all_of(c(tiendas_cols, "Vacaciones"))), na.rm = TRUE)) %>%
  filter(abs(HORAS - suma) > 0.01)

if (nrow(inconsistentes) > 0) {
  message("\n*** FILAS DEL MAESTRO CON 'HORAS' DESACTUALIZADO ***")
  pwalk(inconsistentes, function(Periodo, Nombre, HORAS, suma, ...)
    message("  - ", format(Periodo, "%Y-%m"), " ", Nombre,
            ": la celda dice ", HORAS, " y la suma da ", suma))
  message("  (para el .rds uso siempre la suma recalculada, no el valor de la celda)\n")
}

message("Mes ", hoja_premios, ": ", nrow(horas_nuevo), " vendedoras, ",
        sum(horas_nuevo$HORAS), " horas totales.")

# ---- 7. Salidas --------------------------------------------------------------

# (a) Excel con SOLO el mes nuevo, mismo layout que "tabla x hora" (para pegar)
archivo_salida <- file.path(ruta_sueldos,
                            paste0("para_agregar_a_Horas trabajadas ", format(periodo, "%Y-%m"), ".xlsx"))

wb <- createWorkbook()
addWorksheet(wb, "tabla x hora")
writeData(wb, "tabla x hora", horas_nuevo, headerStyle = createStyle(textDecoration = "bold"))
addStyle(wb, "tabla x hora", createStyle(numFmt = "yyyy-mm-dd"),
         rows = 2:(nrow(horas_nuevo) + 1), cols = 1, gridExpand = TRUE)
setColWidths(wb, "tabla x hora", cols = 1:16, widths = c(11, 10, 30, rep(11, 12), 40))
freezePane(wb, "tabla x hora", firstRow = TRUE)
saveWorkbook(wb, archivo_salida, overwrite = TRUE)

# (b) RDS para el Rmd de Presupuestos.
#     Regla: manda el archivo maestro. Si el período ya está pegado en
#     'tabla x hora', se usa esa versión (con tus correcciones a mano);
#     si todavía no está, se le agrega el mes recién parseado.
horas_trabajadas <- (if (periodo_ya_cargado) horas_hist
                     else bind_rows(horas_hist, horas_nuevo)) %>%
  mutate(HORAS = rowSums(across(all_of(c(tiendas_cols, "Vacaciones"))), na.rm = TRUE)) %>%
  arrange(Periodo, Empleado)

saveRDS(horas_trabajadas, file.path(ruta_sueldos, "horas_trabajadas.rds"))

message("Generados:\n  ", archivo_salida,
        "\n  ", file.path(ruta_sueldos, "horas_trabajadas.rds"))
