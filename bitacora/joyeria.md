# Joyería — reportes de ventas

**Archivos:** `Reporte_ventas_Odoo-JOYERIA_historico.Rmd`,
`Reporte_ventas_Odoo-JOYERIA_nuevo_modelo_v2.Rmd`, `Reporte_debutantes_joyeria.Rmd`,
`Joyeria_sin_venta.Rmd`

---

## 2026-08-27

**Qué se hizo:** actualización del reporte histórico de joyería.

## 2026-08-20

**Qué se hizo:** reporte de joyería sin venta.

## 2026-08-19

**Qué se hizo:** nuevo reporte quincenal de debutantes.

## 2026-06-01

**Qué se hizo:** se agregó San Telmo 2 al reporte, imágenes en las hojas Familias y Modelos,
y la hoja de método de pago.

**Por qué:** San Telmo 2 pasó de vender cuero a vender joyería.

---

## Decisiones que ya están asentadas en CLAUDE.md

- Matching de imágenes por **ID de Odoo**, no por nombre de producto.
- `PROVEEDOR_SUBFAMILIAS` ya calcula participación dentro de cada familia — no recalcular.
- D/S usa `dias_periodo` calculado, no `*30` fijo.
- `IMG_PT`, `IMG_IN`, `img_lookup` van en el chunk `helpers`, no en el chunk SKU
  (Familias y Modelos los usan antes).
