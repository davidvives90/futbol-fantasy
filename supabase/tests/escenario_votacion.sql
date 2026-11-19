-- Escenario 0020 · Post-partido rápido: nota general, destacados, voto MVP y envío único.
-- Se ejecuta tras escenario_v03.sql (Liga Lunes, jugadores u301–u312; u301 admin).
\set ON_ERROR_STOP 1
\pset pager off

reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
select t_check(not exists (select 1 from ligas where modo_valoracion <> 'rapida'), 'todas las ligas en modo rápido');
select t_check(not exists (select id from ligas except select liga_id from aspectos_valoracion where clave = 'general' and activo),
               'aspecto general en todas las ligas');

-- notas de un votante: 9 a los de p_altos, 6 al resto; destacado 'defensa' a u305
create or replace function t_notas(votante int, altos int[]) returns jsonb language sql stable as $$
  select jsonb_agg(jsonb_build_object('votado_id', t_m(s),
                                      'nota', case when s = any(altos) then 9 else 6 end,
                                      'destacados', case when s = 305 then '["defensa"]'::jsonb else '[]'::jsonb end))
    from generate_series(301, 306) s where s <> votante $$;
grant execute on function t_notas to authenticated;

set role authenticated;
select t_jugar('2027-03-16 20:00 Europe/Madrid') as v1 \gset
select set_config('t.v1', :'v1', false);

-- ═════════ 1. Envío único ═════════
do $$
declare r int; p uuid := current_setting('t.v1')::uuid; res jsonb;
begin
  for r in 301..306 loop
    perform t_como(r);
    res := enviar_post_partido(p, t_res(2, 1),
             jsonb_build_array(t_jug(301, 1), t_jug(302, 1), t_jug(303, 0), t_jug(304, 1), t_jug(305, 0), t_jug(306, 0)),
             t_notas(r, array[302, 305]),
             case when r = 305 then t_m(302) else t_m(305) end);
    perform t_check((res ->> 'notas')::int = 5 and (res ->> 'mvp')::boolean, 'envío completo de u' || r);
  end loop;
end $$;

-- reenviar sustituye (u303 cambia de opinión y luego vuelve a la original)
select t_como(303);
select enviar_post_partido(:'v1', null, null, jsonb_build_array(jsonb_build_object('votado_id', t_m(301), 'nota', 4)), null);
select t_check((select count(*) from valoraciones where partido_id = :'v1' and votante_id = t_m(303)) = 1
               and not exists (select 1 from votos_mvp where partido_id = :'v1' and votante_id = t_m(303))
               and not exists (select 1 from valoracion_destacados where partido_id = :'v1' and votante_id = t_m(303)),
               'reenviar las notas sustituye notas, destacados y voto MVP anteriores');
select t_check((select count(*) from reportes_jugador where partido_id = :'v1' and reportero_id = t_m(303)) = 6,
               'enviar solo notas no borra el parte');
select enviar_post_partido(:'v1', null, null, t_notas(303, array[302, 305]), t_m(305));

select (mi_post_partido(:'v1')) as mio \gset
select t_check(jsonb_array_length((:'mio'::jsonb) -> 'notas') = 5 and (:'mio'::jsonb ->> 'mvp')::uuid = t_m(305)
               and jsonb_array_length((:'mio'::jsonb) -> 'resultados') = 1, 'mi_post_partido devuelve lo enviado');

-- validaciones
select t_debe_fallar(format('select enviar_post_partido(%L, null, null, %L::jsonb)', :'v1',
                     jsonb_build_array(jsonb_build_object('votado_id', t_m(303), 'nota', 7))), 'no puedes valorarte');
select t_debe_fallar(format('select enviar_post_partido(%L, null, null, %L::jsonb)', :'v1',
                     jsonb_build_array(jsonb_build_object('votado_id', t_m(301), 'nota', 11))), 'nota fuera de rango');
select t_debe_fallar(format('select enviar_post_partido(%L, null, null, %L::jsonb)', :'v1',
                     jsonb_build_array(jsonb_build_object('votado_id', t_m(301), 'nota', 7,
                       'destacados', '["ataque","defensa","esfuerzo"]'::jsonb))), 'máximo 2 destacados');
select t_debe_fallar(format('select enviar_post_partido(%L, null, null, %L::jsonb)', :'v1',
                     jsonb_build_array(jsonb_build_object('votado_id', t_m(301), 'nota', 7,
                       'destacados', '["general"]'::jsonb))), 'general no es un destacado');
select t_debe_fallar(format('select enviar_post_partido(%L, null, null, %L::jsonb, %L)', :'v1', '[]', t_m(303)),
                     'no puedes votarte como MVP');
select t_debe_fallar(format('select enviar_post_partido(%L, null, null, %L::jsonb, %L)', :'v1', '[]', t_m(307)),
                     'el MVP tiene que haber jugado');
select t_debe_fallar(format('select enviar_post_partido(%L, %L::jsonb, %L::jsonb)', :'v1', t_res(1, 1),
                     jsonb_build_array(t_jug(301, 2))), 'el parte sigue validando el cuadre');
select t_debe_fallar(format('insert into votos_mvp (partido_id, liga_id, votante_id, votado_id) values (%L, %L, %L, %L)',
                     :'v1', current_setting('t.liga'), t_m(303), t_m(301)), 'nadie escribe votos MVP directamente');
select t_check((select count(*) from votos_mvp where partido_id = :'v1') = 1, 'cada uno solo ve su voto MVP');

-- ═════════ 2. Cierre: el voto MVP desempata ═════════
select t_como(301);
select t_check(cerrar_post_partido(:'v1') = 'cerrado', 'V1 cerrado sin disputas');
select t_check((select es_mvp from puntos_fantasy where partido_id = :'v1' and miembro_id = t_m(305))
               and not (select es_mvp from puntos_fantasy where partido_id = :'v1' and miembro_id = t_m(302)),
               'empate a nota 9: MVP para u305 (5 votos) aunque u302 tiene más goles + asistencias');
select t_check((select nota_media = 9 and num_votantes = 5 and (desglose ->> 'votos_mvp')::int = 5
                       and (desglose -> 'destacados' ->> 'defensa')::int = 5 and (desglose -> 'notas' ->> 'general')::numeric = 9
                  from puntos_fantasy where partido_id = :'v1' and miembro_id = t_m(305)),
               'u305: nota 9, 5 votos MVP, destacado en defensa ×5');
select t_check((select total from puntos_fantasy where partido_id = :'v1' and miembro_id = t_m(305)) = 2 + 0 + 4 + 3,
               'u305: jugado 2 + derrota 0 + nota 9 → 4 + MVP 3 = 9');
select t_check((select veces from v_destacados where miembro_id = t_m(305) and aspecto = 'defensa') = 5, 'v_destacados publica el recuento');

-- ═════════ 3. Modo detallado ═════════
reset role;
update ligas set modo_valoracion = 'detallada' where id = current_setting('t.liga')::uuid;
set role authenticated;
select t_jugar('2027-03-23 20:00 Europe/Madrid') as v2 \gset
select set_config('t.v2', :'v2', false);
do $$
declare r int; p uuid := current_setting('t.v2')::uuid;
begin
  for r in 301..306 loop
    perform t_como(r);
    perform enviar_post_partido(p, t_res(0, 0),
      jsonb_build_array(t_jug(301, 0), t_jug(302, 0), t_jug(303, 0), t_jug(304, 0), t_jug(305, 0), t_jug(306, 0)),
      (select jsonb_agg(jsonb_build_object('votado_id', t_m(s), 'nota', 2, 'aspectos', '{"ataque": 8, "defensa": 6}'::jsonb))
         from generate_series(301, 306) s where s <> r));
  end loop;
end $$;
select t_como(301);
select t_check(cerrar_post_partido(:'v2') = 'cerrado', 'V2 (detallado) cerrado');
select t_check((select bool_and(nota_media = 7 and (desglose -> 'notas' ->> 'ataque')::numeric = 8
                                and not (desglose -> 'notas' ? 'general'))
                  from puntos_fantasy where partido_id = :'v2'),
               'modo detallado: nota = media de aspectos (7), la nota general se ignora');
select t_check((select count(*) from puntos_fantasy where partido_id = :'v2' and es_mvp) = 6, 'todo igualado: MVP compartido');

-- ═════════ 4. Permisos ═════════
reset role;
set role anon;
select t_debe_fallar(format('select enviar_post_partido(%L)', :'v2'), 'anon no envía');
select t_debe_fallar('select count(*) from votos_mvp', 'anon no lee votos MVP');
reset role;
select t_check(not has_function_privilege('authenticated', 'sembrar_liga_defecto(uuid)', 'execute'), 'sembrar_liga_defecto sigue interna');
select t_check(has_function_privilege('authenticated', 'enviar_post_partido(uuid, jsonb, jsonb, jsonb, uuid)', 'execute'),
               'la app puede enviar el post-partido');

\echo '══════ ESCENARIO VOTACIÓN RÁPIDA COMPLETADO SIN ERRORES ══════'
