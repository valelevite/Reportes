# ==============================================================
#  El Lucero — preparación de datos para el dashboard
#  Lee Datos.xlsx y escribe datos.js (+ el dashboard autocontenido)
# ==============================================================

library(readxl)
library(dplyr)
library(tidyr)
library(jsonlite)

# --------------------------------------------------------------
# 1. RUTAS
# --------------------------------------------------------------
ruta_datos     <- "Datos.xlsx"
ruta_plantilla <- "dashboard.html"                      # el archivo que te pasé
dir.create("publicar", showWarnings = FALSE)
ruta_salida <- "publicar/index.html"            # el archivo final, listo para abrir


# --------------------------------------------------------------
# 2. AGRUPACIONES  —  editar acá cuando cambien las zonas
# --------------------------------------------------------------
# Poner una tienda en varias zonas está permitido, pero entonces el
# total de "Zonas" la cuenta dos veces. Lo normal es que cada tienda
# esté en una sola zona.

zonas <- list(
  "Lucero Zona Centro"        = c("Florida", "Recoleta"),
  "Lucero Zona San Telmo"     = c("San Telmo", "French"),
  "Lucero Güemes+San Telmo 2" = c("Güemes", "San Telmo 2"),
  "Lucero Joyería"            = c("Güemes 2", "El Solar"),
  "AS"                        = c("AS San Telmo", "AS Güemes")
)

negocios <- list(
  "Cuero"   = c("Florida", "Recoleta", "San Telmo", "French", "Güemes", "San Telmo 2"),
  "Joyería" = c("Güemes 2", "El Solar"),
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

  "Personal" = c("Sueldo", "Contribuciones", "Incentivo",
                 "Vacaciones", "Liq Final", "SAC"),

  "Administración (10%)" = c("Administración"),

  "Logística (5%)" = c("Logística"),

  # Todo lo que no tiene línea propia, incluidos los gastos financieros
  # (tarjetas y Mercado Pago). Si preferís que los financieros vayan
  # aparte, sacalos de acá y agregalos como un ítem nuevo.
  "Gastos Varios" = c("ABL", "AYSA", "Edesur", "Internet", "Mantenimiento",
                      "Fumigación", "Matafuegos", "Alarma", "Servicios",
                      "Multa", "Otros gastos",
                      "Tarjeta crédito 1 cuota", "Tarjeta crédito 2 cuotas",
                      "Tarjeta crédito 3 cuotas", "Tarjeta crédito 6 cuotas",
                      "Tarjeta débito", "Mercado Pago"),

  "Impuestos" = c("IIBB"),   # el IVA se agrega abajo, ver punto 5

  "Costo de Mercadería y Packaging" = c("Costo", "Packaging"),

  "Resultado" = c("Resultado final")
)

# Conceptos del Excel que hay que ignorar (subtotales ya contemplados,
# columnas de control, etc.). No entran en ningún ítem.
ignorar <- c("Venta_sin_imp", "Margen_bruto_valor", "Margen_bruto_porc",
             "Subtotal_gastos", "Subtotal_gastos_financieros",
             "Subtotal_sueldos", "Subtotal_impuestos",
             "Resultado operativo")

# Orden en que se muestran las filas
orden_items <- names(mapeo)


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

iva <- crudo %>%
  filter(concepto %in% c("Venta_con_imp", "Venta_sin_imp")) %>%
  pivot_wider(names_from = concepto, values_from = valor,
              values_fn = sum, values_fill = 0) %>%
  transmute(anio, mes, tienda,
            concepto = "IVA",
            valor    = Venta_con_imp - Venta_sin_imp)

crudo <- bind_rows(crudo, iva)
mapeo[["Impuestos"]] <- c(mapeo[["Impuestos"]], "IVA")


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
  complete(nesting(anio, mes, tienda), item = orden_items, fill = list(valor = 0)) %>%
  mutate(item = factor(item, levels = orden_items)) %>%
  arrange(anio, mes, tienda, item) %>%
  mutate(item = as.character(item),
         valor = round(valor, 2))


# --------------------------------------------------------------
# 7. CONTROLES
# --------------------------------------------------------------
sin_mapear <- setdiff(unique(crudo$concepto), c(tabla_mapeo$concepto, ignorar))
if (length(sin_mapear)) {
  warning("Conceptos del Excel que no entran en ningún ítem:\n  ",
          paste(sin_mapear, collapse = "\n  "), call. = FALSE)
}

# ¿Venta − todos los egresos coincide con el Resultado que trae el Excel?
control <- datos %>%
  pivot_wider(names_from = item, values_from = valor) %>%
  mutate(
    egresos    = rowSums(across(all_of(setdiff(orden_items,
                     c("Venta c/imp", "Resultado"))))),
    calculado  = `Venta c/imp` - egresos,
    diferencia = round(Resultado - calculado, 2)
  ) %>%
  filter(abs(diferencia) > 1)

if (nrow(control)) {
  message("⚠ El resultado del Excel no cierra contra la suma de ítems en ",
          nrow(control), " combinaciones tienda/mes:")
  print(control %>% select(anio, mes, tienda, Resultado, calculado, diferencia))
} else {
  message("✔ Todo cierra: venta − egresos = resultado en todas las tiendas y meses.")
}

message("Tiendas con datos: ", paste(sort(unique(datos$tienda)), collapse = ", "))


# --------------------------------------------------------------
# 8. SALIDA
# --------------------------------------------------------------
paquete <- list(
  meta   = list(generado = format(Sys.time(), "%Y-%m-%d %H:%M"),
                base_porcentaje = "Venta c/imp"),
  config = list(zonas = zonas, negocios = negocios),
  datos  = datos
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
  writeLines(plantilla, ruta_salida, useBytes = TRUE)
  message("Listo: '", ruta_salida, "'")
} else {
  message("No encontré '", ruta_plantilla, "'. Se generó datos.js igual.")
}
