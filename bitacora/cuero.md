# Cuero — reportes de ventas

**Archivos:** `Reporte_ventas_Odoo-CUERO.Rmd`

---

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
