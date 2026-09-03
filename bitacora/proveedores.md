# Proveedores por producto

**Archivos:** `Proveedores_dedup.Rmd`, `Proveedores_con_imagen.Rmd`

Entrada: `Proveedores/proveedores_odoo_LUCERO_AAAAMMDD.xlsx` (export Odoo, el Rmd toma
el más nuevo por nombre).

---

## 2026-09-03 — `Proveedores_con_imagen.Rmd`

**Qué se hizo:** Rmd nuevo. Lee `proveedores_dedup.rds`, filtra por `PROVEEDOR_FILTRO`
(default `PASSA DISEGNI S.R.L.`) y arma un Excel con una fila por producto (código
interno, el `[...]` del nombre) y la foto en la primera columna.

- Dedup por código interno: las variantes / códigos de barras se juntan en `COD_BARRAS`
  (+ `N_COD_BARRAS`).
- Imágenes: `imagenes/CODIGO_NOMBRE.jpg`, match por los dígitos iniciales del archivo
  (mismo criterio que los reportes de joyería: `str_extract(basename, "^\\d+")`,
  fallback a los primeros 6 dígitos). Helper `compress_img` (magick, 180px, q72) igual
  que en joyería. `insertImage` 0,65".
- `SIN_IMAGEN`: objeto + `message()` con los productos sin foto.
- Salida: `Proveedores/Productos_<slug del proveedor>.xlsx` (overwrite).
- Control de frescura del `.rds` igual que en los consumidores.

**Estado al cierre:** corrido para PASSA DISEGNI: 196 productos, 189 con foto, 7 sin
(102369, 102551, 102555, 102558, 104988, 106352, 106414). Para otro proveedor, cambiar
`PROVEEDOR_FILTRO`.

## 2026-09-03 — `Proveedores_dedup.Rmd`

**Qué se hizo:** nuevo `Proveedores_dedup.Rmd`. A partir del export de Odoo (código y
producto en blanco en las filas de proveedor adicional; se reconstruyen los bloques con
`cumsum(!is.na(producto))`) arma un dataset de **un proveedor por producto**.

**Unificación de nombres** (chunk `unificar-proveedor`, sobre el crudo, antes de
agrupar) — reemplaza lo que Vale hacía a mano en cada reporte:
- `str_squish`.
- `FAMILIAS_PROVEEDOR` (tibble patrón→canónico): todo lo que empiece con
  `SUCCESSFUL BOXES S.R.L...` o `PASSA DISEGNI S.R.L...` colapsa al canónico. Cubre las
  sucursales tras coma (`, PERDRIEL` / `, CHACO` / `, SD 2463`) y `SRL` sin puntos sin
  listarlas. No se usó un "borrar todo tras la coma" genérico porque
  `BILAVSKY, DARIO FABIAN` es Apellido, Nombre.
- `ALIAS_PROVEEDOR` (tibble de→a): vacío, para casos sueltos futuros.
- Paso genérico: colapsa variantes que difieren solo en punto final / espacios /
  mayúsculas; canónico = variante más frecuente. `REVISO_variantes_nombre` (hoy vacío).

**Filtro previo:** `EXCLUIR_SIN_CODIGO = TRUE` descarta toda fila sin código de barras
(en este export, 197: cuentas contables, servicios, insumos como cueros y cintas,
pseudo-productos de PdV). Quedan en `EXCLUIDOS_sin_codigo`, solo en memoria.

**Resolución cuando hay más de un proveedor:**
1. Si está `SUCCESSFUL BOXES S.R.L.` → se deja solo ese.
2. Si no, y está `C DE I INTERNACIONAL S.A.` → se descarta ese.
3. `CORRECCIONES_PROVEEDOR` (tibble en parámetros, key = código interno del `[...]`):
   fuerza el proveedor de casos puntuales. Hoy: `102617` (ANILLO INICIAL (2), 6
   variantes, estaban sin proveedor) → `MARIEL LINI`; `102502` (ARO PASANTE CRUZ, tenía
   PASSA + YIWU) → `YIWU QIRUI IMPORT AND EXPORT CO. LTD`.
4. Si sigue con más de uno → `REVISAR_proveedores` + `proveedores_a_revisar.xlsx` + un
   `message()` destacado. Solo aparecen los que las reglas **no** resolvieron y que
   **no** están en `CORRECCIONES_PROVEEDOR`; si todo se resuelve no hay aviso ni archivo.

**Salidas** (nombre fijo, se sobreescriben):
- `proveedores_dedup.rds` / `.xlsx`: **solo 3 columnas** `CODIGO_BARRAS`, `PRODUCTO`,
  `PROVEEDOR`, listo para el `match()` por `CODIGO_BARRAS` de
  `Reporte_ventas_Odoo-CUERO.Rmd`, `Reporte_ventas_Odoo-JOYERIA_*.Rmd` y
  `Reporte_debutantes_joyeria.Rmd`. `CRITERIO` / `N_PROVEEDORES_ORIGINAL` quedan solo
  en el objeto `dedup_full` para las tablas de control.
- `proveedores_a_revisar.xlsx` y `proveedores_sin_proveedor.xlsx`: solo si hay filas.
- `SIN_proveedor`: mercadería con código pero sin proveedor en Odoo. Hoy vacío.

**Estado al cierre:** funcionando sobre `proveedores_odoo_LUCERO_20260901.xlsx`. 6569
productos → 5392 proveedor único, 1022 por regla SUCCESSFUL BOXES, 148 por regla C DE I,
7 por corrección manual, 0 sin proveedor, **0 a revisar**. El `.xlsx` no siempre se
puede sobrescribir si está abierto en Excel (el `.rds` sí).

`Reporte_ventas_Odoo-CUERO.Rmd` ya lee este `.rds` (ver [cuero.md](cuero.md)). Falta lo
mismo en los 3 `Reporte_ventas_Odoo-JOYERIA_*.Rmd` y `Reporte_debutantes_joyeria.Rmd`, y
decidir el auto-disparo (refactor a `.R` + control de frescura).
