-- 0034 · Compartir por WhatsApp, temporadas_cerradas con premios y avisos de fin de baja.

-- ── Resumen de un partido para compartir (convocatoria, equipos o resultado)
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
    'mvp', (select jsonb_agg(nombre_miembro(miembro_id)) from puntos_fantasy where partido_id = p.id and es_mvp));
end $$;

-- ── Rendimiento en un periodo (para la clasificación por temporada). Mismas columnas que v_rendimiento.
create or replace function rendimiento_periodo(p_liga uuid, p_desde timestamptz default null, p_hasta timestamptz default null)
returns table (liga_id uuid, miembro_id uuid, partidos bigint, puntos_total numeric, puntos_media numeric, goles bigint,
               goles_partido numeric, asistencias bigint, nota_media numeric, mvps bigint, victorias bigint, empates bigint,
               derrotas bigint, pct_victorias numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not es_miembro(p_liga) then raise exception 'No perteneces a esta liga'; end if;
  return query
  select m.liga_id, pf.miembro_id, count(*), sum(pf.total)::numeric, round(avg(pf.total), 2)::numeric,
         sum(aj.goles)::bigint, round(avg(aj.goles), 2)::numeric, sum(aj.asistencias)::bigint,
         round(avg(pf.nota_media), 2)::numeric, count(*) filter (where pf.es_mvp),
         sum(pf.victorias)::bigint, sum(pf.empates)::bigint, sum(pf.derrotas)::bigint,
         round(100.0 * sum(pf.victorias) / nullif(sum(pf.victorias + pf.empates + pf.derrotas), 0), 1)
    from puntos_fantasy pf
    join miembros m on m.id = pf.miembro_id
    join partidos pa on pa.id = pf.partido_id
    join acta_jugador aj on aj.partido_id = pf.partido_id and aj.miembro_id = pf.miembro_id
   where m.liga_id = p_liga
     and (p_desde is null or pa.fecha_hora >= p_desde)
     and (p_hasta is null or pa.fecha_hora < p_hasta)
   group by m.liga_id, pf.miembro_id;
end $$;

-- ── Temporadas y premios
create table if not exists temporadas_cerradas (
  id             uuid primary key default gen_random_uuid(),
  liga_id        uuid not null references ligas on delete cascade,
  numero         int not null,
  nombre         text not null check (length(nombre) between 1 and 60),
  desde          timestamptz not null,
  hasta          timestamptz not null,
  partidos       int not null default 0,
  clasificacion  jsonb not null default '[]',
  cerrada_en     timestamptz not null default now(),
  unique (liga_id, numero)
);
create table if not exists premios (
  id            uuid primary key default gen_random_uuid(),
  temporada_id  uuid not null references temporadas_cerradas on delete cascade,
  liga_id       uuid not null references ligas on delete cascade,
  miembro_id    uuid not null references miembros on delete cascade,
  tipo          text not null,         -- campeon | pichichi | asistente | mvp | fiel | mejor_nota | ganador
  valor         numeric,
  unique (temporada_id, tipo, miembro_id)
);
create index if not exists premios_miembro on premios (miembro_id);
alter table temporadas_cerradas enable row level security;
alter table premios enable row level security;
drop policy if exists temporadas_leer on temporadas_cerradas;
create policy temporadas_leer on temporadas_cerradas for select to authenticated using (es_miembro(liga_id));
drop policy if exists premios_leer on premios;
create policy premios_leer on premios for select to authenticated using (es_miembro(liga_id));
revoke insert, update, delete on temporadas_cerradas, premios from anon, authenticated;
grant select on temporadas_cerradas, premios to authenticated;

-- Inicio de la temporada en curso (fin de la última cerrada; null = desde siempre)
create or replace function inicio_temporada(p_liga uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select max(hasta) from temporadas_cerradas where liga_id = p_liga
$$;

create or replace function cerrar_temporada(p_liga uuid, p_nombre text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_num int; v_desde timestamptz; v_hasta timestamptz; v_n int; v_min int; v_nombre text;
begin
  if not es_admin(p_liga) then raise exception 'Solo el administrador puede cerrar la temporada'; end if;
  v_desde := coalesce(inicio_temporada(p_liga), '-infinity'::timestamptz);
  select count(*) into v_n from partidos where liga_id = p_liga and estado = 'cerrado' and fecha_hora >= v_desde;
  if v_n = 0 then raise exception 'Esta temporada aún no tiene partidos cerrados'; end if;
  if exists (select 1 from partidos where liga_id = p_liga and estado in ('jugado', 'post_partido', 'en_revision')
               and fecha_hora >= v_desde) then
    raise exception 'Hay partidos sin cerrar: ciérralos antes de cerrar la temporada';
  end if;
  -- la temporada termina ahora (o tras el último partido cerrado, si la fecha de alguno quedó en el futuro)
  select greatest(now(), max(fecha_hora) + interval '1 second') into v_hasta
    from partidos where liga_id = p_liga and estado = 'cerrado' and fecha_hora >= v_desde;
  select coalesce(max(numero), 0) + 1 into v_num from temporadas_cerradas where liga_id = p_liga;
  v_nombre := coalesce(nullif(trim(coalesce(p_nombre, '')), ''), 'Temporada ' || v_num);

  create temp table _r on commit drop as select * from rendimiento_periodo(p_liga, nullif(v_desde, '-infinity'), v_hasta);
  insert into temporadas_cerradas (liga_id, numero, nombre, desde, hasta, partidos, clasificacion)
  values (p_liga, v_num, v_nombre,
          coalesce((select min(fecha_hora) from partidos where liga_id = p_liga and estado = 'cerrado' and fecha_hora >= v_desde), now()),
          v_hasta, v_n,
          coalesce((select jsonb_agg(to_jsonb(r) order by r.puntos_total desc) from _r r), '[]'))
  returning id into v_id;

  -- Mínimo de partidos para premios de media/porcentaje: la mitad de los que jugó el más fiel
  select ceil(max(partidos) / 2.0) into v_min from _r;
  insert into premios (temporada_id, liga_id, miembro_id, tipo, valor)
  select v_id, p_liga, miembro_id, tipo, valor from (
    select miembro_id, 'campeon' tipo, puntos_total valor, rank() over (order by puntos_total desc) rk from _r
    union all select miembro_id, 'pichichi', goles, rank() over (order by goles desc) from _r where goles > 0
    union all select miembro_id, 'asistente', asistencias, rank() over (order by asistencias desc) from _r where asistencias > 0
    union all select miembro_id, 'mvp', mvps, rank() over (order by mvps desc) from _r where mvps > 0
    union all select miembro_id, 'fiel', partidos, rank() over (order by partidos desc) from _r
    union all select miembro_id, 'mejor_nota', nota_media, rank() over (order by nota_media desc) from _r
               where nota_media is not null and partidos >= v_min
    union all select miembro_id, 'ganador', pct_victorias, rank() over (order by pct_victorias desc) from _r
               where pct_victorias is not null and partidos >= v_min
  ) x where rk = 1;

  perform notificar((select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = p_liga and estado = 'activo'),
                    p_liga, 'temporada', v_nombre || ' cerrada 🏆', 'Mira quién se ha llevado los premios', '/palmares');
  return v_id;
end $$;

-- Deshacer el cierre de la última temporada (por si se cerró antes de tiempo)
create or replace function reabrir_temporada(p_liga uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not es_admin(p_liga) then raise exception 'Solo el administrador puede reabrir la temporada'; end if;
  delete from temporadas_cerradas where liga_id = p_liga and numero = (select max(numero) from temporadas_cerradas where liga_id = p_liga);
end $$;

-- ── Aviso de fin de baja
alter table ausencias add column if not exists aviso_fin boolean not null default false;

create or replace function enviar_recordatorios() returns int
language plpgsql security definer set search_path = public as $$
declare p record; k int := 0; v_libres int; v_perfiles uuid[];
begin
  -- 0) Apertura de la convocatoria (modo «apertura»): aviso a todos; a los fijos, que tienen plaza reservada
  for p in select pa.*, l.horas_reserva_fijos as hr from partidos pa join ligas l on l.id = pa.liga_id
            where l.modo_convocatoria = 'apertura' and pa.estado in ('abierto', 'completo') and pa.fecha_hora > now()
              and coalesce(convocatoria_abre_en(pa.id), pa.creado_en) between now() - interval '1 day' and now()
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'apertura') loop
    insert into recordatorios_enviados values (p.id, 'apertura');
    k := k + notificar((select coalesce(array_agg(perfil_id), '{}') from miembros
                         where liga_id = p.liga_id and estado = 'activo' and rango <> 'fijo'
                           and not esta_de_baja(id, p.fecha_hora)),
                       p.liga_id, 'apertura', 'Convocatoria abierta ⚽',
                       '¿Juegas el ' || fecha_corta(p.fecha_hora) || '? Pulsa «Voy» para apuntarte', '/partidos/' || p.id);
    k := k + notificar((select coalesce(array_agg(perfil_id), '{}') from miembros
                         where liga_id = p.liga_id and estado = 'activo' and rango = 'fijo'
                           and not esta_de_baja(id, p.fecha_hora)),
                       p.liga_id, 'apertura', 'Convocatoria abierta ⚽',
                       'Eres fijo: tienes plaza hasta ' || fecha_corta(p.fecha_hora - make_interval(hours => p.hr)) ||
                       '. Pulsa «Voy» o «No voy»', '/partidos/' || p.id);
  end loop;

  -- 0b) Fin de la reserva de los fijos: las plazas sin contestar pasan a la lista de espera
  for p in select pa.* from partidos pa join ligas l on l.id = pa.liga_id
            where l.modo_convocatoria = 'apertura' and pa.estado in ('abierto', 'completo') and pa.fecha_hora > now()
              and pa.fecha_hora - make_interval(hours => l.horas_reserva_fijos) <= now()
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'fin_reserva') loop
    insert into recordatorios_enviados values (p.id, 'fin_reserva');
    perform rellenar_plazas(p.id);
  end loop;

  -- 1) Convocatoria: 24 h antes, si quedan plazas, a quien no ha contestado (o dijo «duda»)
  for p in select pa.* from partidos pa
            where pa.estado = 'abierto' and pa.fecha_hora between now() + interval '2 hours' and now() + interval '24 hours'
              and coalesce(convocatoria_abre_en(pa.id), now()) <= now()
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'convocatoria') loop
    insert into recordatorios_enviados values (p.id, 'convocatoria');
    v_libres := p.plazas - (select count(*) from convocatorias where partido_id = p.id and estado = 'confirmado');
    if v_libres > 0 then
      select coalesce(array_agg(m.perfil_id), '{}') into v_perfiles from miembros m
       where m.liga_id = p.liga_id and m.estado = 'activo' and m.perfil_id is not null
         and not esta_de_baja(m.id, p.fecha_hora)
         and not exists (select 1 from convocatorias c where c.partido_id = p.id and c.miembro_id = m.id
                                                       and c.estado in ('confirmado', 'baja', 'espera'));
      k := k + notificar(v_perfiles, p.liga_id, 'recordatorio_convocatoria',
                         case when v_libres = 1 then 'Falta 1 jugador' else 'Faltan ' || v_libres || ' jugadores' end,
                         '¿Juegas el ' || fecha_corta(p.fecha_hora) || '?', '/partidos/' || p.id);
    end if;
  end loop;

  -- 2) Alineación Fantasy: 1 h antes de que se cierre
  for p in select pa.*, l.horas_cierre_alineacion as h from partidos pa join ligas l on l.id = pa.liga_id
            where pa.estado in ('abierto', 'completo', 'equipos_hechos') and not pa.alineaciones_congeladas and l.fantasy_activo
              and pa.fecha_hora - make_interval(hours => coalesce(l.horas_cierre_alineacion, 2)) between now() and now() + interval '1 hour'
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'alineacion') loop
    insert into recordatorios_enviados values (p.id, 'alineacion');
    k := k + notificar((select perfiles_de_miembros(array_agg(miembro_id)) from fantasy_managers where liga_id = p.liga_id),
                       p.liga_id, 'recordatorio_alineacion', 'Revisa tu alineación',
                       'Se cierra en menos de 1 h (partido del ' || fecha_corta(p.fecha_hora) || ')', '/fantasy');
  end loop;

  -- 3) Post-partido: 3 h antes de que cierre la votación, a quien jugó y no ha enviado nada
  for p in select pa.* from partidos pa
            where pa.estado = 'post_partido' and pa.votacion_cierra between now() and now() + interval '3 hours'
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'votar') loop
    insert into recordatorios_enviados values (p.id, 'votar');
    k := k + notificar((select perfiles_de_miembros(array_agg(c.miembro_id)) from convocatorias c
                         where c.partido_id = p.id and c.estado = 'confirmado' and c.equipo is not null
                           and not exists (select 1 from reportes_encuentro r where r.partido_id = p.id and r.reportero_id = c.miembro_id)
                           and not exists (select 1 from valoraciones v where v.partido_id = p.id and v.votante_id = c.miembro_id)),
                       p.liga_id, 'recordatorio_votar', 'Último aviso: post-partido',
                       'La votación cierra a las ' || to_char(p.votacion_cierra at time zone 'Europe/Madrid', 'HH24:MI') || ' (1 minuto)',
                       '/partidos/' || p.id);
  end loop;
  -- 4) Votaciones de la liga que han llegado a su fecha de cierre
  k := k + cerrar_votaciones_vencidas();

  -- 5) Fin de una baja: «¿Vuelves?» al jugador (una vez, el día siguiente al último día de baja)
  for p in select a.id, a.liga_id, m.perfil_id from ausencias a join miembros m on m.id = a.miembro_id
            where not a.aviso_fin and a.hasta is not null and m.estado = 'activo'
              and a.hasta < (now() at time zone 'Europe/Madrid')::date
              and a.hasta >= (now() at time zone 'Europe/Madrid')::date - 3 loop
    update ausencias set aviso_fin = true where id = p.id;
    k := k + notificar(array[p.perfil_id], p.liga_id, 'fin_baja', 'Se acabó tu baja 💪',
                       '¿Vuelves? Apúntate al próximo partido', '/partidos');
  end loop;
  return k;
end $$;

revoke execute on function resumen_compartir(uuid), rendimiento_periodo(uuid, timestamptz, timestamptz),
  inicio_temporada(uuid), cerrar_temporada(uuid, text), reabrir_temporada(uuid) from public, anon;
grant execute on function resumen_compartir(uuid), rendimiento_periodo(uuid, timestamptz, timestamptz),
  inicio_temporada(uuid), cerrar_temporada(uuid, text), reabrir_temporada(uuid) to authenticated;
