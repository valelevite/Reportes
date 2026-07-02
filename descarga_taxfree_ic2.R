library(chromote)
library(lubridate)
library(purrr)
library(fs)
library(dplyr)
library(jsonlite)

# ============================================================
# CONFIGURACIÓN
# ============================================================

tiendas <- tibble::tribble(
  ~tienda,      ~usuario,        ~password,
  "Florida",    "IC20328407",   "Florid@823",
  # "Tienda 2", "usuario2",      "clave2",
  # ... agregar el resto
)

carpeta_destino <- "C:/Users/PC/Documents/Valeria/Reportes/Tax free/Tax free para armar"

LOGIN_URL <- "https://ic2.globalblue.com/issuing"

# Fragmento identificador del ícono de 3 rayitas (tomado del atributo
# "d" del <path> que nos pasaste — funciona como un id único).
PATRON_ICONO_MENU <- "M4.42334 8.36581"

# ============================================================
# FECHAS — mes calendario anterior completo
# ============================================================

fecha_ref    <- Sys.Date()
mes_desde    <- floor_date(fecha_ref, "month") %m-% months(1)
mes_hasta    <- floor_date(fecha_ref, "month") - days(1)

date_from    <- format(mes_desde, "%Y/%m/01 06:00")
date_to      <- format(mes_hasta, "%Y/%m/%d 23:59")
etiqueta_mes <- format(mes_desde, "%Y_%m")

message("Rango a descargar: ", date_from, " -> ", date_to)

# ============================================================
# HELPER: ubicar el iframe del ReportViewer dentro de una sesión
# dada, con reintentos y diagnóstico si no lo encuentra.
# ============================================================

obtener_contexto_iframe <- function(b, patron = "ReportViewer", intentos = 5, espera_entre_intentos = 3) {

  listar_frames <- function(nodo, nivel = 0) {
    prefijo <- strrep("  ", nivel)
    url <- if (is.null(nodo$frame$url) || nodo$frame$url == "") "(sin url)" else nodo$frame$url
    message(prefijo, "- ", url)
    if (!is.null(nodo$childFrames)) {
      for (child in nodo$childFrames) listar_frames(child, nivel + 1)
    }
  }

  buscar_frame <- function(nodo) {
    if (!is.null(nodo$frame$url) && grepl(patron, nodo$frame$url, ignore.case = TRUE)) {
      return(nodo$frame$id)
    }
    if (!is.null(nodo$childFrames)) {
      for (child in nodo$childFrames) {
        r <- buscar_frame(child)
        if (!is.null(r)) return(r)
      }
    }
    NULL
  }

  for (intento in seq_len(intentos)) {
    tree <- b$Page$getFrameTree()$frameTree
    frame_id <- buscar_frame(tree)

    if (is.null(frame_id) && !is.null(tree$childFrames) && length(tree$childFrames) > 0) {
      frame_id <- tree$childFrames[[1]]$frame$id
    }

    if (!is.null(frame_id)) {
      ctx <- b$Page$createIsolatedWorld(frameId = frame_id)
      return(ctx$executionContextId)
    }

    message("  (intento ", intento, "/", intentos, ": iframe todavía no aparece, esperando ",
            espera_entre_intentos, "s más...)")
    Sys.sleep(espera_entre_intentos)
  }

  message("No se encontró ningún iframe tras ", intentos, " intentos. ",
          "Estructura de frames detectada:")
  tree <- b$Page$getFrameTree()$frameTree
  listar_frames(tree)

  NULL
}

# ============================================================
# HELPER: click "real" via CDP Input (cuenta como gesto genuino
# del usuario, a diferencia de dispatchEvent() desde JS que los
# navegadores pueden bloquear si dispara un window.open()).
# js_encontrar_elemento debe ser una expresión JS que devuelva el
# elemento buscado (o null/undefined si no lo encuentra).
# ============================================================

click_real <- function(b, js_encontrar_elemento) {

  rect_json <- b$Runtime$evaluate(sprintf("
    (function() {
      var el = %s;
      if (!el) return null;
      el.scrollIntoView({block: 'center', inline: 'center'});
      var r = el.getBoundingClientRect();
      return JSON.stringify({x: r.x + r.width/2, y: r.y + r.height/2});
    })();
  ", js_encontrar_elemento))

  valor <- rect_json$result$value
  if (is.null(valor)) return(FALSE)

  coords <- jsonlite::fromJSON(valor)

  b$Input$dispatchMouseEvent(type = "mouseMoved", x = coords$x, y = coords$y)
  Sys.sleep(0.1)
  b$Input$dispatchMouseEvent(type = "mousePressed", x = coords$x, y = coords$y,
                              button = "left", clickCount = 1)
  Sys.sleep(0.1)
  b$Input$dispatchMouseEvent(type = "mouseReleased", x = coords$x, y = coords$y,
                              button = "left", clickCount = 1)
  TRUE
}

# ============================================================
# HELPER: hace click en el menú -> INFORMES y devuelve una
# ChromoteSession nueva conectada a la ventana que se abre.
# Esto preserva el traspaso de sesión (probablemente via
# postMessage/window.open) que se pierde si navegamos directo.
# ============================================================

abrir_ventana_informes <- function(b) {

  ids_antes <- vapply(b$Target$getTargets()$targetInfos, function(x) x$targetId, character(1))

  ok_icono <- click_real(b, sprintf("document.querySelector('path[d^=\"%s\"]')", PATRON_ICONO_MENU))
  message("  click ícono menú: ", ifelse(ok_icono, "encontrado y clickeado", "NO ENCONTRADO"))

  if (!ok_icono) {
    warning("No se encontró el ícono de menú (3 rayitas).")
    return(NULL)
  }

  Sys.sleep(1.5)

  js_buscar_informes <- "
    Array.prototype.slice.call(document.querySelectorAll('*')).find(function(e) {
      return e.children.length === 0 && e.textContent.trim().toUpperCase() === 'INFORMES';
    })
  "

  ok_informes <- click_real(b, js_buscar_informes)
  message("  click texto INFORMES: ", ifelse(ok_informes, "encontrado y clickeado", "NO ENCONTRADO"))

  if (!ok_informes) {
    warning("No se encontró el texto 'INFORMES' en el menú abierto.")
    return(NULL)
  }

  Sys.sleep(2)

  ids_despues <- vapply(b$Target$getTargets()$targetInfos, function(x) x$targetId, character(1))
  nuevo_id <- setdiff(ids_despues, ids_antes)

  if (length(nuevo_id) == 0) {
    warning("No se detectó ninguna ventana/pestaña nueva después del click en INFORMES.")
    return(NULL)
  }

  b_reportes <- ChromoteSession$new(parent = b$parent, targetId = nuevo_id[1])
  b_reportes$default_timeout <- 60
  b_reportes
}

# ============================================================
# FUNCIÓN PRINCIPAL
# ============================================================

descargar_informe_tienda <- function(tienda, usuario, password) {

  message("\n--- Procesando: ", tienda, " ---")

  b <- ChromoteSession$new()
  on.exit(b$close(), add = TRUE)
  b$default_timeout <- 60

  # --- 1. Login ---
  b$Page$navigate(LOGIN_URL)
  tryCatch(
    b$Page$loadEventFired(timeout_ = 30),
    error = function(e) message("Aviso: sin evento de carga a tiempo, continúo igual.")
  )
  Sys.sleep(2)

  b$Runtime$evaluate(sprintf("
    (function() {
      var u = document.querySelector('#username');
      var p = document.querySelector('#password');
      u.value = '%s';
      u.dispatchEvent(new Event('input', {bubbles:true}));
      p.value = '%s';
      p.dispatchEvent(new Event('input', {bubbles:true}));
    })();
  ", usuario, password))

  Sys.sleep(1)
  b$Runtime$evaluate("document.querySelector('#btnLogin').click();")
  Sys.sleep(4)

  # --- 2. Abrir la ventana de informes a través del menú (preserva sesión) ---
  b_reportes <- abrir_ventana_informes(b)

  if (is.null(b_reportes)) {
    warning(tienda, ": no se pudo abrir la ventana de informes.")
    return(invisible(NULL))
  }

  on.exit(try(b_reportes$close(), silent = TRUE), add = TRUE)

  # Forzar un viewport tipo escritorio: el sitio parece colapsar la barra
  # de herramientas del ReportViewer (incluido el ícono de exportar) si
  # la ventana se renderiza angosta.
  try(
    b_reportes$Emulation$setDeviceMetricsOverride(
      width = 1920, height = 1080, deviceScaleFactor = 1, mobile = FALSE
    ),
    silent = TRUE
  )

  tryCatch(
    b_reportes$Page$loadEventFired(timeout_ = 30),
    error = function(e) message("Aviso: sin evento de carga a tiempo en ventana de informes, continúo igual.")
  )
  Sys.sleep(4)

  # --- 3. Completar fechas (directo en el documento, sin iframe) ---
  resultado_fechas <- b_reportes$Runtime$evaluate(sprintf("
    (function() {
      var df = document.querySelector('#dateFrom');
      var dt = document.querySelector('#dateTo');
      if (!df || !dt) return 'NO_ENCONTRADO';
      df.value = '%s';
      df.dispatchEvent(new Event('change', {bubbles:true}));
      dt.value = '%s';
      dt.dispatchEvent(new Event('change', {bubbles:true}));
      return 'OK';
    })();
  ", date_from, date_to))

  if (identical(resultado_fechas$result$value, "NO_ENCONTRADO")) {
    warning(tienda, ": no se encontraron #dateFrom/#dateTo en el documento.")
    return(invisible(NULL))
  }

  # Cerrar el calendario emergente que queda abierto tras escribir la fecha
  b_reportes$Input$dispatchKeyEvent(type = "keyDown", key = "Escape")
  b_reportes$Input$dispatchKeyEvent(type = "keyUp", key = "Escape")
  Sys.sleep(0.5)

  Sys.sleep(1)

  # --- 4. Generar el informe ---
  b_reportes$Runtime$evaluate("document.querySelector('#btnGenerateTrxReport').click();")
  Sys.sleep(10)

  # Configurar descarga automática en la ventana de informes
  b_reportes$Page$setDownloadBehavior(behavior = "allow", downloadPath = carpeta_destino)

  # --- 5. Ícono de exportar (documento principal, y si no, dentro de un iframe) ---
  resultado_export <- list(result = list(value = "NO_ENCONTRADO"))
  contexto_toolbar <- NULL  # NULL = documento principal

  js_click_export <- "
    (function() {
      var btn = document.querySelector('#ReportViewer1_ctl09_ctl04_ctl00_ButtonImg');
      if (!btn) return 'NO_ENCONTRADO';
      btn.click();
      return 'OK';
    })();
  "

  for (intento in 1:4) {
    resultado_export <- b_reportes$Runtime$evaluate(js_click_export)
    if (identical(resultado_export$result$value, "OK")) break
    Sys.sleep(2)
  }

  if (!identical(resultado_export$result$value, "OK")) {
    message("  no está en el documento principal, probando dentro de un iframe...")
    contexto_toolbar <- obtener_contexto_iframe(b_reportes, intentos = 3, espera_entre_intentos = 2)

    if (!is.null(contexto_toolbar)) {
      resultado_export <- b_reportes$Runtime$evaluate(js_click_export, contextId = contexto_toolbar)
    }
  }

  if (!identical(resultado_export$result$value, "OK")) {
    captura <- file.path(carpeta_destino, sprintf("debug_%s.png", tienda))
    try(b_reportes$screenshot(filename = captura), silent = TRUE)
    warning(tienda, ": no se encontró el ícono de exportar (ni en documento ni en iframe). ",
            "Guardé una captura en: ", captura)
    return(invisible(NULL))
  }

  Sys.sleep(1)

  # --- 6. Elegir CSV (mismo contexto que funcionó para el ícono) ---
  js_click_csv <- "
    (function() {
      var links = document.querySelectorAll('a.ActiveLink');
      for (var i = 0; i < links.length; i++) {
        if (links[i].title === 'CSV (delimitado por comas)') {
          links[i].click();
          return 'OK';
        }
      }
      return 'NO_ENCONTRADO';
    })();
  "

  if (is.null(contexto_toolbar)) {
    b_reportes$Runtime$evaluate(js_click_csv)
  } else {
    b_reportes$Runtime$evaluate(js_click_csv, contextId = contexto_toolbar)
  }

  Sys.sleep(6)

  # --- 7. Renombrar el archivo descargado ---
  archivos_recientes <- fs::dir_info(carpeta_destino, type = "file") |>
    dplyr::filter(modification_time > (Sys.time() - 60)) |>
    dplyr::arrange(dplyr::desc(modification_time))

  if (nrow(archivos_recientes) > 0) {
    nuevo_nombre <- file.path(carpeta_destino, sprintf("%s %s.csv", tienda, etiqueta_mes))
    fs::file_move(archivos_recientes$path[1], nuevo_nombre)
    message(tienda, ": guardado como ", nuevo_nombre)
  } else {
    warning(tienda, ": no se detectó ningún archivo nuevo descargado.")
  }
}

# ============================================================
# EJECUCIÓN
# ============================================================

pwalk(tiendas, function(tienda, usuario, password) {
  descargar_informe_tienda(tienda, usuario, password)
})

message("\nProceso terminado.")
