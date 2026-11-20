-- 0026 · Convocatoria con apertura y Fantasy desactivable
--  · ligas.modo_convocatoria: 'apertura' (nuevo, por defecto) | 'clasica' (fijos inscritos solos al crear el partido).
--    En 'apertura' la convocatoria nace VACÍA y se abre X horas después de acabar el partido anterior
--    (duracion_partido_min + horas_apertura_convocatoria). Todos, fijos incluidos, pulsan «Voy».
--    Los fijos tienen plaza reservada hasta horas_reserva_fijos antes del partido: mientras tanto reservas e
--    invitados que pulsan «Voy» van a la lista de espera si no queda plaza sin contar las reservadas.
--  · ligas.fantasy_activo: la liga puede usar solo convocatorias (sin Fantasy).

alter table ligas
  add column modo_convocatoria text not null default 'apertura'
    constraint ligas_modo_convocatoria_ck check (modo_convocatoria in ('apertura', 'clasica')),
  add column duracion_partido_min smallint not null default 60
    constraint ligas_duracion_partido_ck check (duracion_partido_min between 20 and 240),
  add column horas_apertura_convocatoria smallint not null default 2
    constraint ligas_horas_apertura_ck check (horas_apertura_convocatoria between 0 and 168),
  add column horas_reserva_fijos smallint not null default 24
    constraint ligas_horas_reserva_ck check (horas_reserva_fijos between 0 and 168),
  add column fantasy_activo boolean not null default true;

-- Las ligas que ya existían siguen como hasta ahora salvo que el admin cambie el modo
-- (en producción la liga de David pasa a 'apertura', ver plataforma/0106).
update ligas set modo_convocatoria = 'clasica';

-- Cuándo se abre la convocatoria (null = ya abierta / no hay partido anterior / modo clásico)
create or replace function convocatoria_abre_en(p_partido uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select case when l.modo_convocatoria = 'clasica' then null else
         (select max(a.fecha_hora) from partidos a
           where a.liga_id = p.liga_id and a.fecha_hora < p.fecha_hora and a.estado <> 'cancelado')
         + make_interval(mins => l.duracion_partido_min) + make_interval(hours => l.horas_apertura_convocatoria) end
    from partidos p join ligas l on l.id = p.liga_id where p.id = p_partido
$$;

-- Plazas guardadas para fijos que aún no han contestado (0 en modo clásico o pasado el plazo)
create or replace function plazas_reservadas_fijos(p_partido uuid) returns int
language sql stable security definer set search_path = public as $$
  select case when l.modo_convocatoria = 'clasica'
                or p.fecha_hora - make_interval(hours => l.horas_reserva_fijos) <= now() then 0
              else (select count(*) from miembros m
                     where m.liga_id = p.liga_id and m.rango = 'fijo' and m.estado in ('activo', 'pendiente_registro')
                       and not exists (select 1 from convocatorias c where c.partido_id = p.id and c.miembro_id = m.id
                                                                     and c.estado in ('confirmado', 'baja', 'espera')))::int end
    from partidos p join ligas l on l.id = p.liga_id where p.id = p_partido
$$;

create or replace function gestionar_cupo() returns trigger
language plpgsql security definer set search_path = public as $$
declare p partidos; v_conf int; v_admin boolean; v_abre timestamptz; v_rango rango_jugador; v_res int;
begin
  select * into p from partidos where id = new.partido_id for update;   -- serializa altas simultáneas
  v_admin := auth.uid() is null or es_admin(p.liga_id);                 -- null = service_role / tareas internas

  if not v_admin then
    if p.estado not in ('abierto', 'completo', 'equipos_hechos') then
      raise exception 'La convocatoria de este partido ya está cerrada';
    end if;
    v_abre := convocatoria_abre_en(p.id);
    if v_abre is not null and v_abre > now() then
      raise exception 'La convocatoria se abre el %', fecha_corta(v_abre);
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
    v_rango := coalesce(new.rango, (select rango from miembros where id = new.miembro_id));
    -- un fijo solo compite con los confirmados; los demás, además, respetan las plazas guardadas a fijos
    v_res := case when v_rango = 'fijo' then 0 else plazas_reservadas_fijos(p.id) end;
    if v_conf + v_res >= p.plazas then new.estado := 'espera'; end if;
  end if;

  if new.estado <> 'confirmado' then new.equipo := null; end if;
  return new;
end $$;

-- Mete desde la lista de espera a todos los que quepan (respetando la reserva de los fijos). Devuelve cuántos.
create or replace function rellenar_plazas(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; c record; v_conf int; k int := 0;
begin
  select * into p from partidos where id = p_partido;
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') then return 0; end if;
  loop
    select count(*) into v_conf from convocatorias where partido_id = p_partido and estado = 'confirmado';
    exit when v_conf >= p.plazas;
    select cv.miembro_id, m.rango into c from convocatorias cv join miembros m on m.id = cv.miembro_id
     where cv.partido_id = p_partido and cv.estado = 'espera'
     order by prioridad_espera(p.liga_id, m.rango), cv.inscrito_en limit 1;
    exit when not found;
    exit when c.rango <> 'fijo' and v_conf + plazas_reservadas_fijos(p_partido) >= p.plazas;
    update convocatorias set estado = 'confirmado' where partido_id = p_partido and miembro_id = c.miembro_id;
    exit when not found;
    k := k + 1;
    exit when k > 50;
  end loop;
  return k;
end $$;

create or replace function promover_espera() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_partido uuid := coalesce(new.partido_id, old.partido_id); p partidos; v_conf int;
begin
  select * into p from partidos where id = v_partido;
  if p.id is null then return null; end if;   -- partido borrado en cascada

  -- Alguien deja plaza libre, o un fijo contesta (su plaza reservada deja de estarlo): entran los que quepan
  if pg_trigger_depth() <= 1 and p.estado in ('abierto', 'completo', 'equipos_hechos')
     and (tg_op = 'DELETE' or tg_op = 'INSERT' or new.estado is distinct from old.estado) then
    perform rellenar_plazas(v_partido);
  end if;

  if p.estado in ('abierto', 'completo') then
    select count(*) into v_conf from convocatorias where partido_id = v_partido and estado = 'confirmado';
    update partidos set estado = case when v_conf >= plazas then 'completo'::estado_partido else 'abierto' end
     where id = v_partido and estado in ('abierto', 'completo');
  end if;
  return null;
end $$;

-- En modo «apertura» nadie entra solo: los fijos también pulsan «Voy»
create or replace function inscribir_fijos(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  insert into convocatorias (partido_id, miembro_id, estado)
  select p.id, m.id, 'confirmado'
    from partidos p join ligas l on l.id = p.liga_id join miembros m on m.liga_id = p.liga_id
   where p.id = p_partido and p.estado in ('abierto', 'completo') and l.modo_convocatoria = 'clasica'
     and m.rango = 'fijo' and m.estado in ('activo', 'pendiente_registro')
   order by m.unido_en, m.id
  on conflict (partido_id, miembro_id) do nothing;
  get diagnostics k = row_count;
  return k;
end $$;

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
                         where liga_id = p.liga_id and estado = 'activo' and rango <> 'fijo'),
                       p.liga_id, 'apertura', 'Convocatoria abierta ⚽',
                       '¿Juegas el ' || fecha_corta(p.fecha_hora) || '? Pulsa «Voy» para apuntarte', '/partidos/' || p.id);
    k := k + notificar((select coalesce(array_agg(perfil_id), '{}') from miembros
                         where liga_id = p.liga_id and estado = 'activo' and rango = 'fijo'),
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
  return k;
end $$;

revoke execute on function convocatoria_abre_en(uuid), plazas_reservadas_fijos(uuid), rellenar_plazas(uuid)
  from public, anon;
revoke execute on function rellenar_plazas(uuid) from authenticated;
grant execute on function convocatoria_abre_en(uuid), plazas_reservadas_fijos(uuid) to authenticated;
