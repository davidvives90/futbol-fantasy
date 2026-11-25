-- 0056 · Fase 4: 150 logros y avisos con humor (sigue la liga de la porra de escenario_fase3)
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Porra'), false);
select t_check((select count(*) from logros_catalogo) = 150, 'catálogo con 150 logros');
select t_check((select count(*) from logros_familias_txt) = 270, '30 familias × 9 idiomas');
select t_check((select count(*) from logros_niveles_txt) = 45, '5 niveles × 9 idiomas');
select t_check(not exists (select familia from logros_catalogo group by familia having count(*) <> 5), 'cada familia tiene 5 niveles');
select t_check(nombre_logro('goles_25') = 'Pichichi de barrio · Oro', 'nombre compuesto del logro');
select t_check(traducir_aviso('🏅 Pichichi de barrio · Oro', 'en') = '🏅 Local Golden Boot · Gold', 'aviso de logro traducido');
select t_check(_max_racha(array[true, true, false, true, true, true, false]) = 3, 'racha más larga');
select t_check(_max_racha(null) = 0, 'racha vacía');
select t_check(not exists (select 1 from logros where tipo in ('primer_gol', 'hat_trick', 'manita')), 'sin códigos antiguos');
select t_check(not exists (select 1 from logros l where not exists (select 1 from logros_catalogo c where c.codigo = l.tipo)),
               'todo logro guardado está en el catálogo');

-- La porra de la fase 3: 1001 marcó 2 goles y 1002 acertó boletos
select t_check(exists (select 1 from logros where miembro_id = t_m(1001) and tipo = 'goles_1'), '1001: primer gol');
select t_check(exists (select 1 from logros where miembro_id = t_m(1001) and tipo = 'noche_2'), '1001: doblete (noche mágica bronce)');
select t_check(not exists (select 1 from logros where miembro_id = t_m(1001) and tipo = 'noche_3'), '1001: sin hat-trick');
select t_check(exists (select 1 from logros where miembro_id = t_m(1002) and tipo = 'pitoniso_1'), '1002: pitoniso por la porra');
select t_check((metricas_logros(t_m(1001)) ->> 'goles')::int = 2, 'métrica de goles');
select t_check((metricas_logros(t_m(1004)) ->> 'derrotas')::int = 1, 'métrica de derrotas');
-- Aviso solo del nivel más alto de cada familia y con ruta a la pantalla de logros
select t_check((select count(*) from notificaciones n join miembros m on m.perfil_id = n.perfil_id
                 where m.id = t_m(1001) and n.tipo = 'logro' and n.titulo like '%Noche mágica%') = 1, 'un aviso por familia');
select t_check((select bool_and(ruta like '/logros/%') from notificaciones where tipo = 'logro' and titulo like '% · %'),
               'el aviso de logro abre la pantalla de logros');

set role authenticated;
select t_como(1003);
select logros_de(t_m(1001), 'en') as lg \gset
select t_check((:'lg'::jsonb ->> 'total')::int = 150, 'logros_de: 150');
select t_check(jsonb_array_length(:'lg'::jsonb -> 'logros') = 150, 'logros_de: lista completa');
select t_check((:'lg'::jsonb -> 'logros' -> 0 ->> 'nombre') = 'Local Golden Boot', 'logros_de en inglés');
select t_check((select (x ->> 'valor')::numeric = 2 and x ->> 'conseguido_en' is not null
                  from jsonb_array_elements(:'lg'::jsonb -> 'logros') x where x ->> 'codigo' = 'noche_2'), 'progreso y fecha');
select t_check((select (x ->> 'oculto')::boolean from jsonb_array_elements(:'lg'::jsonb -> 'logros') x where x ->> 'codigo' = 'gafe_3'),
               'los de humor van ocultos');
reset role;
insert into auth.users (id, email) values (t_uid(1099), 'fuera4@test');
insert into perfiles (id, nombre) values (t_uid(1099), 'Fuera');
set role authenticated;
select t_como(1099);
select t_debe_fallar(format($$select logros_de(%L)$$, t_m(1001)), 'fuera de la liga no se ven');
reset role;

-- Avisos con humor
update perfiles set idioma = 'es', avisos_humor = true where id = t_uid(1001);
update perfiles set idioma = 'en', avisos_humor = true where id = t_uid(1002);
update perfiles set avisos_humor = false where id = t_uid(1003);
select notificar(array[t_uid(1001), t_uid(1002), t_uid(1003)], current_setting('t.liga')::uuid, 'equipos', 'Equipos hechos ✅', '');
select t_check((select titulo from notificaciones where perfil_id = t_uid(1001) and tipo = 'equipos' order by id desc limit 1)
                 in (select texto from frases_humor where tipo = 'equipos' and idioma = 'es'), 'título con humor en castellano');
select t_check((select cuerpo from notificaciones where perfil_id = t_uid(1001) and tipo = 'equipos' order by id desc limit 1)
                 = 'Equipos hechos ✅', 'sin cuerpo, el título serio pasa al cuerpo');
select t_check((select titulo from notificaciones where perfil_id = t_uid(1002) and tipo = 'equipos' order by id desc limit 1)
                 in (select texto from frases_humor where tipo = 'equipos' and idioma = 'en'), 'título con humor en inglés');
select t_check((select titulo from notificaciones where perfil_id = t_uid(1003) and tipo = 'equipos' order by id desc limit 1)
                 = 'Equipos hechos ✅', 'quien lo desactiva recibe el aviso serio');
update ligas set avisos_humor = false where id = current_setting('t.liga')::uuid;
select notificar(array[t_uid(1001)], current_setting('t.liga')::uuid, 'equipos', 'Equipos hechos ✅', 'Mira los equipos');
select t_check((select titulo || '|' || cuerpo from notificaciones where perfil_id = t_uid(1001) and tipo = 'equipos'
                 order by id desc limit 1) = 'Equipos hechos ✅|Mira los equipos', 'liga sin humor: aviso serio');
update ligas set avisos_humor = true where id = current_setting('t.liga')::uuid;
select notificar(array[t_uid(1001)], current_setting('t.liga')::uuid, 'porra', '🎯 ¡Porra ganada!', 'Cobras 20 pts');
select t_check((select titulo from notificaciones where perfil_id = t_uid(1001) and tipo = 'porra' order by id desc limit 1)
                 = '🎯 ¡Porra ganada!', 'tipos sin frases: título original');
select t_check((select count(*) from frases_humor) = 14 * 3 * 9, '14 tipos × 3 frases × 9 idiomas');
select t_check(revisar_logros() >= 0, 'revisión horaria');
