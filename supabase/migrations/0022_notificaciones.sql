-- 0022 · Notificaciones + correcciones
--  · FIX «DELETE requires a WHERE clause»: Supabase (extensión safeupdate) rechaza DELETE sin WHERE en peticiones de la
--    API, también dentro de funciones. Afectaba a enviar_parte (post-partido), recalcular_precios (cierre de jornada)
--    y calculo_factura. Se reescriben automáticamente con «where true».
--  · Bandeja de notificaciones por usuario (notificaciones) + tokens de dispositivo para push (dispositivos).
--    Las genera la base de datos: eventos (triggers) y recordatorios programados (pg_cron cada 15 min).
--    El envío push (FCM) lo hace la Edge Function «enviar-push» con las filas push_estado = 'pendiente'.

-- ───────────── FIX DELETE sin WHERE ─────────────
do $$
declare f record;
begin
  for f in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosrc ~* 'delete\s+from\s+\w+\s*;' loop
    execute regexp_replace(pg_get_functiondef(f.oid), '(delete\s+from\s+\w+)\s*;', '\1 where true;', 'gi');
  end loop;
end $$;

-- ───────────── Tablas ─────────────
create table dispositivos (
  token          text primary key,
  perfil_id      uuid not null references auth.users on delete cascade,
  plataforma     text not null default 'android',
  actualizado_en timestamptz not null default now()
);
create index on dispositivos (perfil_id);

create table notificaciones (
  id          bigint generated always as identity primary key,
  perfil_id   uuid not null references auth.users on delete cascade,
  liga_id     uuid references ligas on delete cascade,
  tipo        text not null,
  titulo      text not null,
  cuerpo      text not null default '',
  ruta        text,                                   -- pantalla de la app que abre, p. ej. /partidos/<id>
  leida       boolean not null default false,
  push_estado text not null default 'pendiente'
              check (push_estado in ('pendiente', 'enviada', 'sin_dispositivo', 'error', 'no_push')),
  creado_en   timestamptz not null default now()
);
create index on notificaciones (perfil_id, creado_en desc);
create index on notificaciones (push_estado) where push_estado = 'pendiente';

create table recordatorios_enviados (
  partido_id uuid not null references partidos on delete cascade,
  tipo       text not null,
  creado_en  timestamptz not null default now(),
  primary key (partido_id, tipo)
);

alter table dispositivos enable row level security;
alter table notificaciones enable row level security;
alter table recordatorios_enviados enable row level security;
revoke all on dispositivos, notificaciones, recordatorios_enviados from anon, public, authenticated;
grant select on notificaciones to authenticated;
create policy notif_propias on notificaciones for select to authenticated using (perfil_id = auth.uid());

-- ───────────── Ayudantes ─────────────
create or replace function nombre_miembro(p_miembro uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(p.nombre, m.nombre_provisional, 'Un jugador')
    from miembros m left join perfiles p on p.id = m.perfil_id where m.id = p_miembro
$$;

-- «lun 30/11 18:00» en hora de Madrid
create or replace function fecha_corta(p timestamptz) returns text
language sql immutable set search_path = public as $$
  select (array['lun','mar','mié','jue','vie','sáb','dom'])[extract(isodow from p at time zone 'Europe/Madrid')::int]
         || ' ' || to_char(p at time zone 'Europe/Madrid', 'DD/MM HH24:MI')
$$;

-- Crea una notificación para cada perfil (sin duplicados, ignora nulos).
create or replace function notificar(p_perfiles uuid[], p_liga uuid, p_tipo text, p_titulo text, p_cuerpo text,
                                     p_ruta text default null) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  insert into notificaciones (perfil_id, liga_id, tipo, titulo, cuerpo, ruta)
  select distinct u, p_liga, p_tipo, p_titulo, coalesce(p_cuerpo, ''), p_ruta
    from unnest(p_perfiles) u where u is not null;
  get diagnostics k = row_count;
  return k;
end $$;

create or replace function perfiles_de_miembros(p_miembros uuid[]) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct perfil_id), '{}') from miembros
   where id = any(p_miembros) and perfil_id is not null and estado = 'activo'
$$;

-- ───────────── RPC de la app ─────────────
create or replace function registrar_dispositivo(p_token text, p_plataforma text default 'android') returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  if coalesce(length(p_token), 0) < 20 then raise exception 'Token no válido'; end if;
  insert into dispositivos (token, perfil_id, plataforma) values (p_token, auth.uid(), coalesce(p_plataforma, 'android'))
  on conflict (token) do update set perfil_id = auth.uid(), plataforma = excluded.plataforma, actualizado_en = now();
end $$;

create or replace function borrar_dispositivo(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from dispositivos where token = p_token and perfil_id = auth.uid()
$$;

create or replace function marcar_notificaciones_leidas(p_ids bigint[] default null) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  update notificaciones set leida = true
   where perfil_id = auth.uid() and not leida and (p_ids is null or id = any(p_ids));
  get diagnostics k = row_count;
  return k;
end $$;

-- ───────────── Eventos: partidos ─────────────
create or replace function notif_partido() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ruta text := '/partidos/' || new.id; v_mvp text; v_afectados uuid[];
begin
  select perfiles_de_miembros(array_agg(miembro_id)) into v_afectados from convocatorias
   where partido_id = new.id and estado in ('confirmado', 'duda', 'espera');

  if new.estado is distinct from old.estado then
    if new.estado = 'post_partido' then
      perform notificar((select perfiles_de_miembros(array_agg(miembro_id)) from convocatorias
                          where partido_id = new.id and estado = 'confirmado' and equipo is not null),
                        new.liga_id, 'post_partido', 'Post-partido abierto ⚽',
                        'Pon el resultado y tus notas (1 minuto)' ||
                        coalesce(' · hasta ' || fecha_corta(new.votacion_cierra), ''), v_ruta);
    elsif new.estado = 'en_revision' and exists (select 1 from disputas where partido_id = new.id and not resuelta) then
      perform notificar((select coalesce(array_agg(perfil_id), '{}') from miembros
                          where liga_id = new.liga_id and rol = 'admin' and estado = 'activo'),
                        new.liga_id, 'disputas', 'Hay datos en disputa',
                        'Revisa el acta del ' || fecha_corta(new.fecha_hora) || ' para cerrar la jornada', v_ruta);
    elsif new.estado = 'cerrado' then
      select string_agg(nombre_miembro(miembro_id), ' y ') into v_mvp from puntos_fantasy
       where partido_id = new.id and es_mvp;
      perform notificar((select coalesce(array_agg(perfil_id), '{}') from miembros
                          where liga_id = new.liga_id and estado = 'activo'),
                        new.liga_id, 'puntos', 'Puntos publicados 🏆',
                        'Jornada del ' || fecha_corta(new.fecha_hora) || coalesce(' · MVP: ' || v_mvp, ''), v_ruta);
    elsif new.estado = 'cancelado' and new.fecha_hora < now() + interval '14 days' then
      perform notificar(v_afectados, new.liga_id, 'cancelado', 'Partido cancelado',
                        'Se cancela el partido del ' || fecha_corta(new.fecha_hora), v_ruta);
    end if;
  elsif new.fecha_hora is distinct from old.fecha_hora
        and new.estado in ('abierto', 'completo', 'equipos_hechos') and new.fecha_hora < now() + interval '14 days' then
    perform notificar(v_afectados, new.liga_id, 'cambio_hora', 'Cambio de hora',
                      'El partido pasa a ' || fecha_corta(new.fecha_hora), v_ruta);
  end if;
  return null;
end $$;

create trigger t_notif_partido after update of estado, fecha_hora on partidos
  for each row execute function notif_partido();

-- ───────────── Eventos: convocatoria ─────────────
create or replace function notif_convocatoria() returns trigger
language plpgsql security definer set search_path = public as $$
declare p partidos; v_perfil uuid;
begin
  select perfil_id into v_perfil from miembros where id = new.miembro_id and estado = 'activo';
  if v_perfil is null then return null; end if;
  select * into p from partidos where id = new.partido_id;
  -- Solo partidos de los próximos 7 días y no en el mismo momento de crearlos (fijos inscritos solos, temporadas)
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') or p.fecha_hora > now() + interval '7 days'
     or p.creado_en >= now() then
    return null;
  end if;

  if tg_op = 'UPDATE' and old.estado = 'espera' and new.estado = 'confirmado' then
    perform notificar(array[v_perfil], p.liga_id, 'entras', '¡Entras en la convocatoria! ✅',
                      'Se ha liberado una plaza para el ' || fecha_corta(p.fecha_hora), '/partidos/' || p.id);
  elsif auth.uid() is not null and auth.uid() <> v_perfil
        and (tg_op = 'INSERT' or new.estado is distinct from old.estado)
        and new.estado in ('confirmado', 'baja', 'espera') then
    perform notificar(array[v_perfil], p.liga_id, 'admin_convocatoria',
                      case new.estado when 'baja' then 'Te han quitado de la convocatoria'
                                      when 'espera' then 'Te han apuntado (lista de espera)'
                                      else 'Te han apuntado al partido' end,
                      'Partido del ' || fecha_corta(p.fecha_hora), '/partidos/' || p.id);
  end if;
  return null;
end $$;

create trigger t_notif_convocatoria after insert or update of estado on convocatorias
  for each row execute function notif_convocatoria();

-- ───────────── Eventos: Fantasy ─────────────
create or replace function notif_oferta() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_jugador text;
begin
  select nombre_miembro(f.jugador_id) into v_jugador from fichas f where f.id = new.ficha_id;
  if tg_op = 'INSERT' and new.estado = 'pendiente' then
    perform notificar(perfiles_de_miembros(array[new.vendedor_id]), new.liga_id, 'oferta',
                      'Oferta por ' || coalesce(v_jugador, 'tu jugador') || ' 💰',
                      nombre_miembro(new.comprador_id) || ' ofrece ' || trim(to_char(new.importe, 'FM999990.##')) || ' M',
                      '/fantasy');
  elsif tg_op = 'UPDATE' and old.estado = 'pendiente' and new.estado in ('aceptada', 'rechazada') then
    perform notificar(perfiles_de_miembros(array[new.comprador_id]), new.liga_id, 'oferta_respuesta',
                      case when new.estado = 'aceptada' then 'Oferta aceptada ✅' else 'Oferta rechazada' end,
                      coalesce(v_jugador, 'Jugador') || ' · ' || trim(to_char(new.importe, 'FM999990.##')) || ' M', '/fantasy');
  end if;
  return null;
end $$;

create trigger t_notif_oferta after insert or update of estado on ofertas
  for each row execute function notif_oferta();

create or replace function notif_transaccion() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tipo = 'clausula_cobrada' then
    perform notificar(perfiles_de_miembros(array[new.manager_id]), new.liga_id, 'clausula',
                      'Te han pagado una cláusula',
                      coalesce(nombre_miembro(new.jugador_id), 'Un jugador') || ' se va por ' ||
                      trim(to_char(new.importe, 'FM999990.##')) || ' M', '/fantasy');
  end if;
  return null;
end $$;

create trigger t_notif_transaccion after insert on transacciones_fantasy
  for each row execute function notif_transaccion();

-- ───────────── Recordatorios programados ─────────────
create or replace function enviar_recordatorios() returns int
language plpgsql security definer set search_path = public as $$
declare p record; k int := 0; v_libres int; v_perfiles uuid[];
begin
  -- 1) Convocatoria: 24 h antes, si quedan plazas, a quien no ha contestado (o dijo «duda»)
  for p in select pa.* from partidos pa
            where pa.estado = 'abierto' and pa.fecha_hora between now() + interval '2 hours' and now() + interval '24 hours'
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'convocatoria') loop
    insert into recordatorios_enviados values (p.id, 'convocatoria');
    v_libres := p.plazas - (select count(*) from convocatorias where partido_id = p.id and estado = 'confirmado');
    if v_libres > 0 then
      select coalesce(array_agg(m.perfil_id), '{}') into v_perfiles from miembros m
       where m.liga_id = p.liga_id and m.estado = 'activo' and m.perfil_id is not null
         and not exists (select 1 from convocatorias c where c.partido_id = p.id and c.miembro_id = m.id
                                                       and c.estado in ('confirmado', 'baja', 'espera'));
      k := k + notificar(v_perfiles, p.liga_id, 'recordatorio_convocatoria',
                         case when v_libres = 1 then 'Falta 1 jugador' else 'Faltan ' || v_libres || ' jugadores' end,
                         '¿Juegas el ' || fecha_corta(p.fecha_hora) || '?', '/partidos/' || p.id);
    end if;
  end loop;

  -- 2) Alineación Fantasy: 1 h antes de que se cierre
  for p in select pa.*, l.horas_cierre_alineacion as h from partidos pa join ligas l on l.id = pa.liga_id
            where pa.estado in ('abierto', 'completo', 'equipos_hechos') and not pa.alineaciones_congeladas
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
  return k;
end $$;

-- ───────────── Permisos ─────────────
revoke execute on function nombre_miembro(uuid), fecha_corta(timestamptz),
  notificar(uuid[], uuid, text, text, text, text), perfiles_de_miembros(uuid[]),
  registrar_dispositivo(text, text), borrar_dispositivo(text), marcar_notificaciones_leidas(bigint[]),
  notif_partido(), notif_convocatoria(), notif_oferta(), notif_transaccion(), enviar_recordatorios()
  from public, anon;
revoke execute on function nombre_miembro(uuid), notificar(uuid[], uuid, text, text, text, text),
  perfiles_de_miembros(uuid[]), notif_partido(), notif_convocatoria(), notif_oferta(), notif_transaccion(),
  enviar_recordatorios()
  from authenticated;
grant execute on function registrar_dispositivo(text, text), borrar_dispositivo(text),
  marcar_notificaciones_leidas(bigint[]), fecha_corta(timestamptz) to authenticated;
