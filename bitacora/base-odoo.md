# Base Odoo (`df_base`)

**Archivos:** `Arreglo_base_Odoo_5.Rmd` → `Data/df_base.rds`

Pipeline upstream: arma el dataframe base de facturas que consumen el resto de los reportes.
Si algo se rompe acá, se rompe todo lo de abajo.

---

## 2026-08-19

**Qué se hizo:**
- Se corrigió la lectura de nombres de columnas: Odoo cambió el formato de exportación de facturas
  y los encabezados dejaron de coincidir.

**Estado al cierre:** funcionando con la exportación nueva.

## 2026-06-25

**Qué se hizo:** actualización del arreglo de base.

## 2026-07-16

**Qué se hizo:** se empezó a migrar el resto de los scripts para que consuman `df_base.rds`
en lugar de re-leer las exportaciones crudas.
