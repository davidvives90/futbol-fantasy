-- 0001 · Tipos y tablas principales
-- Fútbol Fantasy Amigos · Supabase (Postgres 15+)

create extension if not exists pgcrypto;

create type rol_liga         as enum ('admin', 'jugador');
create type estado_miembro   as enum ('pendiente_registro', 'solicitud', 'activo', 'expulsado', 'abandonado', 'rechazado');
create type visibilidad_liga as enum ('publica', 'privada');
create type estado_partido   as enum ('abierto', 'completo', 'equipos_hechos', 'jugado',
                                      'post_partido', 'en_revision', 'cerrado', 'cancelado');
create type estado_inscr     as enum ('confirmado', 'duda', 'baja', 'espera');
create type tipo_mov         as enum ('cargo', 'pago', 'ajuste');
create type posicion_campo   as enum ('portero', 'defensa', 'medio', 'delantero');

-- Usuario registrado (1:1 con auth.users)
create table perfiles (
  id          uuid primary key references auth.users on delete cascade,
  nombre      text not null,
  apodo       text,
  avatar_url  text,
  posicion    posicion_campo,
  telefono    text,
  fcm_token   text,
  creado_en   timestamptz not null default now()
);

create table ligas (
  id                   uuid primary key default gen_random_uuid(),
  nombre               text not null check (length(trim(nombre)) between 3 and 60),
  descripcion          text,
  ciudad               text,
  campo_nombre         text,
  campo_maps_url       text check (campo_maps_url is null or campo_maps_url ~ '^https://'),
  precio_estimado      numeric(6,2) check (precio_estimado is null or precio_estimado >= 0),
  jugadores_por_equipo smallint not null default 5 check (jugadores_por_equipo between 3 and 11),
  num_equipos          smallint not null default 2 check (num_equipos between 2 and 4),
  plazas               smallint generated always as (jugadores_por_equipo * num_equipos) stored,
  puntuar_por_posicion boolean not null default true,  -- gol vale distinto según posición
  horas_post_partido   smallint not null default 48 check (horas_post_partido between 1 and 168),
  visibilidad          visibilidad_liga not null default 'privada',
  requiere_aprobacion  boolean not null default true,
  codigo_invitacion    text unique not null default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  creada_por           uuid references perfiles on delete set null,
  creada_en            timestamptz not null default now()
);

-- Jugador dentro de una liga. perfil_id nulo = jugador pre-creado aún sin registrar.
create table miembros (
  id                 uuid primary key default gen_random_uuid(),
  liga_id            uuid not null references ligas on delete cascade,
  perfil_id          uuid references perfiles on delete set null,
  nombre_provisional text,
  contacto           text,
  posicion           posicion_campo,          -- si es nula se usa la del perfil
  rol                rol_liga not null default 'jugador',
  estado             estado_miembro not null default 'activo',
  token_invitacion   text unique default replace(gen_random_uuid()::text, '-', ''),
  invitado_por       uuid references miembros on delete set null,
  unido_en           timestamptz not null default now(),
  unique (liga_id, perfil_id),
  check (perfil_id is not null or nombre_provisional is not null)
);

create table partidos (
  id               uuid primary key default gen_random_uuid(),
  liga_id          uuid not null references ligas on delete cascade,
  fecha_hora       timestamptz not null,
  hora_confirmada  boolean not null default false,
  campo_maps_url   text check (campo_maps_url is null or campo_maps_url ~ '^https://'),
  plazas           smallint not null check (plazas between 6 and 44),
  num_equipos      smallint not null default 2 check (num_equipos between 2 and 4),
  coste_total      numeric(8,2) not null default 0 check (coste_total >= 0),
  estado           estado_partido not null default 'abierto',
  votacion_cierra  timestamptz,                -- fin de la ventana post-partido
  cargos_generados boolean not null default false,
  creado_por       uuid references miembros on delete set null,
  creado_en        timestamptz not null default now()
);

-- Cada enfrentamiento entre dos equipos del partido (con 2 equipos solo existe n = 1).
-- Los goles son el resultado CONSOLIDADO a partir de los reportes.
create table encuentros (
  partido_id       uuid references partidos on delete cascade,
  n                smallint check (n >= 1),
  equipo_local     smallint not null check (equipo_local between 1 and 4),
  equipo_visitante smallint not null check (equipo_visitante between 1 and 4),
  goles_local      smallint,
  goles_visitante  smallint,
  confianza        numeric(5,2),               -- % de reportes que coinciden (mínimo de los dos campos)
  num_reportes     int not null default 0,
  en_disputa       boolean not null default false,
  primary key (partido_id, n),
  check (equipo_local <> equipo_visitante)
);

create table convocatorias (
  partido_id   uuid references partidos on delete cascade,
  miembro_id   uuid references miembros on delete cascade,
  estado       estado_inscr not null default 'confirmado',
  inscrito_en  timestamptz not null default clock_timestamp(),
  equipo       smallint check (equipo between 1 and 4),
  primary key (partido_id, miembro_id)
);

create table facturas (
  id              uuid primary key default gen_random_uuid(),
  liga_id         uuid not null references ligas on delete cascade,
  partido_id      uuid references partidos on delete set null,
  archivo_path    text not null,               -- ruta en Storage: <liga_id>/<id>.<ext>
  nombre_archivo  text,
  importe         numeric(8,2) check (importe is null or importe >= 0),
  fecha           date not null default current_date,
  notas           text,
  subida_por      uuid references miembros on delete set null,
  creada_en       timestamptz not null default now()
);

create table movimientos (
  id             uuid primary key default gen_random_uuid(),
  liga_id        uuid not null references ligas on delete cascade,
  miembro_id     uuid not null references miembros on delete cascade,
  partido_id     uuid references partidos on delete set null,
  factura_id     uuid references facturas on delete set null,
  tipo           tipo_mov not null,
  importe        numeric(8,2) not null,          -- cargo < 0, pago > 0, ajuste ±
  concepto       text,
  registrado_por uuid references miembros on delete set null,
  fecha          timestamptz not null default now(),
  check ((tipo = 'cargo' and importe <= 0) or (tipo = 'pago' and importe > 0) or tipo = 'ajuste')
);

-- Acta CONSOLIDADA por jugador (la rellena consolidar_acta a partir de los reportes)
create table acta_jugador (
  partido_id    uuid references partidos on delete cascade,
  miembro_id    uuid references miembros on delete cascade,
  goles         smallint not null default 0,
  asistencias   smallint not null default 0,
  autogoles     smallint not null default 0,
  paradas_clave smallint not null default 0,
  penaltis_parados  smallint not null default 0,
  penaltis_fallados smallint not null default 0,
  porterias_cero smallint not null default 0,    -- deducido de encuentros (no se reporta)
  goles_encajados smallint not null default 0,   -- deducido de encuentros
  confianza     numeric(5,2),
  num_reportes  int not null default 0,
  en_disputa    boolean not null default false,
  primary key (partido_id, miembro_id)
);

-- Reglas de puntuación configurables. posicion nula = vale para todos;
-- una fila con posicion concreta tiene prioridad para esa posición.
create table reglas_puntuacion (
  id       bigint generated always as identity primary key,
  liga_id  uuid not null references ligas on delete cascade,
  clave    text not null check (clave ~ '^[a-z0-9_]+$'),
  posicion posicion_campo,
  puntos   numeric(5,2) not null,
  unique nulls not distinct (liga_id, clave, posicion)
);

create table puntos_fantasy (
  partido_id  uuid references partidos on delete cascade,
  miembro_id  uuid references miembros on delete cascade,
  posicion    posicion_campo,
  victorias   smallint not null default 0,
  empates     smallint not null default 0,
  derrotas    smallint not null default 0,
  nota_media  numeric(4,2),
  num_votantes int not null default 0,
  es_mvp      boolean not null default false,
  desglose    jsonb not null,     -- {"jugado":2,"resultado":3,"goles":8,"mvp":3,"notas":{"ataque":7.5,...}}
  total       numeric(6,2) not null,
  calculado_en timestamptz not null default now(),
  primary key (partido_id, miembro_id)
);

create index on miembros (perfil_id);
create index on miembros (liga_id, estado);
create index on partidos (liga_id, fecha_hora desc);
create index on convocatorias (partido_id, estado, inscrito_en);
create index on convocatorias (miembro_id);
create index on movimientos (miembro_id);
create index on movimientos (partido_id);
create index on facturas (partido_id);
create index on ligas (visibilidad, ciudad);
-- 0002 · Ligas: ayudantes de seguridad, alta, invitaciones y administración

-- ───────────── Ayudantes (los usan las políticas RLS) ─────────────
create or replace function mi_miembro(p_liga uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select id from miembros
   where liga_id = p_liga and perfil_id = auth.uid() and estado = 'activo'
$$;

create or replace function es_miembro(p_liga uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select mi_miembro(p_liga) is not null
$$;

create or replace function es_admin(p_liga uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros
                  where liga_id = p_liga and perfil_id = auth.uid()
                    and estado = 'activo' and rol = 'admin')
$$;

create or replace function liga_de_partido(p_partido uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select liga_id from partidos where id = p_partido
$$;

-- ¿Comparten liga activa el usuario actual y este perfil? (para leer perfiles ajenos)
create or replace function comparte_liga(p_perfil uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros a join miembros b on a.liga_id = b.liga_id
                  where a.perfil_id = auth.uid() and a.estado = 'activo'
                    and b.perfil_id = p_perfil and b.estado in ('activo', 'solicitud'))
$$;

-- Posición efectiva de un miembro: la de la liga o, si no hay, la del perfil
create or replace function posicion_de(p_miembro uuid) returns posicion_campo
language sql stable security definer set search_path = public as $$
  select coalesce(m.posicion, p.posicion)
    from miembros m left join perfiles p on p.id = m.perfil_id
   where m.id = p_miembro
$$;

-- Valor de una regla: primero la específica de la posición, luego la general, si no 0
create or replace function regla(p_liga uuid, p_clave text, p_posicion posicion_campo default null)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(
    (select puntos from reglas_puntuacion where liga_id = p_liga and clave = p_clave and posicion = p_posicion),
    (select puntos from reglas_puntuacion where liga_id = p_liga and clave = p_clave and posicion is null),
    0)
$$;

create or replace function exigir_admin(p_liga uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not es_admin(p_liga) then
    raise exception 'Solo los administradores de la liga pueden hacer esto' using errcode = '42501';
  end if;
end $$;

-- ───────────── Alta de liga ─────────────
create or replace function crear_liga(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Hay que iniciar sesión'; end if;
  if not exists (select 1 from perfiles where id = auth.uid()) then
    raise exception 'Completa tu perfil antes de crear una liga';
  end if;

  insert into ligas (nombre, descripcion, ciudad, campo_nombre, campo_maps_url, precio_estimado,
                     jugadores_por_equipo, num_equipos, visibilidad, requiere_aprobacion,
                     puntuar_por_posicion, horas_post_partido, creada_por)
  values (p->>'nombre', p->>'descripcion', p->>'ciudad', p->>'campo_nombre', p->>'campo_maps_url',
          (p->>'precio_estimado')::numeric,
          coalesce((p->>'jugadores_por_equipo')::smallint, 5),
          coalesce((p->>'num_equipos')::smallint, 2),
          coalesce((p->>'visibilidad')::visibilidad_liga, 'privada'),
          coalesce((p->>'requiere_aprobacion')::boolean, true),
          coalesce((p->>'puntuar_por_posicion')::boolean, true),
          coalesce((p->>'horas_post_partido')::smallint, 48),
          auth.uid())
  returning id into v_id;

  insert into miembros (liga_id, perfil_id, rol, estado) values (v_id, auth.uid(), 'admin', 'activo');
  perform sembrar_liga_defecto(v_id);   -- reglas y aspectos de valoración (0007)
  return v_id;
end $$;

-- ───────────── Invitaciones ─────────────
-- Pre-crear jugadores: devuelve un token por persona para construir su enlace
create or replace function precrear_jugadores(p_liga uuid, p_nombres text[], p_contactos text[] default null)
returns table (miembro_id uuid, nombre text, token text)
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_admin(p_liga);
  return query
    insert into miembros (liga_id, nombre_provisional, contacto, estado, invitado_por)
    select p_liga, trim(t.n), t.c, 'pendiente_registro', mi_miembro(p_liga)
      from unnest(p_nombres, coalesce(p_contactos, array[]::text[])) as t(n, c)
     where t.n is not null and trim(t.n) <> ''
    returning miembros.id, miembros.nombre_provisional, miembros.token_invitacion;
end $$;

-- Enlaces pendientes (solo admins: el token no es legible por los demás)
create or replace function enlaces_invitacion(p_liga uuid)
returns table (miembro_id uuid, nombre text, contacto text, token text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_admin(p_liga);
  return query select m.id, m.nombre_provisional, m.contacto, m.token_invitacion
                 from miembros m
                where m.liga_id = p_liga and m.estado = 'pendiente_registro'
                order by m.nombre_provisional;
end $$;

-- Unirse con enlace personal (reclama la ficha pre-creada) o con el código general de la liga
create or replace function unirse(p_codigo text) returns uuid
language plpgsql security definer set search_path = public as $$
declare m miembros; l ligas;
begin
  if auth.uid() is null then raise exception 'Hay que iniciar sesión'; end if;
  if not exists (select 1 from perfiles where id = auth.uid()) then
    raise exception 'Completa tu perfil antes de unirte a una liga';
  end if;

  -- 1) Token personal
  select * into m from miembros where token_invitacion = p_codigo and estado = 'pendiente_registro';
  if found then
    if exists (select 1 from miembros where liga_id = m.liga_id and perfil_id = auth.uid()) then
      raise exception 'Ya perteneces a esta liga; pide al administrador que te asigne la ficha de %',
        m.nombre_provisional;
    end if;
    update miembros set perfil_id = auth.uid(), estado = 'activo',
                        token_invitacion = null, unido_en = now()
     where id = m.id;
    return m.liga_id;
  end if;

  -- 2) Código general de la liga
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

create or replace function regenerar_codigo(p_liga uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v text;
begin
  perform exigir_admin(p_liga);
  update ligas set codigo_invitacion = upper(substr(md5(gen_random_uuid()::text), 1, 6))
   where id = p_liga returning codigo_invitacion into v;
  return v;
end $$;

-- ───────────── Buscador y solicitudes ─────────────
create or replace function buscar_ligas(p_texto text)
returns table (id uuid, nombre text, ciudad text, campo_nombre text,
               jugadores_por_equipo smallint, num_equipos smallint,
               precio_estimado numeric, requiere_aprobacion boolean, num_miembros bigint)
language sql stable security definer set search_path = public as $$
  select l.id, l.nombre, l.ciudad, l.campo_nombre, l.jugadores_por_equipo, l.num_equipos,
         l.precio_estimado, l.requiere_aprobacion,
         (select count(*) from miembros m where m.liga_id = l.id and m.estado = 'activo')
    from ligas l
   where l.visibilidad = 'publica'
     and (coalesce(p_texto, '') = ''
          or l.nombre ilike '%' || p_texto || '%' or l.ciudad ilike '%' || p_texto || '%')
   order by l.nombre
   limit 30
$$;

create or replace function solicitar_unirse(p_liga uuid) returns estado_miembro
language plpgsql security definer set search_path = public as $$
declare l ligas; v estado_miembro;
begin
  if auth.uid() is null then raise exception 'Hay que iniciar sesión'; end if;
  select * into l from ligas where id = p_liga and visibilidad = 'publica';
  if not found then raise exception 'Liga no encontrada'; end if;
  if exists (select 1 from miembros where liga_id = p_liga and perfil_id = auth.uid()
               and estado in ('expulsado', 'rechazado')) then
    raise exception 'No puedes volver a esta liga';
  end if;
  v := case when l.requiere_aprobacion then 'solicitud'::estado_miembro else 'activo' end;
  insert into miembros (liga_id, perfil_id, estado) values (p_liga, auth.uid(), v)
  on conflict (liga_id, perfil_id) do update set estado = excluded.estado, unido_en = now()
   where miembros.estado = 'abandonado';
  return v;
end $$;

create or replace function aprobar_solicitud(p_miembro uuid, p_aceptar boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare m miembros;
begin
  select * into m from miembros where id = p_miembro;
  if not found or m.estado <> 'solicitud' then raise exception 'No hay solicitud pendiente'; end if;
  perform exigir_admin(m.liga_id);
  update miembros set estado = case when p_aceptar then 'activo'::estado_miembro else 'rechazado' end,
                      invitado_por = mi_miembro(m.liga_id), unido_en = now()
   where id = p_miembro;
end $$;

-- ───────────── Administración de miembros ─────────────
create or replace function num_admins(p_liga uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from miembros where liga_id = p_liga and rol = 'admin' and estado = 'activo'
$$;

-- Da de baja al miembro en los partidos que aún no se han jugado (el trigger promueve la espera)
create or replace function liberar_plazas_futuras(p_miembro uuid) returns void
language sql security definer set search_path = public as $$
  update convocatorias c set estado = 'baja'
    from partidos p
   where c.partido_id = p.id and c.miembro_id = p_miembro and c.estado <> 'baja'
     and p.estado in ('abierto', 'completo', 'equipos_hechos');
$$;

create or replace function cambiar_rol(p_miembro uuid, p_rol rol_liga) returns void
language plpgsql security definer set search_path = public as $$
declare m miembros;
begin
  select * into m from miembros where id = p_miembro;
  if not found then raise exception 'Miembro no encontrado'; end if;
  perform exigir_admin(m.liga_id);
  if p_rol = 'admin' and (m.estado <> 'activo' or m.perfil_id is null) then
    raise exception 'Solo un jugador registrado y activo puede ser administrador';
  end if;
  if m.rol = 'admin' and p_rol = 'jugador' and num_admins(m.liga_id) <= 1 then
    raise exception 'La liga debe tener al menos un administrador';
  end if;
  update miembros set rol = p_rol where id = p_miembro;
end $$;

-- Expulsar: conserva historial y deudas, libera sus plazas futuras, no puede volver con el código
create or replace function expulsar(p_miembro uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m miembros;
begin
  select * into m from miembros where id = p_miembro;
  if not found then raise exception 'Miembro no encontrado'; end if;
  perform exigir_admin(m.liga_id);
  if m.perfil_id = auth.uid() then raise exception 'No puedes expulsarte a ti mismo'; end if;
  if m.rol = 'admin' and num_admins(m.liga_id) <= 1 then
    raise exception 'La liga debe tener al menos un administrador';
  end if;
  update miembros set estado = 'expulsado', rol = 'jugador', token_invitacion = null
   where id = p_miembro;
  perform liberar_plazas_futuras(p_miembro);
end $$;

create or replace function abandonar_liga(p_liga uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_m uuid := mi_miembro(p_liga);
begin
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if es_admin(p_liga) and num_admins(p_liga) <= 1 then
    raise exception 'Eres el último administrador: nombra a otro antes de salir';
  end if;
  update miembros set estado = 'abandonado', rol = 'jugador' where id = v_m;
  perform liberar_plazas_futuras(v_m);
end $$;

-- ───────────── Partidos ─────────────
-- Crea un partido copiando formato y plazas de la liga (se pueden sobrescribir)
create or replace function crear_partido(p_liga uuid, p_fecha_hora timestamptz,
                                         p_coste numeric default 0,
                                         p_plazas smallint default null,
                                         p_num_equipos smallint default null,
                                         p_campo_maps_url text default null,
                                         p_hora_confirmada boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare l ligas; v_id uuid;
begin
  perform exigir_admin(p_liga);
  select * into l from ligas where id = p_liga;
  insert into partidos (liga_id, fecha_hora, hora_confirmada, campo_maps_url, plazas, num_equipos,
                        coste_total, creado_por)
  values (p_liga, p_fecha_hora, p_hora_confirmada, p_campo_maps_url,
          coalesce(p_plazas, l.plazas), coalesce(p_num_equipos, l.num_equipos),
          coalesce(p_coste, 0), mi_miembro(p_liga))
  returning id into v_id;
  return v_id;
end $$;
-- 0003 · Convocatoria (cupo y lista de espera), equipos y tesorería

-- ───────────── Cupo y lista de espera ─────────────
-- BEFORE: si no hay plaza, el "confirmado" pasa a "espera". También protege equipo y estado del partido.
create or replace function gestionar_cupo() returns trigger
language plpgsql security definer set search_path = public as $$
declare p partidos; v_conf int; v_admin boolean;
begin
  select * into p from partidos where id = new.partido_id for update;   -- serializa altas simultáneas
  v_admin := auth.uid() is null or es_admin(p.liga_id);                 -- null = service_role / tareas internas

  if not v_admin then
    if p.estado not in ('abierto', 'completo', 'equipos_hechos') then
      raise exception 'La convocatoria de este partido ya está cerrada';
    end if;
    if tg_op = 'UPDATE' and new.equipo is distinct from old.equipo then
      raise exception 'Solo un administrador puede cambiar los equipos';
    end if;
    if tg_op = 'INSERT' then new.equipo := null; end if;
  end if;

  if tg_op = 'UPDATE' and old.estado <> 'confirmado' and new.estado = 'confirmado' then
    new.inscrito_en := clock_timestamp();   -- volver a apuntarse = al final de la cola
  end if;

  if new.estado = 'confirmado' and (tg_op = 'INSERT' or old.estado <> 'confirmado') then
    select count(*) into v_conf from convocatorias
     where partido_id = new.partido_id and estado = 'confirmado' and miembro_id <> new.miembro_id;
    if v_conf >= p.plazas then new.estado := 'espera'; end if;
  end if;

  if new.estado <> 'confirmado' then new.equipo := null; end if;
  return new;
end $$;

-- AFTER: si se libera una plaza, sube el primero de la espera; recalcula abierto/completo
create or replace function promover_espera() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_partido uuid := coalesce(new.partido_id, old.partido_id); p partidos; v_conf int;
begin
  select * into p from partidos where id = v_partido;
  if p.id is null then return null; end if;   -- partido borrado en cascada

  if tg_op <> 'INSERT' and old.estado = 'confirmado'
     and (tg_op = 'DELETE' or new.estado <> 'confirmado')
     and p.estado in ('abierto', 'completo', 'equipos_hechos') then
    update convocatorias set estado = 'confirmado'
     where (partido_id, miembro_id) = (
       select partido_id, miembro_id from convocatorias
        where partido_id = v_partido and estado = 'espera'
        order by inscrito_en limit 1);
    -- TODO notificación push "¡Tienes plaza!" (Edge Function escuchando este cambio)
  end if;

  if p.estado in ('abierto', 'completo') then
    select count(*) into v_conf from convocatorias where partido_id = v_partido and estado = 'confirmado';
    update partidos set estado = case when v_conf >= plazas then 'completo'::estado_partido else 'abierto' end
     where id = v_partido and estado in ('abierto', 'completo');
  end if;
  return null;
end $$;

create trigger t_cupo before insert or update of estado, equipo on convocatorias
  for each row execute function gestionar_cupo();
create trigger t_espera after insert or update of estado or delete on convocatorias
  for each row execute function promover_espera();

-- ───────────── Equipos ─────────────
-- p_asignacion: {"<miembro_id>": 1, "<miembro_id>": 2, ...} (resultado del balanceo + ajustes manuales)
create or replace function guardar_equipos(p_partido uuid, p_asignacion jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; v_sin int;
begin
  select * into p from partidos where id = p_partido;
  perform exigir_admin(p.liga_id);
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') then
    raise exception 'Los equipos ya no se pueden cambiar';
  end if;

  update convocatorias c set equipo = (p_asignacion ->> c.miembro_id::text)::smallint
   where c.partido_id = p_partido and c.estado = 'confirmado';

  select count(*) into v_sin from convocatorias
   where partido_id = p_partido and estado = 'confirmado'
     and (equipo is null or equipo > p.num_equipos);
  if v_sin > 0 then raise exception 'Hay % confirmados sin equipo válido', v_sin; end if;

  update partidos set estado = 'equipos_hechos' where id = p_partido;

  -- Con 2 equipos el encuentro es único y se crea solo
  if p.num_equipos = 2 then
    insert into encuentros (partido_id, n, equipo_local, equipo_visitante)
    values (p_partido, 1, 1, 2) on conflict do nothing;
  end if;
end $$;

-- Con 3-4 equipos: lista de enfrentamientos [[1,2],[3,1],...]. Se puede rehacer hasta consolidar.
create or replace function definir_encuentros(p_partido uuid, p_lista jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; i int;
begin
  select * into p from partidos where id = p_partido;
  perform exigir_admin(p.liga_id);
  if p.estado in ('en_revision', 'cerrado', 'cancelado') then
    raise exception 'El acta ya está consolidada';
  end if;
  delete from encuentros where partido_id = p_partido;
  for i in 0 .. jsonb_array_length(p_lista) - 1 loop
    insert into encuentros (partido_id, n, equipo_local, equipo_visitante)
    values (p_partido, i + 1, (p_lista -> i ->> 0)::smallint, (p_lista -> i ->> 1)::smallint);
  end loop;
end $$;

-- ───────────── Tesorería ─────────────
-- Un cargo por confirmado. Coste = suma de facturas del partido si las hay; si no, coste_total.
-- Los céntimos del redondeo van al primer inscrito. Idempotente.
create or replace function generar_cargos(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; n int; v_coste numeric(8,2); cuota numeric(8,2); resto numeric(8,2);
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.cargos_generados then return 0; end if;

  select coalesce(sum(importe), 0) into v_coste from facturas where partido_id = p_partido;
  if v_coste = 0 then v_coste := p.coste_total; end if;

  select count(*) into n from convocatorias where partido_id = p_partido and estado = 'confirmado';
  if n = 0 or v_coste = 0 then
    update partidos set cargos_generados = true where id = p_partido;
    return 0;
  end if;

  cuota := trunc(v_coste / n, 2);
  resto := v_coste - cuota * n;
  insert into movimientos (liga_id, miembro_id, partido_id, tipo, importe, concepto, registrado_por)
  select p.liga_id, c.miembro_id, p.id, 'cargo',
         -(cuota + case when row_number() over (order by c.inscrito_en) = 1 then resto else 0 end),
         'Partido ' || to_char(p.fecha_hora at time zone 'Europe/Madrid', 'DD/MM'),
         mi_miembro(p.liga_id)
    from convocatorias c
   where c.partido_id = p_partido and c.estado = 'confirmado';

  update partidos set cargos_generados = true where id = p_partido;
  return n;
end $$;

-- Registrar un pago (o un ajuste con signo) de un miembro
create or replace function registrar_pago(p_miembro uuid, p_importe numeric,
                                          p_partido uuid default null, p_concepto text default null,
                                          p_tipo tipo_mov default 'pago')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_liga uuid; v_id uuid;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  perform exigir_admin(v_liga);
  if p_tipo = 'cargo' then raise exception 'Los cargos los genera el sistema'; end if;
  insert into movimientos (liga_id, miembro_id, partido_id, tipo, importe, concepto, registrado_por)
  values (v_liga, p_miembro, p_partido, p_tipo, p_importe, p_concepto, mi_miembro(v_liga))
  returning id into v_id;
  return v_id;
end $$;

-- Saldo de cada miembro (negativo = debe dinero)
create view v_saldos with (security_invoker = true) as
select m.liga_id, m.id as miembro_id,
       coalesce(sum(mv.importe), 0)                                   as saldo,
       coalesce(-sum(mv.importe) filter (where mv.tipo = 'cargo'), 0) as total_cargado,
       coalesce(sum(mv.importe) filter (where mv.tipo = 'pago'), 0)   as total_pagado
  from miembros m
  left join movimientos mv on mv.miembro_id = m.id
 where m.perfil_id = auth.uid() or es_admin(m.liga_id)    -- cada uno el suyo; admins, todos
 group by m.liga_id, m.id;

-- Estado de pago de cada asistente en cada partido
create view v_pagos_partido with (security_invoker = true) as
select c.partido_id, c.miembro_id,
       coalesce(-sum(mv.importe) filter (where mv.tipo = 'cargo'), 0) as importe,
       coalesce(sum(mv.importe)  filter (where mv.tipo = 'pago'), 0)  as pagado,
       case when coalesce(sum(mv.importe), 0) >= 0 then 'pagado' else 'pendiente' end as estado_pago
  from convocatorias c
  left join movimientos mv on mv.partido_id = c.partido_id and mv.miembro_id = c.miembro_id
 where c.estado = 'confirmado'
 group by c.partido_id, c.miembro_id;
-- 0004 · Post-partido: partes de los jugadores, valoraciones por aspectos y consolidación por consenso
--
-- Flujo:  equipos_hechos ──marcar_jugado()──▶ post_partido (ventana de N horas: cada asistente envía su parte)
--         ──cerrar_post_partido()──▶ consolidar_acta()
--              ├─ sin disputas ─▶ calcular_puntos() ─▶ cerrado
--              └─ con disputas ─▶ en_revision ──resolver_disputa() (admin) ×N──▶ calcular_puntos() ─▶ cerrado

-- ───────────── Tablas ─────────────
create table aspectos_valoracion (
  liga_id     uuid references ligas on delete cascade,
  clave       text check (clave ~ '^[a-z_]+$'),
  nombre      text not null,
  descripcion text,
  orden       smallint not null default 0,
  aplica_a    text not null default 'todos' check (aplica_a in ('todos', 'porteros', 'campo')),
  activo      boolean not null default true,
  primary key (liga_id, clave)
);

-- Resultado que cada reportero cree que hubo en cada encuentro
create table reportes_encuentro (
  partido_id      uuid not null,
  n               smallint not null,
  reportero_id    uuid not null references miembros on delete cascade,
  goles_local     smallint not null check (goles_local between 0 and 99),
  goles_visitante smallint not null check (goles_visitante between 0 and 99),
  creado_en       timestamptz not null default now(),
  primary key (partido_id, n, reportero_id),
  foreign key (partido_id, n) references encuentros on delete cascade
);

-- Lo que cada reportero recuerda de cada jugador. null = "no lo sé".
create table reportes_jugador (
  partido_id        uuid not null references partidos on delete cascade,
  reportero_id      uuid not null references miembros on delete cascade,
  sujeto_id         uuid not null references miembros on delete cascade,
  goles             smallint check (goles between 0 and 50),
  asistencias       smallint check (asistencias between 0 and 50),
  autogoles         smallint check (autogoles between 0 and 20),
  paradas_clave     smallint check (paradas_clave between 0 and 50),
  penaltis_parados  smallint check (penaltis_parados between 0 and 10),
  penaltis_fallados smallint check (penaltis_fallados between 0 and 10),
  creado_en         timestamptz not null default now(),
  primary key (partido_id, reportero_id, sujeto_id)
);

-- Valoraciones subjetivas por aspecto, anónimas (nadie lee las ajenas; solo se publican medias)
create table valoraciones (
  partido_id uuid not null references partidos on delete cascade,
  liga_id    uuid not null,                       -- lo rellena el trigger
  votante_id uuid not null references miembros on delete cascade,
  votado_id  uuid not null references miembros on delete cascade,
  aspecto    text not null,
  nota       smallint not null check (nota between 1 and 10),
  creado_en  timestamptz not null default now(),
  primary key (partido_id, votante_id, votado_id, aspecto),
  foreign key (liga_id, aspecto) references aspectos_valoracion (liga_id, clave),
  check (votante_id <> votado_id)
);

create table disputas (
  id            uuid primary key default gen_random_uuid(),
  partido_id    uuid not null references partidos on delete cascade,
  tipo          text not null check (tipo in ('encuentro', 'jugador')),
  n             smallint,                 -- encuentro (tipo = 'encuentro')
  sujeto_id     uuid references miembros on delete cascade,   -- jugador (tipo = 'jugador')
  campo         text not null,            -- goles_local, goles, asistencias...
  valores       jsonb not null,           -- {"2": 5, "3": 1}: valor reportado → nº de reportes
  valor_propuesto smallint,               -- el que saldría por consenso
  num_reportes  int not null,
  resuelta      boolean not null default false,
  valor_final   smallint,
  resuelta_por  uuid references miembros on delete set null,
  resuelta_en   timestamptz,
  creada_en     timestamptz not null default now(),
  check ((tipo = 'encuentro' and n is not null) or (tipo = 'jugador' and sujeto_id is not null))
);
create unique index disputas_unica on disputas
  (partido_id, tipo, coalesce(n, 0), coalesce(sujeto_id, '00000000-0000-0000-0000-000000000000'), campo);

create index on reportes_jugador (partido_id, sujeto_id);
create index on valoraciones (partido_id, votado_id);

-- ───────────── Validación de partes y valoraciones ─────────────
-- ¿Puede este miembro enviar parte de este partido? Asistente confirmado, o admin de la liga.
create or replace function puede_reportar(p_partido uuid, p_miembro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from convocatorias
                  where partido_id = p_partido and miembro_id = p_miembro and estado = 'confirmado')
      or exists (select 1 from miembros m join partidos p on p.liga_id = m.liga_id
                  where p.id = p_partido and m.id = p_miembro and m.rol = 'admin' and m.estado = 'activo')
$$;

create or replace function jugo_partido(p_partido uuid, p_miembro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from convocatorias
                  where partido_id = p_partido and miembro_id = p_miembro
                    and estado = 'confirmado' and equipo is not null)
$$;

create or replace function validar_parte() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_estado estado_partido; v_aplica text; v_pos posicion_campo;
begin
  select estado into v_estado from partidos where id = new.partido_id;
  if v_estado <> 'post_partido' then
    raise exception 'El partido no está en periodo de partes y valoraciones';
  end if;

  if tg_table_name = 'valoraciones' then
    if not jugo_partido(new.partido_id, new.votante_id) then
      raise exception 'Solo valoran quienes jugaron el partido';
    end if;
    if not jugo_partido(new.partido_id, new.votado_id) then
      raise exception 'Ese jugador no jugó el partido';
    end if;
    new.liga_id := liga_de_partido(new.partido_id);
    select aplica_a into v_aplica from aspectos_valoracion
     where liga_id = new.liga_id and clave = new.aspecto and activo;
    if v_aplica is null then raise exception 'Aspecto de valoración no válido'; end if;
    v_pos := posicion_de(new.votado_id);
    if (v_aplica = 'porteros' and v_pos is distinct from 'portero')
       or (v_aplica = 'campo' and v_pos = 'portero') then
      raise exception 'El aspecto % no se aplica a este jugador', new.aspecto;
    end if;
  elsif tg_table_name = 'reportes_jugador' then
    if not puede_reportar(new.partido_id, new.reportero_id) then
      raise exception 'Solo envían parte los asistentes o un administrador';
    end if;
    if not jugo_partido(new.partido_id, new.sujeto_id) then
      raise exception 'Ese jugador no jugó el partido';
    end if;
  else -- reportes_encuentro
    if not puede_reportar(new.partido_id, new.reportero_id) then
      raise exception 'Solo envían parte los asistentes o un administrador';
    end if;
  end if;
  return new;
end $$;

create trigger t_validar before insert or update on reportes_encuentro
  for each row execute function validar_parte();
create trigger t_validar before insert or update on reportes_jugador
  for each row execute function validar_parte();
create trigger t_validar before insert or update on valoraciones
  for each row execute function validar_parte();

-- ───────────── Consenso ─────────────
-- Moda de los valores no nulos (empate de modas → mediana redondeada de todos);
-- con p_mediana = true usa directamente la mediana (para conteos dispersos como paradas).
-- confianza = % de reportes que coinciden con el valor elegido.
create or replace function consenso(p_vals smallint[], p_mediana boolean default false,
                                    out valor smallint, out confianza numeric, out n int, out conteo jsonb)
language plpgsql immutable as $$
declare v_top int; v_modas int;
begin
  select count(*)::int into n from unnest(p_vals) v where v is not null;
  if n = 0 then valor := null; confianza := null; conteo := '{}'; return; end if;

  select jsonb_object_agg(v::text, c) into conteo
    from (select v, count(*) c from unnest(p_vals) v where v is not null group by v) t;

  if not p_mediana then
    select max(c) into v_top
      from (select count(*) c from unnest(p_vals) v where v is not null group by v) t;
    select count(*) into v_modas
      from (select count(*) c from unnest(p_vals) v where v is not null group by v) t where c = v_top;
    if v_modas = 1 then
      select v into valor from unnest(p_vals) v where v is not null
       group by v order by count(*) desc limit 1;
    end if;
  end if;

  if valor is null then
    select round(percentile_cont(0.5) within group (order by v))::smallint into valor
      from unnest(p_vals) v where v is not null;
  end if;

  confianza := round(100.0 * (select count(*) from unnest(p_vals) v where v = valor) / n, 2);
end $$;

-- Valor ya decidido por un admin para un campo (tiene prioridad sobre el consenso)
create or replace function valor_resuelto(p_partido uuid, p_tipo text, p_n smallint, p_sujeto uuid, p_campo text)
returns smallint language sql stable security definer set search_path = public as $$
  select valor_final from disputas
   where partido_id = p_partido and tipo = p_tipo and campo = p_campo and resuelta
     and coalesce(n, 0) = coalesce(p_n, 0)
     and coalesce(sujeto_id, '00000000-0000-0000-0000-000000000000')
         = coalesce(p_sujeto, '00000000-0000-0000-0000-000000000000')
$$;

-- Decide el valor de un campo y abre disputa si no hay acuerdo suficiente.
-- Reglas de disputa:
--   · resultado de un encuentro: menos de 3 partes o confianza < 60 %
--   · conteos por mediana (paradas): solo si 1-2 partes dicen algo distinto de 0
--   · dato de un jugador: nadie lo indica → 0 sin disputa; 1-2 partes que dicen algo distinto de 0 → disputa
--     (hace falta corroborarlo); 3 o más partes con confianza < 60 % → disputa
create or replace function decidir_campo(p_partido uuid, p_tipo text, p_n smallint, p_sujeto uuid,
                                         p_campo text, p_vals smallint[], p_mediana boolean default false,
                                         out valor smallint, out confianza numeric, out n int, out disputado boolean)
language plpgsql security definer set search_path = public as $$
declare c record; v_res smallint;
begin
  c := consenso(p_vals, p_mediana);
  n := c.n; confianza := c.confianza; valor := coalesce(c.valor, 0); disputado := false;

  v_res := valor_resuelto(p_partido, p_tipo, p_n, p_sujeto, p_campo);
  if v_res is not null then valor := v_res; confianza := 100; return; end if;

  if p_tipo = 'encuentro' then
    disputado := c.n < 3 or c.confianza < 60;
  elsif p_mediana then
    -- conteos aproximados (paradas): la dispersión es normal, solo se exige corroboración
    disputado := c.n between 1 and 2 and c.valor <> 0;
  else
    disputado := (c.n between 1 and 2 and c.valor <> 0) or (c.n >= 3 and c.confianza < 60);
  end if;

  if disputado then
    insert into disputas (partido_id, tipo, n, sujeto_id, campo, valores, valor_propuesto, num_reportes)
    values (p_partido, p_tipo, p_n, p_sujeto, p_campo, c.conteo, c.valor, c.n);
  end if;
end $$;

-- Consolida el acta a partir de todos los partes. Recalculable. Devuelve nº de disputas abiertas.
create or replace function consolidar_acta(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; e record; j record; gl record; gv record;
        f_g record; f_a record; f_ag record; f_pc record; f_pp record; f_pf record;
        v_abiertas int;
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado not in ('post_partido', 'en_revision') then
    raise exception 'Solo se consolida tras el partido (estado actual: %)', p.estado;
  end if;

  delete from disputas where partido_id = p_partido and not resuelta;

  -- 1) Resultado de cada encuentro
  for e in select * from encuentros where partido_id = p_partido order by n loop
    gl := decidir_campo(p_partido, 'encuentro', e.n, null, 'goles_local',
            (select array_agg(goles_local) from reportes_encuentro where partido_id = p_partido and n = e.n));
    gv := decidir_campo(p_partido, 'encuentro', e.n, null, 'goles_visitante',
            (select array_agg(goles_visitante) from reportes_encuentro where partido_id = p_partido and n = e.n));
    update encuentros
       set goles_local = gl.valor, goles_visitante = gv.valor,
           confianza = least(gl.confianza, gv.confianza),
           num_reportes = greatest(gl.n, gv.n),
           en_disputa = gl.disputado or gv.disputado
     where partido_id = p_partido and n = e.n;
  end loop;

  -- 2) Datos de cada jugador
  delete from acta_jugador where partido_id = p_partido;
  for j in select c.miembro_id, c.equipo from convocatorias c
            where c.partido_id = p_partido and c.estado = 'confirmado' and c.equipo is not null loop
    f_g  := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'goles',
              (select array_agg(goles) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));
    f_a  := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'asistencias',
              (select array_agg(asistencias) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));
    f_ag := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'autogoles',
              (select array_agg(autogoles) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));
    f_pc := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'paradas_clave',
              (select array_agg(paradas_clave) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id),
              true);   -- mediana: nadie cuenta las paradas igual
    f_pp := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'penaltis_parados',
              (select array_agg(penaltis_parados) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));
    f_pf := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'penaltis_fallados',
              (select array_agg(penaltis_fallados) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));

    insert into acta_jugador (partido_id, miembro_id, goles, asistencias, autogoles, paradas_clave,
                              penaltis_parados, penaltis_fallados, porterias_cero, goles_encajados,
                              confianza, num_reportes, en_disputa)
    select p_partido, j.miembro_id, f_g.valor, f_a.valor, f_ag.valor, f_pc.valor, f_pp.valor, f_pf.valor,
           coalesce(count(*) filter (where contra = 0), 0),
           coalesce(sum(contra), 0),
           (select min(x) from unnest(array[f_g.confianza, f_a.confianza, f_ag.confianza,
                                            f_pp.confianza, f_pf.confianza]) x),
           (select count(*) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id),
           f_g.disputado or f_a.disputado or f_ag.disputado or f_pc.disputado or f_pp.disputado or f_pf.disputado
      from (select case when en.equipo_local = j.equipo then en.goles_visitante else en.goles_local end as contra
              from encuentros en
             where en.partido_id = p_partido and j.equipo in (en.equipo_local, en.equipo_visitante)) t;
  end loop;

  select count(*) into v_abiertas from disputas where partido_id = p_partido and not resuelta;
  return v_abiertas;
end $$;

-- ───────────── Transiciones del partido ─────────────
-- Admin: el partido se ha jugado → genera cargos y abre la ventana de partes y valoraciones
create or replace function marcar_jugado(p_partido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; v_horas int;
begin
  select * into p from partidos where id = p_partido for update;
  perform exigir_admin(p.liga_id);
  if p.estado <> 'equipos_hechos' then raise exception 'Primero hay que confirmar los equipos'; end if;
  if not exists (select 1 from encuentros where partido_id = p_partido) then
    raise exception 'Define los encuentros (quién juega contra quién) antes de cerrar el partido';
  end if;
  select horas_post_partido into v_horas from ligas where id = p.liga_id;

  update partidos set estado = 'jugado' where id = p_partido;
  perform generar_cargos(p_partido);
  update partidos set estado = 'post_partido', votacion_cierra = now() + make_interval(hours => v_horas)
   where id = p_partido;
end $$;

-- Cierre de la ventana (admin o tarea programada): consolida; si hay disputas pasa a revisión
create or replace function cerrar_post_partido(p_partido uuid) returns estado_partido
language plpgsql security definer set search_path = public as $$
declare p partidos; v_abiertas int;
begin
  select * into p from partidos where id = p_partido;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado <> 'post_partido' then raise exception 'El partido no está en periodo post-partido'; end if;

  v_abiertas := consolidar_acta(p_partido);
  if v_abiertas > 0 then
    update partidos set estado = 'en_revision' where id = p_partido;
    -- TODO push a los admins: "Hay % datos sin acuerdo en el partido"
    return 'en_revision';
  end if;
  perform calcular_puntos(p_partido);
  return 'cerrado';
end $$;

-- Admin decide el valor de un dato en disputa. Al resolver la última, se calculan los puntos.
create or replace function resolver_disputa(p_disputa uuid, p_valor smallint) returns estado_partido
language plpgsql security definer set search_path = public as $$
declare d disputas; p partidos; v_abiertas int;
begin
  select * into d from disputas where id = p_disputa;
  if not found then raise exception 'Disputa no encontrada'; end if;
  select * into p from partidos where id = d.partido_id;
  perform exigir_admin(p.liga_id);
  if p.estado not in ('post_partido', 'en_revision') then raise exception 'El acta ya está cerrada'; end if;
  if p_valor < 0 then raise exception 'Valor no válido'; end if;

  update disputas set resuelta = true, valor_final = p_valor,
                      resuelta_por = mi_miembro(p.liga_id), resuelta_en = now()
   where id = p_disputa;

  if p.estado = 'en_revision' then
    v_abiertas := consolidar_acta(p.id);     -- aplica los valores resueltos
    if v_abiertas = 0 then
      perform calcular_puntos(p.id);
      return 'cerrado';
    end if;
  end if;
  return p.estado;
end $$;

-- Para pg_cron / Edge Function: cierra todas las ventanas vencidas
create or replace function cerrar_ventanas_vencidas() returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  for r in select id from partidos where estado = 'post_partido' and votacion_cierra <= now() loop
    perform cerrar_post_partido(r.id);
    k := k + 1;
  end loop;
  return k;
end $$;
-- En Supabase:  select cron.schedule('cerrar-post-partido', '*/15 * * * *', 'select cerrar_ventanas_vencidas()');

-- ───────────── Vistas de control ─────────────
-- Progreso de la ventana post-partido (cuántos han enviado parte y valoraciones), sin revelar contenido
create view v_progreso_post_partido as
select p.id as partido_id,
       (select count(*) from convocatorias c where c.partido_id = p.id and c.estado = 'confirmado' and c.equipo is not null) as asistentes,
       (select count(distinct reportero_id) from reportes_encuentro r where r.partido_id = p.id) as partes_resultado,
       (select count(distinct reportero_id) from reportes_jugador r where r.partido_id = p.id) as partes_jugadores,
       (select count(distinct votante_id) from valoraciones v where v.partido_id = p.id) as votantes,
       p.votacion_cierra
  from partidos p
 where es_miembro(p.liga_id);

-- ¿Cuadran los goles de los jugadores con el resultado? (solo partidos de un único encuentro)
create view v_descuadres as
select e.partido_id, e.goles_local, e.goles_visitante,
       sum(case when c.equipo = e.equipo_local then a.goles else 0 end)
     + sum(case when c.equipo = e.equipo_visitante then a.autogoles else 0 end) as goles_local_jugadores,
       sum(case when c.equipo = e.equipo_visitante then a.goles else 0 end)
     + sum(case when c.equipo = e.equipo_local then a.autogoles else 0 end) as goles_visitante_jugadores
  from encuentros e
  join convocatorias c on c.partido_id = e.partido_id and c.estado = 'confirmado'
  join acta_jugador a on a.partido_id = c.partido_id and a.miembro_id = c.miembro_id
 where es_miembro(liga_de_partido(e.partido_id))
   and (select count(*) from encuentros e2 where e2.partido_id = e.partido_id) = 1
 group by e.partido_id, e.goles_local, e.goles_visitante;

-- Fiabilidad de cada reportero: % de sus datos que coinciden con el acta final (partidos cerrados).
-- security_invoker: cada jugador ve la suya; los admins, la de toda la liga.
-- TODO: usarla para ponderar votos (p. ej. peso 0,5 a reporteros con fiabilidad < 50 %).
create view v_fiabilidad with (security_invoker = true) as
with datos as (
  select r.reportero_id, (r.goles_local = e.goles_local)::int + (r.goles_visitante = e.goles_visitante)::int as aciertos, 2 as total
    from reportes_encuentro r
    join encuentros e using (partido_id, n)
    join partidos p on p.id = r.partido_id and p.estado = 'cerrado'
  union all
  select r.reportero_id,
         coalesce((r.goles = a.goles)::int, 0) + coalesce((r.asistencias = a.asistencias)::int, 0)
         + coalesce((r.autogoles = a.autogoles)::int, 0),
         (r.goles is not null)::int + (r.asistencias is not null)::int + (r.autogoles is not null)::int
    from reportes_jugador r
    join acta_jugador a on a.partido_id = r.partido_id and a.miembro_id = r.sujeto_id
    join partidos p on p.id = r.partido_id and p.estado = 'cerrado'
)
select m.liga_id, d.reportero_id as miembro_id,
       sum(d.total) as datos_reportados,
       round(100.0 * sum(d.aciertos) / nullif(sum(d.total), 0), 1) as pct_acierto
  from datos d join miembros m on m.id = d.reportero_id
 group by m.liga_id, d.reportero_id;
-- 0005 · Cálculo de puntos Fantasy y vistas de estadísticas
--
-- Puntuación (claves de reglas_puntuacion, valores por defecto en 0007):
--   jugado · victoria / empate (por encuentro) · gol_<posicion> (o gol si la liga no puntúa por posición)
--   asistencia · porteria_cero_<posicion> (por encuentro sin encajar) · goles_encajados_3 (portero, por cada 3)
--   parada_clave_2 (por cada 2) · penalti_parado · penalti_fallado · autogol
--   valoracion: tramos de la nota de compañeros, tope valoracion_max · mvp
--
-- Nota de compañeros: cada votante → media de sus aspectos; con ≥ 5 votantes media recortada
-- (sin el votante más alto ni el más bajo); con < 3 votantes no hay nota (0 puntos, sin MVP).

create or replace function puntos_por_nota(p_nota numeric, p_tope numeric) returns numeric
language sql immutable as $$
  select case when p_nota is null then 0
              else least(p_tope, case when p_nota < 5 then 0
                                      when p_nota < 6 then 1
                                      when p_nota < 7 then 2
                                      when p_nota < 8 then 3
                                      else 4 end)
         end
$$;

-- Nota general de un jugador en un partido + nº de votantes + media por aspecto
create or replace function nota_partido(p_partido uuid, p_miembro uuid,
                                        out nota numeric, out votantes int, out por_aspecto jsonb)
language plpgsql stable security definer set search_path = public as $$
declare v_suma numeric; v_max numeric; v_min numeric;
begin
  select count(*), sum(m), max(m), min(m) into votantes, v_suma, v_max, v_min
    from (select avg(v.nota) m from valoraciones v
           where v.partido_id = p_partido and v.votado_id = p_miembro group by v.votante_id) t;

  if votantes >= 5 then
    nota := round((v_suma - v_max - v_min) / (votantes - 2), 2);
  elsif votantes >= 3 then
    nota := round(v_suma / votantes, 2);
  else
    nota := null;
  end if;

  select coalesce(jsonb_object_agg(aspecto, round(m, 2)), '{}') into por_aspecto
    from (select v.aspecto, avg(v.nota) m from valoraciones v
           where v.partido_id = p_partido and v.votado_id = p_miembro group by v.aspecto) t;
  if votantes < 3 then por_aspecto := '{}'; end if;   -- con pocos votos no se publica nada
end $$;

create or replace function calcular_puntos(p_partido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; a record; v_pos posicion_campo; v_gol text;
        v_v int; v_e int; v_d int; v_nota record; d jsonb; v_total numeric;
        v_max_nota numeric; v_max_ga int;
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
    v_pos := posicion_de(a.miembro_id);
    v_gol := case when l.puntuar_por_posicion and v_pos is not null then 'gol_' || v_pos else 'gol' end;

    select count(*) filter (where gf > gc), count(*) filter (where gf = gc), count(*) filter (where gf < gc)
      into v_v, v_e, v_d
      from (select case when e.equipo_local = a.equipo then e.goles_local else e.goles_visitante end gf,
                   case when e.equipo_local = a.equipo then e.goles_visitante else e.goles_local end gc
              from encuentros e
             where e.partido_id = p_partido and a.equipo in (e.equipo_local, e.equipo_visitante)) t;

    v_nota := nota_partido(p_partido, a.miembro_id);

    d := jsonb_build_object(
      'jugado',            regla(l.id, 'jugado', v_pos),
      'resultado',         v_v * regla(l.id, 'victoria', v_pos) + v_e * regla(l.id, 'empate', v_pos),
      'goles',             a.goles * regla(l.id, v_gol, v_pos),
      'asistencias',       a.asistencias * regla(l.id, 'asistencia', v_pos),
      'porteria_cero',     case when v_pos is null then 0
                                else a.porterias_cero * regla(l.id, 'porteria_cero_' || v_pos, v_pos) end,
      'goles_encajados',   case when v_pos = 'portero'
                                then floor(a.goles_encajados / 3.0) * regla(l.id, 'goles_encajados_3', v_pos)
                                else 0 end,
      'paradas',           floor(a.paradas_clave / 2.0) * regla(l.id, 'parada_clave_2', v_pos),
      'penaltis_parados',  a.penaltis_parados * regla(l.id, 'penalti_parado', v_pos),
      'penaltis_fallados', a.penaltis_fallados * regla(l.id, 'penalti_fallado', v_pos),
      'autogoles',         a.autogoles * regla(l.id, 'autogol', v_pos),
      'valoracion',        puntos_por_nota(v_nota.nota, regla(l.id, 'valoracion_max', v_pos)),
      'mvp',               0);

    select sum(value::numeric) into v_total from jsonb_each_text(d);
    d := d || jsonb_build_object('notas', v_nota.por_aspecto);

    insert into puntos_fantasy (partido_id, miembro_id, posicion, victorias, empates, derrotas,
                                nota_media, num_votantes, es_mvp, desglose, total)
    values (p_partido, a.miembro_id, v_pos, v_v, v_e, v_d, v_nota.nota, v_nota.votantes, false, d, v_total);
  end loop;

  -- MVP: mayor nota (≥ 3 votantes); desempate goles + asistencias; si persiste, compartido
  select max(nota_media) into v_max_nota from puntos_fantasy
   where partido_id = p_partido and num_votantes >= 3;
  if v_max_nota is not null then
    select max(aj.goles + aj.asistencias) into v_max_ga
      from puntos_fantasy pf join acta_jugador aj using (partido_id, miembro_id)
     where pf.partido_id = p_partido and pf.num_votantes >= 3 and pf.nota_media = v_max_nota;

    update puntos_fantasy pf
       set es_mvp = true,
           desglose = jsonb_set(pf.desglose, '{mvp}', to_jsonb(regla(p.liga_id, 'mvp', pf.posicion))),
           total = pf.total + regla(p.liga_id, 'mvp', pf.posicion)
      from acta_jugador aj
     where aj.partido_id = pf.partido_id and aj.miembro_id = pf.miembro_id
       and pf.partido_id = p_partido and pf.num_votantes >= 3
       and pf.nota_media = v_max_nota and aj.goles + aj.asistencias = v_max_ga;
  end if;

  update partidos set estado = 'cerrado' where id = p_partido;
end $$;

-- ───────────── Vistas de estadísticas (respetan RLS del usuario) ─────────────
create view v_rendimiento with (security_invoker = true) as
select m.liga_id, pf.miembro_id,
       count(*)                                         as partidos,
       sum(pf.total)                                    as puntos_total,
       round(avg(pf.total), 2)                          as puntos_media,
       sum(aj.goles)                                    as goles,
       round(avg(aj.goles), 2)                          as goles_partido,
       sum(aj.asistencias)                              as asistencias,
       round(avg(pf.nota_media), 2)                     as nota_media,
       count(*) filter (where pf.es_mvp)                as mvps,
       sum(pf.victorias)                                as victorias,
       sum(pf.empates)                                  as empates,
       sum(pf.derrotas)                                 as derrotas,
       round(100.0 * sum(pf.victorias)
             / nullif(sum(pf.victorias + pf.empates + pf.derrotas), 0), 1) as pct_victorias
  from puntos_fantasy pf
  join miembros m on m.id = pf.miembro_id
  join acta_jugador aj using (partido_id, miembro_id)
 group by m.liga_id, pf.miembro_id;

create view v_clasificacion with (security_invoker = true) as
select r.*, rank() over (partition by r.liga_id order by r.puntos_total desc, r.puntos_media desc) as posicion
  from v_rendimiento r;

create view v_pichichi with (security_invoker = true) as
select r.*, rank() over (partition by r.liga_id order by r.goles desc, r.partidos asc) as posicion
  from v_rendimiento r
 where r.goles > 0;

-- Historial partido a partido (ficha del jugador y forma reciente para el balanceo)
create view v_historial_jugador with (security_invoker = true) as
select pf.miembro_id, p.liga_id, p.id as partido_id, p.fecha_hora,
       pf.victorias, pf.empates, pf.derrotas, aj.goles, aj.asistencias,
       pf.nota_media, pf.es_mvp, pf.total, pf.desglose,
       row_number() over (partition by pf.miembro_id order by p.fecha_hora desc) as recencia
  from puntos_fantasy pf
  join partidos p on p.id = pf.partido_id
  join acta_jugador aj using (partido_id, miembro_id);

-- Media por aspecto de valoración (a partir de las medias ya publicadas, nunca de votos sueltos)
create view v_notas_aspecto with (security_invoker = true) as
select m.liga_id, pf.miembro_id, n.key as aspecto,
       round(avg(n.value::numeric), 2) as nota_media, count(*) as partidos
  from puntos_fantasy pf
  join miembros m on m.id = pf.miembro_id
  cross join lateral jsonb_each_text(pf.desglose -> 'notas') n
 group by m.liga_id, pf.miembro_id, n.key;
-- 0006 · Seguridad: Row Level Security, permisos y Storage
-- Principio: las escrituras sensibles pasan por funciones (security definer) que validan;
-- las políticas solo abren lo que la app hace directamente.

alter table perfiles            enable row level security;
alter table ligas               enable row level security;
alter table miembros            enable row level security;
alter table partidos            enable row level security;
alter table encuentros          enable row level security;
alter table convocatorias       enable row level security;
alter table facturas            enable row level security;
alter table movimientos         enable row level security;
alter table acta_jugador        enable row level security;
alter table reglas_puntuacion   enable row level security;
alter table puntos_fantasy      enable row level security;
alter table aspectos_valoracion enable row level security;
alter table reportes_encuentro  enable row level security;
alter table reportes_jugador    enable row level security;
alter table valoraciones        enable row level security;
alter table disputas            enable row level security;

-- ───────────── Permisos base ─────────────
revoke all on all tables in schema public from anon, public;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Tokens y contactos de miembros: solo vía enlaces_invitacion() (admins)
revoke select, insert, update, delete on miembros from authenticated;
grant select (id, liga_id, perfil_id, nombre_provisional, posicion, rol, estado, invitado_por, unido_en)
  on miembros to authenticated;
grant update (posicion) on miembros to authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
-- Internas: no se llaman desde la app
revoke execute on function decidir_campo, consolidar_acta, cerrar_ventanas_vencidas,
                           liberar_plazas_futuras from authenticated;
-- (consolidar_acta queda accesible vía cerrar_post_partido / resolver_disputa)

-- ───────────── Perfiles ─────────────
create policy perfil_leer on perfiles for select to authenticated
  using (id = auth.uid() or comparte_liga(id));
create policy perfil_crear on perfiles for insert to authenticated with check (id = auth.uid());
create policy perfil_editar on perfiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ───────────── Ligas ─────────────
create policy liga_leer on ligas for select to authenticated
  using (visibilidad = 'publica' or es_miembro(id)
         or exists (select 1 from miembros m where m.liga_id = ligas.id and m.perfil_id = auth.uid()
                      and m.estado = 'solicitud'));
create policy liga_editar on ligas for update to authenticated
  using (es_admin(id)) with check (es_admin(id));
create policy liga_borrar on ligas for delete to authenticated using (es_admin(id));
-- alta: crear_liga()

-- ───────────── Miembros ─────────────
create policy miembro_leer on miembros for select to authenticated
  using (perfil_id = auth.uid() or es_miembro(liga_id));
create policy miembro_posicion on miembros for update to authenticated
  using (perfil_id = auth.uid() or es_admin(liga_id))
  with check (perfil_id = auth.uid() or es_admin(liga_id));
-- altas, roles, expulsiones: funciones de 0002

-- ───────────── Partidos y encuentros ─────────────
create policy partido_leer on partidos for select to authenticated using (es_miembro(liga_id));
create policy partido_editar on partidos for update to authenticated
  using (es_admin(liga_id)) with check (es_admin(liga_id));
create policy partido_borrar on partidos for delete to authenticated
  using (es_admin(liga_id) and estado in ('abierto', 'completo', 'cancelado'));
-- alta: crear_partido(); cambios de estado: funciones

create policy encuentro_leer on encuentros for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));
-- escritura: guardar_equipos / definir_encuentros / consolidar_acta

-- ───────────── Convocatorias ─────────────
create policy conv_leer on convocatorias for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));
create policy conv_apuntarse on convocatorias for insert to authenticated
  with check (miembro_id = mi_miembro(liga_de_partido(partido_id))
              or (es_admin(liga_de_partido(partido_id))
                  and exists (select 1 from miembros m where m.id = miembro_id
                                and m.liga_id = liga_de_partido(partido_id)
                                and m.estado in ('activo', 'pendiente_registro'))));
create policy conv_cambiar on convocatorias for update to authenticated
  using (miembro_id = mi_miembro(liga_de_partido(partido_id)) or es_admin(liga_de_partido(partido_id)))
  with check (miembro_id = mi_miembro(liga_de_partido(partido_id)) or es_admin(liga_de_partido(partido_id)));
create policy conv_borrar on convocatorias for delete to authenticated
  using (es_admin(liga_de_partido(partido_id)));
-- el trigger gestionar_cupo impide a no-admins tocar equipos o partidos cerrados

-- ───────────── Tesorería ─────────────
create policy factura_leer on facturas for select to authenticated using (es_miembro(liga_id));
create policy factura_admin on facturas for all to authenticated
  using (es_admin(liga_id)) with check (es_admin(liga_id));

create policy mov_leer on movimientos for select to authenticated
  using (miembro_id = mi_miembro(liga_id) or es_admin(liga_id));
create policy mov_admin_corregir on movimientos for delete to authenticated using (es_admin(liga_id));
-- altas: registrar_pago() / generar_cargos(); sin update: los errores se corrigen con un ajuste

-- ───────────── Acta, puntos, reglas y aspectos ─────────────
create policy acta_leer on acta_jugador for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));
create policy puntos_leer on puntos_fantasy for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));

create policy reglas_leer on reglas_puntuacion for select to authenticated using (es_miembro(liga_id));
create policy reglas_admin on reglas_puntuacion for all to authenticated
  using (es_admin(liga_id)) with check (es_admin(liga_id));

create policy aspectos_leer on aspectos_valoracion for select to authenticated using (es_miembro(liga_id));
create policy aspectos_admin on aspectos_valoracion for all to authenticated
  using (es_admin(liga_id)) with check (es_admin(liga_id));

-- ───────────── Partes post-partido ─────────────
-- Cada uno escribe y lee los suyos (el trigger validar_parte comprueba estado y asistencia).
-- Los admins leen todos los partes de su liga para resolver disputas.
create policy rep_enc_propio on reportes_encuentro for all to authenticated
  using (reportero_id = mi_miembro(liga_de_partido(partido_id)))
  with check (reportero_id = mi_miembro(liga_de_partido(partido_id)));
create policy rep_enc_admin on reportes_encuentro for select to authenticated
  using (es_admin(liga_de_partido(partido_id)));

create policy rep_jug_propio on reportes_jugador for all to authenticated
  using (reportero_id = mi_miembro(liga_de_partido(partido_id)))
  with check (reportero_id = mi_miembro(liga_de_partido(partido_id)));
create policy rep_jug_admin on reportes_jugador for select to authenticated
  using (es_admin(liga_de_partido(partido_id)));

-- Valoraciones: anónimas. Solo el votante ve las suyas; NI los admins leen votos ajenos.
create policy val_propia on valoraciones for all to authenticated
  using (votante_id = mi_miembro(liga_de_partido(partido_id)))
  with check (votante_id = mi_miembro(liga_de_partido(partido_id)));

create policy disputa_leer on disputas for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));
-- resolución: resolver_disputa()

-- ───────────── Storage: bucket privado de facturas ─────────────
-- Ruta de cada archivo: <liga_id>/<factura_id>.<ext>
insert into storage.buckets (id, name, public) values ('facturas', 'facturas', false)
on conflict (id) do nothing;

create policy facturas_leer on storage.objects for select to authenticated
  using (bucket_id = 'facturas' and es_miembro(((storage.foldername(name))[1])::uuid));
create policy facturas_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'facturas' and es_admin(((storage.foldername(name))[1])::uuid));
create policy facturas_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'facturas' and es_admin(((storage.foldername(name))[1])::uuid));

-- ───────────── Realtime ─────────────
-- En Supabase, publicar los cambios que la app escucha en vivo:
--   alter publication supabase_realtime add table convocatorias, partidos, encuentros, disputas;
-- 0007 · Valores por defecto de cada liga nueva: reglas de puntuación y aspectos de valoración
-- Inspirado en el sistema de LaLiga Fantasy MARCA (ver docs/puntuacion_fantasy.md), adaptado a fútbol amateur.

create or replace function sembrar_liga_defecto(p_liga uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into reglas_puntuacion (liga_id, clave, puntos) values
    (p_liga, 'jugado',                  2),
    (p_liga, 'victoria',                3),   -- por encuentro ganado
    (p_liga, 'empate',                  1),
    (p_liga, 'gol_portero',             6),   -- si ligas.puntuar_por_posicion
    (p_liga, 'gol_defensa',             6),
    (p_liga, 'gol_medio',               5),
    (p_liga, 'gol_delantero',           4),
    (p_liga, 'gol',                     4),   -- sin posición o liga sin puntuación por posición
    (p_liga, 'asistencia',              3),
    (p_liga, 'porteria_cero_portero',   4),   -- por encuentro sin encajar
    (p_liga, 'porteria_cero_defensa',   2),
    (p_liga, 'goles_encajados_3',      -1),   -- portero, por cada 3 encajados
    (p_liga, 'parada_clave_2',          1),   -- por cada 2 paradas clave
    (p_liga, 'penalti_parado',          3),
    (p_liga, 'penalti_fallado',        -2),
    (p_liga, 'autogol',                -2),
    (p_liga, 'valoracion_max',          4),   -- tope de puntos por nota de compañeros
    (p_liga, 'mvp',                     3)
  on conflict do nothing;

  insert into aspectos_valoracion (liga_id, clave, nombre, descripcion, orden, aplica_a) values
    (p_liga, 'ataque',       'Ataque',          'Peligro, regate, remate y desmarque',            1, 'campo'),
    (p_liga, 'porteria',     'Portería',        'Paradas, salidas y colocación',                  1, 'porteros'),
    (p_liga, 'defensa',      'Defensa',         'Recuperaciones, marcaje, ayudas atrás',          2, 'todos'),
    (p_liga, 'pase_vision',  'Pase y visión',   'Precisión, último pase, hacer jugar al equipo',  3, 'todos'),
    (p_liga, 'esfuerzo',     'Esfuerzo',        'Intensidad, presión y compromiso',               4, 'todos'),
    (p_liga, 'juego_limpio', 'Juego limpio',    'Deportividad y respeto',                         5, 'todos')
  on conflict do nothing;
end $$;

revoke execute on function sembrar_liga_defecto(uuid) from public, anon, authenticated;
-- 0008 · Liga Fantasy de mánagers: encuesta inicial, precios, mercado, plantillas, alineaciones y liquidación
-- Contrato: docs/mercado_fantasy.md
--
-- Decisiones donde la especificación dejaba margen (documentadas también en el README):
--  · Congelación de alineaciones: congelar_alineaciones(partido) fija no_habitual/multiplicador y copia la
--    alineación anterior a quien no guardó. Se ejecuta (idempotente) en el primer momento en que algo lo
--    necesita tras el cierre: recalcular_precios, liquidar_jornada o la tarea programada (pg_cron)
--    congelar_alineaciones_vencidas(). Como el estado "no habitual" solo cambia en recalcular_precios, que
--    congela antes de tocarlo, el valor congelado es siempre el vigente a la hora de cierre, aunque la
--    tarea programada no exista. La visibilidad de alineaciones ajenas depende solo de la hora.
--  · La alineación admite MENOS jugadores que el máximo (media plantilla); nunca más.
--  · Si un jugador pasa a no habitual estando ya en una plantilla, no se obliga a venderlo; el límite de
--    1 no habitual solo bloquea nuevas compras.
--  · El mercado está cerrado si la liga no tiene encuesta general cerrada (no hay precios) o si algún partido
--    no cerrado/cancelado ya pasó su hora de cierre de alineaciones. Un partido olvidado sin cerrar bloquea el
--    mercado hasta que un admin lo cierra o lo cancela.
--  · Venta: precio × (1 − comisión) redondeado a céntimos (no a 0,05).
--  · Los mánagers que llegan después de la encuesta reciben el mismo presupuesto inicial al hacer su primera
--    operación (asegurar_manager). Los jugadores que llegan después entran al mercado con G = 50.

-- ───────────── Parámetros del mercado en cada liga ─────────────
alter table ligas
  add column precio_min              numeric(6,2) not null default 1    check (precio_min > 0),
  add column precio_max              numeric(6,2) not null default 12,
  add column max_plantilla           smallint     not null default 6    check (max_plantilla between 1 and 15),
  add column bonus_no_habitual       numeric(4,2) not null default 1.5  check (bonus_no_habitual >= 1),
  add column horas_cierre_alineacion smallint     not null default 2    check (horas_cierre_alineacion between 0 and 72),
  add column ingreso_por_punto       numeric(6,3) not null default 0.10 check (ingreso_por_punto >= 0),
  add column comision_venta          numeric(4,3) not null default 0.05 check (comision_venta between 0 and 0.5),
  add column k_encuesta              numeric(5,2) not null default 5    check (k_encuesta >= 0),
  add column max_variacion           numeric(4,3) not null default 0.15 check (max_variacion between 0 and 1),
  add column presupuesto_inicial     numeric(8,2),                       -- se fija al cerrar la encuesta general
  add constraint ligas_precios_ck check (precio_max > precio_min);

alter table partidos
  add column alineaciones_congeladas boolean not null default false,
  add column jornada_liquidada       boolean not null default false;

create type atributo_valoracion as enum ('calidad', 'velocidad', 'resistencia', 'defensa', 'regate', 'portero');
create type estado_encuesta     as enum ('abierta', 'cerrada');
create type tipo_tx_fantasy     as enum ('presupuesto_inicial', 'compra', 'venta', 'ingreso_puntos', 'ajuste');

-- ───────────── Tablas ─────────────
create table encuestas_valoracion (
  id          uuid primary key default gen_random_uuid(),
  liga_id     uuid not null references ligas on delete cascade,
  sujeto_id   uuid references miembros on delete cascade,   -- null = encuesta general; si no, mini-encuesta
  estado      estado_encuesta not null default 'abierta',
  creada_en   timestamptz not null default now(),
  cerrada_en  timestamptz
);
create unique index encuesta_abierta_unica on encuestas_valoracion (liga_id, coalesce(sujeto_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where estado = 'abierta';
create unique index encuesta_general_unica on encuestas_valoracion (liga_id) where sujeto_id is null and estado = 'cerrada';

create table respuestas_ranking (
  encuesta_id  uuid not null references encuestas_valoracion on delete cascade,
  evaluador_id uuid not null references miembros on delete cascade,
  atributo     atributo_valoracion not null,
  miembro_id   uuid not null references miembros on delete cascade,
  posicion     smallint not null check (posicion >= 1),
  primary key (encuesta_id, evaluador_id, atributo, miembro_id),
  unique (encuesta_id, evaluador_id, atributo, posicion)
);

create table valoracion_jugador (
  liga_id         uuid not null references ligas on delete cascade,
  miembro_id      uuid not null references miembros on delete cascade,
  calidad         numeric(5,2),
  velocidad       numeric(5,2),
  resistencia     numeric(5,2),
  defensa         numeric(5,2),
  regate          numeric(5,2),
  portero         numeric(5,2),
  general         numeric(5,2) not null,
  num_evaluadores int not null default 0,
  actualizado_en  timestamptz not null default now(),
  primary key (liga_id, miembro_id)
);

create table mercado_jugador (
  liga_id        uuid not null references ligas on delete cascade,
  miembro_id     uuid not null references miembros on delete cascade,
  precio         numeric(6,2) not null check (precio > 0),
  rating         numeric(5,2) not null,
  no_habitual    boolean not null default false,
  actualizado_en timestamptz not null default now(),
  primary key (liga_id, miembro_id)
);

create table historial_precios (
  id          bigint generated always as identity primary key,
  liga_id     uuid not null references ligas on delete cascade,
  miembro_id  uuid not null references miembros on delete cascade,
  partido_id  uuid references partidos on delete set null,   -- null = precio inicial / mini-encuesta
  precio      numeric(6,2) not null,
  rating      numeric(5,2) not null,
  demanda     numeric(5,4),
  creado_en   timestamptz not null default now()
);
create index on historial_precios (liga_id, miembro_id, creado_en desc);
create unique index historial_una_vez_por_jornada on historial_precios (liga_id, miembro_id, partido_id)
  where partido_id is not null;

create table fantasy_managers (
  liga_id         uuid not null references ligas on delete cascade,
  miembro_id      uuid not null references miembros on delete cascade,
  saldo           numeric(8,2) not null check (saldo >= 0),
  puntos_totales  numeric(8,2) not null default 0,
  creado_en       timestamptz not null default now(),
  primary key (liga_id, miembro_id)
);

create table plantillas (
  liga_id        uuid not null references ligas on delete cascade,
  manager_id     uuid not null references miembros on delete cascade,
  jugador_id     uuid not null references miembros on delete cascade,
  precio_compra  numeric(6,2) not null,
  comprado_en    timestamptz not null default now(),
  primary key (manager_id, jugador_id)
);
create index on plantillas (liga_id, jugador_id);

create table transacciones_fantasy (
  id             uuid primary key default gen_random_uuid(),
  liga_id        uuid not null references ligas on delete cascade,
  manager_id     uuid not null references miembros on delete cascade,
  jugador_id     uuid references miembros on delete set null,
  partido_id     uuid references partidos on delete set null,
  tipo           tipo_tx_fantasy not null,
  importe        numeric(8,2) not null,
  saldo_despues  numeric(8,2) not null,
  creado_en      timestamptz not null default clock_timestamp()
);
create index on transacciones_fantasy (manager_id, creado_en desc);

create table alineaciones (
  partido_id     uuid not null references partidos on delete cascade,
  manager_id     uuid not null references miembros on delete cascade,
  jugador_id     uuid not null references miembros on delete cascade,
  no_habitual    boolean,            -- congelado al cierre (null = aún no congelado)
  multiplicador  numeric(4,2),       -- 1 o bonus_no_habitual, congelado al cierre
  copiada        boolean not null default false,   -- copiada de la jornada anterior
  primary key (partido_id, manager_id, jugador_id)
);
create index on alineaciones (manager_id);

create table puntos_manager (
  partido_id  uuid not null references partidos on delete cascade,
  manager_id  uuid not null references miembros on delete cascade,
  puntos      numeric(7,2) not null,
  ingreso     numeric(8,2) not null,
  desglose    jsonb not null,        -- [{"jugador_id":…, "puntos":13, "multiplicador":1.5, "total":19.5}, …]
  primary key (partido_id, manager_id)
);

-- ───────────── Ayudantes ─────────────
create or replace function redondear_005(x numeric) returns numeric
language sql immutable as $$ select round(x * 20) / 20 $$;

-- Precio base cuadrático a partir de un rating 0–100
create or replace function precio_base(p_liga uuid, p_rating numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select l.precio_min + (l.precio_max - l.precio_min) * power(greatest(0, least(100, p_rating)) / 100.0, 2)
    from ligas l where l.id = p_liga
$$;

-- Jugadores que aparecen en el mercado / en la encuesta: activos y pre-creados (no expulsados)
create or replace function jugadores_liga(p_liga uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select id from miembros where liga_id = p_liga and estado in ('activo', 'pendiente_registro')
$$;

-- No habitual: pre-creado sin cuenta, o < 40 % de los últimos 10 partidos cerrados (si la liga tiene ≥ 5)
create or replace function es_no_habitual(p_miembro uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare m miembros; v_total int; v_jugados int;
begin
  select * into m from miembros where id = p_miembro;
  if m.perfil_id is null then return true; end if;
  select count(*), count(pf.miembro_id) into v_total, v_jugados
    from (select id from partidos where liga_id = m.liga_id and estado = 'cerrado'
           order by fecha_hora desc limit 10) p
    left join puntos_fantasy pf on pf.partido_id = p.id and pf.miembro_id = p_miembro;
  if (select count(*) from partidos where liga_id = m.liga_id and estado = 'cerrado') < 5 then
    return false;
  end if;
  return v_jugados::numeric / nullif(v_total, 0) < 0.4;
end $$;

create or replace function hora_cierre_alineacion(p_partido uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select p.fecha_hora - make_interval(hours => l.horas_cierre_alineacion)
    from partidos p join ligas l on l.id = p.liga_id where p.id = p_partido
$$;

create or replace function alineacion_visible(p_partido uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select now() >= hora_cierre_alineacion(p_partido)
      or (select estado in ('jugado', 'post_partido', 'en_revision', 'cerrado') from partidos where id = p_partido)
$$;

create or replace function mercado_abierto(p_liga uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from encuestas_valoracion
                  where liga_id = p_liga and sujeto_id is null and estado = 'cerrada')
     and not exists (select 1 from partidos p join ligas l on l.id = p.liga_id
                       where p.liga_id = p_liga and p.estado not in ('cerrado', 'cancelado')
                         and now() >= p.fecha_hora - make_interval(hours => l.horas_cierre_alineacion))
$$;

-- Fila de mánager (con el presupuesto inicial) para quien llega después de la encuesta
create or replace function asegurar_manager(p_liga uuid, p_miembro uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_presu numeric;
begin
  if exists (select 1 from fantasy_managers where liga_id = p_liga and miembro_id = p_miembro) then return; end if;
  select presupuesto_inicial into v_presu from ligas where id = p_liga;
  if v_presu is null then raise exception 'El mercado aún no está abierto: falta cerrar la encuesta inicial'; end if;
  insert into fantasy_managers (liga_id, miembro_id, saldo) values (p_liga, p_miembro, v_presu)
  on conflict do nothing;
  if found then
    insert into transacciones_fantasy (liga_id, manager_id, tipo, importe, saldo_despues)
    values (p_liga, p_miembro, 'presupuesto_inicial', v_presu, v_presu);
  end if;
end $$;

-- ───────────── 1. Encuesta inicial de valoración conjunta ─────────────
create or replace function abrir_encuesta(p_liga uuid, p_sujeto uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform exigir_admin(p_liga);
  if p_sujeto is null and exists (select 1 from encuestas_valoracion
                                   where liga_id = p_liga and sujeto_id is null and estado = 'cerrada') then
    raise exception 'La encuesta inicial ya se hizo; para un jugador nuevo abre una mini-encuesta';
  end if;
  if p_sujeto is not null and p_sujeto not in (select jugadores_liga(p_liga)) then
    raise exception 'Ese jugador no está en la liga';
  end if;
  insert into encuestas_valoracion (liga_id, sujeto_id) values (p_liga, p_sujeto) returning id into v_id;
  return v_id;
end $$;

-- Cada mánager envía, por atributo, el orden completo de los jugadores (1.º = mejor)
create or replace function enviar_ranking(p_encuesta uuid, p_atributo text, p_orden uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare e encuestas_valoracion; v_eval uuid; v_attr atributo_valoracion; v_n int;
begin
  select * into e from encuestas_valoracion where id = p_encuesta;
  if not found then raise exception 'Encuesta no encontrada'; end if;
  if e.estado <> 'abierta' then raise exception 'La encuesta está cerrada'; end if;
  v_eval := mi_miembro(e.liga_id);
  if v_eval is null then raise exception 'Solo responden los miembros activos de la liga'; end if;
  begin
    v_attr := p_atributo::atributo_valoracion;
  exception when invalid_text_representation then
    raise exception 'Atributo no válido: %', p_atributo;
  end;

  select count(*) into v_n from jugadores_liga(e.liga_id);
  if coalesce(array_length(p_orden, 1), 0) <> v_n
     or (select count(distinct x) from unnest(p_orden) x) <> v_n
     or exists (select 1 from unnest(p_orden) x where x not in (select jugadores_liga(e.liga_id))) then
    raise exception 'Hay que ordenar a los % jugadores de la liga, sin repetir ninguno', v_n;
  end if;

  delete from respuestas_ranking where encuesta_id = p_encuesta and evaluador_id = v_eval and atributo = v_attr;
  insert into respuestas_ranking (encuesta_id, evaluador_id, atributo, miembro_id, posicion)
  select p_encuesta, v_eval, v_attr, t.x, t.ord::smallint
    from unnest(p_orden) with ordinality as t(x, ord);
end $$;

-- Nota 0–100 de un jugador en un atributo: sin autoevaluación; media recortada con ≥ 5 evaluadores
create or replace function nota_atributo(p_encuesta uuid, p_miembro uuid, p_attr atributo_valoracion,
                                         out nota numeric, out evaluadores int)
language plpgsql stable security definer set search_path = public as $$
declare v_suma numeric; v_max numeric; v_min numeric;
begin
  select count(*), sum(s), max(s), min(s) into evaluadores, v_suma, v_max, v_min
    from (select case when t.n <= 1 then 100.0 else 100.0 * (t.n - r.posicion) / (t.n - 1) end as s
            from respuestas_ranking r
            join (select evaluador_id, count(*) n from respuestas_ranking
                   where encuesta_id = p_encuesta and atributo = p_attr group by evaluador_id) t
              on t.evaluador_id = r.evaluador_id
           where r.encuesta_id = p_encuesta and r.atributo = p_attr
             and r.miembro_id = p_miembro and r.evaluador_id <> p_miembro) x;
  if evaluadores = 0 then nota := null;
  elsif evaluadores >= 5 then nota := (v_suma - v_max - v_min) / (evaluadores - 2);
  else nota := v_suma / evaluadores;
  end if;
end $$;

-- Media general G según posición (portero / campo)
create or replace function media_general(p_pos posicion_campo, cal numeric, vel numeric, res numeric,
                                         def numeric, reg numeric, por numeric) returns numeric
language sql immutable as $$
  select case when p_pos = 'portero'
              then 0.60 * coalesce(por, 50) + 0.20 * coalesce(cal, 50) + 0.20 * coalesce(res, 50)
              else 0.35 * coalesce(cal, 50) + 0.15 * coalesce(vel, 50) + 0.15 * coalesce(res, 50)
                 + 0.15 * coalesce(def, 50) + 0.20 * coalesce(reg, 50) end
$$;

create or replace function cerrar_encuesta(p_encuesta uuid) returns int
language plpgsql security definer set search_path = public as $$
declare e encuestas_valoracion; j uuid; v_cal record; v_vel record; v_res record; v_def record;
        v_reg record; v_por record; v_g numeric; v_precio numeric; v_presu numeric; k int := 0;
        v_jugados int;
begin
  select * into e from encuestas_valoracion where id = p_encuesta for update;
  if not found then raise exception 'Encuesta no encontrada'; end if;
  perform exigir_admin(e.liga_id);
  if e.estado <> 'abierta' then raise exception 'La encuesta ya está cerrada'; end if;

  for j in select x from jugadores_liga(e.liga_id) x
            where e.sujeto_id is null or x = e.sujeto_id loop
    v_cal := nota_atributo(p_encuesta, j, 'calidad');
    v_vel := nota_atributo(p_encuesta, j, 'velocidad');
    v_res := nota_atributo(p_encuesta, j, 'resistencia');
    v_def := nota_atributo(p_encuesta, j, 'defensa');
    v_reg := nota_atributo(p_encuesta, j, 'regate');
    v_por := nota_atributo(p_encuesta, j, 'portero');
    v_g := round(media_general(posicion_de(j), v_cal.nota, v_vel.nota, v_res.nota,
                               v_def.nota, v_reg.nota, v_por.nota), 2);

    insert into valoracion_jugador (liga_id, miembro_id, calidad, velocidad, resistencia, defensa, regate,
                                    portero, general, num_evaluadores, actualizado_en)
    values (e.liga_id, j, round(v_cal.nota, 2), round(v_vel.nota, 2), round(v_res.nota, 2),
            round(v_def.nota, 2), round(v_reg.nota, 2), round(v_por.nota, 2), v_g, v_cal.evaluadores, now())
    on conflict (liga_id, miembro_id) do update
      set calidad = excluded.calidad, velocidad = excluded.velocidad, resistencia = excluded.resistencia,
          defensa = excluded.defensa, regate = excluded.regate, portero = excluded.portero,
          general = excluded.general, num_evaluadores = excluded.num_evaluadores, actualizado_en = now();

    -- Precio: siempre en la encuesta general; en una mini-encuesta solo si aún no ha jugado
    select count(*) into v_jugados from puntos_fantasy pf join partidos p on p.id = pf.partido_id
     where pf.miembro_id = j and p.liga_id = e.liga_id;
    if e.sujeto_id is null or v_jugados = 0 then
      v_precio := redondear_005(precio_base(e.liga_id, v_g));
      insert into mercado_jugador (liga_id, miembro_id, precio, rating, no_habitual)
      values (e.liga_id, j, v_precio, v_g, es_no_habitual(j))
      on conflict (liga_id, miembro_id) do update
        set precio = excluded.precio, rating = excluded.rating, no_habitual = excluded.no_habitual,
            actualizado_en = now();
      insert into historial_precios (liga_id, miembro_id, precio, rating)
      values (e.liga_id, j, v_precio, v_g);
    end if;
    k := k + 1;
  end loop;

  update encuestas_valoracion set estado = 'cerrada', cerrada_en = now() where id = p_encuesta;

  if e.sujeto_id is null then
    -- Presupuesto inicial = 6,5 × precio medio inicial, redondeado a 0,5
    select round(6.5 * avg(precio) * 2) / 2 into v_presu from mercado_jugador where liga_id = e.liga_id;
    update ligas set presupuesto_inicial = v_presu where id = e.liga_id;
    perform asegurar_manager(e.liga_id, m.id)
       from miembros m where m.liga_id = e.liga_id and m.estado = 'activo';
  end if;
  return k;
end $$;

-- Jugadores que llegan con el mercado ya abierto: entran con G = 50
create or replace function alta_jugador_mercado() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_precio numeric;
begin
  if new.estado in ('activo', 'pendiente_registro')
     and exists (select 1 from encuestas_valoracion where liga_id = new.liga_id
                  and sujeto_id is null and estado = 'cerrada')
     and not exists (select 1 from mercado_jugador where liga_id = new.liga_id and miembro_id = new.id) then
    v_precio := redondear_005(precio_base(new.liga_id, 50));
    insert into mercado_jugador (liga_id, miembro_id, precio, rating, no_habitual)
    values (new.liga_id, new.id, v_precio, 50, new.perfil_id is null);
    insert into historial_precios (liga_id, miembro_id, precio, rating) values (new.liga_id, new.id, v_precio, 50);
  end if;
  return null;
end $$;

create trigger t_alta_mercado after insert or update of estado on miembros
  for each row execute function alta_jugador_mercado();

-- ───────────── 5. Alineaciones (congelación) ─────────────
-- Idempotente. Tras la hora de cierre: copia la alineación anterior a quien no guardó y congela no_habitual.
create or replace function congelar_alineaciones(p_partido uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_tam int; fm record; v_prev uuid;
begin
  select * into p from partidos where id = p_partido for update;
  if p.alineaciones_congeladas or p.estado = 'cancelado' then return false; end if;
  if now() < hora_cierre_alineacion(p_partido) and p.estado not in ('jugado', 'post_partido', 'en_revision', 'cerrado') then
    return false;
  end if;
  select * into l from ligas where id = p.liga_id;
  v_tam := p.plazas / p.num_equipos;

  for fm in select miembro_id from fantasy_managers where liga_id = p.liga_id loop
    if not exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id) then
      select a.partido_id into v_prev
        from alineaciones a join partidos pp on pp.id = a.partido_id
       where a.manager_id = fm.miembro_id and pp.liga_id = p.liga_id and pp.fecha_hora < p.fecha_hora
       order by pp.fecha_hora desc limit 1;
      if v_prev is not null then
        insert into alineaciones (partido_id, manager_id, jugador_id, copiada)
        select p_partido, fm.miembro_id, a.jugador_id, true
          from alineaciones a
          join plantillas pl on pl.manager_id = a.manager_id and pl.jugador_id = a.jugador_id
         where a.partido_id = v_prev and a.manager_id = fm.miembro_id
         order by a.jugador_id
         limit v_tam;
      end if;
    end if;
  end loop;

  update alineaciones a
     set no_habitual = coalesce(mj.no_habitual, false),
         multiplicador = case when coalesce(mj.no_habitual, false) then l.bonus_no_habitual else 1 end
    from mercado_jugador mj
   where a.partido_id = p_partido and mj.liga_id = p.liga_id and mj.miembro_id = a.jugador_id;
  update alineaciones set no_habitual = false, multiplicador = 1
   where partido_id = p_partido and multiplicador is null;

  update partidos set alineaciones_congeladas = true where id = p_partido;
  return true;
end $$;

create or replace function congelar_vencidas_liga(p_liga uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  for r in select p.id from partidos p
            where p.liga_id = p_liga and not p.alineaciones_congeladas and p.estado <> 'cancelado'
              and now() >= hora_cierre_alineacion(p.id)
            order by p.fecha_hora loop
    if congelar_alineaciones(r.id) then k := k + 1; end if;
  end loop;
  return k;
end $$;

-- Para pg_cron (cada 15 min): select congelar_alineaciones_vencidas();
create or replace function congelar_alineaciones_vencidas() returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  for r in select distinct liga_id from partidos
            where not alineaciones_congeladas and estado <> 'cancelado' loop
    k := k + congelar_vencidas_liga(r.liga_id);
  end loop;
  return k;
end $$;

create or replace function guardar_alineacion(p_partido uuid, p_jugadores uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; v_m uuid; v_tam int; v_n int;
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  v_m := mi_miembro(p.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') or p.alineaciones_congeladas
     or now() >= hora_cierre_alineacion(p_partido) then
    raise exception 'La alineación de este partido ya está cerrada (cierra % h antes del partido)',
      (select horas_cierre_alineacion from ligas where id = p.liga_id);
  end if;
  perform asegurar_manager(p.liga_id, v_m);

  v_tam := p.plazas / p.num_equipos;
  v_n := coalesce(array_length(p_jugadores, 1), 0);
  if v_n > v_tam then
    raise exception 'La alineación es de media plantilla del partido: como máximo % jugadores', v_tam;
  end if;
  if (select count(distinct x) from unnest(p_jugadores) x) <> v_n then
    raise exception 'Hay jugadores repetidos en la alineación';
  end if;
  if exists (select 1 from unnest(p_jugadores) x
              where not exists (select 1 from plantillas where manager_id = v_m and jugador_id = x)) then
    raise exception 'Solo puedes alinear jugadores de tu plantilla';
  end if;

  delete from alineaciones where partido_id = p_partido and manager_id = v_m;
  insert into alineaciones (partido_id, manager_id, jugador_id)
  select p_partido, v_m, x from unnest(p_jugadores) x;
  return v_n;
end $$;

-- ───────────── 3. Mercado ─────────────
create or replace function comprar_jugador(p_liga uuid, p_jugador uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare l ligas; v_m uuid; fm fantasy_managers; mj mercado_jugador; v_n int; v_nh int;
begin
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if not mercado_abierto(p_liga) then
    raise exception 'El mercado está cerrado (desde % h antes de un partido hasta que se calculan sus puntos)',
      (select horas_cierre_alineacion from ligas where id = p_liga);
  end if;
  select * into l from ligas where id = p_liga;
  perform asegurar_manager(p_liga, v_m);
  select * into fm from fantasy_managers where liga_id = p_liga and miembro_id = v_m for update;

  select * into mj from mercado_jugador where liga_id = p_liga and miembro_id = p_jugador;
  if not found or p_jugador not in (select jugadores_liga(p_liga)) then
    raise exception 'Ese jugador no está en el mercado';
  end if;
  if exists (select 1 from plantillas where manager_id = v_m and jugador_id = p_jugador) then
    raise exception 'Ya lo tienes en tu plantilla';
  end if;
  select count(*), count(*) filter (where m2.no_habitual) into v_n, v_nh
    from plantillas pl join mercado_jugador m2 on m2.liga_id = pl.liga_id and m2.miembro_id = pl.jugador_id
   where pl.manager_id = v_m;
  if v_n >= l.max_plantilla then
    raise exception 'Tu plantilla está llena (máximo % jugadores)', l.max_plantilla;
  end if;
  if mj.no_habitual and v_nh >= 1 then
    raise exception 'Solo puedes tener un jugador no habitual en la plantilla';
  end if;
  if fm.saldo < mj.precio then
    raise exception 'Saldo insuficiente: tienes % M y cuesta % M', fm.saldo, mj.precio;
  end if;

  update fantasy_managers set saldo = saldo - mj.precio where liga_id = p_liga and miembro_id = v_m;
  insert into plantillas (liga_id, manager_id, jugador_id, precio_compra) values (p_liga, v_m, p_jugador, mj.precio);
  insert into transacciones_fantasy (liga_id, manager_id, jugador_id, tipo, importe, saldo_despues)
  values (p_liga, v_m, p_jugador, 'compra', -mj.precio, fm.saldo - mj.precio);
  return fm.saldo - mj.precio;
end $$;

create or replace function vender_jugador(p_liga uuid, p_jugador uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare l ligas; v_m uuid; fm fantasy_managers; v_precio numeric; v_cobro numeric;
begin
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if not mercado_abierto(p_liga) then
    raise exception 'El mercado está cerrado (desde % h antes de un partido hasta que se calculan sus puntos)',
      (select horas_cierre_alineacion from ligas where id = p_liga);
  end if;
  select * into l from ligas where id = p_liga;
  select * into fm from fantasy_managers where liga_id = p_liga and miembro_id = v_m for update;
  if not exists (select 1 from plantillas where manager_id = v_m and jugador_id = p_jugador and liga_id = p_liga) then
    raise exception 'Ese jugador no está en tu plantilla';
  end if;
  select precio into v_precio from mercado_jugador where liga_id = p_liga and miembro_id = p_jugador;
  v_cobro := round(v_precio * (1 - l.comision_venta), 2);

  delete from plantillas where manager_id = v_m and jugador_id = p_jugador;
  update fantasy_managers set saldo = saldo + v_cobro where liga_id = p_liga and miembro_id = v_m;
  insert into transacciones_fantasy (liga_id, manager_id, jugador_id, tipo, importe, saldo_despues)
  values (p_liga, v_m, p_jugador, 'venta', v_cobro, fm.saldo + v_cobro);
  return fm.saldo + v_cobro;
end $$;

-- ───────────── 2. Precios tras cada jornada ─────────────
-- Idempotente por (liga, partido): si ya hay historial de esa jornada no hace nada.
create or replace function recalcular_precios(p_liga uuid, p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare l ligas; v_managers int; v_dmedia numeric; r record; v_rend numeric; v_n int; v_g numeric;
        v_w numeric; v_r numeric; v_d numeric; v_f numeric; v_nuevo numeric; v_lo numeric; v_hi numeric;
        k int := 0;
begin
  if auth.uid() is not null then perform exigir_admin(p_liga); end if;
  if exists (select 1 from historial_precios where liga_id = p_liga and partido_id = p_partido) then
    return 0;
  end if;
  if not exists (select 1 from mercado_jugador where liga_id = p_liga) then return 0; end if;
  perform congelar_vencidas_liga(p_liga);   -- congela con el estado no_habitual previo al cambio
  select * into l from ligas where id = p_liga;

  select count(*) into v_managers from fantasy_managers fm join miembros m on m.id = fm.miembro_id
   where fm.liga_id = p_liga and m.estado = 'activo';
  select avg(coalesce(h.n, 0)::numeric / nullif(v_managers, 0)) into v_dmedia
    from mercado_jugador mj
    left join (select jugador_id, count(*) n from plantillas where liga_id = p_liga group by jugador_id) h
      on h.jugador_id = mj.miembro_id
   where mj.liga_id = p_liga;

  -- Rendimiento: percentil (0–100) de la media de los últimos 5 partidos jugados
  create temp table if not exists tmp_rend (miembro_id uuid primary key, partidos int, pct numeric) on commit drop;
  delete from tmp_rend;
  insert into tmp_rend
  select miembro_id, n,
         case when count(*) over () = 1 then 50 else 100 * percent_rank() over (order by media) end
    from (select h.miembro_id, avg(h.total) media,
                 (select count(*) from puntos_fantasy pf2 join partidos p2 on p2.id = pf2.partido_id
                   where pf2.miembro_id = h.miembro_id and p2.liga_id = p_liga) n
            from (select pf.miembro_id, pf.total,
                         row_number() over (partition by pf.miembro_id order by p.fecha_hora desc) rn
                    from puntos_fantasy pf join partidos p on p.id = pf.partido_id
                   where p.liga_id = p_liga and p.estado = 'cerrado') h
           where h.rn <= 5
           group by h.miembro_id) t;

  for r in select mj.*, coalesce(vj.general, 50) as g,
                  coalesce((select count(*) from plantillas pl where pl.liga_id = p_liga
                             and pl.jugador_id = mj.miembro_id), 0) as holders
             from mercado_jugador mj
             left join valoracion_jugador vj on vj.liga_id = mj.liga_id and vj.miembro_id = mj.miembro_id
            where mj.liga_id = p_liga for update of mj loop
    select partidos, pct into v_n, v_rend from tmp_rend where miembro_id = r.miembro_id;
    v_n := coalesce(v_n, 0);
    v_w := case when l.k_encuesta + v_n = 0 then 1 else l.k_encuesta / (l.k_encuesta + v_n) end;
    v_r := v_w * r.g + (1 - v_w) * coalesce(v_rend, r.g);
    v_d := r.holders::numeric / nullif(v_managers, 0);
    v_f := greatest(0.85, least(1.25, 1 + 0.4 * (coalesce(v_d, 0) - coalesce(v_dmedia, 0))));
    v_lo := r.precio * (1 - l.max_variacion);
    v_hi := r.precio * (1 + l.max_variacion);
    v_nuevo := greatest(v_lo, least(v_hi, precio_base(p_liga, v_r) * v_f));
    v_nuevo := greatest(l.precio_min, least(l.precio_max, v_nuevo));
    v_nuevo := redondear_005(v_nuevo);
    -- el redondeo nunca puede saltarse el tope de variación
    if v_nuevo > v_hi then v_nuevo := floor(v_hi * 20) / 20; end if;
    if v_nuevo < v_lo then v_nuevo := ceil(v_lo * 20) / 20; end if;
    v_nuevo := greatest(v_nuevo, l.precio_min);

    update mercado_jugador
       set precio = v_nuevo, rating = round(v_r, 2), no_habitual = es_no_habitual(r.miembro_id),
           actualizado_en = now()
     where liga_id = p_liga and miembro_id = r.miembro_id;
    insert into historial_precios (liga_id, miembro_id, partido_id, precio, rating, demanda)
    values (p_liga, r.miembro_id, p_partido, v_nuevo, round(v_r, 2), round(coalesce(v_d, 0), 4));
    k := k + 1;
  end loop;
  return k;
end $$;

-- ───────────── 6. Liquidación de la jornada ─────────────
create or replace function liquidar_jornada(p_partido uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; fm record; v_pts numeric; v_ing numeric; v_des jsonb;
begin
  select * into p from partidos where id = p_partido for update;
  if not found then raise exception 'Partido no encontrado'; end if;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado <> 'cerrado' then raise exception 'El partido aún no tiene los puntos calculados'; end if;
  if p.jornada_liquidada then return false; end if;      -- idempotente
  select * into l from ligas where id = p.liga_id;

  perform congelar_alineaciones(p_partido);

  for fm in select * from fantasy_managers where liga_id = p.liga_id for update loop
    select coalesce(sum(coalesce(pf.total, 0) * a.multiplicador), 0),
           coalesce(jsonb_agg(jsonb_build_object(
             'jugador_id', a.jugador_id, 'puntos', coalesce(pf.total, 0),
             'multiplicador', a.multiplicador, 'jugo', pf.miembro_id is not null,
             'total', coalesce(pf.total, 0) * a.multiplicador) order by a.jugador_id), '[]'::jsonb)
      into v_pts, v_des
      from alineaciones a
      left join puntos_fantasy pf on pf.partido_id = a.partido_id and pf.miembro_id = a.jugador_id
     where a.partido_id = p_partido and a.manager_id = fm.miembro_id;

    v_ing := round(greatest(v_pts, 0) * l.ingreso_por_punto, 2);
    insert into puntos_manager (partido_id, manager_id, puntos, ingreso, desglose)
    values (p_partido, fm.miembro_id, v_pts, v_ing, v_des);
    update fantasy_managers set puntos_totales = puntos_totales + v_pts, saldo = saldo + v_ing
     where liga_id = p.liga_id and miembro_id = fm.miembro_id;
    if v_ing > 0 then
      insert into transacciones_fantasy (liga_id, manager_id, partido_id, tipo, importe, saldo_despues)
      values (p.liga_id, fm.miembro_id, p_partido, 'ingreso_puntos', v_ing, fm.saldo + v_ing);
    end if;
  end loop;

  update partidos set jornada_liquidada = true where id = p_partido;
  perform recalcular_precios(p.liga_id, p_partido);
  return true;
end $$;

-- Engancha la liquidación al cierre del partido (calcular_puntos termina poniendo estado = 'cerrado')
create or replace function tras_cerrar_partido() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform liquidar_jornada(new.id);
  return null;
end $$;

create trigger t_liquidar_jornada after update of estado on partidos
  for each row when (new.estado = 'cerrado' and old.estado is distinct from 'cerrado')
  execute function tras_cerrar_partido();

-- ───────────── Vistas ─────────────
-- Vistas "de propietario" (sin security_invoker) para poder agregar plantillas ajenas sin exponerlas:
-- se filtran con es_miembro / mi_miembro.
create view v_mercado as
select mj.liga_id, mj.miembro_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as nombre,
       posicion_de(mj.miembro_id) as posicion,
       m.estado,
       mj.precio, mj.rating, mj.no_habitual,
       vj.general as valoracion_encuesta,
       mj.precio - coalesce(prev.precio, mj.precio) as variacion,
       round(100 * (mj.precio - coalesce(prev.precio, mj.precio)) / nullif(coalesce(prev.precio, mj.precio), 0), 1)
         as variacion_pct,
       coalesce(h.n, 0) as num_plantillas,
       round(100.0 * coalesce(h.n, 0) / nullif((select count(*) from fantasy_managers f where f.liga_id = mj.liga_id), 0), 1)
         as pct_plantillas,
       exists (select 1 from plantillas pl where pl.manager_id = mi_miembro(mj.liga_id)
                 and pl.jugador_id = mj.miembro_id) as en_mi_plantilla,
       round(mj.precio * (1 - l.comision_venta), 2) as precio_venta
  from mercado_jugador mj
  join miembros m on m.id = mj.miembro_id
  join ligas l on l.id = mj.liga_id
  left join perfiles pe on pe.id = m.perfil_id
  left join valoracion_jugador vj on vj.liga_id = mj.liga_id and vj.miembro_id = mj.miembro_id
  left join (select jugador_id, count(*) n from plantillas group by jugador_id) h on h.jugador_id = mj.miembro_id
  left join lateral (select hp.precio from historial_precios hp
                      where hp.liga_id = mj.liga_id and hp.miembro_id = mj.miembro_id
                      order by hp.creado_en desc, hp.id desc offset 1 limit 1) prev on true
 where es_miembro(mj.liga_id) and m.estado in ('activo', 'pendiente_registro');

create view v_mi_plantilla as
select pl.liga_id, pl.jugador_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as nombre,
       posicion_de(pl.jugador_id) as posicion,
       pl.precio_compra, mj.precio as precio_actual,
       round(mj.precio * (1 - l.comision_venta), 2) as precio_venta,
       mj.precio - pl.precio_compra as plusvalia,
       mj.no_habitual, pl.comprado_en,
       (select c.estado from partidos p join convocatorias c on c.partido_id = p.id and c.miembro_id = pl.jugador_id
         where p.liga_id = pl.liga_id and p.estado in ('abierto', 'completo', 'equipos_hechos')
         order by p.fecha_hora limit 1) as estado_proximo_partido
  from plantillas pl
  join miembros m on m.id = pl.jugador_id
  join ligas l on l.id = pl.liga_id
  left join perfiles pe on pe.id = m.perfil_id
  left join mercado_jugador mj on mj.liga_id = pl.liga_id and mj.miembro_id = pl.jugador_id
 where pl.manager_id = mi_miembro(pl.liga_id);

create view v_clasificacion_managers as
select fm.liga_id, fm.miembro_id as manager_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as nombre,
       fm.puntos_totales, fm.saldo,
       coalesce(v.valor, 0) as valor_plantilla,
       fm.saldo + coalesce(v.valor, 0) as patrimonio,
       (select pm.puntos from puntos_manager pm join partidos p on p.id = pm.partido_id
         where pm.manager_id = fm.miembro_id order by p.fecha_hora desc limit 1) as puntos_ultima_jornada,
       rank() over (partition by fm.liga_id
                    order by fm.puntos_totales desc, fm.saldo + coalesce(v.valor, 0) desc) as posicion
  from fantasy_managers fm
  join miembros m on m.id = fm.miembro_id
  left join perfiles pe on pe.id = m.perfil_id
  left join (select pl.manager_id, sum(mj.precio) valor
               from plantillas pl join mercado_jugador mj on mj.liga_id = pl.liga_id and mj.miembro_id = pl.jugador_id
              group by pl.manager_id) v on v.manager_id = fm.miembro_id
 where es_miembro(fm.liga_id) and m.estado = 'activo';

-- Puntos de cada mánager por jornada (mejor alineación de la jornada = posicion 1)
create view v_jornada_managers as
select p.liga_id, pm.partido_id, p.fecha_hora, pm.manager_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as nombre,
       pm.puntos, pm.ingreso, pm.desglose,
       rank() over (partition by pm.partido_id order by pm.puntos desc) as posicion
  from puntos_manager pm
  join partidos p on p.id = pm.partido_id
  join miembros m on m.id = pm.manager_id
  left join perfiles pe on pe.id = m.perfil_id
 where es_miembro(p.liga_id);

-- Progreso de la encuesta (cuántos han respondido los 6 atributos), sin revelar respuestas
create view v_progreso_encuesta as
select e.id as encuesta_id, e.liga_id, e.sujeto_id, e.estado,
       (select count(*) from miembros m where m.liga_id = e.liga_id and m.estado = 'activo') as managers,
       (select count(*) from (select evaluador_id from respuestas_ranking r where r.encuesta_id = e.id
                               group by evaluador_id having count(distinct atributo) = 6) t) as completadas,
       (select array_agg(distinct atributo::text) from respuestas_ranking r
         where r.encuesta_id = e.id and r.evaluador_id = mi_miembro(e.liga_id)) as mis_atributos
  from encuestas_valoracion e
 where es_miembro(e.liga_id);

-- Rating para el generador de equipos: rating dinámico del mercado, o la encuesta, o 50
create view v_rating_balanceo as
select m.liga_id, m.id as miembro_id,
       coalesce(mj.rating, vj.general, 50) as rating,
       vj.general as rating_encuesta,
       coalesce(r.partidos, 0) as partidos
  from miembros m
  left join mercado_jugador mj on mj.liga_id = m.liga_id and mj.miembro_id = m.id
  left join valoracion_jugador vj on vj.liga_id = m.liga_id and vj.miembro_id = m.id
  left join (select pf.miembro_id, count(*) partidos from puntos_fantasy pf group by pf.miembro_id) r
    on r.miembro_id = m.id
 where es_miembro(m.liga_id) and m.estado in ('activo', 'pendiente_registro');
-- 0009 · Seguridad del mercado Fantasy
-- Decisiones:
--  · respuestas_ranking: privadas; cada evaluador solo ve las suyas (ni los admins ven las ajenas).
--  · plantillas: privadas (cada mánager ve la suya). Las de los rivales se descubren por sus alineaciones
--    una vez cerradas, y v_mercado muestra solo el agregado (% de plantillas que tienen a cada jugador).
--  · alineaciones: las propias siempre; las ajenas solo tras la hora de cierre de ese partido.
--  · saldo y puntos de cada mánager (fantasy_managers): visibles para toda la liga (es un juego y la
--    clasificación desempata por patrimonio). El detalle de transacciones: solo el propio y los admins.
--  · Todas las escrituras pasan por funciones security definer; no hay políticas de insert/update/delete.

alter table encuestas_valoracion  enable row level security;
alter table respuestas_ranking    enable row level security;
alter table valoracion_jugador    enable row level security;
alter table mercado_jugador       enable row level security;
alter table historial_precios     enable row level security;
alter table fantasy_managers      enable row level security;
alter table plantillas            enable row level security;
alter table transacciones_fantasy enable row level security;
alter table alineaciones          enable row level security;
alter table puntos_manager        enable row level security;

revoke all on encuestas_valoracion, respuestas_ranking, valoracion_jugador, mercado_jugador, historial_precios,
              fantasy_managers, plantillas, transacciones_fantasy, alineaciones, puntos_manager
  from anon, public, authenticated;
grant select on encuestas_valoracion, respuestas_ranking, valoracion_jugador, mercado_jugador, historial_precios,
                fantasy_managers, plantillas, transacciones_fantasy, alineaciones, puntos_manager
  to authenticated;
grant select on v_mercado, v_mi_plantilla, v_clasificacion_managers, v_jornada_managers,
                v_progreso_encuesta, v_rating_balanceo to authenticated;
revoke all on v_mercado, v_mi_plantilla, v_clasificacion_managers, v_jornada_managers,
              v_progreso_encuesta, v_rating_balanceo from anon;

create or replace function liga_de_encuesta(p_encuesta uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select liga_id from encuestas_valoracion where id = p_encuesta
$$;

create policy enc_leer on encuestas_valoracion for select to authenticated using (es_miembro(liga_id));
create policy rank_propio on respuestas_ranking for select to authenticated
  using (evaluador_id = mi_miembro(liga_de_encuesta(encuesta_id)));
create policy valj_leer on valoracion_jugador for select to authenticated using (es_miembro(liga_id));
create policy merc_leer on mercado_jugador for select to authenticated using (es_miembro(liga_id));
create policy hist_leer on historial_precios for select to authenticated using (es_miembro(liga_id));
create policy fm_leer on fantasy_managers for select to authenticated using (es_miembro(liga_id));
create policy plant_propia on plantillas for select to authenticated using (manager_id = mi_miembro(liga_id));
create policy tx_leer on transacciones_fantasy for select to authenticated
  using (manager_id = mi_miembro(liga_id) or es_admin(liga_id));
create policy alin_leer on alineaciones for select to authenticated
  using (manager_id = mi_miembro(liga_de_partido(partido_id))
         or (es_miembro(liga_de_partido(partido_id)) and alineacion_visible(partido_id)));
create policy pm_leer on puntos_manager for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));

-- ───────────── Funciones ─────────────
revoke execute on function
  redondear_005(numeric), precio_base(uuid, numeric), jugadores_liga(uuid), es_no_habitual(uuid),
  hora_cierre_alineacion(uuid), alineacion_visible(uuid), mercado_abierto(uuid), asegurar_manager(uuid, uuid),
  abrir_encuesta(uuid, uuid), enviar_ranking(uuid, text, uuid[]), nota_atributo(uuid, uuid, atributo_valoracion),
  media_general(posicion_campo, numeric, numeric, numeric, numeric, numeric, numeric), cerrar_encuesta(uuid),
  alta_jugador_mercado(), congelar_alineaciones(uuid), congelar_vencidas_liga(uuid),
  congelar_alineaciones_vencidas(), guardar_alineacion(uuid, uuid[]), comprar_jugador(uuid, uuid),
  vender_jugador(uuid, uuid), recalcular_precios(uuid, uuid), liquidar_jornada(uuid), tras_cerrar_partido(),
  liga_de_encuesta(uuid)
  from public, anon;

-- RPC que usa la app
grant execute on function
  abrir_encuesta(uuid, uuid), enviar_ranking(uuid, text, uuid[]), cerrar_encuesta(uuid),
  comprar_jugador(uuid, uuid), vender_jugador(uuid, uuid), guardar_alineacion(uuid, uuid[]),
  mercado_abierto(uuid), hora_cierre_alineacion(uuid), liquidar_jornada(uuid), recalcular_precios(uuid, uuid),
  precio_base(uuid, numeric), redondear_005(numeric), es_no_habitual(uuid)
  to authenticated;
-- Ayudantes que necesitan las políticas y vistas al ejecutarse con el rol del usuario
grant execute on function alineacion_visible(uuid), liga_de_encuesta(uuid), jugadores_liga(uuid)
  to authenticated;
-- Internas (triggers, tarea programada, piezas de otras funciones): sin acceso desde la app
-- asegurar_manager, nota_atributo, media_general, congelar_*, alta_jugador_mercado, tras_cerrar_partido

-- En Supabase (pg_cron), junto a cerrar_ventanas_vencidas:
--   select cron.schedule('congelar-alineaciones', '*/15 * * * *', 'select congelar_alineaciones_vencidas()');
