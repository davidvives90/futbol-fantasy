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
