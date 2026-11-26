-- 0059 · Mejoras de noviembre
--  · Subasta de un jugador propio: el mánager fija el precio de salida y la duración; gana la puja más alta y el
--    vendedor cobra el importe. Si nadie puja, el jugador sigue en su equipo.
--  · Fantasy sencillo (ligas.fantasy_sencillo): alineación libre, sin bonus por rol, sin ariete ni cesiones.
--  · Porra: interruptor general (config_app.porra_global) y bloqueo en ligas con algún menor de 18 años.
--  · config_app: versión mínima de la app Android (aviso de actualización obligatoria) y enlace de descarga.
--  · exportar_mis_datos(): copia de los datos personales (RGPD, portabilidad).
--  · Nueva versión de la política de privacidad (dominio propio, Google, porra y menores): se pide aceptarla.

-- ───────────── Configuración general de la app ─────────────
create table if not exists config_app (
  id                     boolean primary key default true check (id),
  version_minima_android int not null default 0,
  url_descarga           text not null default 'https://github.com/davidvives90/futbol-fantasy/releases/latest/download/app-release.apk',
  porra_global           boolean not null default true,
  actualizado_en         timestamptz not null default now()
);
insert into config_app (id) values (true) on conflict do nothing;
alter table config_app enable row level security;
revoke all on config_app from anon, authenticated;

create or replace function config_app_publica() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('version_minima_android', version_minima_android, 'url_descarga', url_descarga,
                            'porra_global', porra_global)
    from config_app limit 1
$$;
grant execute on function config_app_publica() to anon, authenticated;

create or replace function porra_global() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select porra_global from config_app limit 1), true)
$$;

-- ───────────── Porra y menores ─────────────
create or replace function liga_con_menores(p_liga uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros m join perfiles pf on pf.id = m.perfil_id
                  where m.liga_id = p_liga and m.estado = 'activo'
                    and pf.fecha_nacimiento is not null and pf.fecha_nacimiento > current_date - interval '18 years')
$$;
grant execute on function liga_con_menores(uuid) to authenticated;

create or replace function porra_abierta(p_partido uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select l.porra_activa and porra_global() and not liga_con_menores(l.id)
         and p.estado = 'equipos_hechos' and now() < p.fecha_hora
         and (select count(distinct equipo) from convocatorias c
               where c.partido_id = p.id and c.estado = 'confirmado' and c.equipo is not null) = 2
    from partidos p join ligas l on l.id = p.liga_id where p.id = p_partido
$$;

create or replace function validar_porra_liga() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.porra_activa and not coalesce(old.porra_activa, false) then
    if not porra_global() then raise exception 'La porra no está disponible ahora mismo'; end if;
    if liga_con_menores(new.id) then
      raise exception 'En esta liga hay jugadores menores de 18 años: la porra no se puede activar';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists t_validar_porra on ligas;
create trigger t_validar_porra before update of porra_activa on ligas
  for each row execute function validar_porra_liga();

create or replace function porra_partido(p_partido uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_m uuid; v_abierta boolean;
begin
  select * into p from partidos where id = p_partido;
  if not found or not es_miembro(p.liga_id) then raise exception 'No perteneces a esta liga'; end if;
  select * into l from ligas where id = p.liga_id;
  v_m := mi_miembro(p.liga_id);
  v_abierta := porra_abierta(p_partido);
  if v_abierta then perform porra_calcular_cuotas(p_partido); end if;
  return jsonb_build_object(
    'activa', l.porra_activa, 'abierta', v_abierta, 'modo', l.porra_modo, 'tope', porra_tope(l.id),
    'motivo', case when not porra_global() then 'desactivada' when liga_con_menores(l.id) then 'menores' end,
    'max_ganancia', porra_ganancia_max(l.id),
    'apostado', coalesce((select sum(importe) from apuestas where partido_id = p_partido and miembro_id = v_m
                            and estado <> 'anulada'), 0),
    'saldo', (select saldo from fantasy_managers where liga_id = l.id and miembro_id = v_m),
    'cuotas', coalesce((select jsonb_agg(jsonb_build_object('mercado', mercado, 'seleccion', seleccion, 'cuota', cuota,
                                                            'prob', prob) order by mercado, cuota)
                          from porra_cuotas where partido_id = p_partido), '[]'),
    'mias', coalesce((select jsonb_agg(apuesta_json(a.id) order by a.creada_en desc)
                        from apuestas a where a.partido_id = p_partido and a.miembro_id = v_m), '[]'),
    'todas', case when now() >= p.fecha_hora
                  then coalesce((select jsonb_agg(apuesta_json(a.id) order by a.creada_en)
                                   from apuestas a where a.partido_id = p_partido and a.miembro_id <> v_m), '[]')
                  else '[]' end);
end $$;

-- ───────────── Subasta de un jugador propio ─────────────
alter table subastas add column if not exists vendedor_id uuid references miembros on delete cascade;

alter table transacciones_fantasy drop constraint if exists transacciones_tipo_ck;
alter table transacciones_fantasy add constraint transacciones_tipo_ck check (tipo in (
  'presupuesto_inicial', 'compra', 'venta', 'ingreso_puntos', 'ajuste', 'clausula_pagada', 'clausula_cobrada',
  'subida_clausula', 'oferta_pagada', 'oferta_cobrada', 'cesion_pagada', 'cesion_cobrada',
  'reparto_inicial', 'subasta', 'draft', 'herencia_temporada', 'porra_apuesta', 'porra_premio', 'porra_devolucion',
  'subasta_venta'));

create or replace function poner_en_subasta(p_ficha uuid, p_precio numeric, p_horas int default 24) returns uuid
language plpgsql security definer set search_path = public as $$
declare f fichas; v_m uuid; v_id uuid; v_precio numeric;
begin
  select * into f from fichas where id = p_ficha for update;
  if not found then raise exception 'Jugador no encontrado'; end if;
  v_m := mi_miembro(f.liga_id);
  if v_m is null or f.propietario_id is distinct from v_m then raise exception 'Ese jugador no es tuyo'; end if;
  if not mercado_abierto(f.liga_id) then raise exception 'El mercado está cerrado hasta que se calculen los puntos del partido'; end if;
  if exists (select 1 from cesiones c where c.ficha_id = p_ficha and c.estado in ('ofrecida', 'aceptada')) then
    raise exception 'Está cedido u ofrecido en cesión: retira la cesión antes';
  end if;
  if exists (select 1 from subastas s where s.ficha_id = p_ficha and s.estado = 'abierta') then
    raise exception 'Ya está en subasta';
  end if;
  v_precio := round(p_precio, 2);
  if v_precio is null or v_precio <= 0 then raise exception 'Pon un precio de salida mayor que 0'; end if;
  if p_horas not in (12, 24, 48) then raise exception 'La subasta dura 12, 24 o 48 horas'; end if;
  insert into subastas (liga_id, ficha_id, jugador_id, tipo, precio_salida, cierra_en, vendedor_id)
  values (f.liga_id, p_ficha, f.jugador_id, 'abierta', v_precio, now() + make_interval(hours => p_horas), v_m)
  returning id into v_id;
  if coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
    perform notificar((select coalesce(array_agg(m.perfil_id), '{}') from fantasy_managers fm
                         join miembros m on m.id = fm.miembro_id
                        where fm.liga_id = f.liga_id and m.perfil_id is not null and fm.miembro_id <> v_m),
                      f.liga_id, 'subasta', '🔨 Nueva subasta',
                      nombre_miembro(v_m) || ' subasta a ' || nombre_miembro(f.jugador_id) || ' desde ' || v_precio || ' M',
                      '/fantasy');
  end if;
  return v_id;
end $$;

create or replace function cancelar_mi_subasta(p_subasta uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s subastas;
begin
  select * into s from subastas where id = p_subasta for update;
  if not found or s.vendedor_id is distinct from mi_miembro(s.liga_id) then raise exception 'Esa subasta no es tuya'; end if;
  if s.estado <> 'abierta' then raise exception 'La subasta ya está cerrada'; end if;
  if exists (select 1 from pujas where subasta_id = p_subasta) then
    raise exception 'Ya hay pujas: no se puede cancelar';
  end if;
  update subastas set estado = 'cancelada', resuelta_en = now() where id = p_subasta;
end $$;

-- Vender al mercado o ceder con una subasta abierta: se cancela antes (si no tiene pujas)
create or replace function subasta_bloquea_ficha() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.propietario_id is distinct from new.propietario_id then
    update subastas set estado = 'cancelada', resuelta_en = now()
     where ficha_id = new.id and estado = 'abierta' and vendedor_id is not null
       and vendedor_id = old.propietario_id
       and coalesce(current_setting('ff.resolviendo_subasta', true), '') <> '1';
  end if;
  return new;
end $$;
drop trigger if exists t_subasta_ficha on fichas;
create trigger t_subasta_ficha after update of propietario_id on fichas
  for each row execute function subasta_bloquea_ficha();

create or replace function resolver_subastas(p_liga uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare s record; b record; k int := 0; v_ok boolean;
begin
  for s in select * from subastas where estado = 'abierta' and cierra_en <= now()
              and (p_liga is null or liga_id = p_liga) order by cierra_en for update skip locked loop
    v_ok := false;
    for b in select * from pujas where subasta_id = s.id order by importe desc, creada_en loop
      begin
        -- Subasta de la liga: la copia tiene que seguir libre. Subasta de un mánager: tiene que seguir siendo suya.
        if (select propietario_id from fichas where id = s.ficha_id) is distinct from s.vendedor_id then exit; end if;
        if b.manager_id = s.vendedor_id then continue; end if;
        perform validar_hueco(s.liga_id, b.manager_id, s.jugador_id);
        perform mover_saldo(s.liga_id, b.manager_id, -b.importe, 'subasta', s.jugador_id);
        perform transferir_ficha(s.ficha_id, b.manager_id, b.importe);
        if s.vendedor_id is not null then
          perform mover_saldo(s.liga_id, s.vendedor_id, b.importe, 'subasta_venta', s.jugador_id);
          if coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
            perform notificar(array[(select perfil_id from miembros where id = s.vendedor_id)], s.liga_id, 'subasta',
                              '🔨 Subasta vendida', nombre_miembro(s.jugador_id) || ' vendido por ' || b.importe || ' M',
                              '/fantasy');
          end if;
        end if;
        update subastas set estado = 'adjudicada', ganador_id = b.manager_id, importe = b.importe, resuelta_en = now()
         where id = s.id;
        v_ok := true;
        if coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
          perform notificar(array[(select perfil_id from miembros where id = b.manager_id)], s.liga_id, 'subasta',
                            '🔨 ¡Subasta ganada!', nombre_miembro(s.jugador_id) || ' es tuyo por ' || b.importe || ' M',
                            '/fantasy');
        end if;
        exit;
      exception when others then
        null;   -- esa puja no se puede pagar (saldo, plantilla llena…): pasa a la siguiente
      end;
    end loop;
    if not v_ok then
      update subastas set estado = 'desierta', resuelta_en = now() where id = s.id;
      if s.vendedor_id is not null and coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
        perform notificar(array[(select perfil_id from miembros where id = s.vendedor_id)], s.liga_id, 'subasta',
                          '🔨 Subasta sin pujas', nombre_miembro(s.jugador_id) || ' sigue en tu equipo', '/fantasy');
      end if;
    end if;
    k := k + 1;
  end loop;
  return k;
end $$;
revoke execute on function resolver_subastas(uuid) from public, anon, authenticated;

create or replace function pujar(p_subasta uuid, p_importe numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s subastas; l ligas; v_m uuid; v_saldo numeric; v_mejor numeric; v_lider uuid; v_min numeric; v_imp numeric;
begin
  select * into s from subastas where id = p_subasta for update;
  if not found then raise exception 'Subasta no encontrada'; end if;
  if s.estado <> 'abierta' or now() >= s.cierra_en then raise exception 'La subasta ya está cerrada'; end if;
  select * into l from ligas where id = s.liga_id;
  v_m := mi_miembro(s.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if v_m = s.vendedor_id then raise exception 'No puedes pujar por tu propio jugador'; end if;
  perform asegurar_manager(s.liga_id, v_m);
  perform validar_hueco(s.liga_id, v_m, s.jugador_id);
  v_imp := round(p_importe, 2);
  if v_imp < s.precio_salida then raise exception 'La puja mínima es % M', s.precio_salida; end if;
  select saldo into v_saldo from fantasy_managers where liga_id = s.liga_id and miembro_id = v_m;
  if v_imp > v_saldo then raise exception 'No tienes saldo suficiente: tienes % M', v_saldo; end if;

  if s.tipo = 'abierta' then
    select importe, manager_id into v_mejor, v_lider from pujas where subasta_id = p_subasta
     order by importe desc, creada_en limit 1;
    if v_lider = v_m then raise exception 'Ya vas ganando esta subasta'; end if;
    v_min := coalesce(v_mejor + greatest(0.5, round(v_mejor * 0.02, 2)), s.precio_salida);
    if v_imp < v_min then raise exception 'Tienes que pujar al menos % M', v_min; end if;
    if s.cierra_en - now() < interval '2 minutes' then
      update subastas set cierra_en = now() + interval '2 minutes' where id = p_subasta;
    end if;
    if v_lider is not null and coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
      perform notificar(array[(select perfil_id from miembros where id = v_lider)], s.liga_id, 'subasta',
                        '🔨 Te han superado', 'Han pujado ' || v_imp || ' M por ' || nombre_miembro(s.jugador_id), '/fantasy');
    end if;
  end if;

  insert into pujas (subasta_id, manager_id, importe) values (p_subasta, v_m, v_imp)
  on conflict (subasta_id, manager_id) do update set importe = excluded.importe, creada_en = now();
  return jsonb_build_object('importe', v_imp, 'cierra_en', (select cierra_en from subastas where id = p_subasta));
end $$;

create or replace function subastas_liga(p_liga uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_m uuid;
begin
  if not es_miembro(p_liga) then raise exception 'No perteneces a esta liga'; end if;
  perform resolver_subastas(p_liga);
  v_m := mi_miembro(p_liga);
  return coalesce((select jsonb_agg(x order by x.abierta desc, x.cierra_en desc) from (
    select s.id, s.jugador_id, s.ficha_id, s.vendedor_id, f.numero, s.tipo, s.precio_salida, s.abre_en, s.cierra_en, s.estado,
           s.estado = 'abierta' as abierta, s.ganador_id, s.importe,
           (select count(*) from pujas p where p.subasta_id = s.id) as num_pujas,
           case when s.tipo = 'abierta' or s.estado <> 'abierta'
                then (select max(importe) from pujas p where p.subasta_id = s.id) end as mejor,
           case when s.tipo = 'abierta'
                then (select p.manager_id = v_m from pujas p where p.subasta_id = s.id order by importe desc, creada_en limit 1) end
             as voy_ganando,
           (select importe from pujas p where p.subasta_id = s.id and p.manager_id = v_m) as mi_puja
      from subastas s join fichas f on f.id = s.ficha_id
     where s.liga_id = p_liga and (s.estado = 'abierta' or s.resuelta_en > now() - interval '3 days')) x), '[]');
end $$;

revoke execute on function poner_en_subasta(uuid, numeric, int), cancelar_mi_subasta(uuid) from public, anon;
grant execute on function poner_en_subasta(uuid, numeric, int), cancelar_mi_subasta(uuid) to authenticated;

-- ───────────── Fantasy sencillo ─────────────
alter table ligas add column if not exists fantasy_sencillo boolean not null default false;

create or replace function fantasy_modo_sencillo(p_liga uuid, p_activo boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_admin(p_liga);
  if p_activo then
    update ligas set fantasy_sencillo = true, modo_alineacion = 'libre', bonus_roles = false,
                     ariete_activo = false, cesiones_activas = false, suplentes = greatest(suplentes, 1)
     where id = p_liga;
    -- Cesiones pendientes de aceptar: se retiran
    update cesiones set estado = 'cancelada' where liga_id = p_liga and estado = 'ofrecida';
  else
    update ligas set fantasy_sencillo = false where id = p_liga;
  end if;
end $$;
revoke execute on function fantasy_modo_sencillo(uuid, boolean) from public, anon;
grant execute on function fantasy_modo_sencillo(uuid, boolean) to authenticated;

-- ───────────── Mis datos (RGPD) ─────────────
create or replace function exportar_mis_datos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Inicia sesión'; end if;
  return jsonb_build_object(
    'generado_en', now(),
    'cuenta', (select jsonb_build_object('email', email, 'creada_en', created_at, 'ultimo_acceso', last_sign_in_at)
                 from auth.users where id = v_uid),
    'perfil', (select to_jsonb(p) from perfiles p where p.id = v_uid),
    'consentimientos', coalesce((select jsonb_agg(to_jsonb(c) order by c.accepted_at) from user_consents c where c.user_id = v_uid), '[]'),
    'ligas', coalesce((select jsonb_agg(jsonb_build_object(
                'liga', l.nombre, 'rol', m.rol, 'estado', m.estado, 'unido_en', m.unido_en,
                'partidos', (select coalesce(jsonb_agg(jsonb_build_object('fecha', pa.fecha_hora, 'goles', aj.goles,
                                     'asistencias', aj.asistencias, 'puntos', pf.total, 'mvp', pf.es_mvp) order by pa.fecha_hora), '[]')
                               from acta_jugador aj join partidos pa on pa.id = aj.partido_id
                               left join puntos_fantasy pf on pf.partido_id = aj.partido_id and pf.miembro_id = aj.miembro_id
                              where aj.miembro_id = m.id),
                'logros', (select coalesce(jsonb_agg(jsonb_build_object('logro', nombre_logro(lg.tipo), 'fecha', lg.conseguido_en)), '[]')
                             from logros lg where lg.miembro_id = m.id),
                'movimientos_caja', (select coalesce(jsonb_agg(jsonb_build_object('fecha', mv.fecha, 'tipo', mv.tipo,
                                       'importe', mv.importe, 'concepto', mv.concepto) order by mv.fecha), '[]')
                                       from movimientos mv where mv.miembro_id = m.id),
                'fantasy', (select jsonb_build_object('saldo', fm.saldo, 'puntos', fm.puntos_totales)
                              from fantasy_managers fm where fm.miembro_id = m.id),
                'porra', (select coalesce(jsonb_agg(jsonb_build_object('fecha', a.creada_en, 'tipo', a.tipo, 'importe', a.importe,
                                    'estado', a.estado, 'retorno', a.retorno)), '[]') from apuestas a where a.miembro_id = m.id)
              ) order by l.nombre)
              from miembros m join ligas l on l.id = m.liga_id where m.perfil_id = v_uid), '[]'),
    'notificaciones_recibidas', (select count(*) from notificaciones where perfil_id = v_uid));
end $$;
revoke execute on function exportar_mis_datos() from public, anon;
grant execute on function exportar_mis_datos() to authenticated;

-- ───────────── Política de privacidad nueva ─────────────
insert into politicas (version, url, cambios)
values ('2026-11-26', 'https://www.pachangafantasy.com/privacidad',
        'Web propia (pachangafantasy.com), inicio de sesión con Google, contraseña, porra solo para mayores de 18 años y copias de seguridad cifradas')
on conflict (version) do nothing;
