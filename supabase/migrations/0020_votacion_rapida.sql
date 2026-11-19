-- 0020 · v0.3b · Post-partido rápido (docs/v03b_votacion.md)
--  · Una nota general 1–10 por compañero (aspecto 'general') en vez de 5 aspectos; las ligas pueden volver al
--    modo detallado (ligas.modo_valoracion).
--  · «Destacó en…» (máx. 2 por compañero, solo positivo) conserva la información por aspecto sin pedir números.
--  · Voto «Mi MVP» (1 por votante): desempata el MVP antes que goles + asistencias.
--  · enviar_post_partido: parte + notas + destacados + MVP en una sola llamada atómica.
-- Aditiva: valoraciones, nota_partido y enviar_parte no cambian; calcular_puntos se redefine (misma lógica + MVP
-- por votos + desglose con destacados y votos MVP).

-- ───────────── Modo de valoración de la liga ─────────────
alter table ligas add column modo_valoracion text not null default 'rapida'
  constraint ligas_modo_valoracion_ck check (modo_valoracion in ('rapida', 'detallada'));

-- ───────────── Aspecto 'general' en todas las ligas ─────────────
insert into aspectos_valoracion (liga_id, clave, nombre, descripcion, orden, aplica_a, activo)
select id, 'general', 'Nota general', 'Cómo jugó en conjunto (6 = normal)', 0, 'todos', true from ligas
on conflict (liga_id, clave) do update set activo = true;

create or replace function sembrar_liga_defecto(p_liga uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into reglas_puntuacion (liga_id, clave, puntos) values
    (p_liga, 'jugado',                 2),
    (p_liga, 'victoria',               3),
    (p_liga, 'empate',                 1),
    (p_liga, 'gol',                    5),
    (p_liga, 'asistencia',             3),
    (p_liga, 'parada_clave_2',         1),
    (p_liga, 'penalti_parado',         3),
    (p_liga, 'penalti_fallado',       -2),
    (p_liga, 'autogol',               -2),
    (p_liga, 'valoracion_max',         4),
    (p_liga, 'mvp',                    3),
    (p_liga, 'rol_por_porteria_cero',  3),
    (p_liga, 'rol_por_menos_goleado',  2),
    (p_liga, 'rol_por_encajados_3',   -1),
    (p_liga, 'rol_def_menos_goleado',  1),
    (p_liga, 'rol_med_asistencia',     1),
    (p_liga, 'rol_del_gol',            1)
  on conflict do nothing;

  insert into aspectos_valoracion (liga_id, clave, nombre, descripcion, orden, aplica_a, activo) values
    (p_liga, 'general',      'Nota general',  'Cómo jugó en conjunto (6 = normal)',            0, 'todos', true),
    (p_liga, 'ataque',       'Ataque',        'Peligro, regate, remate y desmarque',           1, 'todos', true),
    (p_liga, 'defensa',      'Defensa',       'Recuperaciones, marcaje, ayudas atrás',         2, 'todos', true),
    (p_liga, 'pase_vision',  'Pase y visión', 'Precisión, último pase, hacer jugar al equipo', 3, 'todos', true),
    (p_liga, 'esfuerzo',     'Esfuerzo',      'Intensidad, presión y compromiso',              4, 'todos', true),
    (p_liga, 'juego_limpio', 'Juego limpio',  'Deportividad y respeto',                        5, 'todos', true),
    (p_liga, 'porteria',     'Portería',      'Paradas, salidas y colocación (si se activa, a todos)', 6, 'todos', false)
  on conflict do nothing;
end $$;

-- ───────────── Destacados y votos MVP (anónimos, como las valoraciones) ─────────────
create table valoracion_destacados (
  partido_id uuid not null references partidos on delete cascade,
  liga_id    uuid not null,
  votante_id uuid not null references miembros on delete cascade,
  votado_id  uuid not null references miembros on delete cascade,
  aspecto    text not null check (aspecto <> 'general'),
  creado_en  timestamptz not null default now(),
  primary key (partido_id, votante_id, votado_id, aspecto),
  foreign key (liga_id, aspecto) references aspectos_valoracion (liga_id, clave) on delete cascade,
  check (votante_id <> votado_id)
);
create index valoracion_destacados_votado on valoracion_destacados (partido_id, votado_id);

create table votos_mvp (
  partido_id uuid not null references partidos on delete cascade,
  liga_id    uuid not null,
  votante_id uuid not null references miembros on delete cascade,
  votado_id  uuid not null references miembros on delete cascade,
  creado_en  timestamptz not null default now(),
  primary key (partido_id, votante_id),
  check (votante_id <> votado_id)
);
create index votos_mvp_votado on votos_mvp (partido_id, votado_id);

alter table valoracion_destacados enable row level security;
alter table votos_mvp enable row level security;
revoke all on valoracion_destacados, votos_mvp from anon, public, authenticated;
grant select on valoracion_destacados, votos_mvp to authenticated;
create policy destacados_propios on valoracion_destacados for select to authenticated
  using (votante_id = mi_miembro(liga_id));
create policy mvp_propio on votos_mvp for select to authenticated
  using (votante_id = mi_miembro(liga_id));
-- escritura: solo enviar_post_partido

-- ───────────── Envío único del post-partido ─────────────
-- p_resultados / p_jugadores: como enviar_parte (null en ambos = no toca el parte).
-- p_notas: [{"votado_id":"…","nota":7,"destacados":["ataque"],"aspectos":{"ataque":7,…}}] (null = no toca las notas).
--   Modo rápido: «nota» se guarda como aspecto 'general'. Modo detallado: «aspectos» (sin 'general').
--   Reemplaza TODAS las notas, destacados y voto MVP previos del votante en ese partido.
-- p_mvp: miembro al que vota como MVP (opcional; solo se tiene en cuenta si p_notas no es null).
create or replace function enviar_post_partido(p_partido uuid, p_resultados jsonb default null,
                                               p_jugadores jsonb default null, p_notas jsonb default null,
                                               p_mvp uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_m uuid; k_parte int := 0; k_notas int := 0; x jsonb; v_votado uuid; v_nota int;
        v_dest jsonb; a record; v_vistos uuid[] := '{}';
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  select * into l from ligas where id = p.liga_id;
  v_m := mi_miembro(p.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if p.estado <> 'post_partido' then raise exception 'El partido no está en periodo de partes y valoraciones'; end if;

  if p_resultados is not null or p_jugadores is not null then
    k_parte := enviar_parte(p_partido, p_resultados, p_jugadores);
  end if;

  if p_notas is not null then
    if jsonb_typeof(p_notas) <> 'array' then raise exception 'Formato de notas no válido'; end if;
    if not jugo_partido(p_partido, v_m) then raise exception 'Solo valoran quienes jugaron el partido'; end if;

    delete from valoraciones where partido_id = p_partido and votante_id = v_m;
    delete from valoracion_destacados where partido_id = p_partido and votante_id = v_m;
    delete from votos_mvp where partido_id = p_partido and votante_id = v_m;

    for x in select value from jsonb_array_elements(p_notas) loop
      v_votado := (x ->> 'votado_id')::uuid;
      if v_votado is null then raise exception 'Falta el jugador valorado'; end if;
      if v_votado = v_m then raise exception 'No puedes valorarte a ti mismo'; end if;
      if v_votado = any(v_vistos) then raise exception 'Jugador valorado dos veces'; end if;
      v_vistos := v_vistos || v_votado;
      if not jugo_partido(p_partido, v_votado) then raise exception 'Ese jugador no jugó el partido'; end if;

      if l.modo_valoracion = 'detallada' and jsonb_typeof(x -> 'aspectos') = 'object' then
        for a in select key, value from jsonb_each_text(x -> 'aspectos') loop
          if a.key = 'general' then continue; end if;
          v_nota := a.value::int;
          if v_nota not between 1 and 10 then raise exception 'La nota va de 1 a 10'; end if;
          insert into valoraciones (partido_id, votante_id, votado_id, aspecto, nota)
          values (p_partido, v_m, v_votado, a.key, v_nota);   -- el trigger valida aspecto activo
        end loop;
      elsif x ? 'nota' and x ->> 'nota' is not null then
        v_nota := (x ->> 'nota')::int;
        if v_nota not between 1 and 10 then raise exception 'La nota va de 1 a 10'; end if;
        insert into valoraciones (partido_id, votante_id, votado_id, aspecto, nota)
        values (p_partido, v_m, v_votado, 'general', v_nota);
      else
        continue;   -- sin nota: no lo valora
      end if;
      k_notas := k_notas + 1;

      v_dest := coalesce(x -> 'destacados', '[]'::jsonb);
      if jsonb_typeof(v_dest) <> 'array' then raise exception 'Formato de destacados no válido'; end if;
      if jsonb_array_length(v_dest) > 2 then raise exception 'Máximo 2 destacados por jugador'; end if;
      insert into valoracion_destacados (partido_id, liga_id, votante_id, votado_id, aspecto)
      select p_partido, p.liga_id, v_m, v_votado, d
        from jsonb_array_elements_text(v_dest) d
       where exists (select 1 from aspectos_valoracion av
                      where av.liga_id = p.liga_id and av.clave = d and av.clave <> 'general')
      on conflict do nothing;
      if exists (select 1 from jsonb_array_elements_text(v_dest) d
                  where d = 'general' or not exists (select 1 from aspectos_valoracion av
                                                      where av.liga_id = p.liga_id and av.clave = d)) then
        raise exception 'Destacado no válido';
      end if;
    end loop;

    if p_mvp is not null then
      if p_mvp = v_m then raise exception 'No puedes votarte como MVP'; end if;
      if not jugo_partido(p_partido, p_mvp) then raise exception 'Tu MVP no jugó el partido'; end if;
      insert into votos_mvp (partido_id, liga_id, votante_id, votado_id) values (p_partido, p.liga_id, v_m, p_mvp);
    end if;
  end if;

  return jsonb_build_object('parte', k_parte, 'notas', k_notas, 'mvp', p_mvp is not null and p_notas is not null);
end $$;

-- Lo que este jugador ya envió (para reabrir y corregir). Solo sus propios datos.
create or replace function mi_post_partido(p_partido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p partidos; v_m uuid;
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  v_m := mi_miembro(p.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  return jsonb_build_object(
    'resultados', coalesce((select jsonb_agg(jsonb_build_object('n', n, 'goles_local', goles_local,
                                                                'goles_visitante', goles_visitante) order by n)
                              from reportes_encuentro where partido_id = p_partido and reportero_id = v_m), '[]'),
    'jugadores', coalesce((select jsonb_agg(jsonb_build_object('sujeto_id', sujeto_id, 'goles', goles,
                              'asistencias', asistencias, 'autogoles', autogoles, 'paradas_clave', paradas_clave,
                              'penaltis_parados', penaltis_parados, 'penaltis_fallados', penaltis_fallados))
                             from reportes_jugador where partido_id = p_partido and reportero_id = v_m), '[]'),
    'notas', coalesce((select jsonb_agg(jsonb_build_object(
                              'votado_id', t.votado_id,
                              'nota', t.general,
                              'aspectos', t.aspectos,
                              'destacados', coalesce((select jsonb_agg(d.aspecto) from valoracion_destacados d
                                                       where d.partido_id = p_partido and d.votante_id = v_m
                                                         and d.votado_id = t.votado_id), '[]')))
                         from (select votado_id,
                                      max(nota) filter (where aspecto = 'general') as general,
                                      coalesce(jsonb_object_agg(aspecto, nota) filter (where aspecto <> 'general'), '{}') as aspectos
                                 from valoraciones where partido_id = p_partido and votante_id = v_m
                                group by votado_id) t), '[]'),
    'mvp', (select votado_id from votos_mvp where partido_id = p_partido and votante_id = v_m));
end $$;

-- ───────────── Puntos: MVP por votos y desglose con destacados ─────────────
create or replace function calcular_puntos(p_partido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; a record; v_v int; v_e int; v_d int; v_nota record; d jsonb; v_total numeric;
        v_max_nota numeric; v_max_votos int; v_max_ga int; v_dest jsonb; v_votos int;
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado not in ('post_partido', 'en_revision') then
    raise exception 'El partido no está pendiente de puntuar (estado: %)', p.estado;
  end if;
  if exists (select 1 from disputas where partido_id = p_partido and not resuelta) then
    raise exception 'Quedan datos en disputa por resolver';
  end if;
  if exists (select 1 from encuentros where partido_id = p_partido and goles_local is null) then
    raise exception 'El acta no está consolidada';
  end if;
  select * into l from ligas where id = p.liga_id;

  delete from puntos_fantasy where partido_id = p_partido;

  for a in select aj.*, c.equipo from acta_jugador aj
             join convocatorias c on c.partido_id = aj.partido_id and c.miembro_id = aj.miembro_id
            where aj.partido_id = p_partido loop
    select count(*) filter (where gf > gc), count(*) filter (where gf = gc), count(*) filter (where gf < gc)
      into v_v, v_e, v_d
      from (select case when e.equipo_local = a.equipo then e.goles_local else e.goles_visitante end gf,
                   case when e.equipo_local = a.equipo then e.goles_visitante else e.goles_local end gc
              from encuentros e
             where e.partido_id = p_partido and a.equipo in (e.equipo_local, e.equipo_visitante)) t;

    v_nota := nota_partido(p_partido, a.miembro_id);

    d := jsonb_build_object(
      'jugado',            regla(l.id, 'jugado'),
      'resultado',         v_v * regla(l.id, 'victoria') + v_e * regla(l.id, 'empate'),
      'goles',             a.goles * regla(l.id, 'gol'),
      'asistencias',       a.asistencias * regla(l.id, 'asistencia'),
      'paradas',           floor(a.paradas_clave / 2.0) * regla(l.id, 'parada_clave_2'),
      'penaltis_parados',  a.penaltis_parados * regla(l.id, 'penalti_parado'),
      'penaltis_fallados', a.penaltis_fallados * regla(l.id, 'penalti_fallado'),
      'autogoles',         a.autogoles * regla(l.id, 'autogol'),
      'valoracion',        puntos_por_nota(v_nota.nota, regla(l.id, 'valoracion_max')),
      'mvp',               0);

    select sum(value::numeric) into v_total from jsonb_each_text(d);

    -- Datos informativos (no suman): notas por aspecto, destacados y votos MVP. Solo con ≥ 3 votantes.
    select coalesce(jsonb_object_agg(aspecto, n), '{}') into v_dest
      from (select aspecto, count(*) n from valoracion_destacados
             where partido_id = p_partido and votado_id = a.miembro_id group by aspecto) t;
    select count(*) into v_votos from votos_mvp where partido_id = p_partido and votado_id = a.miembro_id;
    if coalesce(v_nota.votantes, 0) < 3 then v_dest := '{}'; end if;
    d := d || jsonb_build_object('notas', v_nota.por_aspecto, 'destacados', v_dest, 'votos_mvp', v_votos);

    insert into puntos_fantasy (partido_id, miembro_id, posicion, victorias, empates, derrotas,
                                nota_media, num_votantes, es_mvp, desglose, total)
    values (p_partido, a.miembro_id, posicion_de(a.miembro_id), v_v, v_e, v_d, v_nota.nota, v_nota.votantes,
            false, d, v_total);
  end loop;

  -- MVP: mayor nota (≥ 3 votantes); desempate: votos «Mi MVP», luego goles + asistencias; si persiste, compartido
  select max(nota_media) into v_max_nota from puntos_fantasy
   where partido_id = p_partido and num_votantes >= 3;
  if v_max_nota is not null then
    select max((desglose ->> 'votos_mvp')::int) into v_max_votos from puntos_fantasy
     where partido_id = p_partido and num_votantes >= 3 and nota_media = v_max_nota;
    select max(aj.goles + aj.asistencias) into v_max_ga
      from puntos_fantasy pf join acta_jugador aj using (partido_id, miembro_id)
     where pf.partido_id = p_partido and pf.num_votantes >= 3 and pf.nota_media = v_max_nota
       and (pf.desglose ->> 'votos_mvp')::int = v_max_votos;

    update puntos_fantasy pf
       set es_mvp = true,
           desglose = jsonb_set(pf.desglose, '{mvp}', to_jsonb(regla(p.liga_id, 'mvp'))),
           total = pf.total + regla(p.liga_id, 'mvp')
      from acta_jugador aj
     where aj.partido_id = pf.partido_id and aj.miembro_id = pf.miembro_id
       and pf.partido_id = p_partido and pf.num_votantes >= 3
       and pf.nota_media = v_max_nota and (pf.desglose ->> 'votos_mvp')::int = v_max_votos
       and aj.goles + aj.asistencias = v_max_ga;
  end if;

  update partidos set estado = 'cerrado' where id = p_partido;
end $$;

-- ───────────── Estadística de destacados (publicada, a partir de partidos cerrados) ─────────────
create or replace view v_destacados with (security_invoker = true) as
select m.liga_id, pf.miembro_id, d.key as aspecto, sum(d.value::int) as veces, count(*) as partidos
  from puntos_fantasy pf
  join miembros m on m.id = pf.miembro_id
  cross join lateral jsonb_each_text(coalesce(pf.desglose -> 'destacados', '{}')) d
 group by m.liga_id, pf.miembro_id, d.key;

-- ───────────── Permisos ─────────────
revoke all on v_destacados from anon, public, authenticated;
grant select on v_destacados to authenticated;
revoke execute on function enviar_post_partido(uuid, jsonb, jsonb, jsonb, uuid), mi_post_partido(uuid),
                           calcular_puntos(uuid), sembrar_liga_defecto(uuid) from public, anon;
revoke execute on function sembrar_liga_defecto(uuid) from authenticated;
grant execute on function enviar_post_partido(uuid, jsonb, jsonb, jsonb, uuid), mi_post_partido(uuid),
                          calcular_puntos(uuid) to authenticated;
