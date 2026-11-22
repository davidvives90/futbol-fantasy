-- 0050: modos de convocatoria (libre, turnos, mínimo) y quién rellena el acta
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Ponderada'), false);
insert into auth.users (id, email) select t_uid(i), 'u' || i || '@test' from generate_series(707, 708) i;
insert into perfiles (id, nombre) select t_uid(i), 'PP ' || i from generate_series(707, 708) i;
do $$ declare c text := (select codigo_invitacion from ligas where id = current_setting('t.liga')::uuid);
begin for i in 707..708 loop perform t_como(i); perform unirse(c); end loop; end $$;
select set_config('request.jwt.claim.sub', '', false);

do $$
declare v_liga uuid := current_setting('t.liga')::uuid; v_admin uuid := t_m(701);
        v_p uuid; v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e text; v_n int;
begin
  set local request.jwt.claim.sub = '';
  update miembros set rango = 'reserva' where id in (t_m(705), t_m(706));
  update miembros set rango = 'invitado' where id = t_m(704);
  update ligas set duracion_partido_min = 60, horas_apertura_convocatoria = 0, horas_turno = 24 where id = v_liga;

  -- ═════════ 1. Por orden de llegada: nadie apuntado de oficio y la espera no da prioridad a los fijos
  update ligas set modo_convocatoria = 'libre' where id = v_liga;
  insert into partidos (liga_id, fecha_hora, plazas, num_equipos, creado_por)
  values (v_liga, now() + interval '20 days', 6, 2, v_admin) returning id into v_p;
  perform t_check(not exists (select 1 from convocatorias where partido_id = v_p), 'libre: lista vacía al crear');
  foreach v_n in array array[702, 703, 705, 704, 707, 708, 706, 701] loop
    perform t_como(v_n);
    insert into convocatorias (partido_id, miembro_id, estado) values (v_p, t_m(v_n), 'confirmado');
    perform pg_sleep(0.01);
  end loop;
  perform t_check((select estado from convocatorias where partido_id = v_p and miembro_id = t_m(706)) = 'espera', 'libre: 7º a la espera');
  perform t_como(702);
  update convocatorias set estado = 'baja' where partido_id = v_p and miembro_id = t_m(702);
  select estado into v_e from convocatorias where partido_id = v_p and miembro_id = t_m(706);
  perform t_check(v_e = 'confirmado', 'libre: entra el primero que llegó (reserva), no el fijo: ' || v_e);
  perform t_check((select estado from convocatorias where partido_id = v_p and miembro_id = t_m(701)) = 'espera', 'libre: el fijo sigue esperando');

  -- ═════════ 2. Turnos: fijos primero, reservas 24 h después, invitados 48 h después
  perform set_config('request.jwt.claim.sub', '', true);
  update ligas set modo_convocatoria = 'turnos' where id = v_liga;
  insert into partidos (liga_id, fecha_hora, plazas, num_equipos, creado_por)
  values (v_liga, now() - interval '2 hours', 6, 2, v_admin) returning id into v_a;
  insert into partidos (liga_id, fecha_hora, plazas, num_equipos, creado_por)
  values (v_liga, now() + interval '3 days', 6, 2, v_admin) returning id into v_b;
  perform t_check(not exists (select 1 from convocatorias where partido_id = v_b), 'turnos: lista vacía al crear');
  perform t_check(convocatoria_abre_para(v_b, t_m(702)) <= now(), 'turnos: los fijos ya pueden');
  perform t_check(convocatoria_abre_para(v_b, t_m(705)) > now() + interval '22 hours', 'turnos: reservas en ~23 h');
  perform t_check(convocatoria_abre_para(v_b, t_m(704)) > now() + interval '46 hours', 'turnos: invitados en ~47 h');
  perform t_como(702);
  insert into convocatorias (partido_id, miembro_id, estado) values (v_b, t_m(702), 'confirmado');
  perform t_check((select estado from convocatorias where partido_id = v_b and miembro_id = t_m(702)) = 'confirmado', 'turnos: el fijo se apunta');
  perform t_como(705);
  begin
    insert into convocatorias (partido_id, miembro_id, estado) values (v_b, t_m(705), 'confirmado');
    perform t_check(false, 'turnos: la reserva no debería poder aún');
  exception when raise_exception then
    perform t_check(sqlerrm like 'Podrás apuntarte a partir del%', 'turnos: reserva espera su turno (' || sqlerrm || ')');
  end;
  -- el aviso del turno de los fijos sale una vez
  perform set_config('request.jwt.claim.sub', '', true);
  perform enviar_recordatorios();
  perform t_check(exists (select 1 from recordatorios_enviados where partido_id = v_b and tipo = 'turno_fijo'), 'turnos: aviso a los fijos');
  perform t_check(not exists (select 1 from recordatorios_enviados where partido_id = v_b and tipo = 'turno_reserva'), 'turnos: aún no a reservas');
  delete from partidos where id in (v_a, v_b);

  -- ═════════ 3. Mínimo: se cancela si no se llega; se confirma si se llega
  update ligas set modo_convocatoria = 'minimo', minimo_jugadores = 4, horas_decision = 24 where id = v_liga;
  insert into partidos (liga_id, fecha_hora, plazas, num_equipos, creado_por)
  values (v_liga, now() + interval '5 hours', 6, 2, v_admin) returning id into v_c;
  insert into partidos (liga_id, fecha_hora, plazas, num_equipos, creado_por)
  values (v_liga, now() + interval '6 hours', 6, 2, v_admin) returning id into v_d;
  insert into convocatorias (partido_id, miembro_id, estado)
  select v_c, t_m(i), 'confirmado' from generate_series(701, 702) i;
  insert into convocatorias (partido_id, miembro_id, estado)
  select v_d, t_m(i), 'confirmado' from generate_series(701, 704) i;
  perform enviar_recordatorios();
  perform t_check((select estado from partidos where id = v_c) = 'cancelado', 'mínimo: 2 de 4 → cancelado');
  perform t_check((select estado from partidos where id = v_d) <> 'cancelado', 'mínimo: 4 de 4 → hay partido');
  perform t_check(exists (select 1 from notificaciones where ruta = '/partidos/' || v_c and cuerpo like 'No se llegó al mínimo (2 de 4)%'),
                  'mínimo: el aviso explica el motivo');
  perform t_check(exists (select 1 from notificaciones where ruta = '/partidos/' || v_d and titulo = 'Hay partido ✅'), 'mínimo: aviso de que hay partido');
  delete from partidos where id in (v_c, v_d);

  -- ═════════ 4. Cambiar de modo: los fijos aparecen o desaparecen como pendientes
  perform set_config('request.jwt.claim.sub', '', true);
  delete from partidos where id = v_p;
  update ligas set modo_convocatoria = 'libre' where id = v_liga;
  insert into partidos (liga_id, fecha_hora, plazas, num_equipos, creado_por)
  values (v_liga, now() + interval '21 days', 6, 2, v_admin) returning id into v_p;
  update ligas set modo_convocatoria = 'apertura' where id = v_liga;
  select count(*) into v_n from convocatorias where partido_id = v_p and estado = 'pendiente';
  perform t_check(v_n >= 2, 'a apertura: fijos pendientes (' || v_n || ')');
  update ligas set modo_convocatoria = 'libre' where id = v_liga;
  perform t_check(not exists (select 1 from convocatorias where partido_id = v_p and estado = 'pendiente'), 'a libre: sin pendientes');
  delete from partidos where id = v_p;

  update ligas set modo_convocatoria = 'clasica' where id = v_liga;
  update miembros set rango = 'fijo' where id in (t_m(704), t_m(705), t_m(706));
end $$;

-- ═════════ 5. Acta: árbitro
select set_config('request.jwt.claim.sub', '', false);
update ligas set quien_rellena = 'arbitro', arbitro_id = t_m(702) where id = current_setting('t.liga')::uuid;
set role authenticated;
select t_jugar7('2027-06-01 20:00 Europe/Madrid') as pa \gset
select t_como(703);
select t_check(not puedo_rellenar_acta(:'pa'), 'árbitro: un jugador no rellena el acta');
select t_debe_fallar(format('select enviar_parte(%L, %L, %L)', :'pa', t_res(1, 0), '[]'), 'árbitro: rechaza el parte de un jugador');
select t_como(702);
select t_check(puedo_rellenar_acta(:'pa'), 'árbitro: el árbitro puede');
select enviar_parte(:'pa', t_res(1, 0), jsonb_build_array(t_jug(701, 1)));
select t_como(701);
select t_check(puedo_rellenar_acta(:'pa'), 'árbitro: el admin también puede');
reset role;
select t_check(peso_parte(:'pa', t_m(702)) = 3, 'árbitro: su parte pesa 3');

-- ═════════ 6. Acta: capitanes
reset role;
update ligas set quien_rellena = 'capitanes', arbitro_id = null where id = current_setting('t.liga')::uuid;
set role authenticated;
select t_jugar7('2027-06-08 20:00 Europe/Madrid') as pc \gset
select t_como(703);
select t_check(puedo_rellenar_acta(:'pc'), 'capitanes: sin capitanes, cualquiera que jugó');
reset role;
select set_config('request.jwt.claim.sub', '', false);
update convocatorias set capitan = true where partido_id = :'pc' and miembro_id in (t_m(701), t_m(704));
set role authenticated;
select t_como(703);
select t_check(not puedo_rellenar_acta(:'pc'), 'capitanes: un jugador ya no');
select t_como(704);
select t_check(puedo_rellenar_acta(:'pc'), 'capitanes: el capitán sí');
select enviar_parte(:'pc', t_res(0, 2), jsonb_build_array(t_jug(704, 2)));

reset role;
update ligas set quien_rellena = 'jugadores' where id = current_setting('t.liga')::uuid;
