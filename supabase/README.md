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
Las siguientes versiones (0010+) deben ser **aditivas**: no modificar los ficheros ya desplegados.
