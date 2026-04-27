# app.R
# Prototipo Planificador - Zona Centro - Noviembre 2025
# Requisitos: shiny, shinyMobile, dplyr, tidyr, lubridate, DT, writexl, shinyWidgets, shinyjs
# Instalar paquetes si hace falta:
# install.packages(c("shiny","shinyMobile","dplyr","tidyr","lubridate","DT","writexl","shinyWidgets","shinyjs"))

library(shiny)
library(shinyMobile)
library(dplyr)
library(tidyr)
library(lubridate)
library(DT)
library(writexl)
library(shinyWidgets)
library(shinyjs)

# -----------------------------
# Datos base (Zona Centro)
# -----------------------------
year <- 2025
month <- 11
feriado_dates <- as_date(c("2025-11-24"))  # feriado: 24/11/2025

stores <- tibble::tribble(
  ~store_id, ~store_name, ~demand, ~open_days, ~open_time, ~close_time, ~max_monthly_hours,
  1, "Florida", 2, "Mon-Sun", "11:00", "20:00", 600,
  2, "Recoleta", 1, "Mon-Sun", "10:00", "21:00", 300,
  3, "Guemes", 1, "Mon-Fri", "09:00", "18:00", 250
)

vendedoras <- tibble::tribble(
  ~name, ~store_id,
  "Sofía", 1,
  "Maitena", 1,
  "Candela", 1,
  "Bárbara", 2,
  "Micaela", 2,
  "Cande", 2,
  "Mailen", 3,
  "Rocío", 3
)

# calendar days for month
days <- tibble(
  date = seq.Date(as_date(sprintf("%04d-%02d-01", year, month)),
                  as_date(sprintf("%04d-%02d-%02d", year, month, days_in_month(ymd(sprintf("%04d-%02d-01", year, month))))),
                  by = "day")
) %>%
  mutate(weekday = wday(date, label = TRUE, week_start = 1),
         is_weekend = weekday %in% c("sáb", "dom"),
         is_feriado = date %in% feriado_dates)

# storage for assignments (reactiveValues)
# each row: date, store_id, vendedora, start, end, hours, counted_hours, is_franco
init_shifts <- tibble(
  date = as.Date(character()),
  store_id = integer(),
  vendedora = character(),
  start = character(),
  end = character(),
  hours = numeric(),
  counted_hours = numeric(),
  is_franco = logical()
)

# helper: parse time strings "HH:MM"
time_to_h <- function(t) {
  if (is.na(t) || t == "") return(0)
  h <- hour(hm(t))
  m <- minute(hm(t))
  h + m/60
}

# UI
ui <- f7Page(
  title = "Planificador - Zona Centro (Nov 2025)",
  f7TabLayout(
    navbar = f7Navbar(title = "Planificador - Zona Centro"),
    do.call(
      f7Tabs,
      c(
        list(id = "tabs"),
        lapply(seq_len(nrow(stores)), function(i) {
          st <- stores[i, ]
        f7Tab(
          tabName = st$store_name,
          icon = f7Icon("house"),
          active = (i == 1),
          f7Block(title = paste("Editar turnos -", st$store_name)),
          fluidRow(
            column(4,
                   dateInput(paste0("date_", st$store_id),
                             label = "Fecha",
                             value = days$date[1],
                             min = min(days$date), max = max(days$date))
            ),
            column(4,
                   selectInput(paste0("vend_", st$store_id),
                               "Vendedora",
                               choices = vendedoras %>%
                                 filter(store_id == st$store_id) %>%
                                 pull(name))
            ),
            column(4,
                   checkboxInput(paste0("is_franco_", st$store_id),
                                 "Marcar FRANCO", value = FALSE)
            )
          ),
          fluidRow(
            column(3,
                   pickerInput(paste0("start_", st$store_id), "Inicio",
                               choices = sprintf("%02d:00", 6:22),
                               selected = st$open_time)
            ),
            column(3,
                   pickerInput(paste0("end_", st$store_id), "Fin",
                               choices = sprintf("%02d:00", 7:23),
                               selected = st$close_time)
            ),
            column(3,
                   numericInput(paste0("hours_override_", st$store_id),
                                "Horas (si querés forzar)",
                                value = NA, min = 4, max = 6, step = 0.5)
            ),
            column(3,
                   actionButton(paste0("add_", st$store_id),
                                "Agregar turno / franco",
                                class = "btn-primary")
            )
          ),
          f7BlockTitle("Resumen y tabla de turnos"),
          fluidRow(
            column(8, DTOutput(paste0("table_", st$store_id))),
            column(4,
                   verbatimTextOutput(paste0("summary_", st$store_id)),
                   br(),
                   actionButton(paste0("sugerir_francos_", st$store_id),
                                "Sugerir francos (round-robin)"),
                   br(), br(),
                   downloadButton(paste0("export_excel"),
                                  "Exportar a Excel (todo)")
            )
          )
        )
      })
    ))))
    

# Server
server <- function(input, output, session) {
  rv <- reactiveValues(shifts = init_shifts)
  
  # helper: compute hours and counted_hours
  compute_hours_row <- function(date, start, end, is_franco_flag) {
    if (isTRUE(is.na(start)) || start == "" || isTRUE(is.na(end)) || end == "") return(list(hours = 0, counted = 0))
    start_h <- time_to_h(start)
    end_h <- time_to_h(end)
    # if end < start assume next day? for simplicity, block that case (end must > start)
    dur <- end_h - start_h
    if (dur < 0) dur <- 0
    hours <- round(dur, 2)
    counted <- hours
    if (date %in% feriado_dates && !is_franco_flag) {
      # feriado trabajado => se computa doble
      counted <- counted * 2
    }
    list(hours = hours, counted = counted)
  }
  
  # Add observers for each store add button
  lapply(seq_len(nrow(stores)), function(i) {
    st <- stores[i, ]
    sid <- st$store_id
    observeEvent(input[[paste0("add_", sid)]], {
      date_sel <- input[[paste0("date_", sid)]]
      vend <- input[[paste0("vend_", sid)]]
      is_franco_flag <- isTRUE(input[[paste0("is_franco_", sid)]])
      start <- input[[paste0("start_", sid)]]
      end <- input[[paste0("end_", sid)]]
      hours_override <- input[[paste0("hours_override_", sid)]]
      
      # if franco -> create an entry is_franco TRUE and no hours
      if (is_franco_flag) {
        # count weekly francos limit check will be done later
        newrow <- tibble(
          date = as_date(date_sel),
          store_id = sid,
          vendedora = vend,
          start = NA_character_,
          end = NA_character_,
          hours = 0,
          counted_hours = 0,
          is_franco = TRUE
        )
        rv$shifts <- bind_rows(rv$shifts, newrow) %>% arrange(date, vendedora)
        showToast(session, "success", "Franco registrado")
        return()
      }
      
      # Validate start < end
      if (is.null(start) || is.null(end) || start == "" || end == "") {
        showModal(modalDialog(title = "Error", "Debe seleccionar inicio y fin del turno", easyClose = TRUE))
        return()
      }
      
      # compute hours
      ch <- compute_hours_row(as_date(date_sel), start, end, FALSE)
      hours <- ch$hours
      counted <- ch$counted
      # allow override to set hours between 4-6 and adjust counted proportionally
      if (!is.na(hours_override)) {
        if (hours_override < 4 || hours_override > 6) {
          showModal(modalDialog(title = "Error", "Horas deben ser entre 4 y 6", easyClose = TRUE))
          return()
        } else {
          hours <- hours_override
          # preserve counted doubling if feriado
          counted <- hours
          if (as_date(date_sel) %in% feriado_dates) counted <- counted * 2
        }
      } else {
        # normal validation hours between 4-6
        if (hours < 4 || hours > 6) {
          showModal(modalDialog(title = "Error", "Duración del turno debe ser entre 4 y 6 horas. Usá override si querés forzar.", easyClose = TRUE))
          return()
        }
      }
      
      # check vendedora monthly max (132)
      v_total <- rv$shifts %>%
        filter(vendedora == vend) %>%
        summarize(sum = sum(counted_hours, na.rm = TRUE)) %>%
        pull(sum)
      v_total <- ifelse(is.na(v_total), 0, v_total)
      if ((v_total + counted) > 132) {
        showModal(modalDialog(title = "Bloqueado",
                              paste0("No se puede asignar: ", vend, " superaría 132 h (actual + nueva = ", round(v_total + counted,1), " h)"),
                              easyClose = TRUE))
        return()
      }
      
      # check store monthly max
      s_total <- rv$shifts %>%
        filter(store_id == sid) %>%
        summarize(sum = sum(counted_hours, na.rm = TRUE)) %>%
        pull(sum)
      s_total <- ifelse(is.na(s_total), 0, s_total)
      if ((s_total + counted) > st$max_monthly_hours) {
        showModal(modalDialog(title = "Bloqueado",
                              paste0("No se puede asignar: la tienda '", st$store_name, "' superaría su máximo mensual (", st$max_monthly_hours, " h)."),
                              easyClose = TRUE))
        return()
      }
      
      # add row
      newrow <- tibble(
        date = as_date(date_sel),
        store_id = sid,
        vendedora = vend,
        start = start,
        end = end,
        hours = hours,
        counted_hours = counted,
        is_franco = FALSE
      )
      rv$shifts <- bind_rows(rv$shifts, newrow) %>% arrange(date, vendedora)
      showToast(session, "success", "Turno agregado")
    })
  })
  
  # Render tables and summaries
  lapply(seq_len(nrow(stores)), function(i) {
    st <- stores[i, ]
    sid <- st$store_id
    output[[paste0("table_", sid)]] <- renderDT({
      # show calendar-like table: rows = dates, columns: date, weekday, and list of assigned names/turnos
      df_days <- days %>% select(date, weekday, is_feriado)
      assigned <- rv$shifts %>% filter(store_id == sid)
      df_show <- df_days %>%
        rowwise() %>%
        mutate(assignments = {
          rows <- assigned %>% filter(date == date)
          if (nrow(rows)==0) {
            ""
          } else {
            paste0(apply(rows, 1, function(r) {
              if (r["is_franco"] == "TRUE") {
                paste0(r["vendedora"], ": FRANCO")
              } else {
                paste0(r["vendedora"], " (", r["start"], "-", r["end"], ", h=", r["hours"], ifelse(as_date(r["date"]) %in% feriado_dates, " [FERIADO x2]", ""), ")")
              }
            }), collapse = " | ")
          }
        }) %>%
        ungroup() %>%
        mutate(Fecha = format(date, "%Y-%m-%d"),
               Dia = as.character(weekday),
               Feriado = ifelse(is_feriado, "SI", ""),
               Assignments = assignments) %>%
        select(Fecha, Dia, Feriado, Assignments)
      datatable(df_show, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
    })
    
    output[[paste0("summary_", sid)]] <- renderPrint({
      assigned <- rv$shifts %>% filter(store_id == sid)
      cat("Tienda:", st$store_name, "\n")
      cat("Max mensual tienda:", st$max_monthly_hours, "h\n")
      cat("Horas asignadas totales (conteo):", round(sum(assigned$counted_hours, na.rm = TRUE),1), "h\n\n")
      
      cat("Resumen por vendedora:\n")
      vsum <- rv$shifts %>%
        filter(store_id == sid) %>%
        group_by(vendedora) %>%
        summarize(hours = sum(hours, na.rm = TRUE),
                  counted = sum(counted_hours, na.rm = TRUE),
                  francos = sum(is_franco, na.rm = TRUE)) %>%
        arrange(desc(counted))
      if (nrow(vsum)==0) {
        cat("No hay asignaciones aún.\n")
      } else {
        print(vsum)
        # check per vendedora if exceed 132
        over <- vsum %>% filter(counted > 132)
        if (nrow(over)>0) {
          cat("\nALERTA: vendedoras con >132 h (conteo):\n")
          print(over)
        }
      }
    })
  })
  
  # Sugerir francos round-robin por tienda
  lapply(seq_len(nrow(stores)), function(i) {
    st <- stores[i, ]
    sid <- st$store_id
    observeEvent(input[[paste0("sugerir_francos_", sid)]], {
      # desired francos per vendedora = 2 * semanas en mes (aprox)
      num_weeks <- ceiling(nrow(days)/7)
      desired <- 2 * num_weeks
      vens <- vendedoras %>% filter(store_id == sid) %>% pull(name)
      # build list of candidate dates (prefer non-assigned days)
      candidate_dates <- days %>% pull(date)
      # we'll assign francos by rotating vendedoras over dates
      new_francos <- tibble(date = as_date(character()), store_id = integer(), vendedora = character(), start = character(), end = character(), hours = numeric(), counted_hours = numeric(), is_franco = logical())
      # current francos count
      curr <- rv$shifts %>% filter(store_id == sid, is_franco) %>% group_by(vendedora) %>% summarize(n = n())
      curr <- tibble(vendedora = vens) %>% left_join(curr, by = "vendedora") %>% mutate(n = ifelse(is.na(n), 0, n))
      # rotate through dates and vendedoras
      idx <- 1
      for (d in candidate_dates) {
        # try assign to one vendedora at a time until all reach desired
        v_idx <- ((idx - 1) %% length(vens)) + 1
        vend <- vens[v_idx]
        if (curr$n[curr$vendedora == vend] < desired) {
          # only assign if not already assigned franco that date
          already <- rv$shifts %>% filter(store_id == sid, date == d, vendedora == vend, is_franco) %>% nrow()
          if (already == 0) {
            new_francos <- bind_rows(new_francos, tibble(date = d, store_id = sid, vendedora = vend,
                                                         start = NA_character_, end = NA_character_, hours = 0, counted_hours = 0, is_franco = TRUE))
            curr$n[curr$vendedora == vend] <- curr$n[curr$vendedora == vend] + 1
          }
        }
        idx <- idx + 1
        # stop early if all reached desired
        if (all(curr$n >= desired)) break
      }
      # append new francos (evita duplicados)
      rv$shifts <- bind_rows(rv$shifts, anti_join(new_francos, rv$shifts, by = c("date","store_id","vendedora"))) %>% arrange(date, vendedora)
      showToast(session, "success", paste("Sugeridos francos (objetivo por vendedora:", desired, "días). Podés ajustar manualmente."))
    })
  })
  
  # Export Excel (one sheet por tienda)
  output$export_excel <- downloadHandler(
    filename = function() {
      paste0("planificacion_nov_2025_zona_centro.xlsx")
    },
    content = function(file) {
      # build sheets per store
      wb_list <- lapply(seq_len(nrow(stores)), function(i) {
        st <- stores[i, ]
        sid <- st$store_id
        assigned <- rv$shifts %>% filter(store_id == sid)
        # left join to days to show rows for each day
        df <- days %>% mutate(Fecha = format(date, "%Y-%m-%d"), Dia = as.character(weekday), Feriado = ifelse(is_feriado, "SI","")) %>%
          left_join(
            assigned %>% mutate(Fecha = format(date, "%Y-%m-%d")) %>%
              group_by(Fecha) %>%
              summarize(Asignaciones = paste0(ifelse(is_franco, paste0(vendedora, ": FRANCO"), paste0(vendedora, " (", start, "-", end, " h=", hours, ifelse(date %in% feriado_dates, " [FERIADO x2]", ""), ")")), collapse = " | ")),
            by = "Fecha"
          ) %>%
          select(Fecha, Dia, Feriado, Asignaciones)
        df
      })
      names(wb_list) <- stores$store_name
      writexl::write_xlsx(wb_list, path = file)
    }
  )
  
  # overall vendedoras summary (optional) - not in UI but could be added
}

shinyApp(ui, server)
