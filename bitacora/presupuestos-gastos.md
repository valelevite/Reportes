# Presupuestos y gastos

**Archivos:** `Presupuestos_v7.Rmd`, `Reporte_gastos_v3.Rmd`, `sueldos_para_gastos_v3.qmd`

Van juntos en un mismo archivo de bitácora porque en la práctica siempre se trabajan
en la misma sesión (armar el presupuesto del mes implica cerrar los gastos del mes).

---

## 2026-08-16

**Qué se hizo:** presupuesto de julio 2026 cerrado.

**Estado al cierre:** julio 2026 completo.

## 2026-08-12 / 2026-08-13

**Qué se hizo:** actualización de archivos para el nuevo presupuesto y el reporte de gastos
mensual de julio 2026. Carga de gastos.

## 2026-07-29

**Qué se hizo:** presupuesto y reporte de gastos de junio 2026 terminados.

---

## Pendiente

Los **refactors de v7** siguen sin empezar. La lista completa está en `CLAUDE.md`
(centralizar parámetros hardcodeados, diccionario de tiendas, `pivot_longer` en vez del
loop de 9 iteraciones, `map_dfr` para carga mensual, convertir `REVISO_*` en `message()`).
No tocar hasta que se decida avanzar.
