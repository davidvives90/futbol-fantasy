# Backend Supabase · Fútbol Fantasy Amigos

## Orden de aplicación

En el SQL Editor de Supabase (o `supabase db push` con la CLI), en este orden:

| Fichero | Contenido |
| --- | --- |
| `migrations/0001_tipos_tablas.sql` | Tipos y tablas: perfiles, ligas, miembros, partidos, encuentros, convocatorias, facturas, movimientos, acta_jugador, reglas_puntuacion, puntos_fantasy |
| `migrations/0002_ligas_funciones.sql` | Ayudantes RLS (`mi_miembro`, `es_admin`…), `crear_liga`, invitaciones (`precrear_jugadores`, `enlaces_invitacion`, `unirse`, `regenerar_codigo`), buscador y solicitudes, `cambiar_rol`, `expulsar`, `abandonar_liga`, `crear_partido` |
| `migrations/0003_convocatoria_caja.sql` | Triggers de cupo y lista de espera, `guardar_equipos`, `definir_encuentros`, `generar_cargos`, `registrar_pago`, vistas `v_saldos`, `v_pagos_partido` |
| `migrations/0004_post_partido_consenso.sql` | Partes de jugadores, valoraciones por aspectos, disputas, `consenso`, `consolidar_acta`, `marcar_jugado`, `cerrar_post_partido`, `resolver_disputa`, `cerrar_ventanas_vencidas`, vistas de progreso, descuadres y fiabilidad |
| `migrations/0005_puntos_vistas.sql` | `calcular_puntos` (por posición, nota recortada, MVP) y vistas `v_rendimiento`, `v_clasificacion`, `v_pichichi`, `v_historial_jugador`, `v_notas_aspecto` |
| `migrations/0006_rls.sql` | RLS de todas las tablas, permisos por columna, bucket privado `facturas` y sus políticas |
| `migrations/0007_seed_reglas.sql` | `sembrar_liga_defecto`: reglas de puntuación y aspectos de valoración de cada liga nueva |
| `migrations/0008_mercado_fantasy.sql` | Liga Fantasy de mánagers (contrato: `docs/mercado_fantasy.md`): parámetros del mercado en `ligas`, encuesta inicial (`abrir_encuesta`, `enviar_ranking`, `cerrar_encuesta`), precios (`precio_base`, `recalcular_precios`), mercado (`comprar_jugador`, `vender_jugador`, `mercado_abierto`), alineaciones (`guardar_alineacion`, `congelar_alineaciones`, `congelar_alineaciones_vencidas`), `liquidar_jornada` (trigger al cerrar el partido) y vistas `v_mercado`, `v_mi_plantilla`, `v_clasificacion_managers`, `v_jornada_managers`, `v_progreso_encuesta`, `v_rating_balanceo` |
| `migrations/0009_mercado_rls.sql` | RLS y permisos de las tablas y funciones del mercado |

Después, en Supabase:

```sql
alter publication supabase_realtime add table convocatorias, partidos, encuentros, disputas;
-- con la extensión pg_cron activada:
select cron.schedule('cerrar-post-partido', '*/15 * * * *', 'select cerrar_ventanas_vencidas()');
select cron.schedule('congelar-alineaciones', '*/15 * * * *', 'select congelar_alineaciones_vencidas()');
```

`tests/00_stubs.sql` **no** se aplica en Supabase: imita `auth.uid()`, `storage.*` y los roles para probar fuera.

## Ciclo de un partido

```
abierto ⇄ completo ──guardar_equipos──▶ equipos_hechos ──marcar_jugado──▶ post_partido (N horas)
   ──cerrar_post_partido──▶ consolidar_acta ─┬─ sin disputas ─▶ calcular_puntos ─▶ cerrado
                                             └─ con disputas ─▶ en_revision ──resolver_disputa×N──▶ cerrado
```

## Consenso post-partido

- Cada asistente (y cualquier admin) envía su parte: `reportes_encuentro` (resultado de cada encuentro) y `reportes_jugador` (goles, asistencias, autogoles, paradas, penaltis de cada jugador; `null` = no lo sé). El acta del admin es un parte más.
- `consolidar_acta` toma la **moda** de cada campo (empate de modas → mediana redondeada; paradas → mediana). Confianza = % de partes que coinciden.
- Disputa si: resultado con < 3 partes o confianza < 60 %; dato de jugador indicado por solo 1-2 partes y distinto de 0; o ≥ 3 partes con confianza < 60 %. Paradas solo exigen corroboración.
- Portería a cero y goles encajados se deducen del resultado consolidado, no se reportan.
- El admin resuelve cada disputa con `resolver_disputa(id, valor)`; su valor prevalece en recálculos. Al resolver la última se calculan los puntos.
- `v_fiabilidad` mide el % de acierto de cada reportero (TODO: ponderar votos con ella).
- Valoraciones: notas 1-10 por aspecto (`aspectos_valoracion`, configurables; `porteria` solo porteros, `ataque` solo jugadores de campo). Anónimas: nadie, ni los admins, lee votos ajenos; solo se publican medias en `puntos_fantasy`.

## Mercado Fantasy (0008–0009)

Especificación completa en `docs/mercado_fantasy.md`. Resumen de funcionamiento y de las decisiones tomadas donde la especificación dejaba margen:

- **Encuesta inicial**: un admin la abre; cada mánager envía con `enviar_ranking(encuesta, atributo, orden[])` el orden completo de los jugadores (activos + pre-creados) en `calidad`, `velocidad`, `resistencia`, `defensa`, `regate` y `portero`. Se valida que sea una permutación completa sin repetidos. `cerrar_encuesta` calcula notas 0–100 (sin autoevaluación, media recortada con ≥ 5 evaluadores), G por posición, precios iniciales (`1 + 11·(G/100)²`, redondeo 0,05), el presupuesto (6,5 × precio medio, redondeo 0,5) y da de alta a los mánagers. La encuesta general solo se hace una vez; para jugadores nuevos hay mini-encuestas (`abrir_encuesta(liga, sujeto)`), que solo fijan precio si aún no ha jugado. Quien llega después entra al mercado con G = 50 (trigger en `miembros`) y los mánagers nuevos reciben el presupuesto inicial en su primera operación.
- **Mercado**: `comprar_jugador` / `vender_jugador` con bloqueo de la fila del mánager; máx. 6 por plantilla y 1 no habitual (solo bloquea compras: si un jugador pasa a no habitual estando ya fichado, no se obliga a venderlo); venta = precio × (1 − comisión) redondeado a céntimos. Cerrado sin encuesta cerrada o si algún partido no cerrado/cancelado ya pasó su hora de cierre (un partido olvidado bloquea el mercado hasta que un admin lo cierra o cancela).
- **Alineaciones**: `guardar_alineacion` admite hasta `plazas / num_equipos` jugadores de la propia plantilla (también menos) hasta 2 h antes. La **congelación** (copia de la alineación anterior a quien no guardó y fijación de no habitual / multiplicador) la hace `congelar_alineaciones`, idempotente, llamada por la tarea programada, por `recalcular_precios` y por `liquidar_jornada`. Como el estado no habitual solo cambia en `recalcular_precios`, que congela antes, el valor congelado es el vigente a la hora de cierre aunque no haya pg_cron. No se congela desde comprar/vender porque esas llamadas fallan con el mercado cerrado y la congelación se desharía.
- **Liquidación**: trigger `t_liquidar_jornada` cuando un partido pasa a `cerrado` (final de `calcular_puntos`). Idempotente (`partidos.jornada_liquidada`; `recalcular_precios` no repite una jornada con historial). Puntos = Σ total × multiplicador; ingreso = máx(puntos, 0) × 0,10 M. Todos los mánagers reciben fila en `puntos_manager` (0 si no alinearon).
- **Precios**: rating `R = w·G + (1 − w)·Rend` con `w = 5 / (5 + n)`; Rend = percentil de la media de puntos de los últimos 5 partidos; demanda acotada a [0,85, 1,25]; variación máx. ±15 % (el redondeo a 0,05 nunca se salta el tope).
- **Privacidad**: rankings de la encuesta privados (ni los admins ven los ajenos); plantillas privadas (las rivales se ven por sus alineaciones tras el cierre y en agregado en `v_mercado`); alineaciones ajenas visibles desde la hora de cierre; saldo y puntos de cada mánager visibles para toda la liga; transacciones solo propias (y admins).
- **Balanceo**: `v_rating_balanceo.rating` = rating dinámico del mercado, o la nota de la encuesta, o 50.

## Probar en local

Requiere PostgreSQL 15+ (se ha probado con 16).

```bash
# cluster temporal (como usuario sin privilegios, p. ej. postgres)
initdb -D /tmp/pgd -U postgres -A trust
pg_ctl -D /tmp/pgd -o "-k /tmp -c listen_addresses=''" -l /tmp/pgd/pg.log start

PGHOST=/tmp PGUSER=postgres bash tests/run.sh   # crea ff_test, aplica todo y ejecuta el escenario

pg_ctl -D /tmp/pgd stop
```

`tests/escenario.sql` ejecuta 90 comprobaciones como usuarios reales (rol `authenticated` con RLS): liga, invitaciones, buscador, admins, lista de espera, equipos, factura y cargos, partes con desacuerdos, disputa, puntos, clasificación, caja y expulsión. Termina con `ESCENARIO COMPLETADO SIN ERRORES`.

`tests/escenario_mercado.sql` (79 comprobaciones) crea otra liga con 12 mánagers y 2 pre-creados: encuesta con un voto atípico neutralizado por la media recortada, precios comprobados a mano (12,00 · 11,35 · 4,20 · 1,00 M; presupuesto 31,5 M), compras y ventas con sus errores (sin saldo, plantilla llena, 2 no habituales, repetido, mercado cerrado), alineaciones (tamaño, plantilla, fuera de plazo, visibilidad), partido completo hasta la liquidación (×1,5 del no habitual, ingresos), precios recalculados con tope del 15 %, idempotencia, jugador nuevo con mini-encuesta y copia automática de la alineación anterior. Termina con `ESCENARIO MERCADO COMPLETADO SIN ERRORES`.

## Despliegue en producción (19-11-2026)

Proyecto Supabase `wyybdsxnmxgfntyrzjmq` (PostgreSQL 17). Aplicadas, en este orden: 0001–0009 (copia exacta en `desplegado_v01/`), `0100_supabase_plataforma` (bucket `facturas`, Realtime en convocatorias/partidos/encuentros/disputas, endurecimiento de permisos, pg_cron: `ff_cerrar_ventanas` cada 15 min y `ff_congelar_alineaciones` cada 5 min) y `0101_endurecer_funciones`. Verificado: 26 tablas, 16 vistas, 67 funciones (igual que en local), todas las tablas con RLS.
Las siguientes versiones deben ser **aditivas**: no modificar los ficheros ya desplegados.

## Ampliación 0.2 (0010–0014, sin desplegar)

Aditivas sobre producción (no tocan `desplegado_v01/`). Orden: `0010_posiciones_flexibles` → `0011_fichas_clausulas` → `0012_ofertas_cesiones` → `0013_roles_alineacion` → `0014_ampliacion_seguridad`.

- **0010 · Posiciones flexibles**: gol = 5 para todos; se borran las reglas por posición (`gol_portero`…, `porteria_cero_*`, `goles_encajados_3`); `puntuar_por_posicion` queda obsoleta (false); aspecto Portería desactivado y todos con `aplica_a = 'todos'`; media de la encuesta única (portero 10 %); reglas `rol_*` y `ligas.bonus_roles`.
- **0011 · Fichas y cláusulas**: tabla `fichas` (C por jugador, C = max(2, ⌈M·max_plantilla·0,8/P⌉), solo crece); la tabla `plantillas` pasa a ser una vista sobre las fichas con dueño (los datos 0.1 se migran: cada plantilla → una ficha con cláusula = max(precio de compra, valor)). RPC `comprar_ficha`, `vender_ficha`, `fijar_clausula`, `pagar_clausula`; `comprar_jugador`/`vender_jugador` quedan como envoltorios.
- **0012 · Ofertas y cesiones**: tablas `ofertas`, `cesiones`; RPC `hacer_oferta`, `responder_oferta`, `cancelar_oferta`, `ofrecer_cesion`, `aceptar_cesion`, `cancelar_cesion`.
- **0013 · Roles y liquidación**: `alineaciones.rol` (POR/DEF/MED/DEL) y `bonus_rol`; `guardar_alineacion(p_partido, p_jugadores, p_roles default null)`; bonus de rol en la liquidación; cesiones que vuelven; protección −1 por jornada; precios con demanda = fichas con dueño / C y sin rendimiento hasta `partidos_min_rendimiento` (3).
- **0014 · Seguridad**: RLS de fichas/ofertas/cesiones, permisos de vistas y funciones (en Supabase lo nuevo recibe permisos por defecto: aquí se revocan las internas).

Decisiones: dueños y cláusulas de las fichas son visibles para toda la liga (necesario para clausular), así que las plantillas ya no son privadas; las ofertas solo las ven comprador y vendedor. Al cerrar las alineaciones (= cierre del mercado) caducan las ofertas pendientes y se retiran las cesiones sin aceptar. El bonus de rol solo cuenta si el jugador jugó y se multiplica por el ×1,5. "Menos goleado" = menor media de goles encajados por encuentro (empates: todos). Una oferta caducada al responder devuelve `'caducada'` sin error.

`tests/run.sh` reproduce producción: stubs + `desplegado_v01/` + `plataforma/0101` → escenarios 0.1 (dejan datos) → permisos por defecto de Supabase → 0010+ → `escenario_ampliacion.sql` (incluye la migración de los datos 0.1).

Versión 0.2 desplegada el 19-11-2026: 0010–0014 (copia exacta en `desplegado_v02/`). Verificado: 28 tablas, 20 vistas, 92 funciones, todas las tablas con RLS, ninguna función ejecutable por anon.

## v0.3 (0015–0019, sin desplegar)

Contrato: `docs/v03_liga.md` (y la sección v0.3 de `docs/contrato_app_backend.md`). Aditivas sobre producción (0001–0014): no tocan `desplegado_v01/` ni `desplegado_v02/`. Orden: `0015_rangos_espera` → `0016_temporadas` → `0017_factura_mensual` → `0018_verificacion_goles` → `0019_v03_seguridad`.

- **0015 · Rangos y espera**: `miembros.rango` (fijo/reserva/invitado; existentes → fijo, altas → reserva, creador → fijo), `cambiar_rango`, `ligas.orden_espera` (prioridad/anotación), `convocatorias.rango`; los fijos se inscriben solos al crear cualquier partido (trigger); la espera ordena fijos → reservas → invitados (en «anotación», reservas e invitados juntos por hora); invitado del Fantasy (×1,5) = rango invitado; `precrear_jugadores(..., p_rango)`.
- **0016 · Temporadas**: tabla `temporadas`, `partidos.temporada_id`, `programar_temporada` (hora de Madrid con horario de verano, solo fechas futuras, sin duplicar días, máx. 120), `cancelar_temporada`, `cambiar_hora_partido`.
- **0017 · Factura mensual**: `ligas.modo_cobro`, `ligas.precio_invitado` (null = variable), periodo y liquidación en `facturas`; al jugar, reservas/invitados pagan el precio fijo; `simular_factura` / `liquidar_factura` reparten el resto entre fijos según partidos jugados (céntimos al más antiguo).
- **0018 · Verificación de goles**: `enviar_parte` (rechaza partes donde los goles superan el resultado propio, o no lo igualan si están todos indicados); en el acta consolidada, disputas `descuadre` que bloquean los puntos y se cierran solas al corregir con `fijar_dato` (o `revisar_descuadres`); `resolver_disputa` no admite descuadres; vista `v_mvps`.
- **0019 · Seguridad**: RLS de `temporadas`, `grant select (rango)` en `miembros`, internas revocadas y RPC concedidas.

MVP y estadísticas revisados (sin cambios de regla, sin errores encontrados): mayor nota con ≥ 3 votantes, desempate goles + asistencias, empate persistente compartido, sin MVP con < 3 votantes, sin duplicar al recalcular; `v_rendimiento`, `v_clasificacion`, `v_pichichi` correctos con varios partidos.

`tests/escenario_v03.sql` (116 comprobaciones) se ejecuta tras aplicar 0015+ sobre los datos de todos los escenarios anteriores. Termina con `ESCENARIO V0.3 COMPLETADO SIN ERRORES`.

Versión 0.3 desplegada el 19-11-2026: 0015–0019 (copia exacta en `desplegado_v03/`; en 0015 la firma antigua de precrear_jugadores se renombra a precrear_jugadores_obsoleta en vez de borrarse). Verificado: 29 tablas, 21 vistas, 109 funciones, todas con RLS, nada ejecutable por anon.
