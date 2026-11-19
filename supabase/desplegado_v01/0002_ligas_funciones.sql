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
