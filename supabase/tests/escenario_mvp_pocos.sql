\set ON_ERROR_STOP 1
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
set role authenticated;
select t_jugar('2027-05-04 20:00 Europe/Madrid') as p \gset
select set_config('t.p', :'p', false);
select t_como(301);
select enviar_post_partido(:'p', t_res(1, 0),
  jsonb_build_array(t_jug(301, 1), t_jug(302, 0), t_jug(303, 0), t_jug(304, 0), t_jug(305, 0), t_jug(306, 0)),
  (select jsonb_agg(jsonb_build_object('votado_id', t_m(s), 'nota', case when s = 304 then 10 else 6 end))
     from generate_series(302, 306) s), t_m(304));
-- otros dos envían solo el parte (sin notas): un único votante
do $$ declare r int; begin
  for r in 302..303 loop
    perform t_como(r);
    perform enviar_post_partido(current_setting('t.p')::uuid, t_res(1, 0),
      jsonb_build_array(t_jug(301, 1), t_jug(302, 0), t_jug(303, 0), t_jug(304, 0), t_jug(305, 0), t_jug(306, 0)));
  end loop; end $$;
select t_como(301);
select t_check(cerrar_post_partido(:'p') = 'cerrado', 'cierre con un solo votante');
reset role;
select t_check((select es_mvp from puntos_fantasy where partido_id = :'p' and miembro_id =
                 (select id from miembros where perfil_id = t_uid(304) and liga_id = current_setting('t.liga')::uuid)),
               'con 1 votante también hay MVP (el mejor valorado)');
\echo '══════ ESCENARIO MVP POCOS VOTANTES COMPLETADO SIN ERRORES ══════'
