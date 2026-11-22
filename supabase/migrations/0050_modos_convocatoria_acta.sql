-- 0050 · Cinco modos de convocatoria y quién rellena el acta del post-partido
--
-- Convocatoria (ligas.modo_convocatoria):
--  · 'apertura' (como hasta ahora): fijos en la lista desde el principio; el resto se apunta cuando se abre
--    (X h después de acabar el partido anterior). En la espera, los fijos primero.
--  · 'clasica': fijos en la lista desde el principio; el resto puede apuntarse desde que se crea el partido.
--  · 'libre' (por orden de llegada): nadie está apuntado de oficio; todos se apuntan y la espera es por orden puro.
--  · 'turnos': primero pueden apuntarse los fijos; horas_turno después, las reservas; otras tantas después,
--    los invitados. Nadie está apuntado de oficio.
--  · 'minimo': como «libre», pero horas_decision antes del partido se comprueba si hay minimo_jugadores
--    confirmados; si no, el partido se cancela solo y se avisa a todos.
--
-- Acta del post-partido (resultado, goles y asistencias) — ligas.quien_rellena:
--  · 'jugadores' (como hasta ahora): todos los que jugaron; la app cruza los partes.
--  · 'arbitro': solo el árbitro (el del partido, o el de la liga; si no hay, el administrador).
--  · 'capitanes': solo los capitanes del partido (si no hay capitanes, todos los que jugaron).
--  Las notas y el MVP los siguen poniendo todos los que jugaron. El administrador siempre puede rellenar el acta.

-- ───────────── Columnas
alter table ligas drop constraint if exists ligas_modo_convocatoria_ck;
alter table ligas add constraint ligas_modo_convocatoria_ck
  check (modo_convocatoria in ('apertura', 'clasica', 'libre', 'turnos', 'minimo'));
alter table ligas
  add column if not exists horas_turno smallint not null default 24
    constraint ligas_horas_turno_ck check (horas_turno between 1 and 168),
  add column if not exists minimo_jugadores smallint
    constraint ligas_minimo_jugadores_ck check (minimo_jugadores between 2 and 60),
  add column if not exists horas_decision smallint not null default 24
    constraint ligas_horas_decision_ck check (horas_decision between 1 and 168),
  add column if not exists quien_rellena text not null default 'jugadores'
    constraint ligas_quien_rellena_ck check (quien_rellena in ('jugadores', 'arbitro', 'capitanes')),
  add column if not exists arbitro_id uuid references miembros on delete set null;
alter table partidos add column if not exists arbitro_id uuid references miembros on delete set null;

-- ───────────── Apertura de la convocatoria

-- Momento base: X h después de acabar el partido anterior (null si no hay partido anterior)
create or replace function _base_convocatoria(p_partido uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select (select max(a.fecha_hora) from partidos a
           where a.liga_id = p.liga_id and a.fecha_hora < p.fecha_hora and a.estado <> 'cancelado')
         + make_interval(mins => l.duracion_partido_min) + make_interval(hours => l.horas_apertura_convocatoria)
    from partidos p join ligas l on l.id = p.liga_id where p.id = p_partido
$$;

-- Cuándo se abre la convocatoria para el primer grupo (null = ya abierta / sin espera)
create or replace function convocatoria_abre_en(p_partido uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select case when l.modo_convocatoria in ('apertura', 'turnos') then _base_convocatoria(p.id) end
    from partidos p join ligas l on l.id = p.liga_id where p.id = p_partido
$$;

-- Cuándo puede apuntarse ESTE miembro (null = ya puede)
create or replace function convocatoria_abre_para(p_partido uuid, p_miembro uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select case l.modo_convocatoria
           when 'apertura' then case when m.rango = 'fijo' then null else _base_convocatoria(p.id) end
           when 'turnos' then _base_convocatoria(p.id)
                              + make_interval(hours => l.horas_turno * case m.rango when 'fijo' then 0
                                                                                   when 'reserva' then 1 else 2 end)
         end
    from partidos p join ligas l on l.id = p.liga_id join miembros m on m.id = p_miembro
   where p.id = p_partido
$$;

-- Fijos «pendientes» de oficio solo en los modos que los apuntan solos
create or replace function inscribir_fijos(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  insert into convocatorias (partido_id, miembro_id, estado)
  select p.id, m.id, 'pendiente'
    from partidos p join ligas l on l.id = p.liga_id join miembros m on m.liga_id = p.liga_id
   where p.id = p_partido and p.estado in ('abierto', 'completo') and p.fecha_hora > now()
     and l.modo_convocatoria in ('apertura', 'clasica')
     and m.rango = 'fijo' and m.estado in ('activo', 'pendiente_registro')
     and not esta_de_baja(m.id, p.fecha_hora)
   order by m.unido_en, m.id
  on conflict (partido_id, miembro_id) do nothing;
  get diagnostics k = row_count;
  return k;
end $$;

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
    if new.estado <> 'baja' then
      v_abre := convocatoria_abre_para(p.id, new.miembro_id);
      if v_abre is not null and v_abre > now() then
        raise exception 'Podrás apuntarte a partir del %', fecha_corta(v_abre);
      end if;
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

  if v_ocupa and not v_ocupa_antes and plazas_ocupadas(p.id, new.miembro_id) >= p.plazas then
    new.estado := 'espera';
  end if;

  if new.estado not in ('confirmado', 'pendiente', 'duda') then new.equipo := null; new.capitan := false; end if;
  return new;
end $$;

-- Suplentes: los fijos primero salvo en «libre» y «mínimo» (orden de llegada puro)
create or replace function rellenar_plazas(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; v_fijos_primero boolean; c record; k int := 0;
begin
  select * into p from partidos where id = p_partido;
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') then return 0; end if;
  select modo_convocatoria not in ('libre', 'minimo') into v_fijos_primero from ligas where id = p.liga_id;
  loop
    exit when plazas_ocupadas(p_partido) >= p.plazas;
    select cv.miembro_id into c from convocatorias cv join miembros m on m.id = cv.miembro_id
     where cv.partido_id = p_partido and cv.estado = 'espera'
     order by (v_fijos_primero and m.rango = 'fijo') desc, cv.inscrito_en, cv.miembro_id limit 1;
    exit when not found;
    update convocatorias set estado = 'confirmado' where partido_id = p_partido and miembro_id = c.miembro_id;
    k := k + 1;
    exit when k > 50;
  end loop;
  return k;
end $$;

-- Al cambiar de modo: en los próximos partidos se apuntan o se quitan los fijos «pendientes»
create or replace function tras_cambiar_modo_convocatoria() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.modo_convocatoria in ('apertura', 'clasica') then
    for r in select id from partidos where liga_id = new.id and estado in ('abierto', 'completo') and fecha_hora > now() loop
      perform inscribir_fijos(r.id);
    end loop;
  else
    -- los que no habían contestado dejan de estar apuntados de oficio
    delete from convocatorias c using partidos p
     where p.id = c.partido_id and p.liga_id = new.id and p.estado in ('abierto', 'completo', 'equipos_hechos')
       and p.fecha_hora > now() and c.estado = 'pendiente';
    for r in select id from partidos where liga_id = new.id and estado in ('abierto', 'completo') and fecha_hora > now() loop
      perform rellenar_plazas(r.id);
      update partidos set estado = case when plazas_ocupadas(r.id) >= plazas then 'completo'::estado_partido
                                        else 'abierto' end
       where id = r.id and estado in ('abierto', 'completo');
    end loop;
  end if;
  return null;
end $$;
drop trigger if exists t_cambiar_modo_convocatoria on ligas;
create trigger t_cambiar_modo_convocatoria after update of modo_convocatoria on ligas
  for each row when (new.modo_convocatoria is distinct from old.modo_convocatoria)
  execute function tras_cambiar_modo_convocatoria();

-- ───────────── Acta del post-partido: quién la rellena

-- Miembros que rellenan el acta de este partido
create or replace function rellenadores_acta(p_partido uuid) returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare p partidos; l ligas; v uuid[];
begin
  select * into p from partidos where id = p_partido;
  select * into l from ligas where id = p.liga_id;
  if l.quien_rellena = 'arbitro' then
    v := array_remove(array[coalesce(p.arbitro_id, l.arbitro_id)], null);
    if coalesce(array_length(v, 1), 0) = 0 then
      select coalesce(array_agg(id), '{}') into v from miembros where liga_id = l.id and rol = 'admin' and estado = 'activo';
    end if;
    return v;
  end if;
  if l.quien_rellena = 'capitanes' then
    select coalesce(array_agg(miembro_id), '{}') into v from convocatorias
     where partido_id = p_partido and capitan and estado = 'confirmado' and equipo is not null;
    if coalesce(array_length(v, 1), 0) > 0 then return v; end if;
  end if;
  select coalesce(array_agg(miembro_id), '{}') into v from convocatorias
   where partido_id = p_partido and estado = 'confirmado' and equipo is not null;
  return v;
end $$;

create or replace function puede_rellenar_acta(p_partido uuid, p_miembro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_miembro = any(rellenadores_acta(p_partido))
      or exists (select 1 from miembros m join partidos p on p.liga_id = m.liga_id
                  where p.id = p_partido and m.id = p_miembro and m.rol = 'admin' and m.estado = 'activo')
$$;

-- Para la app: ¿puedo rellenar el acta de este partido?
create or replace function puedo_rellenar_acta(p_partido uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(puede_rellenar_acta(p_partido, mi_miembro(p.liga_id)), false) from partidos p where p.id = p_partido
$$;

-- Guardia en las tablas del acta (vale para enviar_parte y cualquier otra vía)
create or replace function exigir_relleno_acta() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_modo text;
begin
  if auth.uid() is null then return new; end if;   -- servidor / tareas internas
  if not puede_rellenar_acta(new.partido_id, new.reportero_id) then
    select l.quien_rellena into v_modo from partidos p join ligas l on l.id = p.liga_id where p.id = new.partido_id;
    raise exception '%', case v_modo when 'arbitro' then 'En esta liga el acta la rellena el árbitro. Tú solo pones las notas.'
                                     when 'capitanes' then 'En esta liga el acta la rellenan los capitanes. Tú solo pones las notas.'
                                     else 'Solo los que jugaron rellenan el acta' end;
  end if;
  return new;
end $$;
drop trigger if exists t_exigir_relleno_acta on reportes_encuentro;
create trigger t_exigir_relleno_acta before insert or update on reportes_encuentro
  for each row execute function exigir_relleno_acta();
drop trigger if exists t_exigir_relleno_acta on reportes_jugador;
create trigger t_exigir_relleno_acta before insert or update on reportes_jugador
  for each row execute function exigir_relleno_acta();

-- Peso de cada parte al cruzarlos: el árbitro manda; el administrador pesa 1,5
create or replace function peso_parte(p_partido uuid, p_reportero uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case
           when l.quien_rellena = 'arbitro' and p_reportero = coalesce(p.arbitro_id, l.arbitro_id) then 3
           when exists (select 1 from miembros m where m.id = p_reportero and m.liga_id = l.id and m.rol = 'admin') then 1.5
           else 1 end
    from partidos p join ligas l on l.id = p.liga_id where p.id = p_partido
$$;

-- ───────────── Avisos: apertura por modo, turnos, mínimo y acta

create or replace function notif_partido() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ruta text := '/partidos/' || new.id; v_mvp text; v_afectados uuid[]; v_modo text; v_acta uuid[];
        v_motivo text;
begin
  select perfiles_de_miembros(array_agg(miembro_id)) into v_afectados from convocatorias
   where partido_id = new.id and estado in ('confirmado', 'duda', 'espera');

  if new.estado is distinct from old.estado then
    if new.estado = 'post_partido' then
      select quien_rellena into v_modo from ligas where id = new.liga_id;
      if v_modo = 'jugadores' then
        perform notificar((select perfiles_de_miembros(array_agg(miembro_id)) from convocatorias
                            where partido_id = new.id and estado = 'confirmado' and equipo is not null),
                          new.liga_id, 'post_partido', 'Post-partido abierto ⚽',
                          'Pon el resultado y tus notas (1 minuto)' ||
                          coalesce(' · hasta ' || fecha_corta(new.votacion_cierra), ''), v_ruta);
      else
        v_acta := rellenadores_acta(new.id);
        perform notificar(perfiles_de_miembros(v_acta), new.liga_id, 'post_partido', 'Te toca el acta 📝',
                          'Pon el resultado, los goles y las asistencias' ||
                          coalesce(' · hasta ' || fecha_corta(new.votacion_cierra), ''), v_ruta);
        perform notificar((select perfiles_de_miembros(array_agg(miembro_id)) from convocatorias
                            where partido_id = new.id and estado = 'confirmado' and equipo is not null
                              and not (miembro_id = any(v_acta))),
                          new.liga_id, 'post_partido', 'Post-partido abierto ⚽',
                          'Pon tus notas (1 minuto)' ||
                          coalesce(' · hasta ' || fecha_corta(new.votacion_cierra), ''), v_ruta);
      end if;
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
      v_motivo := nullif(current_setting('app.motivo_cancelacion', true), '');
      perform notificar(v_afectados, new.liga_id, 'cancelado', 'Partido cancelado',
                        coalesce(v_motivo, 'Se cancela el partido del ' || fecha_corta(new.fecha_hora)), v_ruta);
    end if;
  elsif new.fecha_hora is distinct from old.fecha_hora
        and new.estado in ('abierto', 'completo', 'equipos_hechos') and new.fecha_hora < now() + interval '14 days' then
    perform notificar(v_afectados, new.liga_id, 'cambio_hora', 'Cambio de hora',
                      'El partido pasa a ' || fecha_corta(new.fecha_hora), v_ruta);
  end if;
  return null;
end $$;

create or replace function enviar_recordatorios() returns int
language plpgsql security definer set search_path = public as $$
declare p record; k int := 0; v_libres int; v_perfiles uuid[]; v_rango text; v_n int; v_min int;
begin
  -- 0a) Apertura (modo «apertura»): aviso a todos; a los fijos, que ya están en la lista
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

  -- 0b) Orden de llegada y mínimo: un aviso a todos cuando se abre (tras el partido anterior)
  for p in select pa.* from partidos pa join ligas l on l.id = pa.liga_id
            where l.modo_convocatoria in ('libre', 'minimo') and pa.estado in ('abierto', 'completo') and pa.fecha_hora > now()
              and coalesce(_base_convocatoria(pa.id), pa.creado_en) between now() - interval '1 day' and now()
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'apertura') loop
    insert into recordatorios_enviados values (p.id, 'apertura');
    k := k + notificar((select coalesce(array_agg(perfil_id), '{}') from miembros
                         where liga_id = p.liga_id and estado = 'activo' and not esta_de_baja(id, p.fecha_hora)),
                       p.liga_id, 'recordatorio_convocatoria', 'Convocatoria abierta ⚽',
                       '¿Juegas el ' || fecha_corta(p.fecha_hora) || '? Apúntate: entra quien antes llegue', '/partidos/' || p.id);
  end loop;

  -- 0c) Turnos: aviso a cada grupo cuando le toca (fijos, reservas, invitados)
  for p in select pa.*, l.horas_turno as ht from partidos pa join ligas l on l.id = pa.liga_id
            where l.modo_convocatoria = 'turnos' and pa.estado in ('abierto', 'completo') and pa.fecha_hora > now() loop
    foreach v_rango in array array['fijo', 'reserva', 'invitado'] loop
      continue when exists (select 1 from recordatorios_enviados r where r.partido_id = p.id and r.tipo = 'turno_' || v_rango);
      continue when coalesce(_base_convocatoria(p.id), p.creado_en)
                    + make_interval(hours => p.ht * case v_rango when 'fijo' then 0 when 'reserva' then 1 else 2 end)
                    not between now() - interval '1 day' and now();
      insert into recordatorios_enviados values (p.id, 'turno_' || v_rango);
      k := k + notificar((select coalesce(array_agg(perfil_id), '{}') from miembros
                           where liga_id = p.liga_id and estado = 'activo' and rango::text = v_rango
                             and not esta_de_baja(id, p.fecha_hora)),
                         p.liga_id, 'recordatorio_convocatoria', 'Te toca apuntarte ⚽',
                         '¿Juegas el ' || fecha_corta(p.fecha_hora) || '? Ya puedes apuntarte', '/partidos/' || p.id);
    end loop;
  end loop;

  -- 0d) Mínimo: llegado el plazo, si no hay bastantes, se cancela; si los hay, se confirma
  for p in select pa.*, coalesce(l.minimo_jugadores, pa.plazas) as minimo from partidos pa join ligas l on l.id = pa.liga_id
            where l.modo_convocatoria = 'minimo' and pa.estado in ('abierto', 'completo') and pa.fecha_hora > now()
              and pa.fecha_hora - make_interval(hours => l.horas_decision) <= now()
              and not exists (select 1 from recordatorios_enviados r where r.partido_id = pa.id and r.tipo = 'minimo') loop
    insert into recordatorios_enviados values (p.id, 'minimo');
    select count(*) into v_n from convocatorias where partido_id = p.id and estado in ('confirmado', 'pendiente');
    v_min := p.minimo;
    if v_n < v_min then
      perform set_config('app.motivo_cancelacion',
                         'No se llegó al mínimo (' || v_n || ' de ' || v_min || '): se cancela el partido del '
                         || fecha_corta(p.fecha_hora), true);
      update partidos set estado = 'cancelado' where id = p.id;
      perform set_config('app.motivo_cancelacion', '', true);
    else
      k := k + notificar((select perfiles_de_miembros(array_agg(miembro_id)) from convocatorias
                           where partido_id = p.id and estado in ('confirmado', 'pendiente', 'duda')),
                         p.liga_id, 'recordatorio_convocatoria', 'Hay partido ✅',
                         'Sois ' || v_n || ' el ' || fecha_corta(p.fecha_hora), '/partidos/' || p.id);
    end if;
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
         and coalesce(convocatoria_abre_para(p.id, m.id), now()) <= now()
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

  -- 5) Fin de una baja
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

-- ───────────── Mi agenda (Inicio): apertura personal y orden de espera según el modo
create or replace function mi_agenda(p_dias int default 30)
returns table (partido_id uuid, liga_id uuid, liga text, fecha timestamptz, hora_confirmada boolean, campo text,
               plazas int, ocupadas int, estado_partido text, miembro_id uuid, rango text, mi_estado text,
               puesto int, abre_en timestamptz, soy_admin boolean)
language sql stable security definer set search_path = public as $$
  select p.id, l.id, l.nombre, p.fecha_hora, p.hora_confirmada, l.campo_nombre,
         p.plazas::int, plazas_ocupadas(p.id), p.estado::text, m.id, m.rango::text, c.estado::text,
         case when c.estado = 'espera' then
           (select count(*)::int + 1 from convocatorias c2 join miembros m2 on m2.id = c2.miembro_id
             where c2.partido_id = p.id and c2.estado = 'espera'
               and case when l.modo_convocatoria in ('libre', 'minimo') then c2.inscrito_en < c.inscrito_en
                        else ((m2.rango = 'fijo')::int > (m.rango = 'fijo')::int
                              or ((m2.rango = 'fijo') = (m.rango = 'fijo') and c2.inscrito_en < c.inscrito_en)) end) end,
         case when convocatoria_abre_para(p.id, m.id) > now() then convocatoria_abre_para(p.id, m.id) end,
         m.rol = 'admin'
    from miembros m
    join ligas l on l.id = m.liga_id
    join partidos p on p.liga_id = m.liga_id
    left join convocatorias c on c.partido_id = p.id and c.miembro_id = m.id
   where m.perfil_id = (select auth.uid()) and m.estado = 'activo'
     and p.estado in ('abierto', 'completo', 'equipos_hechos')
     and p.fecha_hora > now() - interval '3 hours'
     and p.fecha_hora < now() + make_interval(days => least(greatest(coalesce(p_dias, 30), 1), 120))
   order by p.fecha_hora
$$;

-- ───────────── Permisos
revoke execute on function _base_convocatoria(uuid), rellenadores_acta(uuid), puede_rellenar_acta(uuid, uuid),
  exigir_relleno_acta(), tras_cambiar_modo_convocatoria() from public, anon, authenticated;
revoke execute on function convocatoria_abre_para(uuid, uuid), puedo_rellenar_acta(uuid) from public, anon;
grant execute on function convocatoria_abre_para(uuid, uuid), puedo_rellenar_acta(uuid) to authenticated;

-- ───────────── Traducciones de los avisos nuevos (ver 0037)
delete from avisos_traducciones where orden between 61 and 71;
insert into avisos_traducciones (orden, patron, idioma, plantilla)
select v.o, v.p, l.idioma, v.t[l.n]
  from (values
(61, '^¿Juegas el (.+)\? Apúntate: entra quien antes llegue$', array['Jugues el \1? Apunta''t: entra qui arribi abans', 'Xogas o \1? Apúntate: entra quen antes chegue', '\1ean jokatzen duzu? Eman izena: lehenik iristen dena sartzen da', 'Playing on \1? Sign up: first come, first served', 'Spielst du am \1? Trag dich ein: Wer zuerst kommt, spielt', 'Giochi il \1? Iscriviti: entra chi arriva prima', 'Speel je op \1? Meld je aan: wie het eerst komt, speelt', 'Tu joues le \1 ? Inscris-toi : premier arrivé, premier servi']),
(62, '^Te toca apuntarte ⚽$', array['Et toca apuntar-te ⚽', 'Tócache apuntarte ⚽', 'Izena emateko txanda duzu ⚽', 'Your turn to sign up ⚽', 'Du bist dran mit Eintragen ⚽', 'Tocca a te iscriverti ⚽', 'Jouw beurt om je aan te melden ⚽', 'À toi de t''inscrire ⚽']),
(63, '^¿Juegas el (.+)\? Ya puedes apuntarte$', array['Jugues el \1? Ja et pots apuntar', 'Xogas o \1? Xa podes apuntarte', '\1ean jokatzen duzu? Izena eman dezakezu orain', 'Playing on \1? You can sign up now', 'Spielst du am \1? Du kannst dich jetzt eintragen', 'Giochi il \1? Ora puoi iscriverti', 'Speel je op \1? Je kunt je nu aanmelden', 'Tu joues le \1 ? Tu peux t''inscrire maintenant']),
(64, '^Hay partido ✅$', array['Hi ha partit ✅', 'Hai partido ✅', 'Partida dago ✅', 'The game is on ✅', 'Das Spiel findet statt ✅', 'Si gioca ✅', 'De wedstrijd gaat door ✅', 'Le match a lieu ✅']),
(65, '^Sois (\d+) el (.+)$', array['Sou \1 el \2', 'Sodes \1 o \2', '\1 zarete \2ean', 'You''re \1 players on \2', 'Ihr seid \1 am \2', 'Siete in \1 il \2', 'Jullie zijn met \1 op \2', 'Vous êtes \1 le \2']),
(66, '^No se llegó al mínimo \((\d+) de (\d+)\): se cancela el partido del (.+)$', array['No s''ha arribat al mínim (\1 de \2): es cancel·la el partit del \3', 'Non se chegou ao mínimo (\1 de \2): cancélase o partido do \3', 'Ez da gutxienekora iritsi (\1 / \2): \3ko partida bertan behera geratzen da', 'Not enough players (\1 of \2): the game on \3 is cancelled', 'Mindestzahl nicht erreicht (\1 von \2): Das Spiel am \3 fällt aus', 'Non si è raggiunto il minimo (\1 su \2): la partita del \3 è annullata', 'Minimum niet gehaald (\1 van \2): de wedstrijd op \3 gaat niet door', 'Minimum non atteint (\1 sur \2) : le match du \3 est annulé']),
(68, '^Pon el resultado, los goles y las asistencias · hasta (.+)$', array['Posa el resultat, els gols i les assistències · fins \1', 'Pon o resultado, os goles e as asistencias · ata \1', 'Jarri emaitza, golak eta asistentziak · \1 arte', 'Enter the score, goals and assists · until \1', 'Ergebnis, Tore und Vorlagen eintragen · bis \1', 'Inserisci risultato, gol e assist · fino a \1', 'Vul uitslag, goals en assists in · tot \1', 'Saisis le score, les buts et les passes · jusqu''au \1']),
(69, '^Pon el resultado, los goles y las asistencias$', array['Posa el resultat, els gols i les assistències', 'Pon o resultado, os goles e as asistencias', 'Jarri emaitza, golak eta asistentziak', 'Enter the score, goals and assists', 'Ergebnis, Tore und Vorlagen eintragen', 'Inserisci risultato, gol e assist', 'Vul uitslag, goals en assists in', 'Saisis le score, les buts et les passes']),
(70, '^Pon tus notas \(1 minuto\) · hasta (.+)$', array['Posa les teves notes (1 minut) · fins \1', 'Pon as túas notas (1 minuto) · ata \1', 'Jarri zure notak (minutu 1) · \1 arte', 'Enter your ratings (1 minute) · until \1', 'Noten eintragen (1 Minute) · bis \1', 'Inserisci i tuoi voti (1 minuto) · fino a \1', 'Vul je cijfers in (1 minuut) · tot \1', 'Saisis tes notes (1 minute) · jusqu''au \1']),
(71, '^Pon tus notas \(1 minuto\)$', array['Posa les teves notes (1 minut)', 'Pon as túas notas (1 minuto)', 'Jarri zure notak (minutu 1)', 'Enter your ratings (1 minute)', 'Noten eintragen (1 Minute)', 'Inserisci i tuoi voti (1 minuto)', 'Vul je cijfers in (1 minuut)', 'Saisis tes notes (1 minute)']),
(67, '^Te toca el acta 📝$', array['Et toca l''acta 📝', 'Tócache a acta 📝', 'Akta zuri dagokizu 📝', 'You''re filling in the match report 📝', 'Du füllst den Spielbericht aus 📝', 'Tocca a te il referto 📝', 'Jij vult het wedstrijdverslag in 📝', 'À toi de remplir la feuille de match 📝'])
) v(o, p, t)
  cross join unnest(array['ca','gl','eu','en','de','it','nl','fr']) with ordinality l(idioma, n);
