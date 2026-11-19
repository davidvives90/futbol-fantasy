-- 0015 · v0.3 · Rangos de jugador (fijo / reserva / invitado), fijos autoinscritos y lista de espera por prioridad
-- Contrato: docs/v03_liga.md §1, §2 y §5. Migración aditiva sobre 0001–0014.
--
-- Decisiones:
--  · Miembros existentes (activos o pre-creados) → fijo; altas nuevas → reserva. El creador de una liga nueva → fijo.
--  · Orden de la espera: los FIJOS siempre van primero (un fijo que vuelve tras darse de baja queda el primero de la
--    espera, en los dos modos). Después, en 'prioridad': reservas y luego invitados; en 'anotacion': reservas e
--    invitados juntos por orden de apuntarse. Dentro de cada grupo, por inscrito_en.
--  · Se usa el rango ACTUAL del miembro para ordenar la espera; convocatorias.rango guarda el rango con el que se
--    inscribió y se refresca al jugar (generar_cargos, 0017): es el que cuenta para la caja.
--  · Fantasy: "invitado" (×1,5) = rango invitado. es_no_habitual() se mantiene con el mismo nombre.

-- ───────────── Rangos ─────────────
create type rango_jugador as enum ('fijo', 'reserva', 'invitado');

alter table miembros add column rango rango_jugador not null default 'reserva';
update miembros set rango = 'fijo' where estado in ('activo', 'pendiente_registro');
grant select (rango) on miembros to authenticated;   -- miembros tiene permisos por columna (0006)

alter table ligas
  add column plazas_fijas smallint,
  add column orden_espera text not null default 'prioridad' check (orden_espera in ('prioridad', 'anotacion'));
update ligas set plazas_fijas = plazas;

alter table convocatorias add column rango rango_jugador;
update convocatorias c set rango = m.rango from miembros m where m.id = c.miembro_id;

-- ───────────── Orden de la lista de espera ─────────────
create or replace function prioridad_espera(p_liga uuid, p_rango rango_jugador) returns int
language sql stable security definer set search_path = public as $$
  select case when p_rango = 'fijo' then 0
              when (select orden_espera from ligas where id = p_liga) = 'anotacion' then 1
              when p_rango = 'reserva' then 1
              else 2 end
$$;

-- BEFORE: igual que 0003 + copia del rango al inscribirse
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

  if tg_op = 'INSERT' then
    new.rango := (select rango from miembros where id = new.miembro_id);
  end if;

  if tg_op = 'UPDATE' and old.estado <> 'confirmado' and new.estado = 'confirmado' then
    new.inscrito_en := clock_timestamp();   -- volver a apuntarse = al final de su grupo en la cola
  end if;

  if new.estado = 'confirmado' and (tg_op = 'INSERT' or old.estado <> 'confirmado') then
    select count(*) into v_conf from convocatorias
     where partido_id = new.partido_id and estado = 'confirmado' and miembro_id <> new.miembro_id;
    if v_conf >= p.plazas then new.estado := 'espera'; end if;
  end if;

  if new.estado <> 'confirmado' then new.equipo := null; end if;
  return new;
end $$;

-- Nadie salvo un admin (o el sistema) cambia el rango guardado en una inscripción
create or replace function proteger_rango_conv() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not es_admin(liga_de_partido(new.partido_id)) then
    new.rango := old.rango;
  end if;
  return new;
end $$;

create trigger t_conv_rango before update of rango on convocatorias
  for each row execute function proteger_rango_conv();

-- AFTER: igual que 0003 pero la espera se ordena por prioridad (fijos, reservas, invitados) y luego por hora
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
       select c.partido_id, c.miembro_id from convocatorias c join miembros m on m.id = c.miembro_id
        where c.partido_id = v_partido and c.estado = 'espera'
        order by prioridad_espera(p.liga_id, m.rango), c.inscrito_en limit 1);
    -- TODO notificación push "¡Tienes plaza!" (Edge Function escuchando este cambio)
  end if;

  if p.estado in ('abierto', 'completo') then
    select count(*) into v_conf from convocatorias where partido_id = v_partido and estado = 'confirmado';
    update partidos set estado = case when v_conf >= plazas then 'completo'::estado_partido else 'abierto' end
     where id = v_partido and estado in ('abierto', 'completo');
  end if;
  return null;
end $$;

-- ───────────── Fijos autoinscritos ─────────────
-- Inscribe como confirmados a los fijos de la liga (por antigüedad); si no caben, quedan en espera. Idempotente.
create or replace function inscribir_fijos(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  insert into convocatorias (partido_id, miembro_id, estado)
  select p.id, m.id, 'confirmado'
    from partidos p join miembros m on m.liga_id = p.liga_id
   where p.id = p_partido and p.estado in ('abierto', 'completo')
     and m.rango = 'fijo' and m.estado in ('activo', 'pendiente_registro')
   order by m.unido_en, m.id
  on conflict (partido_id, miembro_id) do nothing;
  get diagnostics k = row_count;
  return k;
end $$;

create or replace function tras_crear_partido() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform inscribir_fijos(new.id);
  return null;
end $$;

create trigger t_inscribir_fijos after insert on partidos
  for each row execute function tras_crear_partido();

-- ───────────── Fantasy: invitado (×1,5) = rango invitado ─────────────
create or replace function es_no_habitual(p_miembro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select rango = 'invitado' from miembros where id = p_miembro), false)
$$;

create or replace function refrescar_no_habitual(p_miembro uuid) returns void
language sql security definer set search_path = public as $$
  update mercado_jugador set no_habitual = es_no_habitual(miembro_id), actualizado_en = now()
   where miembro_id = p_miembro and no_habitual is distinct from es_no_habitual(miembro_id);
$$;

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
    values (new.liga_id, new.id, v_precio, 50, new.rango = 'invitado');
    insert into historial_precios (liga_id, miembro_id, precio, rating) values (new.liga_id, new.id, v_precio, 50);
  end if;
  return null;
end $$;

update mercado_jugador set no_habitual = es_no_habitual(miembro_id);

-- ───────────── RPC: cambiar el rango (admin) ─────────────
create or replace function cambiar_rango(p_miembro uuid, p_rango text) returns void
language plpgsql security definer set search_path = public as $$
declare m miembros; v_r rango_jugador;
begin
  select * into m from miembros where id = p_miembro;
  if not found then raise exception 'Miembro no encontrado'; end if;
  perform exigir_admin(m.liga_id);
  if m.estado not in ('activo', 'pendiente_registro') then
    raise exception 'Solo se cambia el rango de jugadores activos o pre-creados';
  end if;
  begin
    v_r := lower(trim(p_rango))::rango_jugador;
  exception when invalid_text_representation then
    raise exception 'Rango no válido: usa fijo, reserva o invitado';
  end;
  if v_r = m.rango then return; end if;

  update miembros set rango = v_r where id = p_miembro;
  perform refrescar_no_habitual(p_miembro);

  -- Nuevo fijo: dentro de los próximos partidos (si no cabe, primero de la espera)
  if v_r = 'fijo' then
    insert into convocatorias (partido_id, miembro_id, estado)
    select p.id, p_miembro, 'confirmado'
      from partidos p
     where p.liga_id = m.liga_id and p.estado in ('abierto', 'completo') and p.fecha_hora > now()
     order by p.fecha_hora
    on conflict (partido_id, miembro_id) do nothing;
  end if;
end $$;

-- ───────────── Altas: el creador de la liga es fijo; pre-crear con rango ─────────────
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
          coalesce((p->>'puntuar_por_posicion')::boolean, false),
          coalesce((p->>'horas_post_partido')::smallint, 48),
          auth.uid())
  returning id into v_id;
  update ligas set plazas_fijas = plazas where id = v_id;

  insert into miembros (liga_id, perfil_id, rol, estado, rango) values (v_id, auth.uid(), 'admin', 'activo', 'fijo');
  perform sembrar_liga_defecto(v_id);
  return v_id;
end $$;

-- Nueva firma con p_rango (se borra la anterior para que la llamada con nombre desde la app no sea ambigua)
-- (en vez de borrarla, se renombra la firma antigua para que no haya ambigüedad y se retira su acceso)
alter function precrear_jugadores(uuid, text[], text[]) rename to precrear_jugadores_obsoleta;
revoke execute on function precrear_jugadores_obsoleta(uuid, text[], text[]) from public, anon, authenticated;
create or replace function precrear_jugadores(p_liga uuid, p_nombres text[], p_contactos text[] default null,
                                              p_rango text default 'reserva')
returns table (miembro_id uuid, nombre text, token text)
language plpgsql security definer set search_path = public as $$
declare v_r rango_jugador;
begin
  perform exigir_admin(p_liga);
  begin
    v_r := lower(trim(coalesce(p_rango, 'reserva')))::rango_jugador;
  exception when invalid_text_representation then
    raise exception 'Rango no válido: usa fijo, reserva o invitado';
  end;
  return query
    insert into miembros (liga_id, nombre_provisional, contacto, estado, invitado_por, rango)
    select p_liga, trim(t.n), t.c, 'pendiente_registro', mi_miembro(p_liga), v_r
      from unnest(p_nombres, coalesce(p_contactos, array[]::text[])) as t(n, c)
     where t.n is not null and trim(t.n) <> ''
    returning miembros.id, miembros.nombre_provisional, miembros.token_invitacion;
  -- Pre-crear fijos: dentro de los próximos partidos ya convocados
  if v_r = 'fijo' then
    perform inscribir_fijos(p.id) from partidos p
     where p.liga_id = p_liga and p.estado in ('abierto', 'completo') and p.fecha_hora > now();
  end if;
end $$;
