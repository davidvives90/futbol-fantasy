# Especificación: Liga Fantasy de mánagers (mercado, plantillas, alineaciones)

Decisiones del usuario (2026-11-19):
- Propiedad **compartida**: cualquier mánager puede fichar a cualquier jugador de la liga; no hay dueño único.
- **Autofichaje permitido**: un mánager puede tenerse a sí mismo en plantilla y alinearse.
- **No habitual** = automático por asistencia (más los miembros pre-creados sin cuenta).
- **Dinero** = presupuesto inicial igual para todos + ingreso por cada punto de la alineación.

Vocabulario: *mánager* = miembro activo de la liga que juega al Fantasy (todos los miembros activos lo son). *Jugador* = miembro de la liga que aparece en el mercado (activos y pre-creados; no expulsados). Moneda virtual: **M** (millones ficticios), dos decimales.

## 1. Encuesta inicial de valoración conjunta

- La abre un admin (`abrir_encuesta`). Cada mánager ordena a **todos** los jugadores de la liga en 6 rankings: `calidad`, `velocidad`, `resistencia`, `defensa`, `regate`, `portero` (1 = mejor).
- Conversión de posición a nota 0–100 para N jugadores: `s = 100 · (N − r) / (N − 1)`.
- La nota que un evaluador se pone a sí mismo **no cuenta**.
- Nota de cada atributo = media de las notas de los evaluadores; con ≥ 5 evaluadores, media recortada (sin la más alta ni la más baja).
- **Media general G (0–100)**:
  - Jugador de campo: `G = 0,35·calidad + 0,15·velocidad + 0,15·resistencia + 0,15·defensa + 0,20·regate`
  - Portero (`perfiles.posicion = 'portero'`): `G = 0,60·portero + 0,20·calidad + 0,20·resistencia`
- Se cierra cuando la cierra un admin (`cerrar_encuesta`), recomendado con ≥ 60 % de mánagers respondidos. Al cerrar: se guardan las valoraciones, se fijan precios iniciales y se abona el presupuesto inicial a cada mánager.
- Jugador que llega después: G = 50 hasta su primera mini-encuesta (el admin puede lanzar una encuesta solo para él: los mánagers indican en qué puesto del ranking existente lo colocarían) o hasta que juegue.
- Las valoraciones también alimentan el **generador de equipos** (resuelven el arranque en frío de jugadores sin historial).

## 2. Precio

Parámetros por liga (editables por admins): `precio_min = 1`, `precio_max = 12`, `max_plantilla = 6`, `bonus_no_habitual = 1,5`, `horas_cierre_alineacion = 2`, `ingreso_por_punto = 0,10`, `comision_venta = 0,05`, `k_encuesta = 5`, `max_variacion = 0,15`.

- **Precio base** a partir de un rating R (0–100): `base(R) = precio_min + (precio_max − precio_min) · (R/100)²`
  (cuadrático: las estrellas son claramente más caras). Ej.: R 50 → 3,75 M; R 90 → 9,91 M.
- **Precio inicial** = `base(G)`, redondeado a 0,05.
- **Presupuesto inicial** de cada mánager = `6,5 × precio medio inicial de la liga`, redondeado a 0,5 (permite una plantilla media completa con margen).
- **Rating dinámico** tras cada jornada: `R = w·G + (1 − w)·Rend`, con `w = k_encuesta / (k_encuesta + n)` y n = partidos jugados. **Si n < `partidos_min_rendimiento` (3), w = 1**: el rendimiento no cuenta y el precio solo varía por la demanda (decisión del usuario para evitar oscilaciones con pocos partidos).
  `Rend` = percentil (0–100) de su media de puntos Fantasy en sus últimos 5 partidos, entre los jugadores de la liga con ≥ 1 partido.
- **Demanda**: `d = plantillas que lo tienen / mánagers activos`; `d̄` = media de d en la liga. Factor `f = clamp(1 + 0,4·(d − d̄), 0,85, 1,25)`.
- **Precio nuevo** = `clamp(base(R)·f, precio_anterior·(1 − max_variacion), precio_anterior·(1 + max_variacion))`, acotado a [precio_min, precio_max], redondeado a 0,05. Se recalcula una vez por partido cerrado (jornada) y se guarda en el historial.

## 3. Mercado y plantillas

- Comprar al precio actual si hay saldo y hueco: máx `max_plantilla` (6) jugadores, máx **1 no habitual** por plantilla.
- Vender al precio actual menos la comisión (5 %).
- El saldo nunca puede quedar negativo.
- El mercado se **cierra** desde `fecha_hora − horas_cierre_alineacion` del próximo partido hasta que ese partido queda cerrado (puntos calculados), para que nadie fiche con información del resultado ni antes de que cambien los precios.

## 4. No habitual (bonificación ×1,5)

- Es no habitual quien ha jugado **menos del 40 % de los últimos 10 partidos cerrados** de la liga, y cualquier miembro pre-creado que aún no se ha registrado.
- Mientras la liga tenga menos de 5 partidos cerrados, solo cuentan los pre-creados sin cuenta (no hay historial para juzgar asistencia).
- El estado se **congela** en cada alineación al cerrarse: si después pasa a habitual, ese partido sigue valiendo ×1,5.

## 5. Alineación

- Tamaño = **media plantilla del partido** = `partidos.plazas / partidos.num_equipos` (5 en un 5 contra 5). Se alinean como máximo ese número de jugadores de la propia plantilla (con 6 en plantilla, uno queda fuera).
- Se puede cambiar hasta `fecha_hora − 2 h`; después queda bloqueada (lo valida la base de datos).
- La app muestra junto a cada jugador si está confirmado en la convocatoria: un alineado que no juega puntúa 0, así que conviene revisarla antes del cierre.
- Si un mánager no guarda alineación, se copia automáticamente la del partido anterior (solo jugadores que sigan en su plantilla, hasta el tamaño permitido).

## 6. Liquidación de la jornada (al cerrar el partido)

Se ejecuta al final de `calcular_puntos`:
1. Puntos del mánager = `Σ puntos_fantasy.total(jugador) × (bonus_no_habitual si era no habitual al cierre, si no 1)`; los alineados que no jugaron suman 0.
2. Ingreso = `max(puntos, 0) × ingreso_por_punto` M, abonado al saldo.
3. Recalcular ratings y precios (sección 2) y guardar historial.
4. Reabrir el mercado.

## 7. Clasificación de mánagers

Puntos totales acumulados; desempate por valor de plantilla + saldo. Además: puntos por jornada, mejor alineación de la jornada, jugador más fichado.

## 8. Modelo de datos (nuevas tablas, migración 0008_mercado_fantasy.sql)

- Columnas nuevas en `ligas`: `precio_min, precio_max, max_plantilla, bonus_no_habitual, horas_cierre_alineacion, ingreso_por_punto, comision_venta, k_encuesta, max_variacion`.
- `encuestas_valoracion(id, liga_id, sujeto_id null = encuesta general | miembro para mini-encuesta, estado abierta|cerrada, creada_en, cerrada_en)`
- `respuestas_ranking(encuesta_id, evaluador_id, atributo, miembro_id, posicion)`, PK `(encuesta_id, evaluador_id, atributo, miembro_id)`; privadas (nadie lee las de otro).
- `valoracion_jugador(liga_id, miembro_id, calidad, velocidad, resistencia, defensa, regate, portero, general, num_evaluadores, actualizado_en)`
- `mercado_jugador(liga_id, miembro_id, precio, rating, no_habitual, actualizado_en)`; `historial_precios(liga_id, miembro_id, partido_id, precio, rating, demanda, creado_en)`
- `fantasy_managers(liga_id, miembro_id, saldo, puntos_totales)`
- `plantillas(liga_id, manager_id, jugador_id, precio_compra, comprado_en)`, PK `(manager_id, jugador_id)`
- `transacciones_fantasy(id, liga_id, manager_id, jugador_id, partido_id, tipo presupuesto_inicial|compra|venta|ingreso_puntos|ajuste, importe, saldo_despues, creado_en)`
- `alineaciones(partido_id, manager_id, jugador_id, no_habitual, multiplicador)`, PK `(partido_id, manager_id, jugador_id)`
- `puntos_manager(partido_id, manager_id, puntos, ingreso, desglose jsonb)`
- RPC: `abrir_encuesta`, `enviar_ranking(p_encuesta, p_atributo, p_orden uuid[])`, `cerrar_encuesta`, `comprar_jugador(p_liga, p_jugador)`, `vender_jugador(p_liga, p_jugador)`, `guardar_alineacion(p_partido, p_jugadores uuid[])`, `mercado_abierto(p_liga)`, `liquidar_jornada(p_partido)`, `recalcular_precios(p_liga, p_partido)`.
- Vistas: `v_mercado` (precio, variación última jornada, % de plantillas que lo tienen, no habitual, rating), `v_clasificacion_managers`, `v_mi_plantilla`.

---

# 9. AMPLIACIÓN (2026-11-19): fichas limitadas, cláusulas, ofertas y cesiones

Decisiones del usuario: **copias limitadas** (sustituye a la propiedad compartida ilimitada), **cláusula libre con coste**, **cesión con % que pone el dueño**, rendimiento en el precio solo desde 3 partidos. Esta sección **prevalece** sobre las secciones 3 y 8 donde choquen.

## 9.1 Fichas (copias limitadas)
- Cada jugador del mercado tiene `C` fichas: `C = max(2, ceil(M · max_plantilla · 0,8 / P))`, M = mánagers activos, P = jugadores en el mercado. Ej.: 14 mánagers, 14 jugadores, plantilla 6 → C = 5.
- C se calcula al cerrar la encuesta y se **recalcula solo al alza** cuando entran mánagers o jugadores (nunca se quitan fichas con dueño).
- Una ficha está **libre** (en el mercado) o tiene **un propietario**. Un mánager no puede tener dos fichas del mismo jugador.
- La tabla `plantillas` se sustituye por `fichas`. "Plantilla" = fichas propias + como máximo 1 ficha recibida en cesión esa jornada (la cedida ocupa una plaza extra: 6 + 1).
- Demanda para el precio: `d = fichas con dueño / C`.

## 9.2 Comprar y vender
- **Comprar ficha libre** al precio de mercado (igual que antes). La cláusula inicial = precio pagado.
- **Vender al mercado**: la ficha vuelve a estar libre; el vendedor cobra precio − 5 %.
- Si no quedan fichas libres, el jugador solo se consigue por **cláusula** o por **oferta**.

## 9.3 Cláusula de rescisión
- Cada ficha con dueño tiene una cláusula pública, siempre ≥ valor de mercado (si el valor sube por encima, la cláusula sube automáticamente al valor).
- El dueño puede **subirla** cuando quiera pagando `coste_subida_clausula` (10 %) de la subida; **bajarla** es gratis (hasta el valor de mercado).
- **Pagar la cláusula**: cualquier mánager con hueco y saldo se lleva la ficha al instante pagando la cláusula íntegra al dueño, sin que este pueda negarse.
- **Protección**: una ficha recién adquirida (compra, cláusula u oferta) no se puede clausular hasta que se cierre el siguiente partido (`proteccion_jornadas` = 1).
- Solo con el mercado abierto. No se puede clausular una ficha que está cedida esa jornada.

## 9.4 Ofertas negociadas
- Un mánager hace una oferta por una ficha concreta (importe libre, puede ser menor que la cláusula). Estados: `pendiente → aceptada | rechazada | cancelada | caducada`.
- El dueño acepta o rechaza; el comprador puede cancelarla. Caduca a las 48 h o al cerrarse el mercado.
- Al aceptar se vuelven a validar saldo, hueco, límite de no habituales y que la ficha siga siendo del mismo dueño; el dinero no se reserva al ofertar. Al aceptarse una oferta, las demás pendientes por esa ficha se cancelan.
- Contraoferta = el comprador envía una oferta nueva.

## 9.5 Cesión (1 por jornada)
- Cada mánager puede **ceder como máximo 1 ficha por jornada** y **recibir como máximo 1**.
- El dueño publica una ficha como cedible para el próximo partido con un % que fija él, entre `cesion_pct_min` (5 %) y `cesion_pct_max` (30 %) del valor de mercado.
- Otro mánager la acepta pagando `pct × valor` al dueño. Esa jornada el jugador está en la plantilla del receptor (plaza extra) y solo él puede alinearlo; el dueño no. Cuenta para el límite de 1 no habitual del receptor.
- La cesión debe cerrarse antes del cierre de alineaciones. Mientras dura, la ficha no se puede vender, clausular ni ofertar. Vuelve sola al dueño al liquidar la jornada.
- El dueño puede retirar la oferta de cesión mientras nadie la haya aceptado.

## 9.6 Parámetros nuevos en `ligas`
`copias_por_jugador` (calculado), `coste_subida_clausula` 0,10, `proteccion_jornadas` 1, `cesion_pct_min` 0,05, `cesion_pct_max` 0,30, `horas_caducidad_oferta` 48, `partidos_min_rendimiento` 3.

## 9.7 Modelo de datos y RPC (sustituye a `plantillas`, `comprar_jugador`, `vender_jugador`)
- `fichas(id, liga_id, jugador_id, numero, propietario_id null, clausula, precio_compra, adquirida_en, protegida_hasta_partido_id)`; único `(propietario_id, jugador_id)` cuando hay dueño.
- `ofertas(id, liga_id, ficha_id, comprador_id, vendedor_id, importe, estado, creada_en, expira_en, resuelta_en)`
- `cesiones(id, liga_id, ficha_id, propietario_id, cesionario_id null, partido_id, pct, importe, estado ofrecida|aceptada|finalizada|cancelada, creada_en)`
- `transacciones_fantasy.tipo` añade: `clausula_pagada`, `clausula_cobrada`, `subida_clausula`, `oferta_pagada`, `oferta_cobrada`, `cesion_pagada`, `cesion_cobrada`.
- RPC: `comprar_ficha(p_liga, p_jugador)`, `vender_ficha(p_ficha)`, `fijar_clausula(p_ficha, p_importe)`, `pagar_clausula(p_ficha)`, `hacer_oferta(p_ficha, p_importe)`, `responder_oferta(p_oferta, p_aceptar)`, `cancelar_oferta(p_oferta)`, `ofrecer_cesion(p_ficha, p_pct)`, `aceptar_cesion(p_cesion)`, `cancelar_cesion(p_cesion)`.
- Vistas: `v_mercado` añade `fichas_totales`, `fichas_libres`, `clausula_minima` (la más barata entre las fichas clausulables); `v_fichas_jugador(jugador)` con dueño, cláusula, protegida, cedida; `v_mis_ofertas` (enviadas y recibidas); `v_cesiones_disponibles`; `v_mi_plantilla` incluye la cedida con marca `cedida_a_mi`.
- RLS: cláusulas y dueños de fichas visibles para la liga (necesario para clausular); ofertas solo para comprador y vendedor; cesiones ofrecidas visibles para toda la liga.
- `guardar_alineacion`: permite fichas propias no cedidas + la cedida a mí esa jornada.
- `liquidar_jornada`: puntos de la ficha cedida para el receptor; finaliza cesiones; caduca ofertas vencidas; recalcula C si procede.

---

# 10. AMPLIACIÓN (2026-11-19): posiciones flexibles y roles en la alineación

Contexto del usuario: no hay portero fijo, todos rotan y a todos les pueden marcar. La posición solo debe existir para formar la alineación, y se valora que el rol elegido dé algo de puntos. Esta sección **prevalece** sobre lo anterior donde choque (incluida la puntuación por posición de `docs/puntuacion_fantasy.md`).

## 10.1 Puntos del partido real: neutros respecto a la posición
- Se eliminan `gol_portero`, `gol_defensa`, `gol_medio`, `gol_delantero`, `porteria_cero_portero`, `porteria_cero_defensa`, `goles_encajados_3` y la columna/flag `puntuar_por_posicion`. Un gol vale `gol` = **5** para todos (punto medio entre 4 y 6 de MARCA).
- `perfiles.posicion` pasa a ser solo "posición preferida" (informativa). `reglas_puntuacion.posicion` deja de usarse (se puede eliminar la columna).
- Paradas clave y penaltis parados/fallados se pueden reportar para **cualquier** jugador (quien estuvo de portero un rato). Siguen puntuando igual para todos (`parada_clave_2` +1 por cada 2, `penalti_parado` +3, `penalti_fallado` −2).
- Aspectos de valoración iguales para todos: ataque, defensa, pase_vision, esfuerzo, juego_limpio. El aspecto `porteria` se desactiva por defecto (configurable; si una liga lo activa, aplica a todos).
- Encuesta: el ranking `portero` se mantiene (habilidad bajo palos). Media general única: `G = 0,30·calidad + 0,15·velocidad + 0,15·resistencia + 0,15·defensa + 0,15·regate + 0,10·portero`.
- Balanceo de equipos: se elimina la penalización por porteros; opcionalmente equilibrar también la suma del atributo `portero` entre equipos (peso pequeño).

## 10.2 Roles en la alineación Fantasy
- Al guardar la alineación el mánager asigna a cada jugador un rol: `POR` (exactamente 1), `DEF`, `MED`, `DEL` (reparto libre). La app la dibuja como un campo con esa formación.
- `ligas.bonus_roles` (bool, por defecto **true**). Si es false, el rol es solo estético.
- Bonus de rol (se suman a los puntos del jugador SOLO para ese mánager; claves en `reglas_puntuacion`, editables):
  | Clave | Rol | Puntos | Cuándo |
  |---|---|---|---|
  | `rol_por_porteria_cero` | POR | +3 | su equipo real no encajó en todo el partido |
  | `rol_por_menos_goleado` | POR | +2 | su equipo fue el menos goleado del partido (empate: todos los empatados) |
  | `rol_por_encajados_3` | POR | −1 | por cada 3 goles que encajó su equipo |
  | `rol_def_menos_goleado` | DEF | +1 | su equipo fue el menos goleado |
  | `rol_med_asistencia` | MED | +1 | por cada asistencia (extra) |
  | `rol_del_gol` | DEL | +1 | por cada gol (extra) |
- "Goles encajados del equipo" = suma de goles en contra de su `convocatorias.equipo` en todos los `encuentros` del partido. Con 3–4 equipos, "menos goleado" compara la media de goles encajados por encuentro jugado.
- Puntos del mánager por jugador = `(puntos_fantasy.total + bonus_rol) × multiplicador_no_habitual`.
- `alineaciones` añade `rol` (enum `POR|DEF|MED|DEL`) y `bonus_rol`; `puntos_manager.desglose` incluye el bonus por jugador.
- `guardar_alineacion(p_partido, p_jugadores uuid[], p_roles text[])` valida exactamente 1 POR (si la alineación tiene ≥ 1 jugador).
- La alineación copiada automáticamente conserva los roles; si el portero copiado ya no está, el primero pasa a POR.
