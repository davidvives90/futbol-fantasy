-- 0053 · Fase 1
--  1. RGPD: versiones de la política (politicas) y registro de aceptaciones (user_consents).
--  2. Perfil: dorsal (1-99).
--  3. Votación «Podio» (Top 3) además de la rápida y la detallada; podio de los 3 mejores en todas.
--     puntos_fantasy.puesto (1, 2, 3) queda guardado; el 1.º es el MVP.
--  4. Equipo de la jornada (mejor once/cinco por puntos Fantasy, respetando posiciones).
--  5. Fusión de fichas: un jugador fantasma y la cuenta real se unen sin duplicar (reclamar con enlace o
--     el administrador a mano).
--  6. Crear los mánagers del Fantasy de golpe (y uno tardío).
--  7. Historial importado (CSV o tabla): suma en rendimiento, equipos nivelados y logros.

-- ───────────── 1. RGPD ─────────────
create table if not exists politicas (
  version      text primary key,
  publicada_en timestamptz not null default now(),
  url          text not null,
  cambios      text
);
insert into politicas (version, url, cambios)
values ('2026-11-25', 'https://davidvives90.github.io/futbol-fantasy/privacidad.html', 'Primera versión con aceptación explícita')
on conflict do nothing;
alter table politicas enable row level security;
drop policy if exists politicas_leer on politicas;
create policy politicas_leer on politicas for select using (true);
grant select on politicas to anon, authenticated;

-- Historial de solo añadir: cada cambio es una fila nueva (sirve de prueba ante una auditoría).
create table if not exists user_consents (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users on delete cascade,
  policy_version text not null references politicas,
  accepted_at    timestamptz not null default now(),
  consent_flags  jsonb not null,
  plataforma     text,
  check (consent_flags ? 'terminos' and consent_flags ? 'privacidad')
);
create index if not exists user_consents_user on user_consents (user_id, accepted_at desc);
alter table user_consents enable row level security;
drop policy if exists consents_propios on user_consents;
create policy consents_propios on user_consents for select using (user_id = auth.uid());
grant select on user_consents to authenticated;

create or replace function politica_vigente() returns politicas
language sql stable security definer set search_path = public as $$
  select * from politicas order by publicada_en desc, version desc limit 1
$$;

-- Último consentimiento del usuario y si cubre la política vigente.
create or replace function mi_consentimiento() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'politica', (select to_jsonb(p) from politica_vigente() p),
    'ultimo', (select to_jsonb(c) - 'user_id' from user_consents c where c.user_id = auth.uid()
                order by c.accepted_at desc, c.id desc limit 1),
    'al_dia', exists (select 1 from user_consents c
                       where c.user_id = auth.uid() and c.policy_version = (select version from politica_vigente())
                         and (c.consent_flags ->> 'terminos')::boolean and (c.consent_flags ->> 'privacidad')::boolean))
$$;

-- Acepta la política vigente (términos y privacidad obligatorios) o cambia los permisos opcionales.
create or replace function registrar_consentimiento(p_version text, p_errores boolean default false,
                                                    p_anuncios boolean default false, p_plataforma text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Hay que iniciar sesión'; end if;
  if p_version is distinct from (select version from politica_vigente()) then
    raise exception 'La política ha cambiado: vuelve a leerla';
  end if;
  insert into user_consents (user_id, policy_version, consent_flags, plataforma)
  values (auth.uid(), p_version,
          jsonb_build_object('terminos', true, 'privacidad', true,
                             'errores', coalesce(p_errores, false), 'anuncios_personalizados', coalesce(p_anuncios, false)),
          left(p_plataforma, 20));
  return mi_consentimiento();
end $$;

revoke execute on function politica_vigente(), mi_consentimiento(), registrar_consentimiento(text, boolean, boolean, text)
  from public, anon;
grant execute on function politica_vigente(), mi_consentimiento(), registrar_consentimiento(text, boolean, boolean, text)
  to authenticated;

-- ───────────── 2. Dorsal ─────────────
alter table perfiles add column if not exists dorsal smallint check (dorsal between 1 and 99);

-- ───────────── 3. Podio ─────────────
alter table ligas drop constraint if exists ligas_modo_valoracion_ck;
alter table ligas add constraint ligas_modo_valoracion_ck check (modo_valoracion in ('rapida', 'detallada', 'podio'));
alter table ligas add column if not exists puntos_podio smallint[] not null default '{5,3,1}'
  check (array_length(puntos_podio, 1) = 3 and puntos_podio[1] >= puntos_podio[2] and puntos_podio[2] >= puntos_podio[3]
         and puntos_podio[3] >= 0 and puntos_podio[1] <= 20);
alter table puntos_fantasy add column if not exists puesto smallint check (puesto between 1 and 3);

create table if not exists votos_podio (
  partido_id uuid not null references partidos on delete cascade,
  liga_id    uuid not null,
  votante_id uuid not null references miembros on delete cascade,
  votado_id  uuid not null references miembros on delete cascade,
  puesto     smallint not null check (puesto between 1 and 3),
  creado_en  timestamptz not null default now(),
  primary key (partido_id, votante_id, puesto),
  unique (partido_id, votante_id, votado_id),
  check (votante_id <> votado_id)
);
alter table votos_podio enable row level security;
drop policy if exists podio_propio on votos_podio;
create policy podio_propio on votos_podio for select using (votante_id = mi_miembro(liga_id));
grant select on votos_podio to authenticated;

-- Regla con valor por defecto si la liga no la tiene (las nuevas claves no están sembradas)
create or replace function regla_def(p_liga uuid, p_clave text, p_def numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select puntos from reglas_puntuacion where liga_id = p_liga and clave = p_clave and posicion is null), p_def)
$$;

-- Puntos de votación del podio (suma de todos los votantes) y votos por puesto
create or replace function puntos_votacion_podio(p_partido uuid, p_miembro uuid,
                                                 out puntos int, out primeros int, out segundos int, out votantes int)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.puntos_podio[v.puesto]), 0)::int,
         count(*) filter (where v.puesto = 1)::int, count(*) filter (where v.puesto = 2)::int,
         count(distinct v.votante_id)::int
    from votos_podio v join ligas l on l.id = v.liga_id
   where v.partido_id = p_partido and v.votado_id = p_miembro
$$;

drop function if exists enviar_post_partido(uuid, jsonb, jsonb, jsonb, uuid);
create or replace function enviar_post_partido(p_partido uuid, p_resultados jsonb default null,
                                               p_jugadores jsonb default null, p_notas jsonb default null,
                                               p_mvp uuid default null, p_podio uuid[] default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_m uuid; k_parte int := 0; k_notas int := 0; x jsonb; v_votado uuid; v_nota int;
        v_dest jsonb; a record; v_vistos uuid[] := '{}'; i int;
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

  -- Podio: 1.º, 2.º y 3.º mejor (sin votarse a uno mismo). Vale con 1 o 2 si jugaron pocos.
  if p_podio is not null then
    if l.modo_valoracion <> 'podio' then raise exception 'Esta liga no vota por podio'; end if;
    if not jugo_partido(p_partido, v_m) then raise exception 'Solo votan quienes jugaron el partido'; end if;
    if coalesce(array_length(p_podio, 1), 0) not between 1 and 3 then raise exception 'Elige entre 1 y 3 jugadores'; end if;
    delete from votos_podio where partido_id = p_partido and votante_id = v_m;
    for i in 1 .. array_length(p_podio, 1) loop
      v_votado := p_podio[i];
      if v_votado is null then raise exception 'Falta el jugador del puesto %', i; end if;
      if v_votado = v_m then raise exception 'No puedes votarte a ti mismo'; end if;
      if v_votado = any(v_vistos) then raise exception 'Un jugador solo puede estar una vez en tu podio'; end if;
      if not jugo_partido(p_partido, v_votado) then raise exception 'Ese jugador no jugó el partido'; end if;
      v_vistos := v_vistos || v_votado;
      insert into votos_podio (partido_id, liga_id, votante_id, votado_id, puesto)
      values (p_partido, p.liga_id, v_m, v_votado, i);
    end loop;
    k_notas := array_length(p_podio, 1);
  end if;

  if p_notas is not null and l.modo_valoracion <> 'podio' then
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
          values (p_partido, v_m, v_votado, a.key, v_nota);
        end loop;
      elsif x ? 'nota' and x ->> 'nota' is not null then
        v_nota := (x ->> 'nota')::int;
        if v_nota not between 1 and 10 then raise exception 'La nota va de 1 a 10'; end if;
        insert into valoraciones (partido_id, votante_id, votado_id, aspecto, nota)
        values (p_partido, v_m, v_votado, 'general', v_nota);
      else
        continue;
      end if;
      k_notas := k_notas + 1;

      v_dest := coalesce(x -> 'destacados', '[]'::jsonb);
      if jsonb_typeof(v_dest) <> 'array' then raise exception 'Formato de destacados no válido'; end if;
      if jsonb_array_length(v_dest) > 2 then raise exception 'Máximo 2 destacados por jugador'; end if;
      if exists (select 1 from jsonb_array_elements_text(v_dest) d
                  where d = 'general' or not exists (select 1 from aspectos_valoracion av
                                                      where av.liga_id = p.liga_id and av.clave = d)) then
        raise exception 'Destacado no válido';
      end if;
      insert into valoracion_destacados (partido_id, liga_id, votante_id, votado_id, aspecto)
      select p_partido, p.liga_id, v_m, v_votado, d from jsonb_array_elements_text(v_dest) d
      on conflict do nothing;
    end loop;

    if p_mvp is not null then
      if p_mvp = v_m then raise exception 'No puedes votarte como MVP'; end if;
      if not jugo_partido(p_partido, p_mvp) then raise exception 'Tu MVP no jugó el partido'; end if;
      insert into votos_mvp (partido_id, liga_id, votante_id, votado_id) values (p_partido, p.liga_id, v_m, p_mvp);
    end if;
  end if;

  return jsonb_build_object('parte', k_parte, 'notas', k_notas,
                            'mvp', p_mvp is not null and p_notas is not null, 'podio', p_podio is not null);
end $$;
revoke execute on function enviar_post_partido(uuid, jsonb, jsonb, jsonb, uuid, uuid[]) from public, anon;
grant execute on function enviar_post_partido(uuid, jsonb, jsonb, jsonb, uuid, uuid[]) to authenticated;

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
                              'votado_id', t.votado_id, 'nota', t.general, 'aspectos', t.aspectos,
                              'destacados', coalesce((select jsonb_agg(d.aspecto) from valoracion_destacados d
                                                       where d.partido_id = p_partido and d.votante_id = v_m
                                                         and d.votado_id = t.votado_id), '[]')))
                         from (select votado_id,
                                      max(nota) filter (where aspecto = 'general') as general,
                                      coalesce(jsonb_object_agg(aspecto, nota) filter (where aspecto <> 'general'), '{}') as aspectos
                                 from valoraciones where partido_id = p_partido and votante_id = v_m
                                group by votado_id) t), '[]'),
    'mvp', (select votado_id from votos_mvp where partido_id = p_partido and votante_id = v_m),
    'podio', coalesce((select jsonb_agg(votado_id order by puesto) from votos_podio
                        where partido_id = p_partido and votante_id = v_m), '[]'));
end $$;

-- Podio del partido (sustituye a decidir_mvp). Puesto 1 = MVP (puede ser compartido si empatan en todo).
--  · Podio: puntos de votación (5/3/1 por defecto); desempate: votos de 1.º, de 2.º, goles + asistencias.
--  · Rápida/detallada: nota media (con el mínimo de votantes de 0025); desempate: votos «Mi MVP», goles + asist.
-- Puntos Fantasy: 1.º → regla 'mvp'; 2.º → 'podio_2' (2); 3.º → 'podio_3' (1). En modo podio, además,
-- la «valoración» del jugador son sus puntos de podio según su puesto final (5/3/1).
create or replace function decidir_mvp(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_min int; l ligas; k int;
begin
  select li.* into l from ligas li join partidos p on p.liga_id = li.id where p.id = p_partido;
  select least(3, greatest(1, coalesce(max(num_votantes), 0))) into v_min from puntos_fantasy where partido_id = p_partido;
  update puntos_fantasy set puesto = null, es_mvp = false where partido_id = p_partido;

  create temp table if not exists tmp_podio (miembro_id uuid primary key, puesto int) on commit drop;
  delete from tmp_podio where true;

  if l.modo_valoracion = 'podio' then
    insert into tmp_podio
    select miembro_id, r from (
      select pf.miembro_id, s.puntos,
             dense_rank() over (order by s.puntos desc, s.primeros desc, s.segundos desc, aj.goles + aj.asistencias desc) r
        from puntos_fantasy pf join acta_jugador aj using (partido_id, miembro_id)
        cross join lateral puntos_votacion_podio(p_partido, pf.miembro_id) s
       where pf.partido_id = p_partido) t
     where puntos > 0 and r <= 3;
  else
    insert into tmp_podio
    select miembro_id, r from (
      select c.miembro_id, dense_rank() over (order by c.nota desc, c.votos desc, c.ga desc) r
        from (select pf.miembro_id,
                     coalesce(pf.nota_media,
                              (select round(avg(x.m), 2) from (select avg(v.nota) m from valoraciones v
                                                                 where v.partido_id = p_partido and v.votado_id = pf.miembro_id
                                                                 group by v.votante_id) x)) as nota,
                     coalesce((pf.desglose ->> 'votos_mvp')::int, 0) as votos,
                     aj.goles + aj.asistencias as ga
                from puntos_fantasy pf join acta_jugador aj using (partido_id, miembro_id)
               where pf.partido_id = p_partido and pf.num_votantes >= v_min) c
       where c.nota is not null) t
     where r <= 3;
  end if;

  update puntos_fantasy pf
     set puesto = t.puesto, es_mvp = (t.puesto = 1),
         desglose = pf.desglose
                    || jsonb_build_object('mvp', case when t.puesto = 1 then regla(l.id, 'mvp') else 0 end,
                                          'podio', case t.puesto when 2 then regla_def(l.id, 'podio_2', 2)
                                                                 when 3 then regla_def(l.id, 'podio_3', 1) else 0 end)
                    || case when l.modo_valoracion = 'podio'
                            then jsonb_build_object('valoracion', l.puntos_podio[t.puesto]) else '{}' end,
         total = pf.total + case when t.puesto = 1 then regla(l.id, 'mvp') else 0 end
                          + case t.puesto when 2 then regla_def(l.id, 'podio_2', 2)
                                          when 3 then regla_def(l.id, 'podio_3', 1) else 0 end
                          + case when l.modo_valoracion = 'podio' then l.puntos_podio[t.puesto]
                                                                         - coalesce((pf.desglose ->> 'valoracion')::numeric, 0)
                                 else 0 end
    from tmp_podio t
   where pf.partido_id = p_partido and pf.miembro_id = t.miembro_id;

  -- En modo podio quien no entra en el podio no suma valoración (las notas no existen)
  if l.modo_valoracion = 'podio' then
    update puntos_fantasy pf
       set total = pf.total - coalesce((pf.desglose ->> 'valoracion')::numeric, 0),
           desglose = pf.desglose || '{"valoracion": 0}'
     where pf.partido_id = p_partido and pf.puesto is null;
  end if;

  -- Dato informativo para la tarjeta resumen: puntos de votación del podio
  if l.modo_valoracion = 'podio' then
    update puntos_fantasy pf
       set desglose = pf.desglose || jsonb_build_object('votos_podio', s.puntos, 'votos_primero', s.primeros)
      from (select pf2.miembro_id, x.* from puntos_fantasy pf2
              cross join lateral puntos_votacion_podio(p_partido, pf2.miembro_id) x
             where pf2.partido_id = p_partido) s
     where pf.partido_id = p_partido and pf.miembro_id = s.miembro_id;
  end if;

  select count(*) into k from puntos_fantasy where partido_id = p_partido and es_mvp;
  return k;
end $$;
revoke execute on function decidir_mvp(uuid) from public, anon, authenticated;

-- Los datos informativos (votos_podio, votos_primero) no deben sumar: calcular_puntos suma todas las claves
-- numéricas del desglose solo al crear la fila, antes del podio, así que no se ven afectados.

-- Podios de partidos ya cerrados (sin tocar el dinero Fantasy ya liquidado): solo marca el puesto.
do $$
declare p record;
begin
  for p in select pa.id from partidos pa where pa.estado = 'cerrado' and exists
             (select 1 from puntos_fantasy x where x.partido_id = pa.id) loop
    with r as (
      select pf.miembro_id,
             dense_rank() over (order by pf.es_mvp desc, pf.nota_media desc nulls last,
                                coalesce((pf.desglose ->> 'votos_mvp')::int, 0) desc, aj.goles + aj.asistencias desc) rk,
             pf.es_mvp, pf.nota_media
        from puntos_fantasy pf join acta_jugador aj using (partido_id, miembro_id)
       where pf.partido_id = p.id)
    update puntos_fantasy pf set puesto = r.rk
      from r where pf.partido_id = p.id and pf.miembro_id = r.miembro_id and r.rk <= 3
               and (r.es_mvp or r.nota_media is not null);
  end loop;
end $$;

-- ───────────── 4. Equipo de la jornada ─────────────
-- Los N mejores por puntos Fantasy (N = jugadores por equipo). Si los jugadores tienen posición, se respeta un
-- esquema: 1 portero y el resto repartido (F5: 2-1-1, F7: 2-3-1, F11: 4-4-2). Si falta alguien de una
-- posición, el hueco lo ocupa el mejor que quede.
create or replace function equipo_jornada(p_partido uuid)
returns table (miembro_id uuid, posicion posicion_campo, hueco posicion_campo, total numeric, es_mvp boolean, puesto smallint)
language plpgsql stable security definer set search_path = public as $$
declare l ligas; n int; v_def int; v_del int; v_med int; v_con_pos boolean; v_elegidos uuid[] := '{}';
        hueco_pos posicion_campo; k int; r record;
begin
  select li.* into l from ligas li join partidos p on p.liga_id = li.id where p.id = p_partido;
  if not found or not es_miembro(l.id) then raise exception 'No perteneces a esta liga'; end if;
  select count(*) into k from puntos_fantasy pf where pf.partido_id = p_partido;
  n := least(l.jugadores_por_equipo, k);
  if n = 0 then return; end if;

  -- Con posiciones si al menos la mitad de los jugadores tienen una
  select count(*) filter (where pf.posicion is not null) * 2 >= count(*) into v_con_pos
    from puntos_fantasy pf where pf.partido_id = p_partido;

  if v_con_pos and n >= 4 then
    v_def := round((n - 1) * 0.4); v_del := greatest(1, round((n - 1) * 0.2)::int); v_med := n - 1 - v_def - v_del;
    for hueco_pos, k in values ('portero'::posicion_campo, 1), ('defensa', v_def), ('medio', v_med), ('delantero', v_del) loop
      for r in select pf.miembro_id from puntos_fantasy pf
                where pf.partido_id = p_partido and pf.posicion = hueco_pos and pf.miembro_id <> all(v_elegidos)
                order by pf.total desc, pf.puesto nulls last limit k loop
        v_elegidos := v_elegidos || r.miembro_id;
        return query select pf.miembro_id, pf.posicion, hueco_pos, pf.total, pf.es_mvp, pf.puesto
                       from puntos_fantasy pf where pf.partido_id = p_partido and pf.miembro_id = r.miembro_id;
        k := k - 1;
      end loop;
      -- huecos sin jugador de esa posición: el mejor que quede
      for r in select pf.miembro_id from puntos_fantasy pf
                where pf.partido_id = p_partido and pf.miembro_id <> all(v_elegidos)
                  and (select count(*) from puntos_fantasy x where x.partido_id = p_partido
                         and x.posicion = hueco_pos and x.miembro_id = any(v_elegidos)) < case hueco_pos
                        when 'portero' then 1 when 'defensa' then v_def when 'medio' then v_med else v_del end
                order by pf.total desc, pf.puesto nulls last
                limit greatest(0, (case hueco_pos when 'portero' then 1 when 'defensa' then v_def
                                                  when 'medio' then v_med else v_del end)
                                  - (select count(*) from puntos_fantasy x where x.partido_id = p_partido
                                       and x.posicion = hueco_pos and x.miembro_id = any(v_elegidos))::int) loop
        v_elegidos := v_elegidos || r.miembro_id;
        return query select pf.miembro_id, pf.posicion, hueco_pos, pf.total, pf.es_mvp, pf.puesto
                       from puntos_fantasy pf where pf.partido_id = p_partido and pf.miembro_id = r.miembro_id;
      end loop;
    end loop;
  else
    return query select pf.miembro_id, pf.posicion, null::posicion_campo, pf.total, pf.es_mvp, pf.puesto
                   from puntos_fantasy pf where pf.partido_id = p_partido
                  order by pf.total desc, pf.puesto nulls last limit n;
  end if;
end $$;
revoke execute on function equipo_jornada(uuid) from public, anon;
grant execute on function equipo_jornada(uuid) to authenticated;

-- ───────────── 5. Fusión de fichas ─────────────
-- Pasa todo lo de p_absorber (partidos, goles, votos, pagos, Fantasy, logros…) a p_conservar y borra p_absorber.
-- Si ambos tienen el mismo dato (p. ej. los dos en el mismo partido), se queda el de p_conservar.
-- Se recorren todas las claves foráneas a miembros, así que una tabla nueva queda incluida sin tocar esto.
create or replace function _fusionar_miembros(p_conservar uuid, p_absorber uuid) returns int
language plpgsql security definer set search_path = public as $$
declare a miembros; c miembros; fk record; v_ctid tid; k int := 0;
begin
  select * into c from miembros where id = p_conservar for update;
  select * into a from miembros where id = p_absorber for update;
  if c.id is null or a.id is null or c.liga_id <> a.liga_id or c.id = a.id then
    raise exception 'Fichas no válidas para unir';
  end if;

  -- Sin disparadores durante el traspaso (validaciones de partidos ya cerrados, avisos…)
  perform set_config('session_replication_role', 'replica', true);
  for fk in select cl.oid::regclass as tabla, att.attname as col
              from pg_constraint co
              join pg_class cl on cl.oid = co.conrelid
              join pg_attribute att on att.attrelid = co.conrelid and att.attnum = co.conkey[1]
             where co.contype = 'f' and co.confrelid = 'public.miembros'::regclass and array_length(co.conkey, 1) = 1 loop
    for v_ctid in execute format('select ctid from %s where %I = $1', fk.tabla, fk.col) using p_absorber loop
      begin
        execute format('update %s set %I = $1 where ctid = $2', fk.tabla, fk.col) using p_conservar, v_ctid;
        k := k + 1;
      exception when unique_violation or check_violation then
        null;   -- ya existe para p_conservar: se borra al eliminar p_absorber
      end;
    end loop;
  end loop;
  perform set_config('session_replication_role', 'origin', true);

  delete from miembros where id = p_absorber;   -- arrastra lo que quedó duplicado
  update miembros
     set perfil_id = coalesce(c.perfil_id, a.perfil_id),
         rol = case when 'admin' in (c.rol, a.rol) then 'admin'::rol_liga else 'jugador' end,
         estado = case when a.estado = 'activo' or c.estado = 'activo' or a.perfil_id is not null
                       then 'activo'::estado_miembro else c.estado end,
         posicion = coalesce(c.posicion, a.posicion),
         token_invitacion = null,
         unido_en = least(coalesce(c.unido_en, a.unido_en), coalesce(a.unido_en, c.unido_en))
   where id = p_conservar;
  return k;
end $$;
revoke execute on function _fusionar_miembros(uuid, uuid) from public, anon, authenticated;

-- El administrador une una ficha creada a mano (fantasma) con la de un jugador registrado.
create or replace function fusionar_fichas(p_fantasma uuid, p_jugador uuid) returns int
language plpgsql security definer set search_path = public as $$
declare f miembros; j miembros;
begin
  select * into f from miembros where id = p_fantasma;
  select * into j from miembros where id = p_jugador;
  if f.id is null or j.id is null or f.liga_id <> j.liga_id then raise exception 'Fichas no válidas'; end if;
  perform exigir_admin(f.liga_id);
  if f.perfil_id is not null then raise exception 'La primera ficha ya es de un jugador registrado'; end if;
  if j.perfil_id is null then raise exception 'La segunda ficha debe ser de un jugador registrado'; end if;
  -- se conserva la ficha antigua (tiene el historial) y se le asigna la cuenta
  return _fusionar_miembros(p_fantasma, p_jugador);
end $$;
revoke execute on function fusionar_fichas(uuid, uuid) from public, anon;
grant execute on function fusionar_fichas(uuid, uuid) to authenticated;

-- Unirse: con el enlace personal reclama la ficha; si ya estaba en la liga por el código general, se unen.
create or replace function unirse(p_codigo text) returns uuid
language plpgsql security definer set search_path = public as $$
declare m miembros; l ligas; v_yo uuid;
begin
  if auth.uid() is null then raise exception 'Hay que iniciar sesión'; end if;
  if not exists (select 1 from perfiles where id = auth.uid()) then
    raise exception 'Completa tu perfil antes de unirte a una liga';
  end if;

  select * into m from miembros where token_invitacion = p_codigo and estado = 'pendiente_registro' and perfil_id is null;
  if found then
    select id into v_yo from miembros where liga_id = m.liga_id and perfil_id = auth.uid();
    if v_yo is not null then
      if exists (select 1 from miembros where id = v_yo and estado in ('expulsado', 'rechazado')) then
        raise exception 'No puedes volver a esta liga';
      end if;
      perform _fusionar_miembros(m.id, v_yo);
    end if;
    update miembros set perfil_id = auth.uid(), estado = 'activo', token_invitacion = null, unido_en = now()
     where id = m.id;
    return m.liga_id;
  end if;

  select * into l from ligas where codigo_invitacion = upper(trim(p_codigo));
  if not found then raise exception 'Código no válido'; end if;
  if exists (select 1 from miembros where liga_id = l.id and perfil_id = auth.uid()
               and estado in ('expulsado', 'rechazado')) then
    raise exception 'No puedes volver a esta liga';
  end if;
  insert into miembros (liga_id, perfil_id, estado) values (l.id, auth.uid(), 'activo')
  on conflict (liga_id, perfil_id) do update set estado = 'activo', unido_en = now()
   where miembros.estado in ('abandonado', 'solicitud');
  return l.id;
end $$;

-- ───────────── 6. Mánagers de golpe ─────────────
-- Crea el equipo Fantasy de los jugadores registrados indicados (null = todos los activos registrados).
create or replace function crear_managers(p_liga uuid, p_miembros uuid[] default null) returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  perform exigir_admin(p_liga);
  for r in select m.id from miembros m
            where m.liga_id = p_liga and m.estado = 'activo' and m.perfil_id is not null
              and (p_miembros is null or m.id = any(p_miembros))
              and not exists (select 1 from fantasy_managers f where f.liga_id = p_liga and f.miembro_id = m.id)
            order by random() loop   -- orden al azar: el reparto inicial no favorece a nadie
    perform asegurar_manager(p_liga, r.id);
    k := k + 1;
  end loop;
  return k;
end $$;
revoke execute on function crear_managers(uuid, uuid[]) from public, anon;
grant execute on function crear_managers(uuid, uuid[]) to authenticated;

-- ───────────── 7. Historial importado ─────────────
create table if not exists historial_importado (
  miembro_id       uuid primary key references miembros on delete cascade,
  liga_id          uuid not null references ligas on delete cascade,
  partidos         int not null default 0 check (partidos >= 0),
  victorias        int not null default 0 check (victorias >= 0),
  empates          int not null default 0 check (empates >= 0),
  derrotas         int not null default 0 check (derrotas >= 0),
  goles            int not null default 0 check (goles >= 0),
  asistencias      int not null default 0 check (asistencias >= 0),
  mvps             int not null default 0 check (mvps >= 0),
  valoracion_media numeric(4, 2) check (valoracion_media between 1 and 10),
  actualizado_en   timestamptz not null default now(),
  actualizado_por  uuid,
  check (victorias + empates + derrotas <= partidos and mvps <= partidos)
);
create index if not exists historial_importado_liga on historial_importado (liga_id);
alter table historial_importado enable row level security;
drop policy if exists historial_leer on historial_importado;
create policy historial_leer on historial_importado for select using (es_miembro(liga_id));
grant select on historial_importado to authenticated;

create or replace function _normalizar(p text) returns text
language sql immutable as $$
  select lower(translate(trim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')),
                         'áàäâéèëêíìïîóòöôúùüûñçÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇ', 'aaaaeeeeiiiioooouuuuncAAAAEEEEIIIIOOOOUUUUNC'))
$$;

-- Busca la ficha de la liga por nombre (apodo, nombre o nombre provisional), sin tildes ni mayúsculas.
create or replace function _ficha_por_nombre(p_liga uuid, p_nombre text) returns uuid
language sql stable security definer set search_path = public as $$
  select m.id from miembros m left join perfiles pe on pe.id = m.perfil_id
   where m.liga_id = p_liga and m.estado not in ('rechazado', 'expulsado')
     and _normalizar(p_nombre) in (_normalizar(pe.apodo), _normalizar(pe.nombre), _normalizar(m.nombre_provisional))
   order by (m.estado = 'activo') desc, m.unido_en
   limit 1
$$;

-- Previsualización: qué ficha corresponde a cada fila y qué falla, sin guardar nada.
-- p_filas: [{miembro_id?, nombre, partidos, victorias, empates, derrotas, goles, asistencias, mvps, valoracion_media}]
create or replace function previsualizar_historial(p_liga uuid, p_filas jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare x jsonb; v_res jsonb := '[]'; v_id uuid; v_err text; v_n int := 0;
        pj int; v int; e int; d int; g int; a int; mv int; nota numeric;
begin
  perform exigir_admin(p_liga);
  if jsonb_typeof(p_filas) <> 'array' then raise exception 'Formato no válido'; end if;
  if jsonb_array_length(p_filas) > 300 then raise exception 'Máximo 300 jugadores por importación'; end if;
  for x in select value from jsonb_array_elements(p_filas) loop
    v_n := v_n + 1; v_err := null;
    begin
      pj := coalesce((x ->> 'partidos')::int, 0); v := coalesce((x ->> 'victorias')::int, 0);
      e := coalesce((x ->> 'empates')::int, 0); d := coalesce((x ->> 'derrotas')::int, 0);
      g := coalesce((x ->> 'goles')::int, 0); a := coalesce((x ->> 'asistencias')::int, 0);
      mv := coalesce((x ->> 'mvps')::int, 0); nota := nullif(x ->> 'valoracion_media', '')::numeric;
      if pj = 0 then pj := v + e + d; end if;
      if least(pj, v, e, d, g, a, mv) < 0 then v_err := 'Hay números negativos';
      elsif v + e + d > pj then v_err := 'Victorias + empates + derrotas superan los partidos';
      elsif mv > pj then v_err := 'Más MVPs que partidos';
      elsif nota is not null and nota not between 1 and 10 then v_err := 'La valoración va de 1 a 10';
      elsif coalesce(trim(x ->> 'nombre'), '') = '' and x ->> 'miembro_id' is null then v_err := 'Falta el nombre';
      end if;
    exception when others then
      v_err := 'Hay un dato que no es un número';
    end;
    v_id := case when x ->> 'miembro_id' is not null
                 then (select id from miembros where id = (x ->> 'miembro_id')::uuid and liga_id = p_liga)
                 else _ficha_por_nombre(p_liga, x ->> 'nombre') end;
    v_res := v_res || jsonb_build_object('fila', v_n, 'nombre', x ->> 'nombre', 'miembro_id', v_id,
                                         'nuevo', v_id is null, 'error', v_err,
                                         'partidos', pj, 'victorias', v, 'empates', e, 'derrotas', d, 'goles', g,
                                         'asistencias', a, 'mvps', mv, 'valoracion_media', nota);
  end loop;
  return v_res;
end $$;

-- Guarda el historial (sustituye el importado antes de esas fichas). Los nombres que no existen se crean como
-- jugadores fantasma con enlace para que los reclamen. Luego reevalúa los logros (sin avisos).
create or replace function importar_historial(p_liga uuid, p_filas jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x jsonb; v_id uuid; k_nuevos int := 0; k int := 0; v_yo uuid := mi_miembro(p_liga);
begin
  perform exigir_admin(p_liga);
  for x in select value from jsonb_array_elements(previsualizar_historial(p_liga, p_filas)) loop
    if x ->> 'error' is not null then
      raise exception 'Fila % (%): %', x ->> 'fila', coalesce(x ->> 'nombre', '?'), x ->> 'error';
    end if;
  end loop;
  for x in select value from jsonb_array_elements(previsualizar_historial(p_liga, p_filas)) loop
    v_id := (x ->> 'miembro_id')::uuid;
    if v_id is null then
      -- puede aparecer dos veces el mismo nombre nuevo en el archivo
      v_id := _ficha_por_nombre(p_liga, x ->> 'nombre');
      if v_id is null then
        insert into miembros (liga_id, nombre_provisional, estado, invitado_por)
        values (p_liga, trim(x ->> 'nombre'), 'pendiente_registro', v_yo) returning id into v_id;
        k_nuevos := k_nuevos + 1;
      end if;
    end if;
    insert into historial_importado (miembro_id, liga_id, partidos, victorias, empates, derrotas, goles, asistencias,
                                     mvps, valoracion_media, actualizado_por)
    values (v_id, p_liga, (x ->> 'partidos')::int, (x ->> 'victorias')::int, (x ->> 'empates')::int,
            (x ->> 'derrotas')::int, (x ->> 'goles')::int, (x ->> 'asistencias')::int, (x ->> 'mvps')::int,
            (x ->> 'valoracion_media')::numeric, auth.uid())
    on conflict (miembro_id) do update set partidos = excluded.partidos, victorias = excluded.victorias,
      empates = excluded.empates, derrotas = excluded.derrotas, goles = excluded.goles,
      asistencias = excluded.asistencias, mvps = excluded.mvps, valoracion_media = excluded.valoracion_media,
      actualizado_en = now(), actualizado_por = auth.uid();
    k := k + 1;
  end loop;

  perform set_config('ff.sin_avisos', '1', true);
  perform evaluar_logros(m.id, null) from miembros m join historial_importado h on h.miembro_id = m.id
   where m.liga_id = p_liga;
  perform set_config('ff.sin_avisos', '', true);
  return jsonb_build_object('guardados', k, 'nuevos', k_nuevos);
end $$;

create or replace function borrar_historial(p_liga uuid, p_miembro uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  perform exigir_admin(p_liga);
  delete from historial_importado where liga_id = p_liga and (p_miembro is null or miembro_id = p_miembro);
  get diagnostics k = row_count;
  return k;
end $$;

revoke execute on function previsualizar_historial(uuid, jsonb), importar_historial(uuid, jsonb),
                           borrar_historial(uuid, uuid), _ficha_por_nombre(uuid, text) from public, anon;
grant execute on function previsualizar_historial(uuid, jsonb), importar_historial(uuid, jsonb),
                          borrar_historial(uuid, uuid) to authenticated;

-- Rendimiento = partidos de la app + historial importado. Los puntos del historial se estiman con las reglas
-- de la liga (jugado, resultado, goles, asistencias, MVP, nota), para que los equipos nivelados los tengan en cuenta.
create or replace view v_rendimiento with (security_invoker = true) as
with app as (
  select m.liga_id, pf.miembro_id, count(*) n, sum(pf.total) pts, sum(aj.goles) g, sum(aj.asistencias) a,
         sum(pf.nota_media) nota_suma, count(pf.nota_media) nota_n, count(*) filter (where pf.es_mvp) mvps,
         sum(pf.victorias) v, sum(pf.empates) e, sum(pf.derrotas) d
    from puntos_fantasy pf join miembros m on m.id = pf.miembro_id
    join acta_jugador aj using (partido_id, miembro_id)
   group by m.liga_id, pf.miembro_id),
imp as (
  select h.liga_id, h.miembro_id, h.partidos n, h.goles g, h.asistencias a, h.mvps,
         h.victorias v, h.empates e, h.derrotas d,
         h.valoracion_media * h.partidos nota_suma, case when h.valoracion_media is null then 0 else h.partidos end nota_n,
         h.partidos * regla(h.liga_id, 'jugado') + h.victorias * regla(h.liga_id, 'victoria')
           + h.empates * regla(h.liga_id, 'empate') + h.goles * regla(h.liga_id, 'gol')
           + h.asistencias * regla(h.liga_id, 'asistencia') + h.mvps * regla(h.liga_id, 'mvp')
           + case when h.valoracion_media is null then 0
                  else h.partidos * puntos_por_nota(h.valoracion_media, regla(h.liga_id, 'valoracion_max')) end pts
    from historial_importado h where h.partidos > 0),
u as (
  select coalesce(app.liga_id, imp.liga_id) liga_id, coalesce(app.miembro_id, imp.miembro_id) miembro_id,
         coalesce(app.n, 0) + coalesce(imp.n, 0) n,
         coalesce(app.pts, 0) + coalesce(imp.pts, 0) pts,
         coalesce(app.g, 0) + coalesce(imp.g, 0) g, coalesce(app.a, 0) + coalesce(imp.a, 0) a,
         coalesce(app.nota_suma, 0) + coalesce(imp.nota_suma, 0) nota_suma,
         coalesce(app.nota_n, 0) + coalesce(imp.nota_n, 0) nota_n,
         coalesce(app.mvps, 0) + coalesce(imp.mvps, 0) mvps,
         coalesce(app.v, 0) + coalesce(imp.v, 0) v, coalesce(app.e, 0) + coalesce(imp.e, 0) e,
         coalesce(app.d, 0) + coalesce(imp.d, 0) d, coalesce(imp.n, 0) n_imp
    from app full join imp on imp.miembro_id = app.miembro_id)
select liga_id, miembro_id,
       n                                       as partidos,
       round(pts, 2)                           as puntos_total,
       round(pts / nullif(n, 0), 2)            as puntos_media,
       g                                       as goles,
       round(g::numeric / nullif(n, 0), 2)     as goles_partido,
       a                                       as asistencias,
       round(nota_suma / nullif(nota_n, 0), 2) as nota_media,
       mvps,
       v                                       as victorias,
       e                                       as empates,
       d                                       as derrotas,
       round(100.0 * v / nullif(v + e + d, 0), 1) as pct_victorias,
       n_imp                                   as partidos_importados
  from u;
grant select on v_rendimiento to authenticated;

-- Logros con el historial importado (goles, partidos y MVPs acumulados). p_partido null = revisión retroactiva.
create or replace function evaluar_logros(p_miembro uuid, p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_liga uuid; v_goles int; v_gp int; v_mvps int; v_pj int; v_cero int; v_racha int; v_inv int;
        t text; k int := 0; n int; v_grupo boolean; h historial_importado;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  select * into h from historial_importado where miembro_id = p_miembro;
  select coalesce(sum(aj.goles), 0), coalesce(sum(aj.porterias_cero), 0) into v_goles, v_cero
    from acta_jugador aj join partidos pa on pa.id = aj.partido_id
   where aj.miembro_id = p_miembro and pa.estado = 'cerrado';
  select coalesce(goles, 0) into v_gp from acta_jugador where miembro_id = p_miembro and partido_id = p_partido;
  v_gp := coalesce(v_gp, 0);
  select count(*), count(*) filter (where es_mvp) into v_pj, v_mvps
    from puntos_fantasy pf join partidos pa on pa.id = pf.partido_id where pf.miembro_id = p_miembro and pa.estado = 'cerrado';
  v_goles := v_goles + coalesce(h.goles, 0);
  v_pj := v_pj + coalesce(h.partidos, 0);
  v_mvps := v_mvps + coalesce(h.mvps, 0);
  select count(*) filter (where exists (select 1 from puntos_fantasy x where x.partido_id = u.id and x.miembro_id = p_miembro))
    into v_racha
    from (select id from partidos where liga_id = v_liga and estado = 'cerrado' order by fecha_hora desc limit 10) u
   having count(*) = 10;
  select count(*) filter (where derrotas = 0) into v_inv
    from (select pf.derrotas from puntos_fantasy pf join partidos pa on pa.id = pf.partido_id
           where pf.miembro_id = p_miembro and pa.estado = 'cerrado' order by pa.fecha_hora desc limit 5) u
   having count(*) = 5;

  for t in select x from unnest(array[
      case when v_goles >= 1 then 'primer_gol' end, case when v_gp >= 3 then 'hat_trick' end,
      case when v_gp >= 5 then 'manita' end,
      case when v_goles >= 10 then 'goles_10' end, case when v_goles >= 25 then 'goles_25' end,
      case when v_goles >= 50 then 'goles_50' end, case when v_goles >= 100 then 'goles_100' end,
      case when v_mvps >= 1 then 'mvp_1' end, case when v_mvps >= 5 then 'mvp_5' end, case when v_mvps >= 10 then 'mvp_10' end,
      case when v_pj >= 10 then 'partidos_10' end, case when v_pj >= 25 then 'partidos_25' end,
      case when v_pj >= 50 then 'partidos_50' end, case when v_pj >= 100 then 'partidos_100' end,
      case when v_racha = 10 then 'racha_10' end, case when v_inv = 5 then 'invicto_5' end,
      case when v_cero >= 5 then 'muro_5' end]) x where x is not null loop
    insert into logros (liga_id, miembro_id, tipo, partido_id) values (v_liga, p_miembro, t, p_partido)
    on conflict (miembro_id, tipo) do nothing;
    get diagnostics n = row_count;
    if n > 0 then
      k := k + 1;
      if coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
        v_grupo := t in ('hat_trick', 'manita', 'mvp_5', 'mvp_10', 'goles_50', 'goles_100', 'partidos_50', 'partidos_100', 'racha_10');
        perform notificar(case when v_grupo
                            then (select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = v_liga and estado = 'activo')
                            else array[(select perfil_id from miembros where id = p_miembro)] end,
                          v_liga, 'logro', '🏅 ' || nombre_logro(t),
                          case when v_grupo then nombre_miembro(p_miembro) || ' consigue «' || nombre_logro(t) || '»'
                               else '¡Nuevo logro: ' || nombre_logro(t) || '!' end,
                          '/clasificacion/jugador/' || p_miembro);
      end if;
    end if;
  end loop;
  return k;
end $$;
revoke execute on function evaluar_logros(uuid, uuid) from public, anon, authenticated;
