# Cuero — reportes de ventas

**Archivos:** `Reporte_ventas_Odoo-CUERO.Rmd`, `graficos_reporte_cuero.R`

---

## 2026-09-04 — ajustes finales sobre el FINAL que armó Vale a mano

Vale generó el `Reporte_Ventas_CUERO_2026-08 FINAL.xlsx` completando "EN PRODUCCIÓN" y
dando algunas terminaciones. Se compararon los dos archivos celda por celda y se pasaron al
código las que no eran propias del mes:

- **Ancho de los gráficos por rubro según cuántas barras tienen.** Con el ancho fijo de 8
  columnas, un rubro con 2 o 3 familias quedaba con las barras estiradísimas. Ahora
  `2*(barras-1)` columnas con tope de 8: 2 barras → 2 columnas, 3 → 4, 5 o más → 8. Esa
  fórmula reproduce exactamente los tres que Vale había angostado a mano (CALZADO, HOME y
  STATIONERY).
- **Bordes en las tablas que van como rango.** `writeDataTable` dibuja las líneas solo; un
  rango no. Faltaban en Nacionalidades y en Grabados, las dos que usan `add_plain_table()`.
  **Ojo con el orden**: el `addStyle` del borde tiene que ir *después* de los formatos de
  número, que se aplican sin `stack` y si no le borran el borde. La primera versión los
  puso antes y quedó con borde solo la columna sin formato numérico.
- El **anillo** de Grabados volvió a H4 y más chico (`H4:J10`): en J quedaba demasiado
  lejos y grande. Lo de "separarlo de la tabla" se resuelve achicándolo, no corriéndolo.

Queda una diferencia cosmética de una fila: el gráfico de STATIONERY termina en la 88 y el
de Vale en la 87. No se forzó la fórmula del alto por eso.

**Migrado a `CLAUDE.md`** (sección 7, "Reporte de ventas de Cuero"): que el reporte sale
listo y el único paso manual es EN PRODUCCIÓN, el armado en dos pasos, la tabla de colores
como fuente de verdad, los colores del formato condicional de CONDICION, el relleno de
subtotales y el parseo de los CSV de Tax free. También se corrigió ahí la descripción de la
regla del 80%: decía "para no sobrepasar" y en realidad el corte queda en el acumulado
**más cercano** al 80%, por arriba o por abajo.

**Estado al cierre:** `Reporte_ventas/Reporte_Ventas_CUERO_2026-08.xlsx` regenerado; sale
igual al FINAL de Vale salvo la columna EN PRODUCCIÓN. El FINAL que ella armó no se tocó.

---

## 2026-09-03 — el reporte de cuero sale en versión final, sin armado manual

**Qué se hizo:** el `.xlsx` que generaba el Rmd salía "crudo" y había que rearmarlo a mano
todos los meses para llegar al `... FINAL.xlsx`: mover tablas, ponerlas lado a lado, borrar
una tabla, armar 15 gráficos, pintar barras, completar columnas. Ahora sale listo. El único
paso manual que queda es "EN PRODUCCIÓN" en la hoja SKU, que viene de otra fuente.

El detalle de qué hace cada parte está en `CLAUDE.md`, sección 7. Acá queda el porqué.

### Layout: `Reporte_ventas_Odoo-CUERO.Rmd`

Constantes nuevas `FILA_TABLA_*` / `COL_MARRO_*`: cada hoja deja libre el bloque donde van
los gráficos, y esas posiciones son el único acoplamiento con `graficos_reporte_cuero.R`.

- **Se sacó `PROVEEDOR_EXTERNO_RUBROS_TOTAL`** de la hoja: se venía borrando a mano todos
  los meses. Su total se sigue calculando porque lo usa el título del gráfico.
- **`add_plain_table()`**, helper nuevo: igual que `add_formatted_table` pero como rango.
  Hace falta en Nacionalidades (Excel no admite encabezados repetidos dentro de una tabla,
  y ahí "Florida" aparece en unidades y en facturación) y en Grabados (tampoco admite
  celdas combinadas adentro). Por eso en los FINAL hechos a mano esas dos habían dejado de
  ser tablas: no era capricho, era que Excel no las deja.

### Gráficos: `graficos_reporte_cuero.R` (nuevo)

Va aparte y después de guardar el `.xlsx` porque **openxlsx no sabe hacer gráficos
nativos**. Se evaluó pegar imágenes de ggplot2 (no quedan editables ni vinculadas a las
celdas) y escribir el XML a mano (~200 líneas propias para mantener); se eligió reabrir el
archivo con `openxlsx2` e insertarlos con `mschart`. Paquetes nuevos: `openxlsx2` y
`mschart`. Se verificó que el round-trip `wb_load`/`wb_save` conserva las 26 tablas y todos
los estilos que había escrito openxlsx.

Trampas que costaron encontrar, por si vuelven a aparecer:

- `mschart` escribe `<c:externalData r:id="rId1"/>` en cada gráfico porque nació para Word
  y PowerPoint, donde los datos van en un libro embebido. Acá los datos están en la hoja,
  así que esa relación apuntaba a la nada y **Excel podía abrir el archivo pidiendo
  repararlo**. Se saca en `limpiar_external_data()`.
- `mschart` no tiene gráfico de anillo. Se genera una torta y se convierte a
  `doughnutChart` + `holeSize` parcheando el XML (`convertir_a_anillo()`).
- `mschart` pinta toda la serie de un color: para pintar cada barra del color que
  representa hay que inyectar los `<c:dPt>` a mano, entre `<c:invertIfNegative>` y
  `<c:dLbls>` (`pintar_puntos()`).
- El tema por defecto de `mschart` usa Arial 20 para el título y 18 para las etiquetas: en
  gráficos de este tamaño queda ilegible.
- **LibreOffice no dibuja las sparklines ni las tortas de un solo dato** al exportar a PDF.
  No es un defecto del archivo: el FINAL de julio hecho con Excel tampoco se renderiza. Las
  verificaciones visuales de esos dos hay que hacerlas abriendo el archivo con Excel.

Decisiones de criterio:

- Un gráfico por rubro sólo si el corte del 80% deja **2 o más familias**: con una barra
  sola no aporta.
- El eje de valores va oculto en **todos** los gráficos porque el % ya está en la etiqueta
  (decisión de Vale). En los FINAL viejos estaba oculto en unos y visible en otros.

### Bugs de datos encontrados en el camino

- **Tax free, importes divididos por mil.** Los CSV de Global Blue vienen a veces en formato
  argentino (`"72.960,00"`) y a veces estadounidense (`"118,930.00"`), y cambia de mes a mes
  sin aviso: 2026-04 y 2026-05 son AR, 2026-06 en adelante US. El parser los leía siempre
  con `locale(decimal_mark = ",")`, así que los meses en formato US quedaban 1000 veces más
  chicos — agosto daba $40.699 en vez de $40.699.293, con participación 0,0%. Se descartó
  fijar el locale por mes porque cambia sin aviso y habría que tocarlo cada vez.
- **Tax free, la fila de Güemes salía sin datos de venta.** El nombre de la tienda sale del
  nombre del archivo (`Guemes 2026_08.csv`) y Odoo usa "Güemes", así que el `right_join` no
  matcheaba. Se agregó `REVISAR_TIENDAS_TAX_FREE` con un `warning()` para que un nombre
  nuevo no vuelva a pasar en silencio. Ojo: el filtro `Tienda != "San Telmo2"` del Rmd hubo
  que actualizarlo al nombre normalizado.
- **Formato moneda que faltaba** en TAX FREE y en Valor stock: los dos por nombres de
  columna que no matcheaban ("Tax free" vs "Tax Free"; "FLORIDA" en mayúsculas vs los
  nombres reales del pivot). `safe_apply_format` no avisa cuando no encuentra la columna,
  simplemente no aplica nada. Valor stock ahora toma todas las columnas menos RUBRO con
  `setdiff()`, así sigue andando si cambian las tiendas.
- **CONDICION en blanco**: los códigos que no están en el Maestro se completaban a mano con
  "activo". El origen es que `fecha_maestro` apunta a agosto 2025, así que siempre faltan
  los productos nuevos. Ahora se completan solos.
- **Valor stock**: el `pivot_wider` dejaba una fila con `RUBRO = NA`, vacía y en cero,
  arriba del Total; había que borrarla a mano. Queda `REVISAR_STOCK_SIN_RUBRO` por si algún
  mes trae valores de verdad.
- **Los 7 umbrales de Pareto a mano** (`<= 0.80` / `0.81` / `0.85`) pasan a `es_top_80()`.
  Los umbrales dispares eran parches para compensar que la regla anterior se quedaba corta.
  Efecto en agosto: marro chica materiales pasa de 1 a 2 barras (era el que se veía raro),
  marro grande materiales de 3 a 4, marro chica colores de 7 a 8, nacionalidades de 6 a 7.

### Dos errores de los FINAL viejos que quedan resueltos solos

En `Reporte_Ventas_CUERO_2026-07 FINAL.xlsx`: el gráfico de proveedores apuntaba al archivo
de junio (`[1]Proveedores externos` — se copió el gráfico y quedó el vínculo externo), y en
SKU-familia la fila 13 tenía "Total MOCASINES HOMBRE" pisado por "Total BOTAS HOMBRE"
(1 / $229.990 en vez de 8 / $1.419.920).

### El 102% de San Telmo en "Participación Ext": se deja como está

No es un error de cálculo. El 72,3% de la venta de San Telmo en agosto ($30,4M de $42,0M)
tiene `NACIONALIDAD = DESCONOCIDA`. Como "Venta extranjeros" excluye ARGENTINA y
DESCONOCIDA, el denominador queda chico y el Tax free —que por definición es venta a
extranjeros— lo supera. El Tax free ($10,4M) entra cómodo dentro de extranjeros +
desconocida ($40,6M).

No es de este mes: el % de venta sin nacionalidad viene subiendo desde febrero en
**San Telmo** (16,3 → 26,3 → 25,5 → 33,6 → 41,4 → 55,5 → 72,3) y en **French**
(2,0 → 8,6 → 26,9 → 24,5 → 30,1 → 45,0 → 59,4). Florida y Recoleta la siguen cargando bien
(menos del 7%). Es lo mismo que hace que DESCONOCIDA encabece la hoja Nacionalidades con el
33,4% del total: no es un país, es el dato que falta.

Se evaluó cambiar el denominador a extranjeros + desconocida (daría 25,7% en San Telmo) y
agregar una columna "Venta sin nacionalidad", pero **Vale decidió dejarlo como está**: el
102% es incómodo pero es una señal honesta de que falta cargar el dato, y cambiar el
denominador subestimaría a las tiendas donde sí se carga. El arreglo de fondo es operativo,
en el punto de venta de San Telmo y French.

Pendiente menor sin mirar: Recoleta da −3,7% en junio 2026 (las notas de crédito sin
nacionalidad superaron a las ventas sin nacionalidad ese mes).

### Otra trampa: prioridad del formato condicional en openxlsx

En Excel gana la regla de **menor** número de prioridad, y openxlsx le asigna la prioridad
más alta a la **última** regla agregada. Hay que cargarlas al revés de como se leen
(primero la genérica, último "discontinuado"); si no, la genérica pinta todo de un color.
Está comentado en `formato_condicion()`. La especificación de los colores se reconstruyó
leyendo el `conditionalFormatting` de los FINAL de julio y junio: no estaba escrita en
ningún lado.

**Estado al cierre:** funcionando. Se corrió el Rmd completo sobre agosto y se verificó
contra el output anterior que las únicas diferencias fueran las buscadas; Modelos, Stock sin
ventas y AUX quedan idénticas. El archivo abre en Excel con los 15 gráficos.

## 2026-09-03

**Qué se hizo:** el chunk `le agrego los proveedores` dejó de leer y limpiar
`proveedores_odoo_LUCERO_AAAAMMDD.xlsx` a mano. Ahora `proveedores_odoo_LUCERO` sale de
`readRDS("Proveedores/proveedores_dedup.rds")` (lo genera `Proveedores_dedup.Rmd`, ver
bitácora [proveedores.md](proveedores.md)), que ya trae un `PROVEEDOR` por
`CODIGO_BARRAS` con las reglas aplicadas (SUCCESSFUL BOXES gana / C DE I se descarta /
correcciones manuales / familias de nombre).

- El `match(FACTURAS_MES2$CODIGO_BARRAS, ...)` y el override de OUTLET quedan igual.
- `REVISO_PROVEEDORES` ahora lee `proveedores_a_revisar.xlsx` si existe (los productos
  con >1 proveedor sin resolver); antes era un `summarise` que no se usaba aguas abajo.
- Nuevo control de frescura: `warning()` si el `.rds` es más viejo que el último export
  de Odoo → hay que correr `Proveedores_dedup.Rmd` primero.
- `fecha_proveedores` quedó comentada (ya no se usa).
- Se agregó el paso "Corro Proveedores_dedup.Rmd" a la lista de pasos del encabezado.

**Estado al cierre:** chunk probado en aislamiento (lee el rds, resuelve el match,
frescura OK). No se tejió el Rmd completo (faltan insumos del mes). Pendiente: hacer lo
mismo en los 3 reportes de joyería y en `Reporte_debutantes_joyeria.Rmd`.

### Tax free auto-ejecutable

El chunk de Tax free dejó de leer `Tax free/Tax free armado/Tax free_<mes>.xlsx` a mano
(antes había que correr `Tax_free_creacion_v2.Rmd` primero). Ahora:
`source("tax_free_creacion.R")` + `Tax_free <- crear_tax_free(mes)` con el **mismo `mes`
del reporte** — arma el consolidado desde los CSV, escribe el `.xlsx` y devuelve el df
tipado (se usa el return, no se re-lee). Ver [taxfree.md](taxfree.md). Único paso manual
que queda: dejar los CSV del mes en `Tax free/Tax free para armar/`. Probado con el
chunk aislado sobre agosto 2026 (252 filas tras el filtro Voided/fecha).

## 2026-07-15

**Qué se hizo:** reporte de ventas de cuero de junio 2026.

## 2026-06-03 / 2026-06-04

**Qué se hizo:** se adaptó el reporte para que San Telmo 2 funcione bien en mayo 2026,
mes en que vendió cuero **y** joyería. Se eliminaron duplicados en la lista de precios.

## 2026-05-22

**Qué se hizo:** los precios pasaron a matchear contra el stock por **código de referencia**
en lugar de por nombre de producto.

**Por qué:** los nombres no eran únicos ni estables.
