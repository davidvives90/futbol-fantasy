-- 0021 · Cuenta máster (soporte interno) y códigos promocionales
--  · masters: cuentas con control total. No se pueden dar de alta desde la app (solo SQL / panel de Supabase).
--  · Un máster es administrador de TODAS las ligas (es_admin) y puede leerlas (es_miembro), sin ser jugador.
--  · Panel máster: resumen, ligas, usuarios, ajustar saldo Fantasy, forzar estado de un partido, auditoría.
--  · Códigos promocionales: dinero Fantasy gratis; el mánager lo canjea en su liga (una vez por mánager y código).
--  · Todo lo que hace un máster con sus RPC queda en auditoria_master.

create table masters (
  perfil_id uuid primary key references auth.users on delete cascade,
  nota      text,
  creado_en timestamptz not null default now()
);
alter table masters enable row level security;
revoke all on masters from anon, public, authenticated;

create or replace function es_master() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from masters where perfil_id = auth.uid())
$$;

-- El máster pasa por los mismos controles que un admin en cualquier liga
create or replace function es_admin(p_liga uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select es_master() or exists (select 1 from miembros
                                 where liga_id = p_liga and perfil_id = auth.uid()
                                   and estado = 'activo' and rol = 'admin')
$$;

create or replace function es_miembro(p_liga uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select mi_miembro(p_liga) is not null or es_master()
$$;

create or replace function comparte_liga(p_perfil uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select es_master() or exists (select 1 from miembros a join miembros b on a.liga_id = b.liga_id
                                 where a.perfil_id = auth.uid() and a.estado = 'activo'
                                   and b.perfil_id = p_perfil and b.estado in ('activo', 'solicitud'))
$$;

create table auditoria_master (
  id        bigint generated always as identity primary key,
  perfil_id uuid not null,
  accion    text not null,
  liga_id   uuid,
  detalle   jsonb not null default '{}',
  creado_en timestamptz not null default now()
);
alter table auditoria_master enable row level security;
revoke all on auditoria_master from anon, public, authenticated;
grant select on auditoria_master to authenticated;
create policy auditoria_master_leer on auditoria_master for select to authenticated using (es_master());

create or replace function exigir_master() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not es_master() then raise exception 'Solo la cuenta máster puede hacer esto' using errcode = '42501'; end if;
end $$;

create or replace function auditar_master(p_accion text, p_liga uuid, p_detalle jsonb) returns void
language sql security definer set search_path = public as $$
  insert into auditoria_master (perfil_id, accion, liga_id, detalle) values (auth.uid(), p_accion, p_liga, coalesce(p_detalle, '{}'))
$$;

-- ───────────── Códigos promocionales ─────────────
create table codigos_promo (
  id        uuid primary key default gen_random_uuid(),
  codigo    text not null unique check (codigo = upper(codigo) and codigo ~ '^[A-Z0-9_-]{3,24}$'),
  importe   numeric(8,2) not null check (importe > 0 and importe <= 1000),
  liga_id   uuid references ligas on delete cascade,          -- null = vale en cualquier liga
  usos_max  int check (usos_max is null or usos_max > 0),     -- null = sin límite
  usos      int not null default 0,
  caduca    timestamptz,
  activo    boolean not null default true,
  nota      text,
  creado_por uuid,
  creado_en timestamptz not null default now()
);
create table canjes_promo (
  codigo_id  uuid not null references codigos_promo on delete cascade,
  liga_id    uuid not null references ligas on delete cascade,
  manager_id uuid not null references miembros on delete cascade,
  importe    numeric(8,2) not null,
  creado_en  timestamptz not null default now(),
  primary key (codigo_id, manager_id)
);
alter table codigos_promo enable row level security;
alter table canjes_promo enable row level security;
revoke all on codigos_promo, canjes_promo from anon, public, authenticated;
grant select on codigos_promo, canjes_promo to authenticated;
create policy codigos_promo_master on codigos_promo for select to authenticated using (es_master());
create policy canjes_promo_leer on canjes_promo for select to authenticated
  using (es_master() or manager_id = mi_miembro(liga_id));

-- El mánager canjea un código en su liga. Devuelve el saldo nuevo. Mensajes genéricos para no dar pistas.
create or replace function canjear_codigo(p_liga uuid, p_codigo text) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_m uuid; c codigos_promo; v_saldo numeric;
begin
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if not exists (select 1 from fantasy_managers where liga_id = p_liga and miembro_id = v_m) then
    raise exception 'Aún no participas en el Fantasy de esta liga';
  end if;
  select * into c from codigos_promo where codigo = upper(trim(p_codigo)) for update;
  if not found or not c.activo or (c.caduca is not null and c.caduca < now())
     or (c.liga_id is not null and c.liga_id <> p_liga)
     or (c.usos_max is not null and c.usos >= c.usos_max) then
    raise exception 'Código no válido o caducado';
  end if;
  if exists (select 1 from canjes_promo where codigo_id = c.id and manager_id = v_m) then
    raise exception 'Ya has canjeado este código';
  end if;
  insert into canjes_promo (codigo_id, liga_id, manager_id, importe) values (c.id, p_liga, v_m, c.importe);
  update codigos_promo set usos = usos + 1 where id = c.id;
  v_saldo := mover_saldo(p_liga, v_m, c.importe, 'ajuste');
  return v_saldo;
end $$;

-- ───────────── RPC del panel máster ─────────────
create or replace function master_resumen() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_master();
  return jsonb_build_object(
    'usuarios', (select count(*) from auth.users),
    'ligas', (select count(*) from ligas),
    'miembros', (select count(*) from miembros where estado = 'activo'),
    'partidos', (select jsonb_object_agg(estado, n) from (select estado, count(*) n from partidos group by estado) t),
    'disputas_abiertas', (select count(*) from disputas where not resuelta),
    'codigos_activos', (select count(*) from codigos_promo where activo and (caduca is null or caduca > now())),
    'canjes', (select count(*) from canjes_promo),
    'dinero_promo', (select coalesce(sum(importe), 0) from canjes_promo));
end $$;

create or replace function master_ligas() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_master();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'nombre', l.nombre, 'creado_en', l.creada_en,
      'miembros', (select count(*) from miembros m where m.liga_id = l.id and m.estado = 'activo'),
      'admins', (select string_agg(coalesce(p.nombre, m.nombre_provisional), ', ') from miembros m left join perfiles p on p.id = m.perfil_id
                  where m.liga_id = l.id and m.rol = 'admin' and m.estado = 'activo'),
      'partidos', (select count(*) from partidos pa where pa.liga_id = l.id),
      'proximo', (select min(fecha_hora) from partidos pa where pa.liga_id = l.id and pa.fecha_hora > now()
                   and pa.estado not in ('cancelado', 'cerrado')),
      'disputas', (select count(*) from disputas d join partidos pa on pa.id = d.partido_id
                    where pa.liga_id = l.id and not d.resuelta))
      order by l.creada_en desc) from ligas l), '[]');
end $$;

create or replace function master_usuarios(p_buscar text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_master();
  return coalesce((select jsonb_agg(x order by x ->> 'creado_en' desc) from (
    select jsonb_build_object(
      'id', u.id, 'email', u.email, 'nombre', p.nombre, 'creado_en', u.created_at,
      'ultimo_acceso', u.last_sign_in_at, 'master', exists (select 1 from masters ma where ma.perfil_id = u.id),
      'ligas', (select jsonb_agg(jsonb_build_object('liga', l.nombre, 'rol', m.rol, 'estado', m.estado))
                  from miembros m join ligas l on l.id = m.liga_id where m.perfil_id = u.id)) x
      from auth.users u left join perfiles p on p.id = u.id
     where p_buscar is null or u.email ilike '%' || p_buscar || '%' or p.nombre ilike '%' || p_buscar || '%'
     limit 200) t), '[]');
end $$;

create or replace function master_codigos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_master();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'codigo', c.codigo, 'importe', c.importe, 'liga_id', c.liga_id,
      'liga', (select nombre from ligas where id = c.liga_id), 'usos', c.usos, 'usos_max', c.usos_max,
      'caduca', c.caduca, 'activo', c.activo, 'nota', c.nota, 'creado_en', c.creado_en)
      order by c.creado_en desc) from codigos_promo c), '[]');
end $$;

create or replace function master_crear_codigo(p_codigo text, p_importe numeric, p_liga uuid default null,
                                               p_usos_max int default null, p_caduca timestamptz default null,
                                               p_nota text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_cod text := upper(trim(p_codigo));
begin
  perform exigir_master();
  insert into codigos_promo (codigo, importe, liga_id, usos_max, caduca, nota, creado_por)
  values (v_cod, round(p_importe, 2), p_liga, p_usos_max, p_caduca, p_nota, auth.uid())
  returning id into v_id;
  perform auditar_master('crear_codigo', p_liga,
    jsonb_build_object('codigo', v_cod, 'importe', p_importe, 'usos_max', p_usos_max, 'caduca', p_caduca));
  return v_id;
end $$;

create or replace function master_activar_codigo(p_id uuid, p_activo boolean) returns void
language plpgsql security definer set search_path = public as $$
declare c codigos_promo;
begin
  perform exigir_master();
  update codigos_promo set activo = p_activo where id = p_id returning * into c;
  if not found then raise exception 'Código no encontrado'; end if;
  perform auditar_master(case when p_activo then 'activar_codigo' else 'desactivar_codigo' end, c.liga_id,
                         jsonb_build_object('codigo', c.codigo));
end $$;

-- Mánagers del Fantasy de una liga (para ajustar saldo)
create or replace function master_managers(p_liga uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_master();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'miembro_id', fm.miembro_id, 'nombre', coalesce(p.nombre, m.nombre_provisional), 'saldo', fm.saldo,
      'puntos', fm.puntos_totales) order by coalesce(p.nombre, m.nombre_provisional))
      from fantasy_managers fm join miembros m on m.id = fm.miembro_id left join perfiles p on p.id = m.perfil_id
     where fm.liga_id = p_liga), '[]');
end $$;

create or replace function master_ajustar_saldo(p_liga uuid, p_miembro uuid, p_importe numeric, p_motivo text)
returns numeric language plpgsql security definer set search_path = public as $$
declare v numeric;
begin
  perform exigir_master();
  if p_importe = 0 then raise exception 'Indica un importe distinto de 0'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Indica el motivo'; end if;
  if not exists (select 1 from fantasy_managers where liga_id = p_liga and miembro_id = p_miembro) then
    raise exception 'Ese jugador no es mánager del Fantasy de esta liga';
  end if;
  v := mover_saldo(p_liga, p_miembro, round(p_importe, 2), 'ajuste');
  perform auditar_master('ajustar_saldo', p_liga,
    jsonb_build_object('miembro_id', p_miembro, 'importe', p_importe, 'motivo', p_motivo, 'saldo', v));
  return v;
end $$;

-- Forzar el estado de un partido (incidencias: reabrir votación, deshacer «jugado», cancelar…).
-- No se toca un partido cerrado: ya repartió puntos y dinero (corregir con ajustes de saldo).
create or replace function master_forzar_estado(p_partido uuid, p_estado estado_partido, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare p partidos;
begin
  perform exigir_master();
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Indica el motivo'; end if;
  select * into p from partidos where id = p_partido for update;
  if not found then raise exception 'Partido no encontrado'; end if;
  if p.estado = 'cerrado' then
    raise exception 'El partido ya está cerrado y repartió puntos; corrige con ajustes de saldo';
  end if;
  if p_estado = 'cerrado' then
    raise exception 'Para cerrar usa el cierre normal del acta (calcula los puntos)';
  end if;
  update partidos
     set estado = p_estado,
         votacion_cierra = case when p_estado = 'post_partido' then greatest(coalesce(votacion_cierra, now()), now() + interval '24 hours')
                                else votacion_cierra end
   where id = p_partido;
  perform auditar_master('forzar_estado', p.liga_id,
    jsonb_build_object('partido_id', p_partido, 'de', p.estado, 'a', p_estado, 'motivo', p_motivo));
end $$;

create or replace function master_partidos(p_liga uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_master();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', pa.id, 'fecha_hora', pa.fecha_hora, 'estado', pa.estado,
      'confirmados', (select count(*) from convocatorias c where c.partido_id = pa.id and c.estado = 'confirmado'),
      'disputas', (select count(*) from disputas d where d.partido_id = pa.id and not d.resuelta))
      order by pa.fecha_hora desc) from partidos pa where pa.liga_id = p_liga), '[]');
end $$;

create or replace function master_auditoria(p_limite int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_master();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'accion', a.accion, 'liga', (select nombre from ligas where id = a.liga_id), 'detalle', a.detalle,
      'quien', (select email from auth.users where id = a.perfil_id), 'creado_en', a.creado_en)
      order by a.creado_en desc)
      from (select * from auditoria_master order by creado_en desc limit least(greatest(p_limite, 1), 500)) a), '[]');
end $$;

-- ───────────── Permisos ─────────────
revoke execute on function es_master(), exigir_master(), auditar_master(text, uuid, jsonb), canjear_codigo(uuid, text),
  master_resumen(), master_ligas(), master_usuarios(text), master_codigos(),
  master_crear_codigo(text, numeric, uuid, int, timestamptz, text), master_activar_codigo(uuid, boolean),
  master_managers(uuid), master_ajustar_saldo(uuid, uuid, numeric, text),
  master_forzar_estado(uuid, estado_partido, text), master_partidos(uuid), master_auditoria(int),
  es_admin(uuid), es_miembro(uuid), comparte_liga(uuid)
  from public, anon;
revoke execute on function exigir_master(), auditar_master(text, uuid, jsonb) from authenticated;
grant execute on function es_master(), canjear_codigo(uuid, text),
  master_resumen(), master_ligas(), master_usuarios(text), master_codigos(),
  master_crear_codigo(text, numeric, uuid, int, timestamptz, text), master_activar_codigo(uuid, boolean),
  master_managers(uuid), master_ajustar_saldo(uuid, uuid, numeric, text),
  master_forzar_estado(uuid, estado_partido, text), master_partidos(uuid), master_auditoria(int),
  es_admin(uuid), es_miembro(uuid), comparte_liga(uuid)
  to authenticated;
