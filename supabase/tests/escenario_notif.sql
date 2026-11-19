-- Escenario 0022 · Notificaciones y FIX de DELETE sin WHERE
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);

select t_check(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.prosrc ~* 'delete\s+from\s+\w+\s*;'),
               'ninguna función hace DELETE sin WHERE (Supabase lo rechaza)');

-- ═════ Post-partido abierto → aviso a los que jugaron
set role authenticated;
select t_jugar('2027-04-06 20:00 Europe/Madrid') as p1 \gset
reset role;
select t_check((select count(distinct perfil_id) from notificaciones where tipo = 'post_partido'
                 and ruta = '/partidos/' || :'p1') = 6, 'aviso de post-partido a los 6 que jugaron');
select t_check(not exists (select 1 from notificaciones where tipo = 'admin_convocatoria' and ruta = '/partidos/' || :'p1'),
               'crear un partido (fijos inscritos solos) no genera avisos');

-- ═════ Cierre → puntos publicados
set role authenticated;
do $$
declare r int; p uuid := (select id from partidos where liga_id = current_setting('t.liga')::uuid and estado = 'post_partido'
                          order by fecha_hora desc limit 1);
begin
  for r in 301..306 loop
    perform t_como(r);
    perform enviar_post_partido(p, t_res(1, 0),
      jsonb_build_array(t_jug(301, 1), t_jug(302, 0), t_jug(303, 0), t_jug(304, 0), t_jug(305, 0), t_jug(306, 0)),
      (select jsonb_agg(jsonb_build_object('votado_id', t_m(s), 'nota', 6)) from generate_series(301, 306) s where s <> r));
  end loop;
end $$;
select t_como(301);
select t_check(cerrar_post_partido(:'p1') = 'cerrado', 'partido cerrado');
reset role;
select t_check((select count(*) from notificaciones where tipo = 'puntos' and ruta = '/partidos/' || :'p1') >= 6,
               'aviso de puntos publicados a la liga');

-- ═════ Recordatorio de convocatoria (24 h antes, si faltan jugadores)
insert into partidos (liga_id, fecha_hora, plazas, num_equipos, estado)
values (current_setting('t.liga')::uuid, now() + interval '20 hours', 20, 2, 'abierto') returning id as p2 \gset
select enviar_recordatorios();
select t_check((select count(*) from notificaciones where tipo = 'recordatorio_convocatoria' and ruta = '/partidos/' || :'p2') > 0,
               'recordatorio a quien no ha contestado');
select t_check(enviar_recordatorios() = 0, 'el recordatorio no se repite');

-- ═════ Admin apunta a otro → aviso al afectado
select m.id as libre, m.perfil_id as libre_perfil from miembros m
 where m.liga_id = current_setting('t.liga')::uuid and m.perfil_id is not null and m.estado = 'activo'
   and not exists (select 1 from convocatorias c where c.partido_id = :'p2' and c.miembro_id = m.id) limit 1 \gset
set role authenticated;
select t_como(301);
select t_check((select count(*) from notificaciones) > 0, 'cada uno ve sus notificaciones');
insert into convocatorias (partido_id, miembro_id, estado) values (:'p2', :'libre', 'confirmado');
reset role;
select t_check(exists (select 1 from notificaciones where perfil_id = :'libre_perfil' and tipo = 'admin_convocatoria'),
               'aviso «te han apuntado»');

-- ═════ Bandeja y dispositivos
set role authenticated;
select t_como(302);
select t_check((select count(*) from notificaciones where perfil_id <> t_uid(302)) = 0, 'no ve las de otros');
select t_check(marcar_notificaciones_leidas() > 0, 'marcar todas como leídas');
select t_check(not exists (select 1 from notificaciones where not leida), 'todas leídas');
select registrar_dispositivo('token-de-prueba-0123456789abcdef', 'android');
select t_como(303);
select registrar_dispositivo('token-de-prueba-0123456789abcdef', 'android');
reset role;
select t_check((select perfil_id from dispositivos where token = 'token-de-prueba-0123456789abcdef') = t_uid(303),
               'un token que cambia de usuario se reasigna');
set role anon;
select t_debe_fallar('select marcar_notificaciones_leidas()', 'anon no toca notificaciones');
reset role;
\echo '══════ ESCENARIO NOTIFICACIONES COMPLETADO SIN ERRORES ══════'
