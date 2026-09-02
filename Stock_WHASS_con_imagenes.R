# ------------------------------------------------------------------
# Stock de WHASS/Stock (AS San Telmo) con imagen de producto
# Toma automáticamente el archivo Stock_AAAAMMDD.xlsx más reciente
# de la carpeta Stock y genera un Excel con una columna IMAGEN.
# ------------------------------------------------------------------

library(openxlsx)
library(dplyr)
library(stringr)
library(tibble)

UBICACION   <- "WHASS/Stock"
CARPETA_IMG <- "imagenes"

# --- 1. Archivo de stock más reciente -----------------------------
archivos_stock <- list.files("Stock", pattern = "^Stock_\\d{8}\\.xlsx$",
                             full.names = TRUE)
fechas_stock   <- as.Date(str_extract(basename(archivos_stock), "\\d{8}"),
                          format = "%Y%m%d")
archivo_stock  <- archivos_stock[which.max(fechas_stock)]
fecha_stock    <- format(max(fechas_stock), "%Y%m%d")

message("Archivo de stock usado: ", archivo_stock)

stock <- read.xlsx(archivo_stock)
names(stock) <- c("Ubicación", "Producto", "Codigo", "Cantidad")

stock_ass <- stock %>%
  filter(Ubicación == UBICACION) %>%
  mutate(Codigo = as.character(Codigo)) %>%
  arrange(desc(Cantidad))

message("Filas en ", UBICACION, ": ", nrow(stock_ass))

# --- 2. Busco la imagen de cada producto y me quedo solo con los que tienen ---
img_files <- list.files(CARPETA_IMG, full.names = TRUE,
                        pattern = "\\.(jpg|jpeg|png|webp)$", ignore.case = TRUE)
img_lookup <- tibble(
  filepath = img_files,
  ref      = str_extract(basename(img_files), "^\\d+")
) %>% filter(!is.na(ref))

buscar_imagen <- function(codigo) {
  if (is.na(codigo) || codigo == "") return(NA_character_)
  idx <- which(img_lookup$ref == codigo)
  # fallback: primeros 6 caracteres (por si el código es EAN/barcode largo)
  if (length(idx) == 0 && nchar(codigo) >= 6)
    idx <- which(img_lookup$ref == substr(codigo, 1, 6))
  if (length(idx) == 0) return(NA_character_)
  img_lookup$filepath[idx[1]]
}

stock_ass$img_path <- vapply(stock_ass$Codigo, buscar_imagen, character(1))

REVISAR_sin_imagen <- unique(stock_ass$Codigo[is.na(stock_ass$img_path)])
message("Productos sin imagen (excluidos): ", length(REVISAR_sin_imagen),
        " de ", nrow(stock_ass))

stock_ass <- stock_ass %>% filter(!is.na(img_path))
message("Productos con imagen (van al Excel): ", nrow(stock_ass))

img_paths <- stock_ass$img_path
stock_ass <- stock_ass %>% select(-img_path)

# --- 3. Workbook ---------------------------------------------------
wb <- createWorkbook()
addWorksheet(wb, "Stock")

st_header <- createStyle(fontName = "Arial", fontSize = 10, textDecoration = "bold",
                         fgFill = "#005363", fontColour = "white",
                         halign = "center", valign = "center",
                         border = "TopBottomLeftRight", wrapText = TRUE)
st_data   <- createStyle(fontName = "Arial", fontSize = 10, valign = "center",
                         border = "TopBottomLeftRight")
st_num    <- createStyle(fontName = "Arial", fontSize = 10, valign = "center",
                         numFmt = "#,##0", halign = "center",
                         border = "TopBottomLeftRight")

writeData(wb, "Stock", stock_ass, startRow = 1, startCol = 1)

n <- nrow(stock_ass)
addStyle(wb, "Stock", st_header, rows = 1, cols = 1:ncol(stock_ass), gridExpand = TRUE)
addStyle(wb, "Stock", st_data, rows = 2:(n + 1), cols = 1:3, gridExpand = TRUE)
addStyle(wb, "Stock", st_num,  rows = 2:(n + 1), cols = 4, gridExpand = TRUE)
setColWidths(wb, "Stock", cols = 1:4, widths = c(14, 55, 12, 12))

# --- 4. Columna de imagen -----------------------------------------
compress_img <- function(filepath, max_px = 180, quality = 72) {
  img  <- magick::image_read(filepath)
  info <- magick::image_info(img)
  if (info$width > max_px || info$height > max_px) {
    img <- magick::image_scale(img, paste0(max_px, "x", max_px))
  }
  tmp <- tempfile(fileext = paste0(".", tolower(tools::file_ext(filepath))))
  magick::image_write(img, path = tmp, quality = quality)
  tmp
}

img_col_idx <- ncol(stock_ass) + 1
writeData(wb, "Stock", "IMAGEN", startRow = 1, startCol = img_col_idx)
addStyle(wb, "Stock", st_header, rows = 1, cols = img_col_idx)
setColWidths(wb, "Stock", cols = img_col_idx, widths = 11)

IMG_IN <- 0.65   # tamaño de imagen en pulgadas
IMG_PT <- 50     # alto de fila en puntos

for (i in seq_len(n)) {
  excel_row <- i + 1
  setRowHeights(wb, "Stock", rows = excel_row, heights = IMG_PT)

  img_tmp <- compress_img(img_paths[i])
  insertImage(wb, "Stock", file = img_tmp,
              startRow = excel_row, startCol = img_col_idx,
              width = IMG_IN, height = IMG_IN, units = "in")
}

freezePane(wb, "Stock", firstActiveRow = 2)
addFilter(wb, "Stock", row = 1, cols = 1:ncol(stock_ass))

# --- 5. Guardado ---------------------------------------------------
nombre_archivo <- paste0("Stock/Stock_WHASS_con_imagenes_", fecha_stock, ".xlsx")
saveWorkbook(wb, nombre_archivo, overwrite = TRUE)
message("Guardado: ", nombre_archivo)
