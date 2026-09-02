# Horas trabajadas

**Archivos:** `horas_desde_premios.R`
`PREMIOS TIENDAS 2026.xlsx` → `Horas trabajadas Tiendas desde 2025-09.xlsx`

Colaboradora: **Silvina** gestiona el Excel de horas.

---

## 2026-08-20

**Qué se hizo:** se creó el script para automatizar la tabla de horas de vendedoras por mes.

**Estado al cierre:** funcionando con fuzzy matching de nombres y 4 controles de validación
(bloques de tienda desconocidos, descuadre de totales, empleados sin número, duplicados de período).

---

## Recordatorio

La `tabla x hora` del Excel maestro es la **fuente de verdad histórica**: las correcciones
van ahí directamente, no en el script. Las variantes de nombre irresolubles se resuelven
en la hoja `alias` del Excel, no en código.
