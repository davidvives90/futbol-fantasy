-- 0062 · Bugs de la prueba con usuarios y tiempo real
--  · Alineación: sin capitán o sin ariete fallaba al guardar («null value in column ariete/capitan»): t.x = NULL da NULL.
--  · Equipos: cualquier admin (o capitán) los confirma solo; se guarda quién y cuándo (vale el último que los cambia).
--  · Tiempo real: más tablas publicadas para que todos los móviles se actualicen sin reiniciar la app.

create or replace function _guardar_alineacion_filas(p_partido uuid, p_manager uuid, p_jugadores uuid[], p_roles text[],
                                                     p_capitan uuid, p_ariete uuid, p_suplentes uuid[])
returns void language sql security definer set search_path = public as $$
  delete from alineaciones where partido_id = p_partido and manager_id = p_manager;
  insert into alineaciones (partido_id, manager_id, jugador_id, rol, capitan, ariete)
  select p_partido, p_manager, t.x, p_roles[t.k], coalesce(t.x = p_capitan, false), coalesce(t.x = p_ariete, false)
    from unnest(p_jugadores) with ordinality as t(x, k);
  insert into alineaciones (partido_id, manager_id, jugador_id, rol, suplente)
  select p_partido, p_manager, t.x, 'MED', t.k from unnest(p_suplentes) with ordinality as t(x, k);
$$;
revoke execute on function _guardar_alineacion_filas(uuid, uuid, uuid[], text[], uuid, uuid, uuid[]) from public, anon, authenticated;

create or replace function guardar_alineacion(p_partido uuid, p_jugadores uuid[], p_roles text[] default null,
                                              p_capitan uuid default null, p_ariete uuid default null,
                                              p_suplentes uuid[] default null) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_m uuid; v_tam int; v_n int; v_roles text[]; v_sup uuid[]; v_todos uuid[];
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  select * into l from ligas where id = p.liga_id;
  v_m := mi_miembro(p.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') or p.alineaciones_congeladas
     or now() >= hora_cierre_alineacion(p_partido) then
    raise exception 'La alineación de este partido ya está cerrada (cierra % h antes del partido)', l.horas_cierre_alineacion;
  end if;
  perform asegurar_manager(p.liga_id, v_m);

  v_tam := p.plazas / p.num_equipos;
  v_n := coalesce(array_length(p_jugadores, 1), 0);
  v_sup := coalesce(p_suplentes, '{}');
  if v_n > v_tam then
    raise exception 'La alineación es de media plantilla del partido: como máximo % jugadores', v_tam;
  end if;
  if coalesce(array_length(v_sup, 1), 0) > l.suplentes then
    raise exception 'Como máximo % suplentes', l.suplentes;
  end if;
  v_todos := coalesce(p_jugadores, '{}') || v_sup;
  if (select count(distinct x) from unnest(v_todos) x) <> coalesce(array_length(v_todos, 1), 0) then
    raise exception 'Hay jugadores repetidos en la alineación';
  end if;
  if exists (select 1 from unnest(v_todos) x
               join fichas f on f.jugador_id = x and f.propietario_id = v_m
               join cesiones c on c.ficha_id = f.id and c.estado = 'aceptada') then
    raise exception 'Ese jugador está cedido esta jornada: no puedes alinearlo';
  end if;
  if exists (select 1 from unnest(v_todos) x
              where not exists (select 1 from fichas f where f.propietario_id = v_m and f.jugador_id = x)
                and not exists (select 1 from cesiones c join fichas f on f.id = c.ficha_id
                                 where c.cesionario_id = v_m and c.partido_id = p_partido
                                   and c.estado = 'aceptada' and f.jugador_id = x)) then
    raise exception 'Solo puedes alinear jugadores de tu plantilla (o el que tengas cedido esta jornada)';
  end if;

  if p_roles is null or l.modo_alineacion <> 'tactico' then
    -- Sin posiciones (alineación libre): el rol no importa
    v_roles := array(select case when k = 1 and l.modo_alineacion = 'tactico' then 'POR' else 'MED' end
                       from generate_series(1, v_n) k);
  else
    if coalesce(array_length(p_roles, 1), 0) <> v_n then
      raise exception 'Hay que indicar un rol por jugador (POR, DEF, MED o DEL)';
    end if;
    v_roles := array(select upper(trim(r)) from unnest(p_roles) r);
    if exists (select 1 from unnest(v_roles) r where r is null or r not in ('POR', 'DEF', 'MED', 'DEL')) then
      raise exception 'Rol no válido: usa POR, DEF, MED o DEL';
    end if;
    if v_n >= 1 and (select count(*) from unnest(v_roles) r where r = 'POR') <> 1 then
      raise exception 'La alineación lleva exactamente un portero (POR)';
    end if;
    if v_n >= 4 and (not 'DEF' = any(v_roles) or not 'DEL' = any(v_roles)) then
      raise exception 'Con 4 o más jugadores, la alineación táctica lleva al menos un defensa y un delantero';
    end if;
  end if;

  -- Capitán y ariete: cualquiera de los titulares (pueden ser el mismo); si la liga no los usa, se ignoran
  if p_capitan is not null and not p_capitan = any(p_jugadores) then
    raise exception 'El capitán tiene que ser uno de los titulares';
  end if;
  if p_ariete is not null and not p_ariete = any(p_jugadores) then
    raise exception 'El ariete tiene que ser uno de los titulares';
  end if;

  perform _guardar_alineacion_filas(p_partido, v_m, p_jugadores, v_roles,
                                    case when l.capitan_activo then p_capitan end,
                                    case when l.ariete_activo then p_ariete end, v_sup);
  return v_n;
end $$;

-- ───────────── Equipos: quién los confirmó ─────────────
alter table partidos add column if not exists equipos_por uuid references miembros on delete set null,
                     add column if not exists equipos_en timestamptz;

create or replace function _aplicar_equipos(p_partido uuid, p_asignacion jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; v_sin int; v_primera boolean;
begin
  select * into p from partidos where id = p_partido for update;
  v_primera := p.estado <> 'equipos_hechos';
  update convocatorias c set equipo = (p_asignacion ->> c.miembro_id::text)::smallint
   where c.partido_id = p_partido and c.estado in ('confirmado', 'pendiente', 'duda');
  select count(*) into v_sin from convocatorias
   where partido_id = p_partido and estado = 'confirmado' and (equipo is null or equipo > p.num_equipos);
  if v_sin > 0 then raise exception 'Hay % confirmados sin equipo válido', v_sin; end if;
  update partidos set estado = 'equipos_hechos', equipos_por = mi_miembro(p.liga_id), equipos_en = now()
   where id = p_partido;
  if p.num_equipos = 2 then
    insert into encuentros (partido_id, n, equipo_local, equipo_visitante)
    values (p_partido, 1, 1, 2) on conflict do nothing;
  end if;
  if v_primera then
    perform notificar(perfiles_de_miembros(array_agg(miembro_id)), p.liga_id, 'equipos', 'Equipos hechos ✅',
                      'Mira en qué equipo juegas el ' || fecha_corta(p.fecha_hora), '/partidos/' || p_partido)
       from convocatorias where partido_id = p_partido and estado = 'confirmado';
  end if;
end $$;

-- ───────────── Tiempo real ─────────────
do $$
declare t text;
begin
  foreach t in array array['miembros', 'ligas', 'fichas', 'mercado_jugador', 'subastas', 'fantasy_managers', 'apuestas',
                           'quinielas', 'transacciones_fantasy', 'ofertas', 'cesiones', 'acta_jugador', 'reportes_encuentro',
                           'puntos_fantasy', 'movimientos', 'avisos_pago', 'valoraciones'] loop
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
-- Con las bajas (DELETE) también llega el filtro por liga/partido
alter table miembros replica identity full;
alter table convocatorias replica identity full;
alter table apuestas replica identity full;
alter table quinielas replica identity full;
alter table subastas replica identity full;
alter table ofertas replica identity full;
alter table cesiones replica identity full;
