-- 0033 · Bajas temporales (lesión, viaje…) e historial de asistencia a las convocatorias.
create table if not exists ausencias (
  id          uuid primary key default gen_random_uuid(),
  liga_id     uuid not null references ligas on delete cascade,
  miembro_id  uuid not null references miembros on delete cascade,
  desde       date not null,
  hasta       date,                      -- null = sin fecha de vuelta
  motivo      text not null default 'otro' check (motivo in ('lesion', 'viaje', 'trabajo', 'personal', 'otro')),
  nota        text check (length(nota) <= 200),
  creada_por  uuid,
  creada_en   timestamptz not null default now(),
  check (hasta is null or hasta >= desde)
);
create index if not exists ausencias_miembro on ausencias (miembro_id, desde);
alter table ausencias enable row level security;
drop policy if exists ausencias_leer on ausencias;
create policy ausencias_leer on ausencias for select to authenticated using (es_miembro(liga_id));
revoke insert, update, delete on ausencias from anon, authenticated;
grant select on ausencias to authenticated;

create or replace function esta_de_baja(p_miembro uuid, p_cuando timestamptz) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ausencias a where a.miembro_id = p_miembro
                   and (p_cuando at time zone 'Europe/Madrid')::date >= a.desde
                   and (a.hasta is null or (p_cuando at time zone 'Europe/Madrid')::date <= a.hasta))
$$;

-- Registrar una baja: uno mismo o el admin para cualquiera. Las bajas que se solapen se funden en una.
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
  -- fundir con las que se solapan o se tocan
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
  -- quien se da de baja deja libre su plaza en las convocatorias afectadas que aún no se han jugado
  update convocatorias c set estado = 'baja'
    from partidos pa where pa.id = c.partido_id and c.miembro_id = p_miembro
     and pa.estado in ('abierto', 'completo') and pa.fecha_hora > now() and c.estado in ('confirmado', 'espera', 'duda')
     and esta_de_baja(p_miembro, pa.fecha_hora);
  return v_id;
end $$;

-- «He vuelto»: termina la baja (ayer como último día, o la borra si aún no había empezado)
create or replace function terminar_ausencia(p_ausencia uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a ausencias; v_perfil uuid;
begin
  select * into a from ausencias where id = p_ausencia;
  if not found then raise exception 'Baja no encontrada'; end if;
  select perfil_id into v_perfil from miembros where id = a.miembro_id;
  if v_perfil is distinct from auth.uid() and not es_admin(a.liga_id) then raise exception 'No puedes cambiar esta baja'; end if;
  if a.desde >= (now() at time zone 'Europe/Madrid')::date then
    delete from ausencias where id = p_ausencia;
  else
    update ausencias set hasta = (now() at time zone 'Europe/Madrid')::date - 1 where id = p_ausencia;
  end if;
end $$;

create or replace function borrar_ausencia(p_ausencia uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a ausencias; v_perfil uuid;
begin
  select * into a from ausencias where id = p_ausencia;
  if not found then return; end if;
  select perfil_id into v_perfil from miembros where id = a.miembro_id;
  if v_perfil is distinct from auth.uid() and not es_admin(a.liga_id) then raise exception 'No puedes borrar esta baja'; end if;
  delete from ausencias where id = p_ausencia;
end $$;

-- Historial de asistencia: los últimos N partidos jugados y, por jugador, qué hizo en cada uno.
--   J = jugó · D = dijo que no / se borró · N = no se apuntó · B = de baja · null = aún no era de la liga
create or replace function historial_asistencia(p_liga uuid, p_partidos int default 12) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not es_miembro(p_liga) then raise exception 'No perteneces a esta liga'; end if;
  return (
    with pa as (
      select id, fecha_hora from partidos
       where liga_id = p_liga and estado in ('jugado', 'post_partido', 'en_revision', 'cerrado') and fecha_hora < now()
       order by fecha_hora desc limit greatest(1, least(coalesce(p_partidos, 12), 52))),
    mi as (select id, unido_en from miembros where liga_id = p_liga and estado = 'activo'),
    celdas as (
      select mi.id miembro_id, pa.id partido_id, pa.fecha_hora,
             case when c.estado = 'confirmado' then 'J'
                  when esta_de_baja(mi.id, pa.fecha_hora) then 'B'
                  when pa.fecha_hora < mi.unido_en - interval '1 day' then null
                  when c.estado = 'baja' then 'D'
                  else 'N' end as e
        from mi cross join pa
        left join convocatorias c on c.partido_id = pa.id and c.miembro_id = mi.id)
    select jsonb_build_object(
      'partidos', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'fecha', fecha_hora) order by fecha_hora desc) from pa), '[]'),
      'miembros', coalesce((select jsonb_agg(jsonb_build_object(
          'miembro_id', x.miembro_id,
          'estados', x.estados,
          'jugados', x.j,
          'pct', case when x.cuentan > 0 then round(100.0 * x.j / x.cuentan) end,
          'baja', (select jsonb_build_object('id', a.id, 'desde', a.desde, 'hasta', a.hasta, 'motivo', a.motivo, 'nota', a.nota)
                     from ausencias a where a.miembro_id = x.miembro_id
                      and coalesce(a.hasta, 'infinity'::date) >= (now() at time zone 'Europe/Madrid')::date
                    order by a.desde limit 1))
          order by x.j desc, x.cuentan)
        from (select miembro_id, jsonb_agg(e order by fecha_hora desc) estados,
                     count(*) filter (where e = 'J') j,
                     count(*) filter (where e in ('J', 'D', 'N')) cuentan
                from celdas group by miembro_id) x), '[]'))
  );
end $$;

-- Bajas de un jugador (pasadas, actual y futuras)
create or replace function ausencias_miembro(p_miembro uuid) returns setof ausencias
language sql stable security definer set search_path = public as $$
  select a.* from ausencias a where a.miembro_id = p_miembro and es_miembro(a.liga_id) order by a.desde desc
$$;

create or replace function plazas_reservadas_fijos(p_partido uuid) returns int
language sql stable security definer set search_path = public as $$
  select case when l.modo_convocatoria = 'clasica'
                or p.fecha_hora - make_interval(hours => l.horas_reserva_fijos) <= now() then 0
              else (select count(*) from miembros m
                     where m.liga_id = p.liga_id and m.rango = 'fijo' and m.estado in ('activo', 'pendiente_registro')
                       and not esta_de_baja(m.id, p.fecha_hora)
                       and not exists (select 1 from convocatorias c where c.partido_id = p.id and c.miembro_id = m.id
                                                                     and c.estado in ('confirmado', 'baja', 'espera')))::int end
    from partidos p join ligas l on l.id = p.liga_id where p.id = p_partido
$$;

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
  return k;
end $$;

create or replace function estadisticas_jugador(p_miembro uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_liga uuid; v_res jsonb; v_forma text; v_racha_inv int := 0; v_max_inv int := 0; v_racha_v int := 0;
        v_max_v int := 0; r record; v_jugados int; v_total int;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  if v_liga is null or not es_miembro(v_liga) then raise exception 'No perteneces a esta liga'; end if;

  -- forma (últimos 5, el más reciente primero) y rachas
  select string_agg(case when victorias > 0 and derrotas = 0 then 'V' when derrotas > 0 and victorias = 0 then 'D' else 'E' end,
                    '' order by fecha_hora desc)
    into v_forma
    from (select pf.victorias, pf.derrotas, p.fecha_hora from puntos_fantasy pf join partidos p on p.id = pf.partido_id
           where pf.miembro_id = p_miembro and p.estado = 'cerrado' order by p.fecha_hora desc limit 5) t;
  for r in select pf.victorias, pf.derrotas from puntos_fantasy pf join partidos p on p.id = pf.partido_id
            where pf.miembro_id = p_miembro and p.estado = 'cerrado' order by p.fecha_hora loop
    if r.derrotas = 0 then v_racha_inv := v_racha_inv + 1; else v_racha_inv := 0; end if;
    if r.victorias > 0 and r.derrotas = 0 then v_racha_v := v_racha_v + 1; else v_racha_v := 0; end if;
    v_max_inv := greatest(v_max_inv, v_racha_inv); v_max_v := greatest(v_max_v, v_racha_v);
  end loop;

  select count(*) into v_jugados from puntos_fantasy pf join partidos p on p.id = pf.partido_id
   where pf.miembro_id = p_miembro and p.estado = 'cerrado';
  -- los partidos en los que estaba de baja (lesión, viaje…) no cuentan para el % de asistencia
  select count(*) into v_total from partidos pa where liga_id = v_liga and estado = 'cerrado'
     and fecha_hora >= (select coalesce(unido_en, '-infinity') from miembros where id = p_miembro)
     and (not esta_de_baja(p_miembro, pa.fecha_hora)
          or exists (select 1 from puntos_fantasy pf where pf.partido_id = pa.id and pf.miembro_id = p_miembro));

  with mis as (
    select c.partido_id, c.equipo, pf.victorias, pf.derrotas from convocatorias c
      join puntos_fantasy pf on pf.partido_id = c.partido_id and pf.miembro_id = c.miembro_id
      join partidos p on p.id = c.partido_id
     where c.miembro_id = p_miembro and p.estado = 'cerrado' and c.equipo is not null),
  companeros as (
    select c.miembro_id, count(*) n, sum(m.victorias) v,
           round(100.0 * sum(m.victorias) / nullif(count(*), 0)) pct
      from mis m join convocatorias c on c.partido_id = m.partido_id and c.equipo = m.equipo and c.miembro_id <> p_miembro
     group by c.miembro_id),
  rivales as (
    select c.miembro_id, count(*) n, sum(m.derrotas) d,
           round(100.0 * sum(m.derrotas) / nullif(count(*), 0)) pct
      from mis m join convocatorias c on c.partido_id = m.partido_id and c.equipo is not null
                                      and c.equipo <> m.equipo and c.estado = 'confirmado'
     group by c.miembro_id)
  select jsonb_build_object(
    'forma', coalesce(v_forma, ''),
    'racha_invicto_max', v_max_inv, 'racha_victorias_max', v_max_v,
    'racha_invicto_actual', v_racha_inv,
    'asistencia_pct', case when v_total > 0 then round(100.0 * v_jugados / v_total) end,
    'porterias_cero', (select coalesce(sum(aj.porterias_cero), 0) from acta_jugador aj join partidos p on p.id = aj.partido_id
                        where aj.miembro_id = p_miembro and p.estado = 'cerrado'),
    'goles_encajados_partido', (select round(avg(aj.goles_encajados), 2) from acta_jugador aj join partidos p on p.id = aj.partido_id
                                 where aj.miembro_id = p_miembro and p.estado = 'cerrado'),
    'votos_mvp', (select coalesce(sum((pf.desglose ->> 'votos_mvp')::int), 0) from puntos_fantasy pf where pf.miembro_id = p_miembro),
    'destacados', (select coalesce(jsonb_object_agg(aspecto, veces), '{}') from v_destacados where miembro_id = p_miembro),
    'mejor_companero', (select jsonb_build_object('miembro_id', miembro_id, 'partidos', n, 'pct_victorias', pct)
                          from companeros where n >= 2 order by pct desc, n desc limit 1),
    'mas_juega_con', (select jsonb_build_object('miembro_id', miembro_id, 'partidos', n, 'pct_victorias', pct)
                        from companeros order by n desc, pct desc limit 1),
    'bestia_negra', (select jsonb_build_object('miembro_id', miembro_id, 'partidos', n, 'pct_derrotas', pct)
                       from rivales where n >= 2 and d > 0 order by pct desc, n desc limit 1))
    into v_res;
  return v_res;
end $$;


revoke execute on function esta_de_baja(uuid, timestamptz), registrar_ausencia(uuid, date, date, text, text),
  terminar_ausencia(uuid), borrar_ausencia(uuid), historial_asistencia(uuid, int), ausencias_miembro(uuid) from public, anon;
grant execute on function registrar_ausencia(uuid, date, date, text, text), terminar_ausencia(uuid), borrar_ausencia(uuid),
  historial_asistencia(uuid, int), ausencias_miembro(uuid) to authenticated;
