# CLAUDE.md — Proyecto El Lucero

> Este archivo es leído automáticamente por Claude Code al inicio de cada sesión.
> Contiene contexto del proyecto, convenciones, estado actual y las instrucciones de bitácora.

---

## Contexto general

El Lucero es una empresa retail de marroquinería, joyería y accesorios con 10 locales en Buenos Aires, operando bajo las marcas **El Lucero Cuero**, **El Lucero Joyería** y **AS**. El trabajo en este proyecto consiste en construir y mantener pipelines de datos y reportes automatizados de performance del negocio.

**Entorno de trabajo:**
- Sistema operativo: **Windows** (sin atajos ⌘)
- IDE principal: **RStudio con R Markdown** (`.Rmd`)
- Fuentes de datos: **Odoo** (ERP), **Alegra**, **Mercadopago**, **Fiserv**
- Colaboradora clave: **Silvina** (gestiona el archivo Excel de horas)

---

## Locales

Florida, San Telmo, Recoleta, French, Güemes, Güemes 2, El Solar, AS San Telmo, AS Güemes (actualmente cerrado, puede reabrir), San Telmo 2.

**Agrupación por zona/negocio** (usada en Tablero Carlos):
- **Cuero Centro**: Güemes, Florida, Recoleta
- **Cuero San Telmo**: San Telmo, French
- **Joyería Centro**: El Solar, Güemes 2
- **Joyería San Telmo**: San Telmo 2 (antes vendía cuero)
- **AS**: AS San Telmo, AS Güemes (pero ahora está cerrada esa tienda. Se supone que en algún momento volverá a abrir)

---

## Convenciones del dominio

- **Formato numérico argentino**: coma como separador decimal, punto como separador de miles
  - Patrón para etiquetas de porcentaje: `gsub("\\.", ",", sprintf("%.1f%%", ...))`
- **Color de marca**: Pantone 3035C / hex `#005363`
- **Todo el texto visible en español**: "Estado de Resultados", "Cascada de resultados" — nunca "P&L"
- **Margen %** se calcula siempre como `1 - (Costo / Venta_sin_imp)`, nunca como promedio simple
- **Porcentajes**: nunca como promedios simples — siempre en relación a la base correcta (`Venta_sin_imp` o `Venta_con_imp` según corresponda)
- **Umbral 80% Pareto**: usa regla del punto medio `(cum_prev + cum_part) / 2 < 0.80` para no sobrepasar; decisión deliberada, no cambiar

---

## Pipelines y reportes activos

### 1. Automatización de horas (`horas_desde_premios.R`)

Parsea horas mensuales de tiendas desde `PREMIOS TIENDAS 2026.xlsx` hacia la estructura de `Horas trabajadas Tiendas desde 2025-09.xlsx`.

- Fuzzy name matching con tokens normalizados (minúsculas, sin tildes, orden alfabético)
- Hoja `alias` en el Excel histórico para variantes de nombre irresolubles
- 4 controles de validación: bloques de tienda desconocidos, descuadre de totales de horas, empleados sin número (con sugerencias), duplicados de período
- Output: `.xlsx` con el mes nuevo (para pegar manualmente en el maestro) + `.rds` con historia completa (para Presupuestos)
- La `tabla x hora` del Excel maestro es la fuente de verdad histórica; las correcciones van ahí directamente

### 2. Reporte Presupuestos (`Presupuestos_v6.Rmd`)

Pipeline de reportes financieros multi-tienda que procesa datos de Mercadopago, sueldos, tarjetas y gastos operativos.

**Fixes aplicados en v6:**
- `mutate()` malformado que causaba coerción silenciosa a NA
- Parsing de fechas con `ymd()` y `as.numeric()` simultáneamente
- `.groups` faltante en llamadas a `summarise()`
- `NA` sin tipo en `if_else()` y `case_when()`
- Filtro de rango de fechas incorrecto (`AÑO >= x & MES <= y`)

**Refactors pendientes para v7** (no tocar hasta que se decida avanzar):
- Centralizar parámetros hardcodeados (alícuotas, porcentajes de aportes, ART) en un chunk inicial
- Diccionario unificado de nombres de tiendas
- Reemplazar loop manual de 9 iteraciones con `pivot_longer`
- Extraer lógica duplicada de `case_when` en funciones reutilizables
- Automatizar carga de archivos mensuales con `map_dfr`
- Convertir objetos `REVISO_*` silenciosos en alertas automáticas con `message()`

### 3. Tickets por hora (v4)

Reportes Excel por tienda con análisis de ventas por franja horaria.

- Heatmaps, gráficos de barras/puntos, análisis de ticket promedio
- Feriados (`feriados`) con textura rayada; tiendas Güemes y Güemes 2 no abren feriados
- Cambios de horario via tabla `horarios` con `fecha_desde`/`fecha_hasta`
- Celdas grises para fuera de horario en todos los heatmaps
- Heatmaps por fecha generados mes a mes, lado a lado en Excel
- AS Güemes actualmente comentado (`#`) — reactivar si reabre
- Estilo de correcciones: siempre targeted "buscá / reemplazá", no reescrituras completas

### 4. Reporte de Joyería (mensual, histórico, debutantes)

Workbooks Excel multi-hoja generados con `openxlsx` + visualizaciones `ggplot2` + imágenes de producto vía `magick`.

**Hojas incluidas** (reporte completo): SKU, Familias, Modelos, Atributos, Proveedores, Nacionalidad, Método de pago, Precio unitario, Valor stock, Stock sin venta.

**Reporte debutantes**: solo hojas SKU, Familias, Modelos. Output: `Reporte_Ventas_DEBUTANTES_JOYERIA_[mes].xlsx`.

**Decisiones técnicas clave:**
- Imágenes de producto: se usa el ID de Odoo (no el nombre) para el matching, descargadas desde `product.template`
- Donut charts: etiquetas con formato argentino vía `gsub("\\.", ",", sprintf("%.1f%%", ...))`
- Proveedores: `colorRampPalette(brewer.pal(8, "Set2"))(n_provs)` para manejar más de 8 proveedores
- `PROVEEDOR_SUBFAMILIAS` ya calcula participación dentro de cada familia — no recalcular
- Días/stock (`D/S`): usa `*dias_periodo` (calculado como `as.integer(fecha_fin - fecha_inicio) + 1`), no `*30` fijo

**Scoping crítico**: variables como `IMG_PT`, `IMG_IN`, `img_lookup` deben definirse en el chunk `helpers` (antes de cualquier chunk de hoja), no dentro del chunk SKU, porque las hojas Familias y Modelos las usan antes de que SKU se ejecute.

### 5. Reporte de gastos por zona

Workbook Excel anual con una hoja por mes (`MM-AAAA`), generado con un loop sobre `MESES_GASTOS`.

- Función `procesar_mes_gastos(mes, anio)` encapsula toda la transformación
- Agrupación por zonas con subtotales usando `imap_dfr`

### 6. Stock joyería sin venta

Reporte Excel con imágenes de producto insertadas. Columnas: DESCRIPCION, CODIGO, El Solar, San Telmo 2, Güemes 2, Total tiendas, Florida Depósito.

---

## Dashboards HTML interactivos

### Dashboard El Lucero

Archivo HTML autocontenido. Usa Chart.js y SheetJS embebidos (sin dependencias externas).

Fuente de datos: `Datos.xlsx` — formato largo con columnas `year`, `month`, `store`, `concept`, `value`.

**Funcionalidades:**
- Filtros duales de selección múltiple: locales y meses
- Tabla "Estado de Resultados" con secciones agrupadas
  - Columnas `% vta c/imp` solo en secciones de gastos, integradas en el encabezado del grupo
  - Filas de Resultado sin columnas de porcentaje
- Gráficos: Resultados por local, Margen %, Cascada de resultados (waterfall), Distribución de gastos (barra 100% apilada), Composición de egresos (doughnut con `chartjs-plugin-datalabels`, sin leyenda lateral)
- Botón "Descargar tabla" (exporta a Excel con SheetJS)

### Tablero Carlos

Dashboard de control para el stakeholder Carlos. Archivos: `plantilla_tablero_Carlos.html` + `preparar_datos.R`.

**Lógica de datos:**
- IVA derivado como `Venta_con_imp - Venta_sin_imp`, sumado a Impuestos
- Resultado = `Venta_c/imp` menos todos los ítems de gasto
- Configuración de zonas/negocios vive **exclusivamente** en el bloque CONFIG del HTML — no duplicar en el JSON de R

**Funcionalidades:**
- 9 líneas con semáforos (Personal, Alquiler y expensas, Gastos varios)
  - Amarillo: ≥ 10,5% | Rojo: ≥ 15,5% (fondo saturado, texto blanco)
- Selector de unidades: dropdown con checkboxes + botón "solo" al hover
- Grupos ordenados por volumen de ventas descendente
- Vista comparativa (solo "Resultado por unidad") y vista detalle por unidad

**Hosting en evaluación:** Cloudflare Pages con Access (recomendado) o Netlify.

---

## Principios de arquitectura

- **Fuente única de verdad**: un archivo canónico por dominio; los scripts lo leen, no lo duplican
- **`.rds` como formato de intercambio**: preserva tipos de datos sin re-parsear; preferido sobre CSV para pasar dataframes entre Rmds
- **Nombres de archivo fijos** (ej. `df_base.rds`), sobreescritos en cada actualización — no versionar por fecha; los Rmds downstream filtran fechas internamente
- **Verificación de frescura**: `file.info("data/df_base.rds")$mtime` al inicio de cada Rmd consumidor
- **Alias/lookups en hojas Excel**, no en el script — editables por no-programadores sin tocar código
- **Validaciones explícitas**: objetos `REVISAR_*` / `REVISO_*` y alertas `message()` para detectar problemas de datos en tiempo de ejecución, no silenciosamente
- **Comentar en vez de borrar**: código incierto se comenta con `#`, no se elimina

---

## Patrones de trabajo con Claude Code

- **Formato preferido de cambios**: bloques "buscá / reemplazá" con explicación de la causa raíz antes del fix. No reescrituras completas de archivos.
- **Iteración con archivo actualizado**: Vale comparte versiones actualizadas del Rmd mid-conversación; Claude debe releer el estado actual antes de continuar, especialmente tras cambios incorrectos o incompletos.
- **Verificar antes de implementar**: consultas conceptuales o de clarificación antes de aceptar una solución; algunos cambios se consultan con stakeholders antes de finalizar.
- **Orden de chunks importa**: variables definidas en chunks tardíos no están disponibles en chunks anteriores. Patrón de fix: mover definiciones upstream a un chunk `helpers`.
- **Comunicación directa**: sin saludos ni relleno. Respuestas concisas y accionables, en español.

---

## Bitácora (OBLIGATORIO al abrir y cerrar cada sesión)

La bitácora vive en `bitacora/`, **un archivo `.md` por dominio de trabajo**, más un índice
corto. No es un archivo único: eso obligaría a leer historia irrelevante en cada sesión.

```
bitacora/
  ESTADO.md              ← índice, una línea por dominio
  base-odoo.md           presupuestos-gastos.md   joyeria.md
  cuero.md               tablero-carlos.md        dashboard-lucero.md
  tickets-hora.md        horas.md                 stock.md
  clientes.md            taxfree.md
```

### Al abrir la sesión

El índice se importa acá abajo, así que ya llega cargado con este archivo:

@bitacora/ESTADO.md

Leer **únicamente** el `.md` del dominio que se va a tocar. No abrir los demás.

### Al cerrar la sesión

1. Agregar la entrada **al inicio** del `.md` del dominio (más reciente primero), después
   del encabezado del archivo:

```markdown
## [FECHA YYYY-MM-DD]

**Qué se hizo:** [cambios, archivo por archivo]

**Por qué:** [solo si la decisión no es obvia leyendo el código]

**Estado al cierre:** [qué quedó funcionando / qué quedó roto o a medias]
```

2. Actualizar la fila de ese dominio en `bitacora/ESTADO.md` (fecha y pendiente principal).

Se tocan **uno o dos archivos por sesión**, nunca más.

### Qué se registra y qué no

**Sí:**
- Cambios en un pipeline recurrente.
- El **porqué** de una decisión: qué se descartó y por razón de qué.
- Lo que quedó a medias, roto o pendiente de consultar con Carlos o Silvina.

**No:**
- **Trabajos de una sola vez.** Un Excel puntual que se pide y no se vuelve a generar no va
  a la bitácora.
- **Lo que ya dice `git log`.** El historial de git registra qué archivo cambió y cómo; si una
  entrada se puede reconstruir mirando el diff, no aporta. La bitácora guarda lo que git no:
  el porqué y el estado pendiente.

### Relación con este archivo

La bitácora es el borrador; `CLAUDE.md` es lo asentado. Cuando una decisión se estabiliza y
pasa a ser convención permanente, **migra a `CLAUDE.md`** y se saca de la bitácora
(ej.: "matcheamos imágenes por ID de Odoo" empezó como entrada de bitácora y hoy es una
convención de dominio).

Si un dominio nuevo no tiene archivo todavía, crearlo y agregar su fila a `ESTADO.md`.
