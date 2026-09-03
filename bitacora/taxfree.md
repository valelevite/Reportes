# Tax free

**Archivos:** `tax_free_creacion.R`, `Tax_free_creacion_v2.Rmd`,
`Tax_free_cruce_con_Alegra_v2.Rmd`, `Tax_free_supervisoras_v2.Rmd`,
`descarga_taxfree_ic2.R`

---

## 2026-09-03

**Qué se hizo:** la lógica de armado del consolidado mensual se movió de
`Tax_free_creacion_v2.Rmd` a **`tax_free_creacion.R`**, función `crear_tax_free(mes)`:
lee los CSV de `Tax free/Tax free para armar/*_<mes_arch>.csv`, arma el df, escribe
`Tax free/Tax free armado/Tax free_<mes>.xlsx` y **devuelve el df ya tipado** (fechas
`Date`, montos `numeric`).

- `Tax_free_creacion_v2.Rmd` quedó como cáscara (setea `mes`, `source()` + llamada).
  Sigue sirviendo para armar el Tax free sin correr un reporte de ventas.
- `Reporte_ventas_Odoo-CUERO.Rmd` ahora hace `source("tax_free_creacion.R")` +
  `crear_tax_free(mes)` con **su propio `mes`** → no se pueden desincronizar los meses.
  Usa el df que devuelve la función, no re-lee el `.xlsx`. Ver [cuero.md](cuero.md).
- Se mantiene la salida `.xlsx` (no `.rds`): el reporte ya recibe el df tipado del
  return, y el `.xlsx` lo sigue leyendo `Reporte_ventas/Reporte_ventas_9.Rmd` y sirve
  para mirarlo a mano. La escritura del `.xlsx` es no-fatal (`warning()` si está abierto
  en Excel).
- Si no hay CSV para el mes, `crear_tax_free()` corta con `stop()` y mensaje claro.

**Estado al cierre:** probado con `mes = "2026-08"` (254 filas, 5 tiendas, tipos OK).
Falta: mismo cambio en `Reporte_ventas/Reporte_ventas_9.Rmd` si se quiere que también
use la función.

## 2026-07-02

**Qué se hizo:** se creó un Rmd para intentar automatizar las descargas de CSV de tax free.

**Estado al cierre:** a medias.

## 2026-06-03

**Qué se hizo:** descarga del tax free de mayo 2026.

---

## Pendiente

La automatización de la descarga de CSV quedó sin terminar.
