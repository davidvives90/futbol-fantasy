-- 0061 · Bote de la porra, apuestas públicas, presupuesto suficiente, logros de todas las ligas, personalización
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Porra'), false);
select current_setting('t.liga') as lp \gset

-- Presupuesto: da para la alineación completa + 10 %
select t_check(presupuesto_liga(:'lp') >= (select jugadores_por_equipo * valor_base * 1.1 from ligas where id = :'lp'),
               'presupuesto suficiente');
update ligas set modo_copias = 'rareza' where id = :'lp';
select t_check(presupuesto_liga(:'lp') >= (select jugadores_por_equipo * valor_base * 1.25 * 1.1 from ligas where id = :'lp'),
               'con rareza, más presupuesto');
update ligas set modo_copias = 'clasico' where id = :'lp';

-- Partido con porra abierta (dinero) y sin menores
update perfiles set fecha_nacimiento = null where id in (select perfil_id from miembros where liga_id = :'lp');
update config_app set porra_global = true;
update ligas set porra_modo = 'dinero', porra_activa = true, fantasy_activo = true where id = :'lp';
update partidos set estado = 'cancelado' where liga_id = :'lp' and estado not in ('cerrado', 'cancelado');
set role authenticated;
select t_como(1001);
select crear_partido(:'lp'::uuid, now() + interval '2 days', 0) as pb \gset
reset role;
insert into convocatorias (partido_id, miembro_id, estado, equipo)
select :'pb', m.id, 'confirmado', case when row_number() over (order by m.id) % 2 = 0 then 1 else 2 end
  from miembros m where m.liga_id = :'lp' and m.estado = 'activo'
on conflict (partido_id, miembro_id) do update set estado = 'confirmado', equipo = excluded.equipo;
update partidos set estado = 'equipos_hechos' where id = :'pb';
select t_check(porra_abierta(:'pb'), 'porra abierta');

-- Tres mánagers: 1001, 1002 y 1003
set role authenticated;
select t_como(1003);
select entrar_fantasy(:'lp'::uuid);
reset role;
update fantasy_managers set saldo = 100 where liga_id = :'lp' and miembro_id in (t_m(1001), t_m(1002), t_m(1003));
delete from porra_botes where liga_id = :'lp';

set role authenticated;
select t_como(1001);
select jugar_quiniela(:'pb', 2, 1) as j1 \gset
select t_check((:'j1'::jsonb ->> 'total')::numeric = (select round(valor_base / 2, 2) + porra_entrada(:'lp') from ligas where id = :'lp'),
               'bote = fondo inicial + entrada');
select jugar_quiniela(:'pb', 3, 1);   -- cambiar sin pagar otra vez
select t_como(1002);
select jugar_quiniela(:'pb', 1, 0);
select t_como(1003);
select jugar_quiniela(:'pb', 0, 2);
select t_check(jsonb_array_length(porra_bote_json(:'pb') -> 'quinielas') = 3, 'quinielas públicas: se ven todas');
select t_debe_fallar(format($$select jugar_quiniela(%L, 31, 0)$$, :'pb'), 'resultado no válido');
reset role;
select t_check((select saldo from fantasy_managers where liga_id = :'lp' and miembro_id = t_m(1001)) = 100 - porra_entrada(:'lp'),
               'la entrada se cobra una vez');

-- Cierre 3-1: 1001 pleno, 1002 acierta el 1X2, 1003 nada
select (select round(valor_base / 2, 2) from ligas where id = :'lp') + 3 * porra_entrada(:'lp') as bote \gset
insert into encuentros (partido_id, n, equipo_local, equipo_visitante, goles_local, goles_visitante)
values (:'pb', 1, 1, 2, 3, 1) on conflict (partido_id, n) do update set goles_local = 3, goles_visitante = 1;
select perfil_id as adm from miembros where liga_id = :'lp' and rol = 'admin' limit 1 \gset
select set_config('request.jwt.claim.sub', :'adm', false);
update partidos set estado = 'cerrado' where id = :'pb';
select t_check((select acierto from quinielas where partido_id = :'pb' and miembro_id = t_m(1001)) = 'pleno', 'pleno');
select t_check((select acierto from quinielas where partido_id = :'pb' and miembro_id = t_m(1002)) = 'signo', 'acierto 1X2');
select t_check((select acierto from quinielas where partido_id = :'pb' and miembro_id = t_m(1003)) = 'nada', 'fallo');
select t_check((select premio from quinielas where partido_id = :'pb' and miembro_id = t_m(1001))
               = floor(:'bote'::numeric * 0.7 * 100) / 100 + floor(:'bote'::numeric * 0.3 / 2 * 100) / 100, 'premio del pleno');
select t_check((select acumulado from porra_botes where liga_id = :'lp') between 0 and 0.05, 'bote repartido (sobran céntimos)');
set role authenticated;
select t_como(1003);
select ranking_porra(:'lp') as rk \gset
select t_check((select (x ->> 'plenos')::int from jsonb_array_elements(:'rk'::jsonb) x where (x ->> 'miembro_id')::uuid = t_m(1001)) = 1,
               'resumen: plenos');
reset role;

-- Bote desierto: se acumula; partido cancelado: se devuelve
set role authenticated;
select t_como(1001);
select crear_partido(:'lp'::uuid, now() + interval '4 days', 0) as pc \gset
reset role;
insert into convocatorias (partido_id, miembro_id, estado, equipo)
select :'pc', m.id, 'confirmado', case when row_number() over (order by m.id) % 2 = 0 then 1 else 2 end
  from miembros m where m.liga_id = :'lp' and m.estado = 'activo'
on conflict (partido_id, miembro_id) do update set estado = 'confirmado', equipo = excluded.equipo;
update partidos set estado = 'equipos_hechos' where id = :'pc';
set role authenticated;
select t_como(1002);
select jugar_quiniela(:'pc', 5, 5);
reset role;
select saldo as s2 from fantasy_managers where liga_id = :'lp' and miembro_id = t_m(1002) \gset
update partidos set estado = 'cancelado' where id = :'pc';
select t_check((select saldo from fantasy_managers where liga_id = :'lp' and miembro_id = t_m(1002)) = :'s2'::numeric + porra_entrada(:'lp'),
               'cancelado: se devuelve la entrada');

-- Apuestas públicas antes del partido
select t_check(exists (select 1 from pg_policies where tablename = 'apuestas' and policyname = 'apuestas_leer'
                       and qual = 'es_miembro(liga_id)'), 'apuestas públicas para la liga');

-- Logros de todas las ligas
set role authenticated;
select t_como(1001);
select logros_perfil(t_m(1001)) as lg \gset
select t_check((:'lg'::jsonb ->> 'total')::int > 100 and (:'lg'::jsonb ->> 'ligas')::int >= 1, 'logros de todas sus ligas');

-- Personalizar la liga (solo admin)
select t_como(1002);
select t_debe_fallar(format($$select personalizar_liga(%L, '#123456', null)$$, :'lp'), 'solo el admin personaliza');
reset role;
select perfil_id as admin from miembros where liga_id = :'lp' and rol = 'admin' limit 1 \gset
select set_config('request.jwt.claim.sub', :'admin', false);
set role authenticated;
select personalizar_liga(:'lp', '#1a2b3c', 'https://x.supabase.co/storage/v1/object/public/logos/a/logo.png');
select t_debe_fallar(format($$select personalizar_liga(%L, 'rojo', null)$$, :'lp'), 'color no válido');
reset role;
select t_check((select color from ligas where id = :'lp') = '#1A2B3C', 'color guardado');
