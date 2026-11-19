-- 0016 · v0.3 · Temporada: partidos recurrentes entre dos fechas (docs/v03_liga.md §3)
--
-- Decisiones:
--  · La hora se interpreta en Europe/Madrid: "lunes a las 21:00" es 21:00 en invierno y en verano.
--  · Solo se crean partidos FUTUROS (los días ya pasados del rango se saltan) y nunca dos el mismo día en la liga
--    (si ya hay un partido no cancelado ese día, se respeta y no se crea otro).
--  · hora_fija = false → hora tentativa: los partidos se crean con hora_confirmada = false.
--  · Los fijos se inscriben solos en cada partido creado (trigger de 0015).

create table temporadas (
  id            uuid primary key default gen_random_uuid(),
  liga_id       uuid not null references ligas on delete cascade,
  nombre        text,
  desde         date not null,
  hasta         date not null,
  dias_semana   smallint[] not null,
  hora          time not null,
  hora_fija     boolean not null default true,
  coste_partido numeric(8,2) not null default 0 check (coste_partido >= 0),
  excluir       date[],
  creada_por    uuid references miembros on delete set null,
  creada_en     timestamptz not null default now(),
  check (hasta >= desde)
);
create index on temporadas (liga_id);

alter table partidos add column temporada_id uuid references temporadas on delete set null;
create index on partidos (temporada_id);

create or replace function programar_temporada(p_liga uuid, p_desde date, p_hasta date, p_dias_semana smallint[],
                                               p_hora time, p_hora_fija boolean default true,
                                               p_coste numeric default 0, p_excluir date[] default null,
                                               p_nombre text default null)
returns int language plpgsql security definer set search_path = public as $$
declare l ligas; v_fechas date[]; v_n int; v_t uuid;
begin
  perform exigir_admin(p_liga);
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'Indica un rango de fechas válido (desde ≤ hasta)';
  end if;
  if p_hasta > p_desde + 400 then raise exception 'La temporada no puede durar más de 400 días'; end if;
  if coalesce(array_length(p_dias_semana, 1), 0) = 0
     or exists (select 1 from unnest(p_dias_semana) d where d is null or d not between 1 and 7) then
    raise exception 'Indica los días de la semana (1 = lunes … 7 = domingo)';
  end if;
  if p_hora is null then raise exception 'Indica la hora'; end if;
  if coalesce(p_coste, 0) < 0 then raise exception 'El coste no puede ser negativo'; end if;
  select * into l from ligas where id = p_liga;

  select coalesce(array_agg(d order by d), '{}') into v_fechas
    from (select g::date as d from generate_series(p_desde::timestamp, p_hasta::timestamp, interval '1 day') g) x
   where extract(isodow from d)::smallint = any(p_dias_semana)
     and not (d = any(coalesce(p_excluir, '{}'::date[])))
     and ((d + p_hora) at time zone 'Europe/Madrid') > now()
     and not exists (select 1 from partidos pa
                      where pa.liga_id = p_liga and pa.estado <> 'cancelado'
                        and (pa.fecha_hora at time zone 'Europe/Madrid')::date = d);
  v_n := coalesce(array_length(v_fechas, 1), 0);
  if v_n > 120 then
    raise exception 'Como máximo 120 partidos por temporada (con estos datos salen %)', v_n;
  end if;
  if v_n = 0 then return 0; end if;

  insert into temporadas (liga_id, nombre, desde, hasta, dias_semana, hora, hora_fija, coste_partido, excluir, creada_por)
  values (p_liga, p_nombre, p_desde, p_hasta, p_dias_semana, p_hora, coalesce(p_hora_fija, true),
          coalesce(p_coste, 0), p_excluir, mi_miembro(p_liga))
  returning id into v_t;

  insert into partidos (liga_id, fecha_hora, hora_confirmada, plazas, num_equipos, coste_total, creado_por, temporada_id)
  select p_liga, (d + p_hora) at time zone 'Europe/Madrid', coalesce(p_hora_fija, true), l.plazas, l.num_equipos,
         coalesce(p_coste, 0), mi_miembro(p_liga), v_t
    from unnest(v_fechas) d
   order by d;
  return v_n;
end $$;

-- Cancela los partidos aún no jugados de una temporada desde una fecha (incluida)
create or replace function cancelar_temporada(p_temporada uuid, p_desde date default current_date) returns int
language plpgsql security definer set search_path = public as $$
declare t temporadas; k int;
begin
  select * into t from temporadas where id = p_temporada;
  if not found then raise exception 'Temporada no encontrada'; end if;
  perform exigir_admin(t.liga_id);
  update partidos set estado = 'cancelado'
   where temporada_id = p_temporada
     and (fecha_hora at time zone 'Europe/Madrid')::date >= coalesce(p_desde, current_date)
     and estado in ('abierto', 'completo', 'equipos_hechos');
  get diagnostics k = row_count;
  return k;
end $$;

create or replace function cambiar_hora_partido(p_partido uuid, p_fecha_hora timestamptz,
                                                p_confirmada boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos;
begin
  select * into p from partidos where id = p_partido for update;
  if not found then raise exception 'Partido no encontrado'; end if;
  perform exigir_admin(p.liga_id);
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') then
    raise exception 'Solo se cambia la hora de un partido que aún no se ha jugado';
  end if;
  if p_fecha_hora is null then raise exception 'Indica la fecha y hora'; end if;
  update partidos set fecha_hora = p_fecha_hora, hora_confirmada = coalesce(p_confirmada, true) where id = p_partido;
end $$;
