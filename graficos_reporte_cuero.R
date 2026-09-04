# graficos_reporte_cuero.R ---------------------------------------------------------
#
# Agrega los gráficos nativos de Excel al reporte de ventas de cuero, sobre el .xlsx
# que ya guardó Reporte_ventas_Odoo-CUERO.Rmd. Antes se hacían todos a mano.
#
# Los datos se leen de las propias hojas del archivo (no de los objetos de R), así que
# la función se puede volver a correr sobre cualquier reporte ya generado sin tener que
# rehacer el Rmd. Las tablas se ubican por nombre (wb_get_tables), no por número de
# fila: si cambia el layout del Rmd los gráficos siguen enganchando, salvo los anclajes,
# que están en la sección "posiciones" de más abajo.
#
# Necesita openxlsx2 y mschart (openxlsx no sabe hacer gráficos nativos).

library(openxlsx2)
library(mschart)
library(officer)   # fp_text, para el tamaño de letra de los gráficos

# --- estilo ------------------------------------------------------------------------
COLOR_BARRA      <- "#0F9ED5"  # rubros, familias por rubro, materiales, nacionalidades
COLOR_BARRA_FAM  <- "#0D86B7"  # familias 80%
COLOR_BARRA_PROV <- "#F0986C"  # proveedores externos (hace juego con la tabla naranja)

# El tema que trae mschart usa Arial 20 para el título y 18 para las etiquetas: en un
# gráfico del tamaño de estos queda ilegible. Estos son los cuerpos que venían usándose.
TEMA_GRAFICO <- mschart_theme(
  main_title  = fp_text(font.size = 12, bold = TRUE, font.family = "Calibri"),
  axis_text_x = fp_text(font.size = 10, font.family = "Calibri"),
  axis_text_y = fp_text(font.size = 10, font.family = "Calibri"),
  legend_position = "n")

FUENTE_ETIQUETAS <- fp_text(font.size = 10, font.family = "Calibri")

# Los gráficos por rubro de "Rubros y Familias" arrancan en esta columna y su ancho sale
# de la cantidad de barras: 2*(barras-1) columnas, con tope de 8. Da 2 columnas para un
# gráfico de 2 barras, 4 para uno de 3 y 8 de 5 barras en adelante, que es como los venía
# ajustando Vale a mano para que las barras no queden estiradas.
COL_GRAFICO_RUBRO      <- "E"
ANCHO_MAX_GRAFICO_RUBRO <- 8

# Color para las barras de un color que no esté en la tabla (avisa por consola cuáles)
COLOR_SIN_TABLA <- "BFBFBF"

# --- tabla de colores --------------------------------------------------------------
# En los gráficos de colores cada barra va pintada del color que representa. La tabla
# vive en un Excel y no acá, para poder agregar o corregir un color sin tocar código
# (misma idea que la hoja `alias` de horas). Devuelve NOMBRE -> "RRGGBB".
RUTA_COLORES <- "Reporte_ventas/Colores excel para materiales.xlsx"

normalizar_color <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x <- chartr("ÁÉÍÓÚÜÀÈÌÒÙÂÊÎÔÛÑ", "AEIOUUAEIOUAEIOUN", x)
  gsub("\\s+", " ", x)
}

leer_colores <- function(ruta = RUTA_COLORES) {
  if (!file.exists(ruta)) {
    warning("No encontré ", ruta, ": los gráficos de colores van en un solo color.")
    return(character(0))
  }
  # fila 1 título, fila 2 en blanco, fila 3 encabezado COLOR | ROJO | VERDE | AZUL
  d <- openxlsx2::read_xlsx(ruta, start_row = 3)
  names(d)[1:4] <- c("COLOR", "R", "G", "B")
  d <- d[!is.na(d$COLOR) & !is.na(d$R) & !is.na(d$G) & !is.na(d$B), ]
  setNames(sprintf("%02X%02X%02X", as.integer(d$R), as.integer(d$G), as.integer(d$B)),
           normalizar_color(d$COLOR))
}

# Traduce los nombres de color de un gráfico a hexadecimales y avisa cuáles faltan
colores_de <- function(nombres, tabla) {
  hex <- unname(tabla[normalizar_color(nombres)])
  faltan <- unique(nombres[is.na(hex)])
  if (length(faltan))
    message("Colores sin RGB en '", basename(RUTA_COLORES), "' (van en gris): ",
            paste(faltan, collapse = ", "))
  ifelse(is.na(hex), COLOR_SIN_TABLA, hex)
}

# --- helpers -----------------------------------------------------------------------

# Regla del punto medio para el corte del 80% (la misma que usa el resto del proyecto):
# se incluye una fila mientras el promedio entre el acumulado previo y el propio no pase
# el 80%, así el corte no se pasa de largo. Devuelve cuántas filas entran.
corte_80 <- function(participacion, umbral = 0.80) {
  p <- ifelse(is.na(participacion), 0, participacion)
  acum <- cumsum(p)
  previo <- c(0, head(acum, -1))
  max(sum((previo + acum) / 2 < umbral), 1)
}

# Recorta un wb_data a un subconjunto de filas de la hoja manteniendo el encabezado,
# para que las referencias del gráfico apunten sólo a esas filas.
wb_slice <- function(d, filas) {
  dm <- attr(d, "dims")
  sh <- attr(d, "sheet")
  idx <- match(as.character(filas), rownames(d))
  idx <- idx[!is.na(idx)]
  out <- d[idx, , drop = FALSE]
  attr(out, "dims")  <- dm[c(1, idx + 1), , drop = FALSE]
  attr(out, "sheet") <- sh
  class(out) <- c("wb_data", "data.frame")
  out
}

# Devuelve el rango ("A3:D12") de una tabla de Excel por nombre. Los nombres quedan en
# minúscula al guardarse.
ref_tabla <- function(wb, hoja, nombre) {
  tablas <- wb_get_tables(wb, sheet = hoja)
  ref <- tablas$tab_ref[tolower(tablas$tab_name) == tolower(nombre)]
  if (length(ref) != 1)
    stop("No encontré la tabla '", nombre, "' en la hoja '", hoja, "'.")
  ref
}

# Primera y última fila de un rango tipo "A3:D12"
filas_de_ref <- function(ref) as.integer(gsub("[^0-9]", "", strsplit(ref, ":")[[1]]))

# Lee una tabla entera como wb_data (encabezado + datos)
datos_tabla <- function(wb, hoja, nombre) {
  wb_data(wb, sheet = hoja, dims = ref_tabla(wb, hoja, nombre))
}

# Gráfico de columnas verticales con etiquetas en % (el formato de todos los de rubros)
grafico_columnas <- function(dat, titulo, color = COLOR_BARRA) {
  x <- names(dat)[1]
  g <- ms_barchart(data = dat, x = x, y = "Participación")
  g <- chart_settings(g, dir = "vertical", grouping = "clustered",
                      gap_width = 219, overlap = -27)
  g <- chart_data_fill(g, values = c("Participación" = color))
  g <- chart_data_labels(g, show_val = TRUE, num_fmt = "0.0%", position = "outEnd")
  g <- chart_labels_text(g, values = FUENTE_ETIQUETAS)
  g <- chart_ax_y(g, display = FALSE)
  g <- chart_labels(g, title = titulo)
  set_theme(g, TEMA_GRAFICO)
}

# Gráfico de barras horizontales, de mayor a menor de arriba hacia abajo
grafico_barras <- function(dat, titulo, color = COLOR_BARRA, gap_width = 100) {
  x <- names(dat)[1]
  g <- ms_barchart(data = dat, x = x, y = "Participación")
  g <- chart_settings(g, dir = "horizontal", grouping = "clustered",
                      gap_width = gap_width)
  g <- chart_data_fill(g, values = c("Participación" = color))
  g <- chart_data_labels(g, show_val = TRUE, num_fmt = "0.0%", position = "outEnd")
  g <- chart_labels_text(g, values = FUENTE_ETIQUETAS)
  g <- chart_ax_x(g, orientation = "maxMin")   # el más grande arriba
  g <- chart_ax_y(g, display = FALSE)          # el valor ya está en la etiqueta
  g <- chart_labels(g, title = titulo)
  set_theme(g, TEMA_GRAFICO)
}

# Todos los cortes de Pareto son "el acumulado más cercano al 80%", así que el título
# siempre dice 80% aunque el acumulado real caiga en 70 y pico o en 80 y pico. En algún
# FINAL viejo figuraba "(70% de la venta)" por eso mismo, pero el criterio es el 80%.
titulo_pareto <- function(nombre) {
  sprintf("%s (80%% de la venta)", nombre)
}

# --- función principal -------------------------------------------------------------
#
# ruta                : el .xlsx que generó el Rmd (se sobrescribe con los gráficos)
# part_proveedores    : participación de los proveedores externos sobre la venta total,
#                       en porcentaje (PARTICIPACION_PROVEEDORES_EXTERNOS del Rmd). Sólo
#                       se usa para el título del gráfico; si es NULL se omite.
# fila_tabla_familia  : fila del encabezado de tabla_rubro_familia en "Rubros y Familias"
#
agregar_graficos_cuero <- function(ruta,
                                   part_proveedores = NULL,
                                   fila_tabla_familia = 30) {

  wb <- wb_load(ruta)

  ## 1. Venta por rubros ------------------------------------------------------------
  rubros <- datos_tabla(wb, "Rubros y Familias", "tabla_venta_rubro")
  filas_rubro <- rownames(rubros)[!rubros[[1]] %in% c("TOTAL", "DESCUENTO")]
  wb <- wb_add_mschart(wb, sheet = "Rubros y Familias", dims = "G3:L13",
                       graph = grafico_columnas(wb_slice(rubros, filas_rubro),
                                                "VENTA POR RUBROS"))

  ## 2. Familias 80% de la venta ----------------------------------------------------
  familias <- datos_tabla(wb, "AUX", "familia_aux")
  n <- corte_80(familias$Participación)
  familias_80 <- wb_slice(familias, rownames(familias)[seq_len(n)])
  wb <- wb_add_mschart(wb, sheet = "Rubros y Familias", dims = "A15:L27",
                       graph = grafico_columnas(
                         familias_80,
                         titulo_pareto("FAMILIAS"),
                         COLOR_BARRA_FAM))

  ## 3. Un gráfico por rubro con sus familias 80% -----------------------------------
  # Las filas de rubro son las que no están indentadas; las familias van con un espacio
  # adelante. El gráfico se ancla al costado del bloque de su propio rubro.
  ref_fam <- ref_tabla(wb, "Rubros y Familias", "tabla_rubro_familia")
  fam <- wb_data(wb, sheet = "Rubros y Familias", dims = ref_fam)
  etiqueta <- fam[[1]]
  es_rubro <- !startsWith(etiqueta, " ") & etiqueta != "TOTAL"
  filas_hoja <- as.integer(rownames(fam))

  for (i in which(es_rubro)) {
    # familias del rubro: desde la fila siguiente hasta el próximo rubro
    siguiente <- which(es_rubro & seq_along(es_rubro) > i)
    fin <- if (length(siguiente)) min(siguiente) - 1 else length(es_rubro)
    if (fin <= i) next                                  # rubro sin familias
    idx_fam <- (i + 1):fin
    n <- corte_80(fam$Participación[idx_fam])
    if (n < 2) next                                     # con una sola barra no aporta
    idx_80 <- idx_fam[seq_len(n)]

    # Alto: el del bloque, con un mínimo de 6 filas para que no quede aplastado, pero
    # sin pasar la fila del rubro siguiente (si no, los gráficos se pisan entre sí).
    fila_rubro <- filas_hoja[i]
    fila_siguiente <- if (length(siguiente)) filas_hoja[min(siguiente)]
                      else max(filas_hoja) + 2
    alto <- min(max(length(idx_fam), 6), fila_siguiente - fila_rubro - 1)

    # Ancho: proporcional a la cantidad de barras. Con el ancho fijo de 8 columnas, un
    # rubro con 2 o 3 familias quedaba con las barras estiradísimas.
    ancho <- min(ANCHO_MAX_GRAFICO_RUBRO, max(2, 2 * (length(idx_80) - 1)))
    col_fin <- int2col(col2int(COL_GRAFICO_RUBRO) + ancho - 1)

    wb <- wb_add_mschart(
      wb, sheet = "Rubros y Familias",
      dims = paste0(COL_GRAFICO_RUBRO, fila_rubro, ":", col_fin, fila_rubro + alto),
      graph = grafico_columnas(
        wb_slice(fam, filas_hoja[idx_80]),
        titulo_pareto(etiqueta[i])))
  }

  ## 3b. Minigráficos de los últimos 13 meses ---------------------------------------
  wb <- agregar_minigraficos(wb)

  ## 4. Materiales y colores --------------------------------------------------------
  # Las tablas TOP_80 ya vienen cortadas; se saca la fila "Otros", que en el gráfico
  # taparía a las demás.
  tabla_colores <- leer_colores()

  materiales <- list(
    list(tabla = "marro_grande_materiales_top_80", dims = "A5:E19",
         titulo = "MARRO GRANDE - MATERIALES", pintar = FALSE),
    list(tabla = "marro_grande_colores_top_80",    dims = "A20:E40",
         titulo = "MARRO GRANDE - COLORES",    pintar = TRUE),
    list(tabla = "marro_chica_materiales_top_80",  dims = "K6:O19",
         titulo = "MARRO CHICA - MATERIALES",  pintar = FALSE),
    list(tabla = "marro_chica_colores_top_80",     dims = "K21:O36",
         titulo = "MARRO CHICA - COLORES",     pintar = TRUE))

  for (m in materiales) {
    d <- datos_tabla(wb, "AUX", m$tabla)
    sin_otros <- rownames(d)[d[[1]] != "Otros"]
    d <- wb_slice(d, sin_otros)
    wb <- wb_add_mschart(wb, sheet = "Materiales y colores", dims = m$dims,
                         graph = grafico_barras(
                           d, paste0(m$titulo, " (80% de la venta)")))
    # En los de colores cada barra va del color que representa
    if (m$pintar) wb <- pintar_puntos(wb, colores_de(d[[1]], tabla_colores))
  }

  ## 5. Proveedores externos --------------------------------------------------------
  prov <- datos_tabla(wb, "Proveedores externos", "proveedor_externo_total")
  prov <- wb_slice(prov, rownames(prov)[prov[[1]] != "TOTAL"])
  titulo_prov <- if (is.null(part_proveedores)) {
    "PROVEEDORES EXTERNOS"
  } else {
    sprintf("PROVEEDORES EXTERNOS (%s%% de la venta)",
            gsub("\\.", ",", format(part_proveedores, trim = TRUE)))
  }
  wb <- wb_add_mschart(wb, sheet = "Proveedores externos", dims = "A3:G19",
                       graph = grafico_barras(prov, titulo_prov,
                                              COLOR_BARRA_PROV, gap_width = 182))

  ## 6. Nacionalidades --------------------------------------------------------------
  # La tabla del AUX ya viene filtrada al 80% acumulado
  nac <- datos_tabla(wb, "AUX", "nacionalidad_para_grafico")
  wb <- wb_add_mschart(wb, sheet = "Nacionalidades", dims = "A2:M15",
                       graph = grafico_columnas(
                         nac, titulo_pareto("NACIONALIDADES")))

  ## 7. Grabados por tienda (anillo) ------------------------------------------------
  grab <- datos_tabla(wb, "AUX", "grabados_tiendas")
  anillo <- ms_piechart(data = grab, x = names(grab)[1], y = "Participación")
  anillo <- chart_data_labels(anillo, show_val = TRUE, show_cat_name = TRUE,
                              num_fmt = "0.0%")
  anillo <- chart_labels_text(anillo, values = FUENTE_ETIQUETAS)
  anillo <- set_theme(anillo, TEMA_GRAFICO)
  # Chico y en H: al costado de la tabla (que llega hasta G) pero sin encimarla
  wb <- wb_add_mschart(wb, sheet = "Otros", dims = "H4:J10", graph = anillo)

  # mschart no tiene gráfico de anillo, así que se convierte la torta a anillo en el XML
  wb <- convertir_a_anillo(wb)
  wb <- limpiar_external_data(wb)

  wb_save(wb, ruta, overwrite = TRUE)
  message("Gráficos agregados a ", basename(ruta))
  invisible(ruta)
}

# mschart sólo genera torta (pieChart). El anillo (doughnutChart) es el mismo elemento
# más un <c:holeSize>, así que se parchea el XML del último gráfico agregado.
convertir_a_anillo <- function(wb) {
  i <- length(wb$charts$chart)
  xml <- wb$charts$chart[i]
  if (!grepl("pieChart", xml, fixed = TRUE)) return(wb)
  xml <- gsub("<c:pieChart>", "<c:doughnutChart>", xml, fixed = TRUE)
  xml <- gsub("</c:pieChart>", "<c:holeSize val=\"75\"/></c:doughnutChart>",
              xml, fixed = TRUE)
  wb$charts$chart[i] <- xml
  wb
}

# Minigráficos (sparklines de Excel) en la columna "Participación en los últimos 13
# meses" de la tabla de rubros. Cada uno lee la serie de su rubro en la TABLA HISTÓRICA
# DE PARTICIPACIÓN POR RUBRO del AUX, que viene ordenada por rubro y después por año/mes,
# así que las 13 filas de cada rubro quedan seguidas.
agregar_minigraficos <- function(wb, hoja = "Rubros y Familias") {

  tablas_aux <- wb_get_tables(wb, sheet = "AUX")
  if (!"tabla_historica_rubro" %in% tablas_aux$tab_name) {
    warning("No está tabla_historica_rubro en AUX: no puse los minigráficos.")
    return(wb)
  }
  ref_hist <- tablas_aux$tab_ref[tablas_aux$tab_name == "tabla_historica_rubro"]
  hist <- wb_data(wb, sheet = "AUX", dims = ref_hist)
  filas_hist <- as.integer(rownames(hist))

  # letra de la columna Participación dentro del rango de la tabla
  col_part <- int2col(col2int(gsub("[0-9:].*", "", ref_hist)) +
                        which(names(hist) == "Participación") - 1)

  rubros <- datos_tabla(wb, hoja, "tabla_venta_rubro")
  rubros <- rubros[!rubros[[1]] %in% c("TOTAL", "DESCUENTO"), ]

  minis <- character(0)
  sin_historico <- character(0)
  for (i in seq_len(nrow(rubros))) {
    rubro <- rubros[[1]][i]
    f <- filas_hist[hist$RUBRO == rubro]
    if (!length(f)) { sin_historico <- c(sin_historico, rubro); next }
    if (length(f) != max(f) - min(f) + 1) {
      warning("Las filas de ", rubro, " no están seguidas en la tabla histórica; ",
              "el minigráfico saldría mal. Lo salteo.")
      next
    }
    minis <- c(minis, create_sparklines(
      "AUX",
      dims  = sprintf("%s%d:%s%d", col_part, min(f), col_part, max(f)),
      sqref = paste0("E", rownames(rubros)[i]),
      color_series = wb_color(hex = paste0("FF", sub("^#", "", COLOR_BARRA)))))
  }

  if (length(sin_historico))
    message("Rubros sin datos en la tabla histórica (quedan sin minigráfico): ",
            paste(sin_historico, collapse = ", "))
  if (!length(minis)) return(wb)

  wb_add_sparklines(wb, sheet = hoja, sparklines = minis)
}

# mschart pinta toda la serie de un solo color. Para que cada barra vaya del color que
# representa hay que agregarle los <c:dPt> al XML del último gráfico insertado. En el
# esquema de OOXML los dPt van entre <c:invertIfNegative> y <c:dLbls> de la serie.
ANCLA_DPT <- '<c:invertIfNegative val="0"/>'

pintar_puntos <- function(wb, colores) {
  i <- length(wb$charts$chart)
  if (!grepl(ANCLA_DPT, wb$charts$chart[i], fixed = TRUE)) {
    warning("No pude pintar las barras por color: cambió el XML que genera mschart.")
    return(wb)
  }
  dpt <- paste0(
    '<c:dPt><c:idx val="', seq_along(colores) - 1, '"/>',
    '<c:invertIfNegative val="0"/><c:bubble3D val="0"/><c:spPr>',
    '<a:solidFill><a:srgbClr val="', colores, '"/></a:solidFill>',
    '<a:ln><a:solidFill><a:srgbClr val="', colores, '"/></a:solidFill></a:ln>',
    '</c:spPr></c:dPt>', collapse = "")
  wb$charts$chart[i] <- sub(ANCLA_DPT, paste0(ANCLA_DPT, dpt),
                            wb$charts$chart[i], fixed = TRUE)
  wb
}

# mschart escribe <c:externalData r:id="rId1"/> porque nació para gráficos de Word y
# PowerPoint, donde los datos van en un libro embebido. Acá los datos están en la propia
# hoja, así que esa relación queda apuntando a la nada y Excel abre el archivo pidiendo
# repararlo. Se saca de todos los gráficos.
limpiar_external_data <- function(wb) {
  wb$charts$chart <- gsub("<c:externalData[^>]*>.*?</c:externalData>", "",
                          wb$charts$chart)
  wb$charts$chart <- gsub("<c:externalData[^>]*/>", "", wb$charts$chart)
  wb
}
