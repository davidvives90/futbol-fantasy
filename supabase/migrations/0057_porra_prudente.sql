-- 0057 · Porra más prudente
--  · Ganancia máxima por boleto: 10 M en dinero Fantasy (una quinta parte del valor base) o 100 pts en modo puntos.
--  · Tope de lo apostado por partido por defecto: 5 M (una décima parte del valor base) o 50 pts.
--  · Mercados «marca» y «no marca»: pagan muy poco (25 % de la cuota justa, entre 1,02 y 1,30).
--    El valor está en acertar el resultado (1-X-2) y el MVP.

alter table apuestas add column if not exists max_ganancia numeric(10,2);
alter table porra_cuotas drop constraint if exists porra_cuotas_mercado_check;
alter table porra_cuotas add constraint porra_cuotas_mercado_check check (mercado in ('1x2', 'goleador', 'no_goleador', 'mvp'));

create or replace function porra_tope(p_liga uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select round(coalesce(porra_max, case when porra_modo = 'dinero' then valor_base / 10 else 50 end), 2) from ligas where id = p_liga
$$;

create or replace function porra_ganancia_max(p_liga uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select round(case when porra_modo = 'dinero' then valor_base / 5 else 100 end, 2) from ligas where id = p_liga
$$;
grant execute on function porra_ganancia_max(uuid) to authenticated;

-- Las cuotas ya calculadas se recalculan con la nueva fórmula
delete from porra_firmas where true;

create or replace function porra_calcular_cuotas(p_partido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_firma text; v_lig uuid; v_media numeric; la numeric; lb numeric; pa numeric[]; pb numeric[];
        i int; j int; p1 numeric := 0; px numeric := 0; p2 numeric := 0; v_suma numeric;
begin
  select p.liga_id into v_lig from partidos p where p.id = p_partido;
  select string_agg(miembro_id || ':' || equipo, ',' order by miembro_id) into v_firma
    from convocatorias where partido_id = p_partido and estado = 'confirmado' and equipo is not null;
  if v_firma is null then return; end if;
  if exists (select 1 from porra_firmas where partido_id = p_partido and firma = v_firma) then return; end if;
  delete from porra_cuotas where partido_id = p_partido;
  insert into porra_firmas (partido_id, firma) values (p_partido, v_firma)
  on conflict (partido_id) do update set firma = excluded.firma, creada_en = now();

  -- goles por partido de cada uno (con un mínimo de partidos, encogido hacia la media de la liga)
  select coalesce(avg(goles_partido), 0.6) into v_media from v_rendimiento where liga_id = v_lig and partidos > 0;
  create temp table if not exists tmp_gp (miembro_id uuid primary key, equipo smallint, gp numeric, pm numeric) on commit drop;
  delete from tmp_gp where true;
  insert into tmp_gp
  select c.miembro_id, c.equipo,
         (coalesce(r.goles, 0) + 3 * v_media) / (coalesce(r.partidos, 0) + 3),
         greatest(1, coalesce(r.puntos_media, 0) + 3)
    from convocatorias c left join v_rendimiento r on r.miembro_id = c.miembro_id
   where c.partido_id = p_partido and c.estado = 'confirmado' and c.equipo is not null;

  select sum(gp) filter (where equipo = 1), sum(gp) filter (where equipo = 2) into la, lb from tmp_gp;
  la := greatest(coalesce(la, 0.5), 0.3); lb := greatest(coalesce(lb, 0.5), 0.3);
  pa := array[exp(-la)]; pb := array[exp(-lb)];
  for i in 1..25 loop pa := pa || (pa[i] * la / i); pb := pb || (pb[i] * lb / i); end loop;
  for i in 0..25 loop
    for j in 0..25 loop
      if i > j then p1 := p1 + pa[i + 1] * pb[j + 1];
      elsif i = j then px := px + pa[i + 1] * pb[j + 1];
      else p2 := p2 + pa[i + 1] * pb[j + 1]; end if;
    end loop;
  end loop;
  insert into porra_cuotas (partido_id, mercado, seleccion, prob, cuota)
  select p_partido, '1x2', s, pr, least(25, greatest(1.05, round(0.92 / greatest(pr, 0.0001), 2)))
    from (values ('1', p1 / (p1 + px + p2)), ('X', px / (p1 + px + p2)), ('2', p2 / (p1 + px + p2))) v(s, pr);

  -- Marca / no marca: muy fáciles de acertar, así que pagan muy poco (25 % de la cuota justa, entre 1,02 y 1,30)
  insert into porra_cuotas (partido_id, mercado, seleccion, prob, cuota)
  select p_partido, 'goleador', miembro_id::text, round(1 - exp(-gp), 4),
         least(1.30, greatest(1.02, round(1 + 0.25 * (0.92 / greatest(1 - exp(-gp), 0.0001) - 1), 2)))
    from tmp_gp;
  insert into porra_cuotas (partido_id, mercado, seleccion, prob, cuota)
  select p_partido, 'no_goleador', miembro_id::text, round(exp(-gp), 4),
         least(1.30, greatest(1.02, round(1 + 0.25 * (0.92 / greatest(exp(-gp), 0.0001) - 1), 2)))
    from tmp_gp;

  select sum(pm * pm) into v_suma from tmp_gp;
  insert into porra_cuotas (partido_id, mercado, seleccion, prob, cuota)
  select p_partido, 'mvp', miembro_id::text, round(pm * pm / v_suma, 4),
         least(25, greatest(1.05, round(0.92 / greatest(pm * pm / v_suma, 0.0001), 2)))
    from tmp_gp;
end $$;
revoke execute on function porra_calcular_cuotas(uuid) from public, anon, authenticated;

create or replace function apuesta_json(p_apuesta uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', a.id, 'miembro_id', a.miembro_id, 'tipo', a.tipo, 'importe', a.importe,
                            'seguro', a.seguro, 'max_ganancia', a.max_ganancia, 'cuota_total', a.cuota_total, 'estado', a.estado, 'retorno', a.retorno,
                            'creada_en', a.creada_en,
                            'selecciones', (select jsonb_agg(jsonb_build_object('mercado', s.mercado, 'seleccion', s.seleccion,
                                                                                 'cuota', s.cuota, 'acierto', s.acierto)
                                                             order by s.mercado, s.seleccion)
                                              from apuesta_selecciones s where s.apuesta_id = a.id))
    from apuestas a where a.id = p_apuesta
$$;
revoke execute on function apuesta_json(uuid) from public, anon, authenticated;

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

drop function if exists porra_retorno(text, numeric, boolean, jsonb);
create or replace function porra_retorno(p_tipo text, p_importe numeric, p_seguro boolean, p_sel jsonb,
                                         p_max_ganancia numeric default null) returns numeric
language plpgsql immutable as $$
declare v_bruto numeric := 0; v_n int; v_pares int; i int; j int; v_c numeric := 1; ok boolean := true;
begin
  v_n := jsonb_array_length(p_sel);
  if p_tipo in ('sencilla', 'combinada') then
    for i in 0 .. v_n - 1 loop
      if not coalesce((p_sel -> i ->> 'acierto')::boolean, false) then ok := false; end if;
      v_c := v_c * (p_sel -> i ->> 'cuota')::numeric;
    end loop;
    v_bruto := case when ok then p_importe * v_c else 0 end;
  else
    v_pares := v_n * (v_n - 1) / 2;
    for i in 0 .. v_n - 2 loop
      for j in i + 1 .. v_n - 1 loop
        if coalesce((p_sel -> i ->> 'acierto')::boolean, false) and coalesce((p_sel -> j ->> 'acierto')::boolean, false) then
          v_bruto := v_bruto + p_importe / v_pares * (p_sel -> i ->> 'cuota')::numeric * (p_sel -> j ->> 'cuota')::numeric;
        end if;
      end loop;
    end loop;
  end if;
  if p_seguro then
    v_bruto := case when v_bruto >= p_importe then p_importe + (v_bruto - p_importe) * 0.70
                    else greatest(v_bruto, p_importe * 0.50) end;
  end if;
  -- Ganancia máxima por boleto
  if p_max_ganancia is not null then v_bruto := least(v_bruto, p_importe + p_max_ganancia); end if;
  return round(v_bruto, 2);
end $$;

create or replace function apostar(p_partido uuid, p_tipo text, p_selecciones jsonb, p_importe numeric,
                                   p_seguro boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_m uuid; v_n int; v_id uuid; x jsonb; v_cuota numeric; v_total numeric := 1;
        v_apostado numeric; v_imp numeric;
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  select * into l from ligas where id = p.liga_id;
  v_m := mi_miembro(p.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if not l.porra_activa then raise exception 'La porra no está activada en esta liga'; end if;
  if not porra_abierta(p_partido) then
    raise exception 'La porra se abre con los equipos hechos y cierra a la hora del partido';
  end if;
  perform porra_calcular_cuotas(p_partido);
  v_imp := round(p_importe, 2);
  if v_imp is null or v_imp <= 0 then raise exception 'Pon un importe mayor que 0'; end if;
  if jsonb_typeof(p_selecciones) <> 'array' then raise exception 'Formato no válido'; end if;
  v_n := jsonb_array_length(p_selecciones);
  if p_tipo = 'sencilla' and v_n <> 1 then raise exception 'La sencilla lleva un solo pronóstico'; end if;
  if p_tipo = 'combinada' and v_n < 2 then raise exception 'La combinada lleva 2 pronósticos o más'; end if;
  if p_tipo = 'multiple' and v_n not between 3 and 4 then raise exception 'La múltiple lleva 3 o 4 pronósticos'; end if;
  if p_tipo not in ('sencilla', 'combinada', 'multiple') then raise exception 'Tipo de boleto no válido'; end if;
  if (select count(*) from jsonb_array_elements(p_selecciones) e where e ->> 'mercado' = '1x2') > 1 then
    raise exception 'Solo un resultado 1-X-2 por boleto';
  end if;
  if (select count(*) from jsonb_array_elements(p_selecciones) e where e ->> 'mercado' = 'mvp') > 1 then
    raise exception 'Solo un MVP por boleto';
  end if;
  if (select count(distinct (e ->> 'mercado') || (e ->> 'seleccion')) from jsonb_array_elements(p_selecciones) e) <> v_n then
    raise exception 'Hay pronósticos repetidos';
  end if;
  if exists (select 1 from jsonb_array_elements(p_selecciones) a, jsonb_array_elements(p_selecciones) b
              where a ->> 'mercado' = 'goleador' and b ->> 'mercado' = 'no_goleador' and a ->> 'seleccion' = b ->> 'seleccion') then
    raise exception 'No puedes decir a la vez que marca y que no marca';
  end if;

  select coalesce(sum(importe), 0) into v_apostado from apuestas
   where partido_id = p_partido and miembro_id = v_m and estado <> 'anulada';
  if v_apostado + v_imp > porra_tope(l.id) then
    raise exception 'Tope de la porra: % por partido (ya llevas %)', porra_tope(l.id), v_apostado;
  end if;

  insert into apuestas (partido_id, liga_id, miembro_id, tipo, modo, importe, seguro, max_ganancia)
  values (p_partido, l.id, v_m, p_tipo, l.porra_modo, v_imp, coalesce(p_seguro, false), porra_ganancia_max(l.id))
  returning id into v_id;
  for x in select value from jsonb_array_elements(p_selecciones) loop
    select cuota into v_cuota from porra_cuotas
     where partido_id = p_partido and mercado = x ->> 'mercado' and seleccion = x ->> 'seleccion';
    if v_cuota is null then raise exception 'Ese pronóstico no está disponible'; end if;
    insert into apuesta_selecciones (apuesta_id, mercado, seleccion, cuota) values (v_id, x ->> 'mercado', x ->> 'seleccion', v_cuota);
    v_total := v_total * v_cuota;
  end loop;
  update apuestas set cuota_total = case when p_tipo = 'multiple' then null else round(v_total, 2) end where id = v_id;

  if l.porra_modo = 'dinero' then
    if not l.fantasy_activo then raise exception 'La porra con dinero necesita el Fantasy activo'; end if;
    perform mover_saldo(l.id, v_m, -v_imp, 'porra_apuesta', null, p_partido);
  end if;
  return apuesta_json(v_id);
end $$;

create or replace function liquidar_porra(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; a record; v_g1 int; v_g2 int; v_signo text; v_ret numeric; v_sel jsonb; k int := 0;
        v_estado text; v_aciertos int; v_n int;
begin
  select * into p from partidos where id = p_partido;
  if p.estado = 'cancelado' then
    for a in select * from apuestas where partido_id = p_partido and estado = 'pendiente' loop
      if a.modo = 'dinero' and exists (select 1 from fantasy_managers where liga_id = a.liga_id and miembro_id = a.miembro_id) then
        perform mover_saldo(a.liga_id, a.miembro_id, a.importe, 'porra_devolucion', null, p_partido);
      end if;
      update apuestas set estado = 'anulada', retorno = a.importe, liquidada_en = now() where id = a.id;
      k := k + 1;
    end loop;
    return k;
  end if;
  if p.estado <> 'cerrado' then return 0; end if;

  select coalesce(sum(case when equipo_local = 1 then goles_local when equipo_visitante = 1 then goles_visitante else 0 end), 0),
         coalesce(sum(case when equipo_local = 2 then goles_local when equipo_visitante = 2 then goles_visitante else 0 end), 0)
    into v_g1, v_g2 from encuentros where partido_id = p_partido;
  v_signo := case when v_g1 > v_g2 then '1' when v_g1 = v_g2 then 'X' else '2' end;

  update apuesta_selecciones s
     set acierto = case s.mercado
                     when '1x2' then s.seleccion = v_signo
                     when 'goleador' then coalesce((select aj.goles > 0 from acta_jugador aj
                                                     where aj.partido_id = p_partido and aj.miembro_id::text = s.seleccion), false)
                     when 'no_goleador' then coalesce((select aj.goles = 0 from acta_jugador aj
                                                        where aj.partido_id = p_partido and aj.miembro_id::text = s.seleccion), true)
                     when 'mvp' then coalesce((select pf.es_mvp from puntos_fantasy pf
                                                where pf.partido_id = p_partido and pf.miembro_id::text = s.seleccion), false)
                   end
    from apuestas ap
   where ap.id = s.apuesta_id and ap.partido_id = p_partido and ap.estado = 'pendiente';

  for a in select * from apuestas where partido_id = p_partido and estado = 'pendiente' for update loop
    select jsonb_agg(jsonb_build_object('cuota', cuota, 'acierto', acierto) order by mercado, seleccion),
           count(*) filter (where acierto), count(*)
      into v_sel, v_aciertos, v_n
      from apuesta_selecciones where apuesta_id = a.id;
    v_ret := porra_retorno(a.tipo, a.importe, a.seguro, v_sel, a.max_ganancia);
    v_estado := case when v_aciertos = v_n then 'ganada'
                     when v_ret > 0 then 'parcial' else 'perdida' end;
    update apuestas set estado = v_estado, retorno = v_ret, liquidada_en = now() where id = a.id;
    if a.modo = 'dinero' and v_ret > 0
       and exists (select 1 from fantasy_managers where liga_id = a.liga_id and miembro_id = a.miembro_id) then
      perform mover_saldo(a.liga_id, a.miembro_id, v_ret, 'porra_premio', null, p_partido);
    end if;
    if coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
      perform notificar(array[(select perfil_id from miembros where id = a.miembro_id)], a.liga_id, 'porra',
                        case when v_ret > a.importe then '🎯 ¡Porra ganada!' when v_ret > 0 then '🛡️ Porra: recuperas algo'
                             else '❌ Porra perdida' end,
                        case when v_ret > 0 then 'Cobras ' || v_ret || case when a.modo = 'dinero' then ' M' else ' pts' end
                             else 'Esta vez no ha habido suerte' end,
                        '/partidos/' || p_partido);
    end if;
    k := k + 1;
  end loop;
  return k;
end $$;
revoke execute on function liquidar_porra(uuid) from public, anon, authenticated;

-- Boletos pendientes: también con el tope de ganancia
update apuestas a set max_ganancia = porra_ganancia_max(a.liga_id) where a.estado = 'pendiente' and a.max_ganancia is null;
