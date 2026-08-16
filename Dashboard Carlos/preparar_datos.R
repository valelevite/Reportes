# ==============================================================
#  El Lucero — preparación de datos para el dashboard
#  Lee Datos.xlsx y escribe datos.js (+ el dashboard autocontenido)
# ==============================================================


#PRIMERO ACTUALIZAR ARCHIVO Datos.xlsx CON EL CREADO PARA EL DASHBOARD GENERAL (TABLA PRESUPUESTOS)

library(readxl)
library(dplyr)
library(tidyr)
library(jsonlite)

# --------------------------------------------------------------
# 1. RUTAS
# --------------------------------------------------------------
ruta_datos     <- "Dashboard Carlos/Datos.xlsx"
ruta_plantilla <- "Dashboard Carlos/plantilla_tablero_Carlos.html"
dir.create("publicar", showWarnings = FALSE)
ruta_salida <- "Dashboard Carlos/publicar/Tablero_Carlos.html" 


# --------------------------------------------------------------
# 2. AGRUPACIONES  —  editar acá cuando cambien las zonas
# --------------------------------------------------------------
# Poner una tienda en varias zonas está permitido, pero entonces el
# total de "Zonas" la cuenta dos veces. Lo normal es que cada tienda
# esté en una sola zona.

zonas <- list(
  "Cuero Centro"      = c("Güemes", "Florida", "Recoleta"),
  "Cuero San Telmo"   = c("San Telmo", "French"),
  "Joyería Centro"    = c("El Solar", "Güemes 2"),
  "Joyería San Telmo" = c("San Telmo 2"),
  "AS"                = c("AS San Telmo", "AS Güemes")
)

negocios <- list(
  "Cuero"   = c("Güemes", "Florida", "Recoleta", "San Telmo", "French"),
   "Joyería" = c("El Solar", "Güemes 2", "San Telmo 2"),
  "AS"      = c("AS San Telmo", "AS Güemes")
)

# Tiendas cerradas: se listan igual arriba (por si reabren) pero no
# aparecen en el dashboard mientras no tengan datos.


# --------------------------------------------------------------
# 3. MAPEO DE CONCEPTOS → ÍTEMS DEL DASHBOARD
# --------------------------------------------------------------
# Cada ítem del dashboard es la suma de los conceptos de Datos.xlsx
# que se listan acá. Si aparece un concepto nuevo en el Excel y no
# está en esta lista, el script avisa al final.

mapeo <- list(
  "Venta c/imp" = c("Venta_con_imp"),
  "Alquiler y expensas" = c("Alquiler", "Expensas"),
  "Personal" = c("Sueldo", "Contribuciones", "Incentivo"),
  "Administración" = c("Administración"),
  "Logística" = c("Logística"),
  "Gastos varios" = c("ABL", "AYSA", "Edesur", "Internet", "Mantenimiento",
                      "Fumigación", "Matafuegos", "Alarma", "Servicios",
                      "Multa"),
  "Impuestos" = c("IIBB"),
  "Costo de Mercadería y Packaging" = c("Costo", "Packaging")
)

orden_items <- c(names(mapeo), "Resultado")

# Conceptos del Excel que hay que ignorar (subtotales ya contemplados,
# columnas de control, etc.). No entran en ningún ítem.
ignorar <- c("Venta_sin_imp", "Margen_bruto_valor", "Margen_bruto_porc",
             "Subtotal_gastos", "Subtotal_gastos_financieros",
             "Subtotal_sueldos", "Subtotal_impuestos",
             "Resultado operativo", "Vacaciones", "Liq Final", "SAC",
             "Tarjeta crédito 1 cuota", "Tarjeta crédito 2 cuotas",
             "Tarjeta crédito 3 cuotas", "Tarjeta crédito 6 cuotas",
             "Tarjeta débito", "Mercado Pago", "Otros gastos", "Resultado final")

# Orden en que se muestran las filas
orden_items <- c(names(mapeo), "Resultado")


# --------------------------------------------------------------
# 4. LECTURA
# --------------------------------------------------------------
crudo <- read_excel(ruta_datos)

# Ajustá estos nombres si en el Excel se llaman distinto
crudo <- crudo %>%
  rename(
    anio     = 1,   # año
    mes      = 2,   # número de mes
    tienda   = 3,   # nombre de tienda
    concepto = 4,   # línea del estado de resultados
    valor    = 5    # importe
  ) %>%
  mutate(
    anio   = as.integer(anio),
    mes    = as.integer(mes),
    tienda = trimws(tienda),
    concepto = trimws(concepto),
    valor  = as.numeric(valor)
  ) %>%
  filter(!is.na(valor), !is.na(tienda), tienda != "")


# --------------------------------------------------------------
# 5. IVA  —  la diferencia entre venta con y sin impuestos
# --------------------------------------------------------------
# El dashboard arranca en Venta c/imp, así que el IVA tiene que
# aparecer como egreso para que cierre contra el Resultado.
# Si en tu Excel el IVA ya viene como concepto propio, borrá este
# bloque y agregá ese concepto a "Impuestos" en el mapeo.

# iva <- crudo %>%
#   filter(concepto %in% c("Venta_con_imp", "Venta_sin_imp")) %>%
#   pivot_wider(names_from = concepto, values_from = valor,
#               values_fn = sum, values_fill = 0) %>%
#   transmute(anio, mes, tienda,
#             concepto = "IVA",
#             valor    = Venta_con_imp - Venta_sin_imp)
# 
# crudo <- bind_rows(crudo, iva)
# mapeo[["Impuestos"]] <- c(mapeo[["Impuestos"]], "IVA")
# 

# --------------------------------------------------------------
# 6. ARMADO DE LOS ÍTEMS
# --------------------------------------------------------------
tabla_mapeo <- tibble(
  item     = rep(names(mapeo), lengths(mapeo)),
  concepto = unlist(mapeo, use.names = FALSE)
)

datos <- crudo %>%
  inner_join(tabla_mapeo, by = "concepto") %>%
  group_by(anio, mes, tienda, item) %>%
  summarise(valor = sum(valor), .groups = "drop") %>%
  complete(nesting(anio, mes, tienda), item = names(mapeo), fill = list(valor = 0))

resultado <- datos %>%
  pivot_wider(names_from = item, values_from = valor) %>%
  mutate(item = "Resultado",
         valor = `Venta c/imp` - `Alquiler y expensas` - Personal -
           Administración - Logística - `Gastos varios` -
           Impuestos - `Costo de Mercadería y Packaging`) %>%
  select(anio, mes, tienda, item, valor)

datos <- bind_rows(datos, resultado) %>%
  mutate(item = factor(item, levels = orden_items)) %>%
  arrange(anio, mes, tienda, item) %>%
  mutate(item = as.character(item), valor = round(valor, 2))


# --- Controles ---
if (any(is.na(datos$item)))
  stop("Hay ítems sin nombre. Revisá que orden_items incluya todos los ítems.")

sin_mapear <- setdiff(unique(crudo$concepto), c(tabla_mapeo$concepto, ignorar))
if (length(sin_mapear))
  warning("Conceptos del Excel que no entran en ningún ítem:\n  ",
          paste(sin_mapear, collapse = "\n  "), call. = FALSE)

message("Tiendas con datos: ", paste(sort(unique(datos$tienda)), collapse = ", "))
message("Ítems: ", paste(unique(datos$item), collapse = " · "))


# --------------------------------------------------------------
# 7. SALIDA
# --------------------------------------------------------------
paquete <- list(
  meta  = list(generado = format(Sys.time(), "%Y-%m-%d %H:%M"),
               base_porcentaje = "Venta c/imp"),
  datos = datos
)

json <- toJSON(paquete, auto_unbox = TRUE, dataframe = "rows", digits = 2)

# a) datos.js — para tener el dashboard y los datos como dos archivos
writeLines(paste0("window.DATOS_EL_LUCERO = ", json, ";"), "datos.js", useBytes = TRUE)

# b) dashboard autocontenido — un solo archivo para abrir o mandar por mail
if (file.exists(ruta_plantilla)) {
  plantilla <- readLines(ruta_plantilla, warn = FALSE, encoding = "UTF-8")
  plantilla <- sub("const DATOS_EMBEBIDOS = null;",
                   paste0("const DATOS_EMBEBIDOS = ", json, ";"),
                   plantilla, fixed = TRUE)
  
  dir.create(dirname(ruta_salida), recursive = TRUE, showWarnings = FALSE) 
  
  writeLines(plantilla, ruta_salida, useBytes = TRUE)
  message("Listo: '", ruta_salida, "'")
} else {
  message("No encontré '", ruta_plantilla, "'. Se generó datos.js igual.")
}
