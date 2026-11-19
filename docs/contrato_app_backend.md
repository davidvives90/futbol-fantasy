# Contrato app Flutter ↔ backend Supabase

Revisión de todas las llamadas de `app/lib` contra `supabase/migrations` (tablas, columnas, parámetros de las RPC, claves de upsert y stream, políticas RLS). Estado: **OK** = encajaba · **corregido** = desajuste arreglado · **pendiente** = falta algo.

Pruebas del backend tras los cambios: `tests/run.sh` en PostgreSQL 16 → 90 comprobaciones, «ESCENARIO COMPLETADO SIN ERRORES» (3 comprobaciones nuevas de contrato). La app no se ha compilado (no hay Flutter en este entorno).

| Pantalla / repositorio | Tabla o RPC | Operación | Estado |
| --- | --- | --- | --- |
| Perfil (`LigasRepo.miPerfil/guardarPerfil`) | `perfiles` | select / upsert propio | OK |
| Mis ligas (`LigasRepo.misLigas`) | `miembros` + embed `ligas`, `perfiles` | select | corregido: `Miembro.select` pedía `*`, pero `token_invitacion` y `contacto` no son legibles por columna → columnas explícitas (+ `posicion` de la liga) |
| Solicitudes pendientes | `miembros` (estado `solicitud`) + `ligas` | select | OK (la política `liga_leer` deja ver la liga solicitada) |
| Crear / editar liga | `crear_liga(p jsonb)` / `ligas` update (admin) | rpc / update | corregido en backend: `crear_liga` ignoraba `puntuar_por_posicion` y `horas_post_partido` |
| Unirse | `unirse(p_codigo)` | rpc | OK |
| Buscar ligas | `buscar_ligas(p_texto)` | rpc | OK (devuelve `num_miembros`) |
| Solicitar unirse / aprobar | `solicitar_unirse(p_liga)`, `aprobar_solicitud(p_miembro, p_aceptar)` | rpc | OK; el enum de la app no tenía `rechazado` → añadido |
| Miembros de la liga | `miembros` + `perfiles` | select | corregido (ver Mis ligas) |
| Pre-crear jugadores | `precrear_jugadores(p_liga, p_nombres[, p_contactos])` | rpc → `{miembro_id, nombre, token}` | OK |
| Reenviar enlace | `enlaces_invitacion(p_liga)` | rpc (solo admins) | corregido: leía `miembros.token_invitacion`, que no es legible |
| Roles, expulsar, abandonar, regenerar código | `cambiar_rol`, `expulsar`, `abandonar_liga`, `regenerar_codigo` | rpc | OK |
| Reglas de puntuación | `reglas_puntuacion` | select / update (admin) | corregido: el update filtra `posicion is null` para no pisar reglas por posición |
| Aspectos de valoración | `aspectos_valoracion` | select / upsert `liga_id,clave` | corregido: faltaba `aplica_a` (al activar/desactivar un aspecto se reseteaba a `todos`) |
| Lista de partidos / detalle | `partidos` | select / stream `id` | OK |
| Crear partido | `crear_partido(p_liga, p_fecha_hora, p_coste, p_plazas, p_num_equipos, p_campo_maps_url, p_hora_confirmada)` | rpc | corregido: la app enviaba `{p_liga, p: jsonb}`; además límites de plazas 6–44 como el `check` |
| Confirmar hora / cancelar | `partidos` | update (admin, política `partido_editar`) | OK |
| Convocatoria | `convocatorias` | stream `partido_id,miembro_id` / upsert | OK (trigger de cupo y lista de espera) |
| Equipos | `guardar_equipos(p_partido, p_asignacion jsonb)` + `definir_encuentros(p_partido, p_lista)` | rpc | corregido: actualizaba `convocatorias.equipo` fila a fila y el estado a mano; no se creaban encuentros (necesarios para `marcar_jugado`). Con 3–4 equipos se generan todos contra todos |
| Partido jugado | `marcar_jugado(p_partido)` | rpc | corregido: la app ponía `estado = post_partido` y `votacion_cierra` a mano (saltaba cargos y validaciones) y tenía un botón aparte «Generar cargos» |
| Post-partido: encuentros | `encuentros` | select | corregido: ahora el parte usa los encuentros que fijó el admin (antes los inventaba el jugador; el FK los exige) |
| Post-partido: resultado | `reportes_encuentro` | upsert PK `partido_id,n,reportero_id` | corregido: enviaba `equipo_local/equipo_visitante`, columnas que no existen |
| Post-partido: datos de jugadores | `reportes_jugador` | upsert PK `partido_id,reportero_id,sujeto_id` | corregido: enviaba `porteria_cero`, que se deduce del resultado y no existe como columna; quitado también de la UI |
| Post-partido: valoraciones | `valoraciones` | upsert PK `partido_id,votante_id,votado_id,aspecto` | corregido: los aspectos se filtran por `aplica_a` (antes por clave fija) y solo se lista a quien tiene equipo, como exige `jugo_partido` |
| Post-partido: ¿ya enviado? | `reportes_encuentro` (propios) | select | OK |
| Post-partido: progreso | `v_progreso_post_partido.partes_resultado` | select | corregido: contaba `reportes_encuentro`, pero por RLS un jugador solo ve los suyos (siempre daba 1) |
| Revisión: cruzar partes | `cerrar_post_partido(p_partido)` | rpc | corregido: llamaba a `consolidar_acta`, que no es ejecutable por `authenticated` |
| Revisión: disputas | `disputas` | select | OK |
| Revisión: resolver | `resolver_disputa(p_disputa uuid, p_valor smallint)` | rpc | corregido: se envía entero (antes `num`) y se quitó la conversión de `porteria_cero` |
| Revisión: confianza | `encuentros.confianza` | select | corregido: ya viene en % (0–100); la app la multiplicaba por 100 |
| Revisión: calcular puntos | `calcular_puntos(p_partido)` | rpc | corregido: queda solo como respaldo en `en_revision` sin disputas (lo normal es que se calculen solos) |
| Resultado | `puntos_fantasy`, `acta_jugador`, `encuentros` | select | corregido: etiquetas del desglose (`penaltis_parados`, `penaltis_fallados`); `notas` (objeto) se omite |
| Caja: saldos | `v_saldos` | select | OK (cada uno el suyo; admins, todos) |
| Caja: movimientos | `movimientos` | select | OK |
| Caja: registrar pago / ajuste | `registrar_pago(p_miembro, p_importe, p_partido, p_concepto, p_tipo)` | rpc | corregido: insertaba en `movimientos`, sin política de insert |
| Caja: facturas | `facturas` + Storage `facturas/<liga_id>/<uuid>.<ext>` | insert / select / signed URL | OK |
| Clasificación / ficha | `v_rendimiento`, `puntos_fantasy` + embed `partidos` | select | OK |
| Tiempo real | publicación `supabase_realtime` | — | pendiente (despliegue): añadir `convocatorias, partidos, encuentros, disputas` (comentado al final de `0006_rls.sql`) |

## Pendiente

- Compilar la app (`flutter pub get && flutter analyze && flutter test`); nada de lo anterior se ha ejecutado en Flutter.
- La app no ofrece todavía editar a mano los enfrentamientos de 3–4 equipos (usa todos contra todos); `PartidosRepo.definirEncuentros` ya existe para una pantalla futura.
- La app no muestra las notas por aspecto (`desglose.notas`) ni usa `v_historial_jugador`, `v_notas_aspecto`, `v_fiabilidad` o `v_pagos_partido`.
- Un admin que no jugó no ve el formulario de parte en la app, aunque el backend se lo permite.

## Mercado Fantasy (app ↔ `0008_mercado_fantasy.sql` + `0009_mercado_rls.sql`) — verificado

Cotejado fila a fila con las migraciones 0008–0009 (versión 0.1). Las secciones 9–10 de `docs/mercado_fantasy.md` (fichas, cláusulas, ofertas, cesiones, roles) aún no están implementadas.

| Pantalla / repositorio | Tabla o RPC | Operación | Columnas / parámetros que usa la app | Estado |
| --- | --- | --- | --- | --- |
| Liga (`Liga.fromMap`), Ajustes Fantasy | `ligas` | select / update admin (`liga_editar`) | `precio_min, precio_max, max_plantilla, bonus_no_habitual, horas_cierre_alineacion, ingreso_por_punto, comision_venta, k_encuesta, max_variacion`; `max_plantilla` y `horas_cierre_alineacion` se envían como enteros (smallint) | corregido (horas enviadas como decimal fallaban en smallint) |
| Mi equipo (`miManager`) | `fantasy_managers` (+ `ligas.presupuesto_inicial` si aún no hay fila) | select | `liga_id, miembro_id, saldo, puntos_totales` | OK |
| Mi equipo (`miPlantilla`) | `v_mi_plantilla` (+ `v_mercado.variacion`) | select | filtro `liga_id` (la vista ya filtra por el usuario); `jugador_id, precio_compra, precio_actual, no_habitual, comprado_en` | corregido (`precio` → `precio_actual`; sin filtro `manager_id`, que la vista no tiene) |
| Mánagers › detalle | `plantillas` de otro mánager | — | — | corregido: las plantillas ajenas son privadas (RLS); la app ya no las pide y muestra solo su última alineación |
| Mánagers › detalle (`ultimaJornada`) | `v_jornada_managers` | select | `liga_id, manager_id, partido_id, puntos, ingreso`, orden `fecha_hora` | corregido (antes `puntos_manager` + embed) |
| Mánagers › detalle | `alineaciones` del último partido liquidado | select | visible porque ya pasó la hora de cierre | OK |
| Comprar / vender | `comprar_jugador(p_liga, p_jugador)`, `vender_jugador(p_liga, p_jugador)` | rpc | mensaje de error del backend tal cual | OK |
| Mercado (`mercado`) | `v_mercado` | select | `miembro_id, precio, variacion` (M), `rating` (0–100), `pct_plantillas` (0–100), `no_habitual` | corregido (`pct_fichado` → `pct_plantillas`) |
| Mercado abierto | `mercado_abierto(p_liga)` | rpc → bool | — | OK |
| Ficha de mercado | `valoracion_jugador` | select | `calidad … portero, general, num_evaluadores` (0–100) | OK |
| Ficha de mercado | `historial_precios` | select | `precio, rating, creado_en` | OK |
| Equipos (balanceo) | `v_rating_balanceo` | select | `miembro_id, rating, rating_encuesta`; con encuesta cerrada se usa el rating 0–100 para todos los convocados (50 si faltara alguno); sin encuesta, fórmula de rendimiento normalizada 0–100 | corregido (ya no se mezclan escalas) |
| Alineación | `alineaciones` | select propia | `partido_id, manager_id, jugador_id, no_habitual, multiplicador` (null hasta congelar → 1) | OK |
| Alineación | `guardar_alineacion(p_partido, p_jugadores uuid[])` | rpc | — | OK |
| Resultado › Tus puntos de mánager | `puntos_manager` | select | `partido_id, manager_id, puntos, ingreso`; provisional = `puntos_fantasy × multiplicador` | OK |
| Clasificación de mánagers | `v_clasificacion_managers` | select | `manager_id, puntos_totales, posicion, valor_plantilla, saldo, puntos_ultima_jornada` | OK |
| Encuesta | `encuestas_valoracion` | select abiertas | `id, liga_id, sujeto_id, estado, creada_en` | OK |
| Encuesta | `respuestas_ranking` | select propias | `atributo` | OK |
| Encuesta | `enviar_ranking(p_encuesta, p_atributo, p_orden uuid[])` | rpc | orden completo de `activo` + `pendiente_registro` (igual que `jugadores_liga`) | OK |
| Ajustes Fantasy | `abrir_encuesta(p_liga, p_sujeto)`, `cerrar_encuesta(p_encuesta)` | rpc | — | OK |
| Ajustes Fantasy › progreso | `v_progreso_encuesta` | select | `completadas, managers` | corregido (antes `evaluadores_completos`, inexistente) |

## Mercado Fantasy (0008–0009) · para la app

Pruebas: `tests/run.sh` → 169 comprobaciones en total (90 + 79 de `escenario_mercado.sql`), ambos escenarios sin errores. La app 0.1 ya usa este contrato (ver tabla anterior).

| Pantalla | Tabla, vista o RPC | Operación | Notas |
| --- | --- | --- | --- |
| Encuesta inicial (admin) | `abrir_encuesta(p_liga uuid, p_sujeto uuid default null)` → uuid | rpc | `p_sujeto` = mini-encuesta para un jugador nuevo |
| Encuesta (cada mánager) | `enviar_ranking(p_encuesta uuid, p_atributo text, p_orden uuid[])` | rpc ×6 | atributos: `calidad, velocidad, resistencia, defensa, regate, portero`; `p_orden` = todos los `jugadores_liga` (miembros `activo` + `pendiente_registro`), 1.º el mejor |
| Progreso de la encuesta | `v_progreso_encuesta` (`managers`, `completadas`, `mis_atributos`) | select | |
| Mis respuestas | `respuestas_ranking` | select | solo las propias |
| Cerrar encuesta (admin) | `cerrar_encuesta(p_encuesta uuid)` → nº de jugadores valorados | rpc | |
| Valoraciones | `valoracion_jugador` | select | notas 0–100 por atributo y `general` |
| Mercado | `v_mercado` (precio, variacion, variacion_pct, rating, no_habitual, num_plantillas, pct_plantillas, en_mi_plantilla, precio_venta) | select | `mercado_abierto(p_liga)` → boolean para el aviso de cierre |
| Comprar / vender | `comprar_jugador(p_liga, p_jugador)` / `vender_jugador(p_liga, p_jugador)` → saldo nuevo | rpc | errores legibles: saldo, plantilla llena, no habitual, mercado cerrado |
| Mi plantilla | `v_mi_plantilla` (precio_compra, precio_actual, precio_venta, plusvalia, no_habitual, estado_proximo_partido) | select | `estado_proximo_partido` = estado en la convocatoria del próximo partido |
| Saldo y clasificación | `fantasy_managers`, `v_clasificacion_managers` | select | saldo visible para toda la liga |
| Movimientos de dinero | `transacciones_fantasy` | select | solo los propios (admins: todos) |
| Historial de precios (gráfico) | `historial_precios` | select | `partido_id` null = precio inicial |
| Alineación | `guardar_alineacion(p_partido uuid, p_jugadores uuid[])` → nº guardados | rpc | máx. `plazas / num_equipos`; hora límite: `hora_cierre_alineacion(p_partido)` |
| Alineaciones del partido | `alineaciones` | select | propias siempre; ajenas tras el cierre; `multiplicador` se rellena al congelar |
| Puntos de la jornada | `puntos_manager`, `v_jornada_managers` | select | `desglose` = lista de jugadores con puntos, multiplicador y total |
| Generador de equipos | `v_rating_balanceo.rating` | select | sustituye a la fórmula basada solo en puntos para el arranque en frío |
| Ajustes del mercado (admin) | `ligas` (`precio_min, precio_max, max_plantilla, bonus_no_habitual, horas_cierre_alineacion, ingreso_por_punto, comision_venta, k_encuesta, max_variacion`) | update (política `liga_editar`) | `presupuesto_inicial` lo fija `cerrar_encuesta` |
| Admin, respaldo | `liquidar_jornada(p_partido)`, `recalcular_precios(p_liga, p_partido)` | rpc | idempotentes; normalmente no hace falta llamarlas (trigger al cerrar el partido) |

## Ampliación 0.2 (migraciones 0010–0014) · para la app

Todas las RPC por `supabase.rpc(nombre, params: {...})` con estos nombres de parámetro exactos. Importes en M (numeric, 2 decimales); porcentajes de cesión como fracción 0–1.

| RPC | Parámetros | Devuelve | Notas | Uso en la app |
| --- | --- | --- | --- | --- |
| `comprar_ficha` | `p_liga uuid, p_jugador uuid` | saldo (numeric) | Error si no quedan fichas libres: "puedes pagar la cláusula… o hacerle una oferta" | Ficha de mercado → Comprar (`FantasyRepo.comprar`) · OK |
| `vender_ficha` | `p_ficha uuid` | saldo | Precio − comisión; no si está cedida | Mi equipo → menú → Vender; ficha de mercado → Vender (`FantasyRepo.vender(fichaId:)`) · OK |
| `comprar_jugador` / `vender_jugador` | `p_liga, p_jugador` | saldo | Firma 0.1, siguen funcionando | Solo como respaldo si no hay `ficha_id` (`FantasyRepo.vender` sin ficha) · OK |
| `fijar_clausula` | `p_ficha uuid, p_importe numeric` | cláusula nueva | Subir cuesta `coste_subida_clausula` (10 %) de la subida; bajar gratis; mínimo = valor de mercado | Mi equipo → menú → Cambiar cláusula (`dialogoClausula`, muestra el coste del 10 %) · OK |
| `pagar_clausula` | `p_ficha uuid` | saldo | El dueño no puede negarse; error si la ficha está protegida o cedida | Ficha de mercado → Dueños → Pagar cláusula · OK |
| `hacer_oferta` | `p_ficha uuid, p_importe numeric` | id oferta | Una nueva del mismo comprador por la misma ficha cancela la anterior | Ficha de mercado → Dueños → Hacer oferta (`dialogoOferta`) · OK |
| `responder_oferta` | `p_oferta uuid, p_aceptar boolean` | `'aceptada' \| 'rechazada' \| 'caducada'` | Solo el dueño; al aceptar se revalidan saldo/hueco/no habitual | Fantasy → Ofertas → recibidas: Aceptar / Rechazar (trata `caducada`) · OK |
| `cancelar_oferta` | `p_oferta uuid` | — | Solo el comprador | Fantasy → Ofertas → enviadas: Cancelar · OK |
| `ofrecer_cesion` | `p_ficha uuid, p_pct numeric` | id cesión | Para el próximo partido con alineación abierta; `cesion_pct_min`–`cesion_pct_max` (0,05–0,30); 1 por jornada | Mi equipo → menú → Ofrecer en cesión (`dialogoCesion`, % como fracción 0–1) · OK |
| `aceptar_cesion` | `p_cesion uuid` | saldo | Paga `pct × valor` al dueño; recibe 1 por jornada | Fantasy → Ofertas → Cesiones: botón con el importe · OK |
| `cancelar_cesion` | `p_cesion uuid` | — | Solo si nadie la ha aceptado | Mi equipo → menú → Retirar cesión; Ofertas → Cesiones → Retirar · OK |
| `guardar_alineacion` | `p_partido uuid, p_jugadores uuid[], p_roles text[]` (opcional) | nº jugadores | Roles `POR/DEF/MED/DEL`, uno por jugador y exactamente 1 `POR`; sin roles: el primero POR y el resto MED. Admite la ficha recibida en cesión | Mi equipo → campo de alineación (`AlineacionCampo`) con `p_roles` · OK |

Vistas y tablas:

| Objeto | Columnas útiles | Visibilidad | Uso en la app |
| --- | --- | --- | --- |
| `v_mercado` | las de 0.1 + `fichas_totales`, `fichas_libres`, `clausula_minima` (la más barata clausulable, null si ninguna), `mi_ficha_id` | miembros | Mercado (fichas libres / agotado · cláusula desde), ficha de mercado · OK |
| `v_fichas_jugador` | `ficha_id, liga_id, jugador_id, numero, propietario_id, propietario_nombre, clausula, protegida, cedida, es_mia, precio_compra, adquirida_en` (filtrar por `jugador_id`) | miembros | Ficha de mercado → Dueños (`fichasJugadorProvider`) · OK |
| `v_mi_plantilla` | las de 0.1 + `ficha_id, clausula, protegida, cedida_a_mi, cedida_a_otro, cesion_partido_id, cesion_estado` | propia (+ la recibida en cesión) | Mi equipo (cláusula, protegida, cedidas), mercado, ofertas · OK |
| `v_mis_ofertas` | `oferta_id, ficha_id, jugador_id, jugador_nombre, direccion ('enviada'/'recibida'), comprador_*, vendedor_*, importe, estado, expira_en, precio_mercado, clausula_actual` | comprador y vendedor | Fantasy → Ofertas (`misOfertasProvider`, insignia de pendientes) · OK |
| `v_cesiones_disponibles` | `cesion_id, ficha_id, jugador_id, jugador_nombre, propietario_id, propietario_nombre, pct, importe, precio_mercado, no_habitual, partido_id, fecha_hora, cierre, es_mia` | miembros | Fantasy → Ofertas → Cesiones; retirar la propia (`miCesionOfrecida`) · OK |
| `alineaciones` | + `rol`, `bonus_rol` | propias; ajenas tras el cierre | Campo de alineación (rol) y resultado provisional (bonus_rol) · OK |
| `puntos_manager.desglose` | cada elemento: `jugador_id, rol, puntos, bonus_rol, multiplicador, jugo, cedido, total` | miembros | Resultado → Tus puntos de mánager; Mánagers → detalle (`DesgloseManager`) · OK |
| `ligas` | + `bonus_roles, copias_por_jugador, coste_subida_clausula, proteccion_jornadas, cesion_pct_min, cesion_pct_max, horas_caducidad_oferta, partidos_min_rendimiento` | miembros; admins editan | Ajustes Fantasy (todos los parámetros nuevos + interruptor bonus_roles) · OK |
| `reglas_puntuacion` | ya no hay `gol_portero`… ni `porteria_cero_*`; nuevas `rol_por_porteria_cero, rol_por_menos_goleado, rol_por_encajados_3, rol_def_menos_goleado, rol_med_asistencia, rol_del_gol` | — | Puntuación → Reglas (oculta las obsoletas, sección de bonus de rol); leyenda en la alineación · OK |

Cambios que afectan a la app 0.1: `aspectos_valoracion` → todos con `aplica_a = 'todos'` y `porteria` inactivo; `plantillas` es ahora una vista con las fichas de toda la liga (no solo las propias); `transacciones_fantasy.tipo` admite `clausula_pagada, clausula_cobrada, subida_clausula, oferta_pagada, oferta_cobrada, cesion_pagada, cesion_cobrada`. El balanceo de equipos ya no debe penalizar porteros (cambio en la app).

Además (app 0.2): la vista `plantillas` (ahora pública en la liga) se usa en Mánagers → detalle para ver la plantilla de un rival con su cláusula (`FantasyRepo.plantillaDe`) · OK. `valoracion_jugador.portero` alimenta el balanceo de equipos (habilidad bajo palos, peso 0,15) en lugar de la antigua penalización por porteros · OK.
