-- 0060 · Más atractiva sin complicarla
--  · Alineación: si los roles no puntúan (bonus_roles = false), la alineación es libre: sin posiciones.
--  · Último aviso: a quien tiene plaza sin confirmar (pendiente o duda) el día antes y unas horas antes, y a quien no
--    ha contestado si aún faltan jugadores.
--  · rendimiento_perfil(): estadísticas del jugador en todas sus ligas (las que compartes con él) y el total.
--  · cara_a_cara(): balance contra y con cada compañero (rivalidades).
--  · equipo_ideal(): los mejores de la última jornada o del último mes.
--  · resumen_compartir(): añade el mejor mánager del Fantasy de la jornada y, con humor, el farolillo rojo.

-- ───────────── Alineación libre cuando los roles no puntúan ─────────────
create or replace function alineacion_libre_sin_roles() returns trigger
language plpgsql as $$
begin
  if not new.bonus_roles then new.modo_alineacion := 'libre'; end if;
  return new;
end $$;
create or replace trigger t_alineacion_sin_roles before insert or update of bonus_roles, modo_alineacion on ligas
  for each row execute function alineacion_libre_sin_roles();
update ligas set modo_alineacion = 'libre' where not bonus_roles and modo_alineacion <> 'libre';

-- ───────────── Último aviso de convocatoria ─────────────
create or replace function recordatorio_ultimo_aviso() returns int
language plpgsql security definer set search_path = public as $$
declare p record; k int := 0; v_libres int;
begin
  -- a) Un día antes: quien tiene plaza pero no ha confirmado (fijos «pendiente» o «duda»)
  for p in select pa.* from partidos pa
            where pa.estado in ('abierto', 'completo') and pa.fecha_hora between now() + interval '5 hours' and now() + interval '24 hours'
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'confirmar') loop
    insert into recordatorios_enviados values (p.id, 'confirmar');
    k := k + notificar((select perfiles_de_miembros(array_agg(miembro_id)) from convocatorias
                         where partido_id = p.id and estado in ('pendiente', 'duda')),
                       p.liga_id, 'recordatorio_convocatoria', '¿Vienes? Confirma tu plaza ⚽',
                       'Partido el ' || fecha_corta(p.fecha_hora) || ': pulsa Voy o No voy para que los demás sepan', '/partidos/' || p.id);
  end loop;

  -- b) Unas horas antes: último aviso a los dudosos y, si faltan jugadores, a quien no ha contestado
  for p in select pa.* from partidos pa
            where pa.estado in ('abierto', 'completo') and pa.fecha_hora between now() + interval '90 minutes' and now() + interval '5 hours'
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'ultimo_aviso') loop
    insert into recordatorios_enviados values (p.id, 'ultimo_aviso');
    k := k + notificar((select perfiles_de_miembros(array_agg(miembro_id)) from convocatorias
                         where partido_id = p.id and estado in ('pendiente', 'duda')),
                       p.liga_id, 'recordatorio_convocatoria', 'Último aviso ⏰',
                       'El partido es a las ' || to_char(p.fecha_hora at time zone 'Europe/Madrid', 'HH24:MI') || '. ¿Vienes o no?',
                       '/partidos/' || p.id);
    v_libres := p.plazas - plazas_ocupadas(p.id);
    if p.estado = 'abierto' and v_libres > 0 then
      k := k + notificar((select coalesce(array_agg(m.perfil_id), '{}') from miembros m
                           where m.liga_id = p.liga_id and m.estado = 'activo' and m.perfil_id is not null
                             and not esta_de_baja(m.id, p.fecha_hora)
                             and coalesce(convocatoria_abre_para(p.id, m.id), now()) <= now()
                             and not exists (select 1 from convocatorias c where c.partido_id = p.id and c.miembro_id = m.id)),
                         p.liga_id, 'recordatorio_convocatoria',
                         case when v_libres = 1 then '¡Falta 1 para el partido!' else '¡Faltan ' || v_libres || ' para el partido!' end,
                         'Hoy a las ' || to_char(p.fecha_hora at time zone 'Europe/Madrid', 'HH24:MI') || '. ¿Te apuntas?',
                         '/partidos/' || p.id);
    end if;
  end loop;
  return k;
end $$;
revoke execute on function recordatorio_ultimo_aviso() from public, anon, authenticated;

-- Partidos ya dentro de las ventanas al desplegar: no se avisa con retraso
insert into recordatorios_enviados (partido_id, tipo)
select id, t from partidos, unnest(array['confirmar', 'ultimo_aviso']) t
 where estado in ('abierto', 'completo') and fecha_hora between now() and now() + interval '24 hours'
on conflict do nothing;

do $$
begin
  perform cron.unschedule('ff_ultimo_aviso');
exception when others then null;
end $$;
do $$
begin
  perform cron.schedule('ff_ultimo_aviso', '*/15 * * * *', 'select public.recordatorio_ultimo_aviso()');
exception when others then null;   -- sin pg_cron (pruebas locales)
end $$;

-- ───────────── Estadísticas en todas las ligas ─────────────
create or replace function rendimiento_perfil(p_miembro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with yo as (select perfil_id, liga_id from miembros where id = p_miembro),
  mm as (select m.id from miembros m, yo
          where (m.id = p_miembro or (yo.perfil_id is not null and m.perfil_id = yo.perfil_id))
            and es_miembro(m.liga_id)),
  r as (select v.*, l.nombre from v_rendimiento v join mm on mm.id = v.miembro_id join ligas l on l.id = v.liga_id)
  select case when not exists (select 1 from yo where es_miembro(yo.liga_id)) then null else jsonb_build_object(
    'ligas', coalesce((select jsonb_agg(to_jsonb(r) order by r.partidos desc, r.nombre) from r), '[]'),
    'total', (select jsonb_build_object(
                'miembro_id', p_miembro, 'partidos', coalesce(sum(partidos), 0),
                'puntos_total', coalesce(sum(puntos_total), 0),
                'puntos_media', round(sum(puntos_total) / nullif(sum(partidos), 0), 2),
                'goles', coalesce(sum(goles), 0),
                'goles_partido', round(sum(goles)::numeric / nullif(sum(partidos), 0), 2),
                'asistencias', coalesce(sum(asistencias), 0),
                'nota_media', round(sum(nota_media * partidos) filter (where nota_media is not null)
                                    / nullif(sum(partidos) filter (where nota_media is not null), 0), 2),
                'mvps', coalesce(sum(mvps), 0),
                'pct_victorias', round(100.0 * sum(victorias) / nullif(sum(victorias + empates + derrotas), 0), 1))
                from r)) end
$$;
grant execute on function rendimiento_perfil(uuid) to authenticated;

-- ───────────── Cara a cara (rivalidades) ─────────────
create or replace function cara_a_cara(p_miembro uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_liga uuid;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  if v_liga is null or not es_miembro(v_liga) then raise exception 'No perteneces a esta liga'; end if;
  return coalesce((
    with mis as (
      select c.partido_id, c.equipo,
             case when pf.victorias > pf.derrotas then 'V' when pf.derrotas > pf.victorias then 'D' else 'E' end res
        from convocatorias c
        join puntos_fantasy pf on pf.partido_id = c.partido_id and pf.miembro_id = c.miembro_id
        join partidos p on p.id = c.partido_id
       where c.miembro_id = p_miembro and p.estado = 'cerrado' and c.equipo is not null),
    otros as (
      select c.miembro_id,
             count(*) filter (where c.equipo <> m.equipo) contra_n,
             count(*) filter (where c.equipo <> m.equipo and m.res = 'V') contra_v,
             count(*) filter (where c.equipo <> m.equipo and m.res = 'E') contra_e,
             count(*) filter (where c.equipo <> m.equipo and m.res = 'D') contra_d,
             count(*) filter (where c.equipo = m.equipo) juntos_n,
             count(*) filter (where c.equipo = m.equipo and m.res = 'V') juntos_v
        from mis m join convocatorias c on c.partido_id = m.partido_id and c.equipo is not null
                                       and c.estado = 'confirmado' and c.miembro_id <> p_miembro
       group by c.miembro_id)
    select jsonb_agg(jsonb_build_object('miembro_id', miembro_id, 'nombre', nombre_miembro(miembro_id),
                                        'contra', contra_n, 'v', contra_v, 'e', contra_e, 'd', contra_d,
                                        'juntos', juntos_n, 'juntos_v', juntos_v)
                     order by contra_n + juntos_n desc, nombre_miembro(miembro_id))
      from otros), '[]');
end $$;
grant execute on function cara_a_cara(uuid) to authenticated;

-- ───────────── Equipo ideal ─────────────
-- p_modo: 'jornada' (último partido cerrado) o 'mes' (últimos 30 días; hay que haber jugado la mitad de los partidos)
create or replace function equipo_ideal(p_liga uuid, p_modo text default 'jornada') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l ligas; v_ult uuid; v_n int; v_min int;
begin
  if not es_miembro(p_liga) then raise exception 'No perteneces a esta liga'; end if;
  select * into l from ligas where id = p_liga;
  if p_modo = 'jornada' then
    select id into v_ult from partidos where liga_id = p_liga and estado = 'cerrado' order by fecha_hora desc limit 1;
    if v_ult is null then return jsonb_build_object('jugadores', '[]'); end if;
    return jsonb_build_object(
      'partido_id', v_ult, 'fecha', (select fecha_hora from partidos where id = v_ult),
      'jugadores', coalesce((select jsonb_agg(x order by x.puntos desc) from (
        select pf.miembro_id, nombre_miembro(pf.miembro_id) nombre, pf.total puntos, 1 partidos,
               coalesce(aj.goles, 0) goles, pf.nota_media, pf.es_mvp
          from puntos_fantasy pf left join acta_jugador aj using (partido_id, miembro_id)
         where pf.partido_id = v_ult
         order by pf.total desc, pf.nota_media desc nulls last limit greatest(l.jugadores_por_equipo, 3)) x), '[]'));
  end if;
  select count(*) into v_n from partidos where liga_id = p_liga and estado = 'cerrado' and fecha_hora > now() - interval '30 days';
  v_min := greatest(1, ceil(v_n / 2.0)::int);
  return jsonb_build_object(
    'partidos', v_n, 'minimo', v_min,
    'jugadores', coalesce((select jsonb_agg(x order by x.puntos desc) from (
      select pf.miembro_id, nombre_miembro(pf.miembro_id) nombre, round(avg(pf.total), 1) puntos, count(*) partidos,
             coalesce(sum(aj.goles), 0) goles, round(avg(pf.nota_media), 1) nota_media, count(*) filter (where pf.es_mvp) > 0 es_mvp
        from puntos_fantasy pf join partidos p on p.id = pf.partido_id
        left join acta_jugador aj using (partido_id, miembro_id)
       where p.liga_id = p_liga and p.estado = 'cerrado' and p.fecha_hora > now() - interval '30 days'
       group by pf.miembro_id having count(*) >= v_min
       order by avg(pf.total) desc limit greatest(l.jugadores_por_equipo, 3)) x), '[]'));
end $$;
grant execute on function equipo_ideal(uuid, text) to authenticated;

-- ───────────── Resumen para compartir, ampliado ─────────────
create or replace function resumen_compartir(p_partido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p partidos; l ligas;
begin
  select * into p from partidos where id = p_partido;
  if not found or not es_miembro(p.liga_id) then raise exception 'Partido no encontrado'; end if;
  select * into l from ligas where id = p.liga_id;
  return jsonb_build_object(
    'liga', l.nombre,
    'fecha', p.fecha_hora,
    'estado', p.estado,
    'campo', l.campo_nombre,
    'plazas', p.plazas,
    'abre_en', convocatoria_abre_en(p.id),
    'confirmados', coalesce((select jsonb_agg(nombre_miembro(miembro_id) order by inscrito_en)
                               from convocatorias where partido_id = p.id and estado = 'confirmado'), '[]'),
    'espera', coalesce((select jsonb_agg(nombre_miembro(miembro_id) order by inscrito_en)
                          from convocatorias where partido_id = p.id and estado = 'espera'), '[]'),
    'equipos', coalesce((select jsonb_object_agg(equipo, nombres) from (
                  select equipo, jsonb_agg(nombre_miembro(miembro_id) order by nombre_miembro(miembro_id)) nombres
                    from convocatorias where partido_id = p.id and estado = 'confirmado' and equipo is not null
                   group by equipo) e), '{}'),
    'encuentros', coalesce((select jsonb_agg(jsonb_build_object('n', n, 'local', equipo_local, 'visitante', equipo_visitante,
                                                                'goles_local', goles_local, 'goles_visitante', goles_visitante) order by n)
                              from encuentros where partido_id = p.id), '[]'),
    'goleadores', coalesce((select jsonb_agg(jsonb_build_object('nombre', nombre_miembro(miembro_id), 'goles', goles)
                                             order by goles desc, nombre_miembro(miembro_id))
                              from acta_jugador where partido_id = p.id and goles > 0), '[]'),
    'mvp', (select jsonb_agg(nombre_miembro(miembro_id)) from puntos_fantasy where partido_id = p.id and es_mvp),
    'mejor_nota', (select jsonb_build_object('nombre', nombre_miembro(miembro_id), 'nota', round(nota_media, 1))
                     from puntos_fantasy where partido_id = p.id and nota_media is not null
                    order by nota_media desc limit 1),
    'farolillo', case when l.avisos_humor then
                   (select jsonb_build_object('nombre', nombre_miembro(miembro_id), 'nota', round(nota_media, 1))
                      from puntos_fantasy where partido_id = p.id and nota_media is not null and num_votantes >= 2
                     order by nota_media, total limit 1) end,
    'fantasy_top', case when l.fantasy_activo then
                     (select jsonb_build_object('nombre', nombre_miembro(manager_id), 'puntos', round(puntos, 1))
                        from puntos_manager where partido_id = p.id order by puntos desc limit 1) end);
end $$;
