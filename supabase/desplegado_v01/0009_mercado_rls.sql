-- 0009 · Seguridad del mercado Fantasy
-- Decisiones:
--  · respuestas_ranking: privadas; cada evaluador solo ve las suyas (ni los admins ven las ajenas).
--  · plantillas: privadas (cada mánager ve la suya). Las de los rivales se descubren por sus alineaciones
--    una vez cerradas, y v_mercado muestra solo el agregado (% de plantillas que tienen a cada jugador).
--  · alineaciones: las propias siempre; las ajenas solo tras la hora de cierre de ese partido.
--  · saldo y puntos de cada mánager (fantasy_managers): visibles para toda la liga (es un juego y la
--    clasificación desempata por patrimonio). El detalle de transacciones: solo el propio y los admins.
--  · Todas las escrituras pasan por funciones security definer; no hay políticas de insert/update/delete.

alter table encuestas_valoracion  enable row level security;
alter table respuestas_ranking    enable row level security;
alter table valoracion_jugador    enable row level security;
alter table mercado_jugador       enable row level security;
alter table historial_precios     enable row level security;
alter table fantasy_managers      enable row level security;
alter table plantillas            enable row level security;
alter table transacciones_fantasy enable row level security;
alter table alineaciones          enable row level security;
alter table puntos_manager        enable row level security;

revoke all on encuestas_valoracion, respuestas_ranking, valoracion_jugador, mercado_jugador, historial_precios,
              fantasy_managers, plantillas, transacciones_fantasy, alineaciones, puntos_manager
  from anon, public, authenticated;
grant select on encuestas_valoracion, respuestas_ranking, valoracion_jugador, mercado_jugador, historial_precios,
                fantasy_managers, plantillas, transacciones_fantasy, alineaciones, puntos_manager
  to authenticated;
grant select on v_mercado, v_mi_plantilla, v_clasificacion_managers, v_jornada_managers,
                v_progreso_encuesta, v_rating_balanceo to authenticated;
revoke all on v_mercado, v_mi_plantilla, v_clasificacion_managers, v_jornada_managers,
              v_progreso_encuesta, v_rating_balanceo from anon;

create or replace function liga_de_encuesta(p_encuesta uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select liga_id from encuestas_valoracion where id = p_encuesta
$$;

create policy enc_leer on encuestas_valoracion for select to authenticated using (es_miembro(liga_id));
create policy rank_propio on respuestas_ranking for select to authenticated
  using (evaluador_id = mi_miembro(liga_de_encuesta(encuesta_id)));
create policy valj_leer on valoracion_jugador for select to authenticated using (es_miembro(liga_id));
create policy merc_leer on mercado_jugador for select to authenticated using (es_miembro(liga_id));
create policy hist_leer on historial_precios for select to authenticated using (es_miembro(liga_id));
create policy fm_leer on fantasy_managers for select to authenticated using (es_miembro(liga_id));
create policy plant_propia on plantillas for select to authenticated using (manager_id = mi_miembro(liga_id));
create policy tx_leer on transacciones_fantasy for select to authenticated
  using (manager_id = mi_miembro(liga_id) or es_admin(liga_id));
create policy alin_leer on alineaciones for select to authenticated
  using (manager_id = mi_miembro(liga_de_partido(partido_id))
         or (es_miembro(liga_de_partido(partido_id)) and alineacion_visible(partido_id)));
create policy pm_leer on puntos_manager for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));

-- ───────────── Funciones ─────────────
revoke execute on function
  redondear_005(numeric), precio_base(uuid, numeric), jugadores_liga(uuid), es_no_habitual(uuid),
  hora_cierre_alineacion(uuid), alineacion_visible(uuid), mercado_abierto(uuid), asegurar_manager(uuid, uuid),
  abrir_encuesta(uuid, uuid), enviar_ranking(uuid, text, uuid[]), nota_atributo(uuid, uuid, atributo_valoracion),
  media_general(posicion_campo, numeric, numeric, numeric, numeric, numeric, numeric), cerrar_encuesta(uuid),
  alta_jugador_mercado(), congelar_alineaciones(uuid), congelar_vencidas_liga(uuid),
  congelar_alineaciones_vencidas(), guardar_alineacion(uuid, uuid[]), comprar_jugador(uuid, uuid),
  vender_jugador(uuid, uuid), recalcular_precios(uuid, uuid), liquidar_jornada(uuid), tras_cerrar_partido(),
  liga_de_encuesta(uuid)
  from public, anon;

-- RPC que usa la app
grant execute on function
  abrir_encuesta(uuid, uuid), enviar_ranking(uuid, text, uuid[]), cerrar_encuesta(uuid),
  comprar_jugador(uuid, uuid), vender_jugador(uuid, uuid), guardar_alineacion(uuid, uuid[]),
  mercado_abierto(uuid), hora_cierre_alineacion(uuid), liquidar_jornada(uuid), recalcular_precios(uuid, uuid),
  precio_base(uuid, numeric), redondear_005(numeric), es_no_habitual(uuid)
  to authenticated;
-- Ayudantes que necesitan las políticas y vistas al ejecutarse con el rol del usuario
grant execute on function alineacion_visible(uuid), liga_de_encuesta(uuid), jugadores_liga(uuid)
  to authenticated;
-- Internas (triggers, tarea programada, piezas de otras funciones): sin acceso desde la app
-- asegurar_manager, nota_atributo, media_general, congelar_*, alta_jugador_mercado, tras_cerrar_partido

-- En Supabase (pg_cron), junto a cerrar_ventanas_vencidas:
--   select cron.schedule('congelar-alineaciones', '*/15 * * * *', 'select congelar_alineaciones_vencidas()');
