-- 0042 · Convocatoria sencilla y equipos por capitanes
--  · Los fijos están en la lista desde que se crea el partido, «pendientes» de confirmar (ocupan plaza).
--    Cada fijo contesta Voy / Duda / No voy. Si dice «No voy», entra el primer suplente por orden de apuntarse.
--  · Los demás (reservas e invitados) se apuntan de suplentes y entran por orden cuando queda sitio.
--  · Bajas largas (lesión…): el fijo de baja no se apunta solo; al volver, se le apunta en los próximos partidos.
--  · ligas.modo_equipos: 'admin' (como hasta ahora) | 'automatico' (la app los hace sola al cerrarse la lista)
--    | 'capitanes' (se sortean 1 o 2 capitanes por equipo, que forman los equipos).

alter table ligas
  add column if not exists modo_equipos text not null default 'admin'
    constraint ligas_modo_equipos_ck check (modo_equipos in ('admin', 'automatico', 'capitanes')),
  add column if not exists capitanes_por_equipo smallint not null default 1
    constraint ligas_capitanes_ck check (capitanes_por_equipo between 1 and 2);
alter table convocatorias add column if not exists capitan boolean not null default false;

-- Plazas ocupadas: confirmados + fijos pendientes + en duda
create or replace function plazas_ocupadas(p_partido uuid, p_excepto uuid default null) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from convocatorias
   where partido_id = p_partido and estado in ('confirmado', 'pendiente', 'duda')
     and miembro_id is distinct from p_excepto
$$;

-- Ya no hay plazas «reservadas»: los fijos están dentro como pendientes
create or replace function plazas_reservadas_fijos(p_partido uuid) returns int
language sql stable as $$ select 0 $$;

create or replace function es_capitan(p_partido uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from convocatorias c join miembros m on m.id = c.miembro_id
                  where c.partido_id = p_partido and c.capitan and m.perfil_id = (select auth.uid()))
$$;

create or replace function gestionar_cupo() returns trigger
language plpgsql security definer set search_path = public as $$
declare p partidos; v_admin boolean; v_abre timestamptz; v_ocupa_antes boolean; v_ocupa boolean;
begin
  select * into p from partidos where id = new.partido_id for update;   -- serializa altas simultáneas
  v_admin := auth.uid() is null or es_admin(p.liga_id);                 -- null = servidor / tareas internas

  if not v_admin then
    if p.estado not in ('abierto', 'completo', 'equipos_hechos') then
      raise exception 'La convocatoria de este partido ya está cerrada';
    end if;
    v_abre := convocatoria_abre_en(p.id);
    if v_abre is not null and v_abre > now() and new.estado <> 'baja'
       and (select rango from miembros where id = new.miembro_id) <> 'fijo' then
      raise exception 'La convocatoria se abre el %', fecha_corta(v_abre);
    end if;
    if tg_op = 'UPDATE' and (new.equipo is distinct from old.equipo or new.capitan is distinct from old.capitan)
       and not es_capitan(p.id) then
      raise exception 'Solo el administrador o los capitanes pueden cambiar los equipos';
    end if;
    if tg_op = 'INSERT' then new.equipo := null; new.capitan := false; end if;
    -- «pendiente» lo pone solo la app (fijos apuntados solos)
    if new.estado = 'pendiente' and (tg_op = 'INSERT' or old.estado <> 'pendiente') then new.estado := 'confirmado'; end if;
  end if;

  if tg_op = 'INSERT' then
    new.rango := (select rango from miembros where id = new.miembro_id);
  end if;

  v_ocupa := new.estado in ('confirmado', 'pendiente', 'duda');
  v_ocupa_antes := tg_op = 'UPDATE' and old.estado in ('confirmado', 'pendiente', 'duda');

  if tg_op = 'UPDATE' and old.estado in ('baja', 'espera') and new.estado in ('espera', 'confirmado', 'duda') then
    if old.estado = 'baja' then new.inscrito_en := clock_timestamp(); end if;   -- volver = al final de la cola
  end if;

  -- Quien no tenía plaza y la pide: entra si queda sitio; si no, a suplentes (en su orden)
  if v_ocupa and not v_ocupa_antes and plazas_ocupadas(p.id, new.miembro_id) >= p.plazas then
    new.estado := 'espera';
  end if;

  if new.estado not in ('confirmado', 'pendiente', 'duda') then new.equipo := null; new.capitan := false; end if;
  return new;
end $$;

-- Mete suplentes mientras quede sitio: primero fijos que esperaban, luego por orden de apuntarse
create or replace function rellenar_plazas(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; c record; k int := 0;
begin
  select * into p from partidos where id = p_partido;
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') then return 0; end if;
  loop
    exit when plazas_ocupadas(p_partido) >= p.plazas;
    select cv.miembro_id into c from convocatorias cv join miembros m on m.id = cv.miembro_id
     where cv.partido_id = p_partido and cv.estado = 'espera'
     order by (m.rango = 'fijo') desc, cv.inscrito_en, cv.miembro_id limit 1;
    exit when not found;
    update convocatorias set estado = 'confirmado' where partido_id = p_partido and miembro_id = c.miembro_id;
    k := k + 1;
    exit when k > 50;
  end loop;
  return k;
end $$;

create or replace function promover_espera() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_partido uuid := coalesce(new.partido_id, old.partido_id); p partidos;
begin
  select * into p from partidos where id = v_partido;
  if p.id is null then return null; end if;   -- partido borrado en cascada

  if pg_trigger_depth() <= 1 and p.estado in ('abierto', 'completo', 'equipos_hechos')
     and (tg_op = 'DELETE' or tg_op = 'INSERT' or new.estado is distinct from old.estado) then
    perform rellenar_plazas(v_partido);   -- el aviso «¡Entras!» lo manda notif_convocatoria (0022)
  end if;

  if p.estado in ('abierto', 'completo') then
    update partidos set estado = case when plazas_ocupadas(v_partido) >= plazas then 'completo'::estado_partido
                                      else 'abierto' end
     where id = v_partido and estado in ('abierto', 'completo');
  end if;
  return null;
end $$;

-- Los fijos (que no estén de baja) quedan apuntados como «pendientes» en cuanto se crea el partido
create or replace function inscribir_fijos(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  insert into convocatorias (partido_id, miembro_id, estado)
  select p.id, m.id, 'pendiente'
    from partidos p join miembros m on m.liga_id = p.liga_id
   where p.id = p_partido and p.estado in ('abierto', 'completo') and p.fecha_hora > now()
     and m.rango = 'fijo' and m.estado in ('activo', 'pendiente_registro')
     and not esta_de_baja(m.id, p.fecha_hora)
   order by m.unido_en, m.id
  on conflict (partido_id, miembro_id) do nothing;
  get diagnostics k = row_count;
  return k;
end $$;

-- Al cambiar las bajas o el rango, se rehace la lista de fijos de los próximos partidos
create or replace function reapuntar_fijos() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_liga uuid := coalesce(new.liga_id, old.liga_id);
begin
  perform inscribir_fijos(p.id) from partidos p
   where p.liga_id = v_liga and p.estado in ('abierto', 'completo') and p.fecha_hora > now();
  return null;
end $$;
drop trigger if exists t_reapuntar_fijos_ausencias on ausencias;
create trigger t_reapuntar_fijos_ausencias after update or delete on ausencias
  for each row execute function reapuntar_fijos();
drop trigger if exists t_reapuntar_fijos_rango on miembros;
create trigger t_reapuntar_fijos_rango after update of rango, estado on miembros
  for each row when (new.rango = 'fijo' and new.estado = 'activo') execute function reapuntar_fijos();

-- registrar_ausencia (0033) también libera la plaza de los «pendientes»
create or replace function registrar_ausencia(p_miembro uuid, p_desde date, p_hasta date, p_motivo text, p_nota text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_liga uuid; v_perfil uuid; v_id uuid; v_desde date; v_hasta date; v_n int; v_min date; v_max date; v_abierta boolean;
begin
  select liga_id, perfil_id into v_liga, v_perfil from miembros where id = p_miembro;
  if v_liga is null then raise exception 'Jugador no encontrado'; end if;
  if v_perfil is distinct from auth.uid() and not es_admin(v_liga) then
    raise exception 'Solo puedes registrar tus bajas (o las de cualquiera si eres administrador)';
  end if;
  if p_desde is null then raise exception 'Indica desde cuándo'; end if;
  if p_hasta is not null and p_hasta < p_desde then raise exception 'La vuelta no puede ser antes de la baja'; end if;
  select count(*), min(desde), bool_or(hasta is null), max(hasta) into v_n, v_min, v_abierta, v_max
    from ausencias where miembro_id = p_miembro and desde <= coalesce(p_hasta, 'infinity'::date) + 1
                     and coalesce(hasta, 'infinity'::date) >= p_desde - 1;
  v_desde := least(p_desde, coalesce(v_min, p_desde));
  v_hasta := case when p_hasta is null or coalesce(v_abierta, false) then null else greatest(p_hasta, coalesce(v_max, p_hasta)) end;
  delete from ausencias where miembro_id = p_miembro and desde <= coalesce(p_hasta, 'infinity'::date) + 1
                          and coalesce(hasta, 'infinity'::date) >= p_desde - 1;
  insert into ausencias (liga_id, miembro_id, desde, hasta, motivo, nota, creada_por)
  values (v_liga, p_miembro, v_desde, v_hasta, coalesce(p_motivo, 'otro'), nullif(trim(coalesce(p_nota, '')), ''), auth.uid())
  returning id into v_id;
  update convocatorias c set estado = 'baja'
    from partidos pa where pa.id = c.partido_id and c.miembro_id = p_miembro
     and pa.estado in ('abierto', 'completo') and pa.fecha_hora > now()
     and c.estado in ('confirmado', 'espera', 'duda', 'pendiente')
     and esta_de_baja(p_miembro, pa.fecha_hora);
  return v_id;
end $$;

-- Equipos: el admin o un capitán del partido
create or replace function guardar_equipos(p_partido uuid, p_asignacion jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; v_sin int; v_primera boolean;
begin
  select * into p from partidos where id = p_partido;
  if not (es_admin(p.liga_id) or es_capitan(p_partido)) then
    raise exception 'Solo el administrador o los capitanes pueden hacer los equipos';
  end if;
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') then
    raise exception 'Los equipos ya no se pueden cambiar';
  end if;
  perform _aplicar_equipos(p_partido, p_asignacion);
end $$;

-- Aplica una asignación {miembro: equipo} a los que juegan (confirmados, pendientes o en duda)
create or replace function _aplicar_equipos(p_partido uuid, p_asignacion jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; v_sin int; v_primera boolean;
begin
  select * into p from partidos where id = p_partido;
  v_primera := p.estado <> 'equipos_hechos';
  update convocatorias c set equipo = (p_asignacion ->> c.miembro_id::text)::smallint
   where c.partido_id = p_partido and c.estado in ('confirmado', 'pendiente', 'duda');
  select count(*) into v_sin from convocatorias
   where partido_id = p_partido and estado = 'confirmado' and (equipo is null or equipo > p.num_equipos);
  if v_sin > 0 then raise exception 'Hay % confirmados sin equipo válido', v_sin; end if;
  update partidos set estado = 'equipos_hechos' where id = p_partido;
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

-- Valoración para equilibrar: encuesta (si la hay) o valor del Fantasy; si no, 50
create or replace function nivel_jugador(p_liga uuid, p_miembro uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select general from valoracion_jugador where liga_id = p_liga and miembro_id = p_miembro),
                  (select rating from mercado_jugador where liga_id = p_liga and miembro_id = p_miembro), 50)
$$;

-- Equipos automáticos: reparto en serpiente por nivel (1-2-2-1…) entre los confirmados
create or replace function equipos_automaticos(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; r record; i int := 0; v_eq int; v_asig jsonb := '{}';
begin
  select * into p from partidos where id = p_partido;
  if auth.uid() is not null and not (es_admin(p.liga_id) or es_capitan(p_partido)) then
    raise exception 'Solo el administrador o los capitanes pueden hacer los equipos';
  end if;
  for r in select c.miembro_id from convocatorias c
            where c.partido_id = p_partido and c.estado in ('confirmado', 'pendiente', 'duda')
            order by nivel_jugador(p.liga_id, c.miembro_id) desc, random() loop
    v_eq := case when (i / p.num_equipos) % 2 = 0 then i % p.num_equipos + 1
                 else p.num_equipos - i % p.num_equipos end;
    v_asig := v_asig || jsonb_build_object(r.miembro_id::text, v_eq);
    i := i + 1;
  end loop;
  if i = 0 then return 0; end if;
  perform _aplicar_equipos(p_partido, v_asig);
  return i;
end $$;

-- Capitanes: el admin los elige ({miembro: equipo}) o se sortean entre los confirmados
create or replace function asignar_capitanes(p_partido uuid, p_capitanes jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; v_perfiles uuid[];
begin
  select * into p from partidos where id = p_partido;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  update convocatorias set capitan = false where partido_id = p_partido and capitan;
  update convocatorias c set capitan = true, equipo = (p_capitanes ->> c.miembro_id::text)::smallint
   where c.partido_id = p_partido and c.estado in ('confirmado', 'pendiente', 'duda')
     and p_capitanes ? c.miembro_id::text;
  select perfiles_de_miembros(array_agg(miembro_id)) into v_perfiles
    from convocatorias where partido_id = p_partido and capitan;
  perform notificar(v_perfiles, p.liga_id, 'capitan', 'Eres capitán ⚽',
                    'Haz los equipos del ' || fecha_corta(p.fecha_hora) || ' y compártelos en el grupo',
                    '/partidos/' || p_partido);
end $$;

create or replace function sortear_capitanes(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; v_n int; v_asig jsonb := '{}'; r record; i int := 0;
begin
  select * into p from partidos where id = p_partido;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  v_n := p.num_equipos * (select capitanes_por_equipo from ligas where id = p.liga_id);
  for r in select miembro_id from convocatorias
            where partido_id = p_partido and estado in ('confirmado', 'pendiente', 'duda')
            order by (estado = 'confirmado') desc, random() limit v_n loop
    v_asig := v_asig || jsonb_build_object(r.miembro_id::text, i % p.num_equipos + 1);
    i := i + 1;
  end loop;
  if i = 0 then return 0; end if;
  perform asignar_capitanes(p_partido, v_asig);
  return i;
end $$;

-- Al arrancar: los fijos de los próximos partidos quedan como pendientes
do $$ declare r record;
begin
  for r in select id from partidos where estado in ('abierto', 'completo') and fecha_hora > now() loop
    perform inscribir_fijos(r.id);
  end loop;
end $$;

revoke execute on function _aplicar_equipos(uuid, jsonb), reapuntar_fijos(), plazas_ocupadas(uuid, uuid),
  nivel_jugador(uuid, uuid) from public, anon, authenticated;
revoke execute on function equipos_automaticos(uuid), asignar_capitanes(uuid, jsonb), sortear_capitanes(uuid),
  es_capitan(uuid) from public, anon;
grant execute on function equipos_automaticos(uuid), asignar_capitanes(uuid, jsonb), sortear_capitanes(uuid),
  es_capitan(uuid) to authenticated;

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
                       p.liga_id, 'recordatorio_convocatoria', 'Convocatoria abierta ⚽',
                       '¿Juegas el ' || fecha_corta(p.fecha_hora) || '? Apúntate de suplente y entras si queda sitio', '/partidos/' || p.id);
    k := k + notificar((select coalesce(array_agg(perfil_id), '{}') from miembros
                         where liga_id = p.liga_id and estado = 'activo' and rango = 'fijo'
                           and not esta_de_baja(id, p.fecha_hora)),
                       p.liga_id, 'recordatorio_convocatoria', 'Convocatoria abierta ⚽',
                       'Eres fijo y ya estás en la lista. Confirma: Voy, Duda o No voy', '/partidos/' || p.id);
  end loop;

  -- 1) Convocatoria: 24 h antes, si quedan plazas, a quien no ha contestado (o dijo «duda»)
  for p in select pa.* from partidos pa
            where pa.estado = 'abierto' and pa.fecha_hora between now() + interval '2 hours' and now() + interval '24 hours'
              and coalesce(convocatoria_abre_en(pa.id), now()) <= now()
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'convocatoria') loop
    insert into recordatorios_enviados values (p.id, 'convocatoria');
    v_libres := p.plazas - plazas_ocupadas(p.id);
    if v_libres > 0 then
      select coalesce(array_agg(m.perfil_id), '{}') into v_perfiles from miembros m
       where m.liga_id = p.liga_id and m.estado = 'activo' and m.perfil_id is not null
         and not esta_de_baja(m.id, p.fecha_hora)
         and not exists (select 1 from convocatorias c where c.partido_id = p.id and c.miembro_id = m.id
                                                       and c.estado in ('confirmado', 'baja', 'espera', 'pendiente', 'duda'));
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

  -- 7) Equipos: con la lista cerrada (completa y sin fijos pendientes o en duda) o a 6 h del partido
  for p in select pa.*, l.modo_equipos as modo, l.capitanes_por_equipo as cpe from partidos pa join ligas l on l.id = pa.liga_id
            where l.modo_equipos in ('automatico', 'capitanes') and pa.estado in ('abierto', 'completo')
              and pa.fecha_hora > now()
              and ((pa.estado = 'completo' and not exists (select 1 from convocatorias c where c.partido_id = pa.id
                                                                                         and c.estado in ('pendiente', 'duda')))
                   or pa.fecha_hora <= now() + interval '6 hours')
              and plazas_ocupadas(pa.id) >= 2 * pa.num_equipos
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'equipos_auto') loop
    insert into recordatorios_enviados values (p.id, 'equipos_auto');
    if p.modo = 'automatico' then
      perform equipos_automaticos(p.id);
    elsif not exists (select 1 from convocatorias c where c.partido_id = p.id and c.capitan) then
      perform sortear_capitanes(p.id);
    end if;
  end loop;

  -- 8) Al empezar el partido, los fijos que no contestaron (y los «duda») cuentan como que van
  update convocatorias c set estado = 'confirmado'
    from partidos pa
   where pa.id = c.partido_id and c.estado in ('pendiente', 'duda')
     and pa.estado in ('abierto', 'completo', 'equipos_hechos') and pa.fecha_hora <= now();
  return k;
end $$;

-- Traducciones de los avisos nuevos (ver 0037)
delete from avisos_traducciones where orden between 51 and 56;
insert into avisos_traducciones (orden, patron, idioma, plantilla)
select v.o, v.p, l.idioma, v.t[l.n]
  from (values
(51, '^Eres fijo y ya estás en la lista\. Confirma: Voy, Duda o No voy$', array['Ets fix i ja ets a la llista. Confirma: Hi vaig, Dubte o No hi vaig', 'Es fixo e xa estás na lista. Confirma: Vou, Dúbida ou Non vou', 'Finkoa zara eta zerrendan zaude. Berretsi: Banoa, Zalantza edo Ez noa', 'You''re a regular and already on the list. Confirm: I''m in, Maybe or I''m out', 'Du bist Stammspieler und schon auf der Liste. Bestätige: Ich komme, Vielleicht oder Ich komme nicht', 'Sei fisso e sei già in lista. Conferma: Ci sono, Forse o Non ci sono', 'Je bent vaste speler en staat al op de lijst. Bevestig: Ik kom, Misschien of Ik kom niet', 'Tu es titulaire et déjà sur la liste. Confirme : J''y vais, Peut-être ou Je n''y vais pas']),
(52, '^¿Juegas el (.+)\? Apúntate de suplente y entras si queda sitio$', array['Jugues el \1? Apunta''t de suplent i entres si queda lloc', 'Xogas o \1? Apúntate de suplente e entras se queda sitio', '\1ean jokatzen duzu? Eman izena ordezko gisa eta lekua badago sartuko zara', 'Playing on \1? Sign up as a sub and you''re in if a spot frees up', 'Spielst du am \1? Trag dich als Ersatz ein, du rückst nach, wenn ein Platz frei wird', 'Giochi il \1? Iscriviti come riserva ed entri se si libera un posto', 'Speel je op \1? Meld je aan als reserve, je komt erin als er plek is', 'Tu joues le \1 ? Inscris-toi comme remplaçant, tu entres s''il reste une place']),
(53, '^Equipos hechos ✅$', array['Equips fets ✅', 'Equipos feitos ✅', 'Taldeak eginda ✅', 'Teams are ready ✅', 'Teams stehen ✅', 'Squadre fatte ✅', 'Teams zijn klaar ✅', 'Équipes prêtes ✅']),
(54, '^Mira en qué equipo juegas el (.+)$', array['Mira en quin equip jugues el \1', 'Mira en que equipo xogas o \1', 'Ikusi zein taldetan jokatzen duzun \1ean', 'See which team you''re on for \1', 'Sieh nach, in welchem Team du am \1 spielst', 'Guarda in che squadra giochi il \1', 'Kijk in welk team je speelt op \1', 'Regarde dans quelle équipe tu joues le \1']),
(55, '^Eres capitán ⚽$', array['Ets capità ⚽', 'Es capitán ⚽', 'Kapitaina zara ⚽', 'You''re captain ⚽', 'Du bist Kapitän ⚽', 'Sei capitano ⚽', 'Je bent aanvoerder ⚽', 'Tu es capitaine ⚽']),
(56, '^Haz los equipos del (.+) y compártelos en el grupo$', array['Fes els equips del \1 i comparteix-los al grup', 'Fai os equipos do \1 e compárteos no grupo', 'Egin \1ko taldeak eta partekatu taldean', 'Pick the teams for \1 and share them in the group', 'Stell die Teams für \1 auf und teile sie in der Gruppe', 'Fai le squadre del \1 e condividile nel gruppo', 'Maak de teams voor \1 en deel ze in de groep', 'Fais les équipes du \1 et partage-les dans le groupe'])
) v(o, p, t)
  cross join unnest(array['ca','gl','eu','en','de','it','nl','fr']) with ordinality l(idioma, n);
