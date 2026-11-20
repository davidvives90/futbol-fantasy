-- 0036 · Recordatorio de deudas, pagos con Bizum, calendario suscribible, logros, exportación y encuestas de fecha.

-- ═════════════ 1. Recordatorio de deudas ═════════════
alter table ligas add column if not exists recordatorio_deudas text not null default 'mensual'
  check (recordatorio_deudas in ('nunca', 'semanal', 'mensual', 'trimestral'));
alter table ligas add column if not exists ultimo_recordatorio_deudas timestamptz default now();
alter table ligas alter column ultimo_recordatorio_deudas set default now();
-- las ligas que ya existen empiezan a contar desde hoy (nada de avisos masivos al desplegar)
update ligas set ultimo_recordatorio_deudas = now() where ultimo_recordatorio_deudas is null;

create or replace function euros_texto(p numeric) returns text language sql immutable set search_path = public as $$
  select replace(to_char(round(p, 2), 'FM999990.00'), '.', ',') || ' €' $$;

-- Avisa a quien deba dinero (interno: lo usan el cron y el botón del admin)
create or replace function _avisar_deudas(p_liga uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0; v_liga text;
begin
  select nombre into v_liga from ligas where id = p_liga;
  for r in select m.perfil_id, sum(mv.importe) saldo from movimientos mv join miembros m on m.id = mv.miembro_id
            where mv.liga_id = p_liga and m.estado = 'activo' and m.perfil_id is not null
            group by m.perfil_id having sum(mv.importe) < -0.005 loop
    k := k + notificar(array[r.perfil_id], p_liga, 'deuda', 'Tienes un pago pendiente 💸',
                       'Debes ' || euros_texto(-r.saldo) || ' en «' || v_liga || '». Cuando pagues, pulsa «Ya he pagado» en Caja',
                       '/caja');
  end loop;
  update ligas set ultimo_recordatorio_deudas = now() where id = p_liga;
  return k;
end $$;

create or replace function recordar_deudas(p_liga uuid) returns int
language plpgsql security definer set search_path = public as $$
begin
  if not es_admin(p_liga) then raise exception 'Solo el administrador puede enviar recordatorios'; end if;
  if exists (select 1 from notificaciones where liga_id = p_liga and tipo = 'deuda' and creado_en > now() - interval '1 hour') then
    raise exception 'Ya se avisó hace menos de una hora';
  end if;
  return _avisar_deudas(p_liga);
end $$;

-- ═════════════ 2. Pagos: Bizum y «Ya he pagado» ═════════════
alter table ligas add column if not exists bizum_telefono text
  check (bizum_telefono is null or bizum_telefono ~ '^\+?[0-9 ]{9,16}$');

create table if not exists avisos_pago (
  id           uuid primary key default gen_random_uuid(),
  liga_id      uuid not null references ligas on delete cascade,
  miembro_id   uuid not null references miembros on delete cascade,
  importe      numeric(8,2) not null check (importe > 0),
  metodo       text not null default 'bizum' check (metodo in ('bizum', 'efectivo', 'transferencia', 'otro')),
  nota         text check (length(nota) <= 200),
  estado       text not null default 'pendiente' check (estado in ('pendiente', 'confirmado', 'rechazado')),
  creado_en    timestamptz not null default now(),
  resuelto_en  timestamptz,
  resuelto_por uuid references miembros on delete set null
);
create index if not exists avisos_pago_liga on avisos_pago (liga_id, estado);
create index if not exists avisos_pago_miembro on avisos_pago (miembro_id);
create index if not exists avisos_pago_resuelto_por on avisos_pago (resuelto_por);
alter table avisos_pago enable row level security;
drop policy if exists avisos_pago_leer on avisos_pago;
create policy avisos_pago_leer on avisos_pago for select to authenticated
  using (es_admin(liga_id) or miembro_id = mi_miembro(liga_id));
revoke insert, update, delete on avisos_pago from anon, authenticated;
grant select on avisos_pago to authenticated;

create or replace function avisar_pago(p_liga uuid, p_importe numeric, p_metodo text default 'bizum', p_nota text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_m uuid; v_id uuid;
begin
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if p_importe is null or p_importe <= 0 or p_importe > 1000 then raise exception 'Importe no válido'; end if;
  -- un solo aviso pendiente por jugador: el nuevo sustituye al anterior
  delete from avisos_pago where miembro_id = v_m and estado = 'pendiente';
  insert into avisos_pago (liga_id, miembro_id, importe, metodo, nota)
  values (p_liga, v_m, round(p_importe, 2), coalesce(p_metodo, 'bizum'), nullif(trim(coalesce(p_nota, '')), ''))
  returning id into v_id;
  perform notificar((select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = p_liga and rol = 'admin' and estado = 'activo'),
                    p_liga, 'aviso_pago', 'Pago por confirmar 💸',
                    nombre_miembro(v_m) || ' dice que ha pagado ' || euros_texto(p_importe) || ' (' || coalesce(p_metodo, 'bizum') || ')',
                    '/caja');
  return v_id;
end $$;

create or replace function resolver_aviso_pago(p_aviso uuid, p_aceptar boolean) returns void
language plpgsql security definer set search_path = public as $$
declare a avisos_pago;
begin
  select * into a from avisos_pago where id = p_aviso for update;
  if not found or not es_admin(a.liga_id) then raise exception 'Aviso no encontrado'; end if;
  if a.estado <> 'pendiente' then raise exception 'Este aviso ya está resuelto'; end if;
  update avisos_pago set estado = case when p_aceptar then 'confirmado' else 'rechazado' end,
         resuelto_en = now(), resuelto_por = mi_miembro(a.liga_id) where id = p_aviso;
  if p_aceptar then
    insert into movimientos (liga_id, miembro_id, tipo, importe, concepto, registrado_por)
    values (a.liga_id, a.miembro_id, 'pago', a.importe, 'Pago (' || a.metodo || ') avisado por el jugador', mi_miembro(a.liga_id));
  end if;
  perform notificar(array[(select perfil_id from miembros where id = a.miembro_id)], a.liga_id, 'aviso_pago',
                    case when p_aceptar then 'Pago confirmado ✅' else 'Pago no confirmado' end,
                    case when p_aceptar then 'El administrador ha apuntado tu pago de ' || euros_texto(a.importe)
                         else 'El administrador no ha encontrado tu pago de ' || euros_texto(a.importe) || '. Habla con él.' end,
                    '/caja');
end $$;

-- ═════════════ 3. Calendario suscribible ═════════════
alter table miembros add column if not exists token_calendario text unique;

create or replace function mi_calendario(p_liga uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_m uuid; v_t text;
begin
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  select token_calendario into v_t from miembros where id = v_m;
  if v_t is null then
    v_t := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    update miembros set token_calendario = v_t where id = v_m;
  end if;
  return v_t;
end $$;

create or replace function _ics_texto(p text) returns text language sql immutable set search_path = public as $$
  select replace(replace(replace(replace(coalesce(p, ''), '\', '\\'), ';', '\;'), ',', '\,'), E'\n', '\n') $$;
create or replace function _ics_fecha(p timestamptz) returns text language sql immutable set search_path = public as $$
  select to_char(p at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"') $$;

-- Calendario .ics de la liga del jugador dueño del token (lo sirve la función «calendario»; el token es el secreto)
create or replace function calendario_ics(p_token text) returns text
language plpgsql stable security definer set search_path = public as $$
declare m miembros; l ligas; b text; r record;
begin
  if p_token is null or length(p_token) < 32 then return null; end if;
  select * into m from miembros where token_calendario = p_token and estado in ('activo', 'pendiente_registro');
  if not found then return null; end if;
  select * into l from ligas where id = m.liga_id;
  b := 'BEGIN:VCALENDAR' || E'\r\n' || 'VERSION:2.0' || E'\r\n' || 'PRODID:-//Futbol Fantasy//ES' || E'\r\n'
    || 'CALSCALE:GREGORIAN' || E'\r\n' || 'METHOD:PUBLISH' || E'\r\n'
    || 'X-WR-CALNAME:' || _ics_texto('⚽ ' || l.nombre) || E'\r\n'
    || 'X-WR-TIMEZONE:Europe/Madrid' || E'\r\n' || 'REFRESH-INTERVAL;VALUE=DURATION:PT6H' || E'\r\n'
    || 'X-PUBLISHED-TTL:PT6H' || E'\r\n';
  for r in select p.* from partidos p where p.liga_id = l.id and p.fecha_hora > now() - interval '60 days'
            order by p.fecha_hora loop
    b := b || 'BEGIN:VEVENT' || E'\r\n'
      || 'UID:' || r.id || '@futbolfantasy' || E'\r\n'
      || 'DTSTAMP:' || _ics_fecha(now()) || E'\r\n'
      || 'DTSTART:' || _ics_fecha(r.fecha_hora) || E'\r\n'
      || 'DTEND:' || _ics_fecha(r.fecha_hora + make_interval(mins => l.duracion_partido_min)) || E'\r\n'
      || 'SUMMARY:' || _ics_texto(case when r.estado = 'cancelado' then '❌ CANCELADO · ' else '⚽ ' end || l.nombre) || E'\r\n'
      || 'DESCRIPTION:' || _ics_texto(case when r.hora_confirmada then '' else 'Hora pendiente de confirmar. ' end
                                      || coalesce('Mapa: ' || coalesce(r.campo_maps_url, l.campo_maps_url), '')) || E'\r\n'
      || coalesce('LOCATION:' || _ics_texto(l.campo_nombre) || E'\r\n', '')
      || 'STATUS:' || case when r.estado = 'cancelado' then 'CANCELLED' else 'CONFIRMED' end || E'\r\n'
      || 'BEGIN:VALARM' || E'\r\n' || 'TRIGGER:-PT2H' || E'\r\n' || 'ACTION:DISPLAY' || E'\r\n'
      || 'DESCRIPTION:' || _ics_texto(l.nombre) || E'\r\n' || 'END:VALARM' || E'\r\n'
      || 'END:VEVENT' || E'\r\n';
  end loop;
  return b || 'END:VCALENDAR' || E'\r\n';
end $$;

-- ═════════════ 4. Logros ═════════════
create table if not exists logros (
  id             uuid primary key default gen_random_uuid(),
  liga_id        uuid not null references ligas on delete cascade,
  miembro_id     uuid not null references miembros on delete cascade,
  tipo           text not null,
  partido_id     uuid references partidos on delete set null,
  conseguido_en  timestamptz not null default now(),
  unique (miembro_id, tipo)
);
create index if not exists logros_liga on logros (liga_id);
create index if not exists logros_partido on logros (partido_id);
alter table logros enable row level security;
drop policy if exists logros_leer on logros;
create policy logros_leer on logros for select to authenticated using (es_miembro(liga_id));
revoke insert, update, delete on logros from anon, authenticated;
grant select on logros to authenticated;

create or replace function nombre_logro(p_tipo text) returns text language sql immutable set search_path = public as $$
  select case p_tipo
    when 'primer_gol' then 'Primer gol' when 'hat_trick' then 'Hat-trick' when 'manita' then 'Manita (5 goles)'
    when 'goles_10' then '10 goles' when 'goles_25' then '25 goles' when 'goles_50' then '50 goles' when 'goles_100' then '100 goles'
    when 'mvp_1' then 'Primer MVP' when 'mvp_5' then '5 MVPs' when 'mvp_10' then '10 MVPs'
    when 'partidos_10' then '10 partidos' when 'partidos_25' then '25 partidos' when 'partidos_50' then '50 partidos'
    when 'partidos_100' then '100 partidos' when 'racha_10' then '10 partidos seguidos sin faltar'
    when 'invicto_5' then '5 partidos sin perder' when 'muro_5' then '5 porterías a cero'
    else p_tipo end $$;

-- Evalúa los logros de un jugador tras un partido cerrado
create or replace function evaluar_logros(p_miembro uuid, p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_liga uuid; v_goles int; v_gp int; v_mvps int; v_pj int; v_cero int; v_racha int; v_inv int;
        t text; k int := 0; n int; v_grupo boolean;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  select coalesce(sum(aj.goles), 0), coalesce(sum(aj.porterias_cero), 0) into v_goles, v_cero
    from acta_jugador aj join partidos pa on pa.id = aj.partido_id
   where aj.miembro_id = p_miembro and pa.estado = 'cerrado';
  select coalesce(goles, 0) into v_gp from acta_jugador where miembro_id = p_miembro and partido_id = p_partido;
  select count(*), count(*) filter (where es_mvp) into v_pj, v_mvps
    from puntos_fantasy pf join partidos pa on pa.id = pf.partido_id where pf.miembro_id = p_miembro and pa.estado = 'cerrado';
  -- seguidos sin faltar: últimos 10 partidos cerrados de la liga
  select count(*) filter (where exists (select 1 from puntos_fantasy x where x.partido_id = u.id and x.miembro_id = p_miembro))
    into v_racha
    from (select id from partidos where liga_id = v_liga and estado = 'cerrado' order by fecha_hora desc limit 10) u
   having count(*) = 10;
  -- sin perder: sus últimos 5 partidos
  select count(*) filter (where derrotas = 0) into v_inv
    from (select pf.derrotas from puntos_fantasy pf join partidos pa on pa.id = pf.partido_id
           where pf.miembro_id = p_miembro and pa.estado = 'cerrado' order by pa.fecha_hora desc limit 5) u
   having count(*) = 5;

  for t in select x from unnest(array[
      case when v_goles >= 1 then 'primer_gol' end, case when v_gp >= 3 then 'hat_trick' end,
      case when v_gp >= 5 then 'manita' end,
      case when v_goles >= 10 then 'goles_10' end, case when v_goles >= 25 then 'goles_25' end,
      case when v_goles >= 50 then 'goles_50' end, case when v_goles >= 100 then 'goles_100' end,
      case when v_mvps >= 1 then 'mvp_1' end, case when v_mvps >= 5 then 'mvp_5' end, case when v_mvps >= 10 then 'mvp_10' end,
      case when v_pj >= 10 then 'partidos_10' end, case when v_pj >= 25 then 'partidos_25' end,
      case when v_pj >= 50 then 'partidos_50' end, case when v_pj >= 100 then 'partidos_100' end,
      case when v_racha = 10 then 'racha_10' end, case when v_inv = 5 then 'invicto_5' end,
      case when v_cero >= 5 then 'muro_5' end]) x where x is not null loop
    insert into logros (liga_id, miembro_id, tipo, partido_id) values (v_liga, p_miembro, t, p_partido)
    on conflict (miembro_id, tipo) do nothing;
    get diagnostics n = row_count;
    if n > 0 then
      k := k + 1;
      if coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
        -- los grandes, a toda la liga; el resto, solo al jugador
        v_grupo := t in ('hat_trick', 'manita', 'mvp_5', 'mvp_10', 'goles_50', 'goles_100', 'partidos_50', 'partidos_100', 'racha_10');
        perform notificar(case when v_grupo
                            then (select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = v_liga and estado = 'activo')
                            else array[(select perfil_id from miembros where id = p_miembro)] end,
                          v_liga, 'logro', '🏅 ' || nombre_logro(t),
                          case when v_grupo then nombre_miembro(p_miembro) || ' consigue «' || nombre_logro(t) || '»'
                               else '¡Nuevo logro: ' || nombre_logro(t) || '!' end,
                          '/clasificacion/jugador/' || p_miembro);
      end if;
    end if;
  end loop;
  return k;
end $$;

-- Al cerrar un partido (ya con puntos y MVP), logros de todos los que jugaron
create or replace function logros_al_cerrar() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select miembro_id from puntos_fantasy where partido_id = new.id loop
    perform evaluar_logros(r.miembro_id, new.id);
  end loop;
  return null;
end $$;
drop trigger if exists logros_al_cerrar on partidos;
create trigger logros_al_cerrar after update of estado on partidos
  for each row when (new.estado = 'cerrado' and old.estado is distinct from 'cerrado')
  execute function logros_al_cerrar();

-- Logros de lo ya jugado (sin avisos)
do $$
declare r record;
begin
  perform set_config('ff.sin_avisos', '1', true);
  for r in select pf.miembro_id, pf.partido_id from puntos_fantasy pf join partidos pa on pa.id = pf.partido_id
            where pa.estado = 'cerrado' order by pa.fecha_hora loop
    perform evaluar_logros(r.miembro_id, r.partido_id);
  end loop;
  perform set_config('ff.sin_avisos', '', true);
end $$;
-- La fecha del logro es la del partido en que se consiguió
update logros lo set conseguido_en = pa.fecha_hora from partidos pa where pa.id = lo.partido_id and lo.conseguido_en > pa.fecha_hora;

-- ═════════════ 5. Exportar (admin) ═════════════
create or replace function exportar_liga(p_liga uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not es_admin(p_liga) then raise exception 'Solo el administrador puede exportar'; end if;
  return jsonb_build_object(
    'liga', (select nombre from ligas where id = p_liga),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('fecha', mv.fecha, 'jugador', nombre_miembro(mv.miembro_id),
                       'tipo', mv.tipo, 'importe', mv.importe, 'concepto', mv.concepto,
                       'partido', (select fecha_hora from partidos where id = mv.partido_id)) order by mv.fecha)
                     from movimientos mv where mv.liga_id = p_liga), '[]'),
    'saldos', coalesce((select jsonb_agg(to_jsonb(x) order by x.jugador) from (
                       select nombre_miembro(m.id) jugador,
                              coalesce(-sum(mv.importe) filter (where mv.tipo = 'cargo'), 0) cargado,
                              coalesce(sum(mv.importe) filter (where mv.tipo = 'pago'), 0) pagado,
                              coalesce(sum(mv.importe), 0) saldo
                         from miembros m left join movimientos mv on mv.miembro_id = m.id
                        where m.liga_id = p_liga and m.estado in ('activo', 'pendiente_registro') group by m.id) x), '[]'),
    'asistencia', historial_asistencia(p_liga, 52),
    'nombres', coalesce((select jsonb_object_agg(id, nombre_miembro(id)) from miembros where liga_id = p_liga), '{}'),
    'clasificacion', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object('jugador', nombre_miembro(r.miembro_id))
                                                order by r.puntos_total desc)
                                 from rendimiento_periodo(p_liga) r), '[]'));
end $$;

-- ═════════════ 6. Encuestas de opción múltiple (día y hora) ═════════════
alter table votaciones add column if not exists multiple boolean not null default false;
alter table votos_votacion add column if not exists opciones int[];

create or replace function crear_encuesta(p_liga uuid, p_titulo text, p_descripcion text, p_opciones jsonb,
                                          p_cierra_en timestamptz, p_anonima boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := crear_votacion(p_liga, p_titulo, p_descripcion, p_opciones, p_cierra_en, null, null, p_anonima);
  update votaciones set multiple = true where id = v_id;
  return v_id;
end $$;

-- Marca todas las opciones que te vienen bien (vacío = quitar tu voto)
create or replace function votar_encuesta(p_votacion uuid, p_opciones int[]) returns void
language plpgsql security definer set search_path = public as $$
declare v votaciones; v_m uuid;
begin
  select * into v from votaciones where id = p_votacion;
  if not found or not es_miembro(v.liga_id) then raise exception 'Votación no encontrada'; end if;
  if not v.multiple then raise exception 'Esta votación es de una sola opción'; end if;
  if v.estado <> 'abierta' or v.cierra_en <= now() then raise exception 'La votación ya está cerrada'; end if;
  if exists (select 1 from unnest(coalesce(p_opciones, '{}')) o where o < 0 or o >= jsonb_array_length(v.opciones)) then
    raise exception 'Opción no válida';
  end if;
  v_m := mi_miembro(v.liga_id);
  if v_m is null or not exists (select 1 from miembros where id = v_m and estado = 'activo') then
    raise exception 'Solo votan los miembros activos';
  end if;
  if coalesce(cardinality(p_opciones), 0) = 0 then
    delete from votos_votacion where votacion_id = p_votacion and miembro_id = v_m;
  else
    insert into votos_votacion (votacion_id, miembro_id, opcion, opciones)
    values (p_votacion, v_m, -1, (select array_agg(distinct o order by o) from unnest(p_opciones) o))
    on conflict (votacion_id, miembro_id) do update set opciones = excluded.opciones, opcion = -1, votado_en = now();
  end if;
end $$;

create or replace function votar_votacion(p_votacion uuid, p_opcion int) returns void
language plpgsql security definer set search_path = public as $$
declare v votaciones; v_m uuid;
begin
  select * into v from votaciones where id = p_votacion;
  if not found or not es_miembro(v.liga_id) then raise exception 'Votación no encontrada'; end if;
  if v.multiple then raise exception 'En esta encuesta se marcan todas las opciones que te vengan bien'; end if;
  if v.estado <> 'abierta' or v.cierra_en <= now() then raise exception 'La votación ya está cerrada'; end if;
  if p_opcion < 0 or p_opcion >= jsonb_array_length(v.opciones) then raise exception 'Opción no válida'; end if;
  v_m := mi_miembro(v.liga_id);
  if v_m is null or not exists (select 1 from miembros where id = v_m and estado = 'activo') then
    raise exception 'Solo votan los miembros activos';
  end if;
  insert into votos_votacion (votacion_id, miembro_id, opcion) values (p_votacion, v_m, p_opcion)
  on conflict (votacion_id, miembro_id) do update set opcion = excluded.opcion, opciones = null, votado_en = now();
end $$;

-- Recuento que vale para las dos clases (una opción o varias)
create or replace function _votos_opcion(p_votacion uuid, p_opcion int) returns bigint
language sql stable security definer set search_path = public as $$
  select count(*) from votos_votacion where votacion_id = p_votacion
     and (opcion = p_opcion or p_opcion = any(coalesce(opciones, '{}'))) $$;

create or replace function _cerrar_votacion(p_votacion uuid, p_estado text default 'cerrada') returns void
language plpgsql security definer set search_path = public as $$
declare v votaciones; v_gan int; v_max bigint; v_n int; v_valor jsonb;
begin
  select * into v from votaciones where id = p_votacion for update;
  if v.estado <> 'abierta' then return; end if;
  if p_estado = 'cancelada' then
    update votaciones set estado = 'cancelada', cerrada_en = now() where id = p_votacion;
    return;
  end if;
  select max(n) into v_max from (select _votos_opcion(p_votacion, i) n
                                   from generate_series(0, jsonb_array_length(v.opciones) - 1) i) s where n > 0;
  if v_max is not null then
    select count(*), min(i) into v_n, v_gan from generate_series(0, jsonb_array_length(v.opciones) - 1) i
     where _votos_opcion(p_votacion, i) = v_max;
    if v_n <> 1 then v_gan := null; end if;
  end if;
  update votaciones set estado = 'cerrada', cerrada_en = now(), ganadora = v_gan where id = p_votacion;
  if v_gan is not null and v.regla_clave is not null then
    v_valor := v.regla_valores -> v_gan;
    if v_valor is not null and v_valor <> 'null'::jsonb then
      update ligas set reglamento = reglamento || jsonb_build_object(v.regla_clave, v_valor) where id = v.liga_id;
      update votaciones set aplicada = true where id = p_votacion;
    end if;
  end if;
  perform notificar((select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = v.liga_id and estado = 'activo'),
                    v.liga_id, 'votacion', 'Votación cerrada',
                    v.titulo || ': ' || coalesce('ganó «' || (v.opciones ->> v_gan) || '»', 'empate, sin ganadora'), '/votaciones');
end $$;

create or replace function votacion_resultados(p_votacion uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v votaciones; v_mio votos_votacion;
begin
  select * into v from votaciones where id = p_votacion;
  if not found or not es_miembro(v.liga_id) then raise exception 'Votación no encontrada'; end if;
  select * into v_mio from votos_votacion where votacion_id = p_votacion and miembro_id = mi_miembro(v.liga_id);
  return jsonb_build_object(
    'mi_voto', case when v.multiple then null else v_mio.opcion end,
    'mis_opciones', case when v.multiple then to_jsonb(coalesce(v_mio.opciones, '{}')) end,
    'total', (select count(*) from votos_votacion where votacion_id = p_votacion),
    'censo', (select count(*) from miembros where liga_id = v.liga_id and estado = 'activo'),
    'votos', (select coalesce(jsonb_agg(jsonb_build_object('opcion', i, 'n', _votos_opcion(p_votacion, i),
                 'miembros', case when v.anonima then '[]'::jsonb else
                    (select coalesce(jsonb_agg(miembro_id), '[]') from votos_votacion where votacion_id = p_votacion
                       and (opcion = i or i = any(coalesce(opciones, '{}')))) end)
                 order by i), '[]')
                from generate_series(0, jsonb_array_length(v.opciones) - 1) i));
end $$;

-- ═════════════ Avisos programados (añade el recordatorio de deudas) ═════════════
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

  -- 6) Recordatorio de deudas con la frecuencia de cada liga (de 10:00 a 21:00)
  if extract(hour from now() at time zone 'Europe/Madrid') between 10 and 20 then
    for p in select l.id from ligas l
              where l.recordatorio_deudas <> 'nunca'
                and coalesce(l.ultimo_recordatorio_deudas, '-infinity') <= now() - case l.recordatorio_deudas
                      when 'semanal' then interval '7 days' when 'mensual' then interval '1 month'
                      else interval '3 months' end loop
      k := k + _avisar_deudas(p.id);
    end loop;
  end if;
  return k;
end $$;

revoke execute on function _avisar_deudas(uuid), evaluar_logros(uuid, uuid), _votos_opcion(uuid, int),
  _cerrar_votacion(uuid, text), logros_al_cerrar() from public, anon, authenticated;
revoke execute on function recordar_deudas(uuid), avisar_pago(uuid, numeric, text, text), resolver_aviso_pago(uuid, boolean),
  mi_calendario(uuid), exportar_liga(uuid), crear_encuesta(uuid, text, text, jsonb, timestamptz, boolean),
  votar_encuesta(uuid, int[]), votacion_resultados(uuid) from public, anon;
grant execute on function recordar_deudas(uuid), avisar_pago(uuid, numeric, text, text), resolver_aviso_pago(uuid, boolean),
  mi_calendario(uuid), exportar_liga(uuid), crear_encuesta(uuid, text, text, jsonb, timestamptz, boolean),
  votar_encuesta(uuid, int[]), votacion_resultados(uuid) to authenticated;
-- el calendario solo lo pide la función «calendario» (servidor); el token largo hace de contraseña
revoke execute on function calendario_ics(text) from public, anon, authenticated;
grant execute on function calendario_ics(text) to service_role;
