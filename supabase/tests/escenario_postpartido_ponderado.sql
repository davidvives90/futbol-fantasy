-- 0047: consolidación ponderada, asistencias ≤ goles y solo conflictos de verdad
\set ON_ERROR_STOP 1
\pset pager off
reset role;
create or replace function t_confirmar(p uuid) returns void language sql security definer set search_path = public as $$
  update convocatorias set estado = 'confirmado' where partido_id = p $$;
grant execute on function t_confirmar to authenticated;
-- partido jugado de 3 contra 3: equipo 1 = u701–u703; equipo 2 = u704–u706
create or replace function t_jugar7(f timestamptz) returns uuid language plpgsql as $$
declare p uuid;
begin
  perform t_como(701);
  p := crear_partido(current_setting('t.liga')::uuid, f, 0);
  perform t_confirmar(p);
  perform guardar_equipos(p, jsonb_build_object(t_m(701), 1, t_m(702), 1, t_m(703), 1, t_m(704), 2, t_m(705), 2, t_m(706), 2));
  perform marcar_jugado(p);
  return p;
end $$;
grant execute on function t_jugar7 to authenticated;
insert into auth.users (id, email) select t_uid(i), 'u' || i || '@test' from generate_series(701, 706) i;
insert into perfiles (id, nombre) select t_uid(i), 'PP ' || i from generate_series(701, 706) i;
set role authenticated;
select t_como(701);
select crear_liga('{"nombre":"Liga Ponderada","jugadores_por_equipo":3,"num_equipos":2}') as lp \gset
select set_config('t.liga', :'lp', false);
select codigo_invitacion as codp from ligas where id = :'lp' \gset
select set_config('t.codigo', :'codp', false);
do $$ begin
  for i in 702..706 loop perform t_como(i); perform unirse(current_setting('t.codigo')); end loop;
  perform t_como(701);
  for i in 702..706 loop perform cambiar_rango(t_m(i), 'fijo'); end loop;
end $$;

-- ═════════ 1. Casi unánime: se cierra solo y cuadra con el marcador
select t_jugar7('2027-05-04 20:00 Europe/Madrid') as p1 \gset
select set_config('t.p1', :'p1', false);
do $$
declare r int; p uuid := current_setting('t.p1')::uuid;
begin
  for r in 701..706 loop
    perform t_como(r);
    if r <= 704 then
      perform enviar_parte(p, t_res(2, 1), jsonb_build_array(t_jug(701, 2), t_jug(702, 0, 1), t_jug(703, 0),
                                                              t_jug(704, 1), t_jug(705, 0), t_jug(706, 0)));
    else
      perform enviar_parte(p, t_res(3, 1), jsonb_build_array(t_jug(701, 2), t_jug(702, 1, 1), t_jug(703, 0),
                                                              t_jug(704, 1), t_jug(705, 0), t_jug(706, 0)));
    end if;
  end loop;
end $$;
select t_como(702);
select t_debe_fallar(format('select enviar_parte(%L, %L, %L)', :'p1', t_res(2, 1),
                            jsonb_build_array(t_jug(701, 2, 0), t_jug(702, 0, 2), t_jug(703, 0, 1))),
                     '3 asistencias con 2 goles: rechazado');
select t_como(701);
select t_check(cerrar_post_partido(:'p1') = 'cerrado', 'P1 se cierra solo (mayoría clara)');
select t_check((select goles_local = 2 and goles_visitante = 1 from encuentros where partido_id = :'p1'), 'P1 resultado 2-1');
select t_check((select goles from acta_jugador where partido_id = :'p1' and miembro_id = t_m(701)) = 2, 'u301 2 goles');
select t_check((select goles from acta_jugador where partido_id = :'p1' and miembro_id = t_m(702)) = 0,
               'u302 0 goles (minoría y no cabe en el marcador)');
select t_check((select sum(goles) from acta_jugador a join convocatorias c on c.partido_id = a.partido_id
                 and c.miembro_id = a.miembro_id where a.partido_id = :'p1' and c.equipo = 1) = 2, 'goles del equipo = marcador');
select t_check((select sum(asistencias) from acta_jugador a join convocatorias c on c.partido_id = a.partido_id
                 and c.miembro_id = a.miembro_id where a.partido_id = :'p1' and c.equipo = 1) <= 2, 'asistencias ≤ goles');

-- ═════════ 2. Contradicción real: solo se pregunta eso y se acepta lo propuesto de un toque
select t_jugar7('2027-05-11 20:00 Europe/Madrid') as p2 \gset
select t_como(702);
select enviar_parte(:'p2', t_res(1, 0), jsonb_build_array(t_jug(701, 1), t_jug(704, 0)));
select t_como(704);
select enviar_parte(:'p2', t_res(0, 1), jsonb_build_array(t_jug(701, 0), t_jug(704, 1)));
select t_como(701);
select t_check(cerrar_post_partido(:'p2') = 'en_revision', 'P2: quién ganó no está claro → revisión');
select t_check((select count(*) from disputas where partido_id = :'p2' and not resuelta and tipo = 'encuentro') = 2,
               'P2: solo el resultado en conflicto');
select t_check(not exists (select 1 from disputas where partido_id = :'p2' and tipo = 'descuadre'), 'sin descuadres');
select t_check(aceptar_propuestas(:'p2') = 'cerrado', 'P2 cerrado aceptando lo propuesto');

-- ═════════ 3. Un solo parte: vale ese parte
select t_jugar7('2027-05-18 20:00 Europe/Madrid') as p3 \gset
select t_como(703);
select enviar_parte(:'p3', t_res(3, 2), jsonb_build_array(t_jug(701, 1, 1), t_jug(703, 2), t_jug(705, 2, 1)));
select t_como(701);
select t_check(cerrar_post_partido(:'p3') = 'cerrado', 'P3 con un solo parte se cierra');
select t_check((select goles from acta_jugador where partido_id = :'p3' and miembro_id = t_m(703)) = 2, 'P3 u303 2 goles');
reset role;
select 'escenario_postpartido_ponderado OK';
