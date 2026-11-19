-- 0017 · v0.3 · Cobro por factura mensual con precio de invitado (docs/v03_liga.md §4)
--
-- Decisiones:
--  · modo 'por_partido' = comportamiento de siempre (cuota = coste del partido / confirmados).
--  · modo 'factura_mensual': al jugar, a reservas e invitados se les carga precio_invitado (si no es null); a los
--    fijos nada. La factura del periodo se reparte con liquidar_factura según partidos jugados por cada fijo.
--  · precio_invitado = null (variable): nadie paga al jugar; al liquidar, reservas e invitados entran en el reparto
--    con la misma cuota por partido que los fijos.
--  · El rango que cuenta es el de cada inscripción en el momento de jugar (convocatorias.rango, que se refresca en
--    generar_cargos al marcar el partido como jugado).
--  · Partidos del periodo: fecha (hora de Madrid) dentro de [desde, hasta] y estado jugado / post_partido /
--    en_revision / cerrado.
--  · Redondeo: cada cargo a céntimos; la diferencia hasta el total va al primer miembro por antigüedad (unido_en).
--  · Si lo pagado por invitados supera la factura, el resto es 0 (no se reparte saldo a favor) y se avisa.
--  · Si en el periodo se mezclan modos (un partido cobrado por_partido), lo cargado a fijos no se descuenta.

alter table ligas
  add column modo_cobro      text not null default 'por_partido' check (modo_cobro in ('por_partido', 'factura_mensual')),
  add column precio_invitado numeric(6,2) check (precio_invitado is null or precio_invitado >= 0);

alter table facturas
  add column periodo_desde date,
  add column periodo_hasta date,
  add column liquidada     boolean not null default false,
  add column liquidada_en  timestamptz,
  add constraint facturas_periodo_ck check (periodo_hasta is null or periodo_desde is null or periodo_hasta >= periodo_desde);

-- ───────────── Cargos al jugar ─────────────
create or replace function generar_cargos(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; n int; v_coste numeric(8,2); cuota numeric(8,2); resto numeric(8,2);
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.cargos_generados then return 0; end if;
  select * into l from ligas where id = p.liga_id;

  -- Rango de cada asistente en el momento de jugar
  update convocatorias c set rango = m.rango
    from miembros m
   where c.partido_id = p_partido and c.estado = 'confirmado' and m.id = c.miembro_id
     and c.rango is distinct from m.rango;

  if l.modo_cobro = 'factura_mensual' then
    n := 0;
    if coalesce(l.precio_invitado, 0) > 0 then
      insert into movimientos (liga_id, miembro_id, partido_id, tipo, importe, concepto, registrado_por)
      select p.liga_id, c.miembro_id, p.id, 'cargo', -l.precio_invitado,
             'Partido ' || to_char(p.fecha_hora at time zone 'Europe/Madrid', 'DD/MM') || ' (' || c.rango || ')',
             mi_miembro(p.liga_id)
        from convocatorias c
       where c.partido_id = p_partido and c.estado = 'confirmado' and c.rango <> 'fijo';
      get diagnostics n = row_count;
    end if;
    update partidos set cargos_generados = true where id = p_partido;
    return n;
  end if;

  select coalesce(sum(importe), 0) into v_coste from facturas where partido_id = p_partido;
  if v_coste = 0 then v_coste := p.coste_total; end if;

  select count(*) into n from convocatorias where partido_id = p_partido and estado = 'confirmado';
  if n = 0 or v_coste = 0 then
    update partidos set cargos_generados = true where id = p_partido;
    return 0;
  end if;

  cuota := trunc(v_coste / n, 2);
  resto := v_coste - cuota * n;
  insert into movimientos (liga_id, miembro_id, partido_id, tipo, importe, concepto, registrado_por)
  select p.liga_id, c.miembro_id, p.id, 'cargo',
         -(cuota + case when row_number() over (order by c.inscrito_en) = 1 then resto else 0 end),
         'Partido ' || to_char(p.fecha_hora at time zone 'Europe/Madrid', 'DD/MM'),
         mi_miembro(p.liga_id)
    from convocatorias c
   where c.partido_id = p_partido and c.estado = 'confirmado';

  update partidos set cargos_generados = true where id = p_partido;
  return n;
end $$;

-- ───────────── Cálculo del reparto (interno) ─────────────
create or replace function calculo_factura(p_factura uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f facturas; l ligas; v_fijo_precio boolean; v_partidos int; v_pagado numeric; v_resto numeric;
        v_total int; v_cuota numeric; v_cargos jsonb;
begin
  select * into f from facturas where id = p_factura;
  if not found then raise exception 'Factura no encontrada'; end if;
  if f.periodo_desde is null or f.periodo_hasta is null then
    raise exception 'La factura necesita un periodo (desde y hasta) para repartirse';
  end if;
  if f.importe is null then raise exception 'La factura no tiene importe'; end if;
  select * into l from ligas where id = f.liga_id;
  v_fijo_precio := l.precio_invitado is not null;

  create temp table if not exists tmp_fact_partidos (id uuid primary key) on commit drop;
  delete from tmp_fact_partidos;
  insert into tmp_fact_partidos
  select id from partidos
   where liga_id = f.liga_id and estado in ('jugado', 'post_partido', 'en_revision', 'cerrado')
     and (fecha_hora at time zone 'Europe/Madrid')::date between f.periodo_desde and f.periodo_hasta;
  select count(*) into v_partidos from tmp_fact_partidos;

  -- Lo ya pagado por reservas e invitados al jugar (solo con precio fijo)
  if v_fijo_precio then
    select coalesce(-sum(mv.importe), 0) into v_pagado
      from movimientos mv
      join convocatorias c on c.partido_id = mv.partido_id and c.miembro_id = mv.miembro_id
      join miembros m on m.id = mv.miembro_id
     where mv.partido_id in (select id from tmp_fact_partidos) and mv.tipo = 'cargo'
       and coalesce(c.rango, m.rango) <> 'fijo';
  else
    v_pagado := 0;
  end if;
  v_resto := greatest(f.importe - v_pagado, 0);

  -- Asistencias que entran en el reparto
  create temp table if not exists tmp_fact_asis (miembro_id uuid primary key, partidos int, unido timestamptz,
                                                  nombre text, rango text) on commit drop;
  delete from tmp_fact_asis;
  insert into tmp_fact_asis
  select c.miembro_id, count(*)::int, min(m.unido_en),
         min(coalesce(pe.apodo, pe.nombre, m.nombre_provisional)), min(coalesce(c.rango, m.rango)::text)
    from convocatorias c
    join miembros m on m.id = c.miembro_id
    left join perfiles pe on pe.id = m.perfil_id
   where c.partido_id in (select id from tmp_fact_partidos) and c.estado = 'confirmado'
     and (not v_fijo_precio or coalesce(c.rango, m.rango) = 'fijo')
   group by c.miembro_id;
  select coalesce(sum(partidos), 0) into v_total from tmp_fact_asis;
  if v_total = 0 then
    raise exception 'No hay partidos jugados por fijos entre el % y el %',
      to_char(f.periodo_desde, 'DD/MM/YYYY'), to_char(f.periodo_hasta, 'DD/MM/YYYY');
  end if;
  v_cuota := v_resto / v_total;

  select coalesce(jsonb_agg(jsonb_build_object('miembro_id', miembro_id, 'nombre', nombre, 'rango', rango,
                                               'partidos', partidos, 'importe', importe) order by rn), '[]'::jsonb)
    into v_cargos
    from (select a.*,
                 round(v_cuota * a.partidos, 2)
                 + case when a.rn = 1 then v_resto - sum(round(v_cuota * a.partidos, 2)) over () else 0 end as importe
            from (select t.*, row_number() over (order by t.unido, t.miembro_id) rn from tmp_fact_asis t) a) x;

  return jsonb_build_object(
    'factura_id', f.id, 'importe', f.importe, 'periodo_desde', f.periodo_desde, 'periodo_hasta', f.periodo_hasta,
    'num_partidos_periodo', v_partidos, 'precio_invitado', l.precio_invitado,
    'pagado_invitados', v_pagado, 'resto', v_resto, 'partidos', v_total, 'cuota', round(v_cuota, 4),
    'aviso', case when f.importe < v_pagado then 'Lo pagado por reservas e invitados supera la factura' end,
    'liquidada', f.liquidada,
    'cargos', v_cargos);
end $$;

-- ───────────── RPC ─────────────
create or replace function simular_factura(p_factura uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f facturas;
begin
  select * into f from facturas where id = p_factura;
  if not found then raise exception 'Factura no encontrada'; end if;
  perform exigir_admin(f.liga_id);
  return calculo_factura(p_factura);
end $$;

create or replace function liquidar_factura(p_factura uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f facturas; r jsonb;
begin
  select * into f from facturas where id = p_factura for update;
  if not found then raise exception 'Factura no encontrada'; end if;
  perform exigir_admin(f.liga_id);
  if f.liquidada then raise exception 'Esta factura ya está liquidada'; end if;
  r := calculo_factura(p_factura);

  insert into movimientos (liga_id, miembro_id, partido_id, factura_id, tipo, importe, concepto, registrado_por)
  select f.liga_id, (c ->> 'miembro_id')::uuid, null, f.id, 'cargo', -((c ->> 'importe')::numeric),
         'Factura ' || to_char(f.periodo_desde, 'DD/MM') || '–' || to_char(f.periodo_hasta, 'DD/MM/YYYY')
           || ' (' || (c ->> 'partidos') || ' partidos)',
         mi_miembro(f.liga_id)
    from jsonb_array_elements(r -> 'cargos') c
   where (c ->> 'importe')::numeric > 0;

  update facturas set liquidada = true, liquidada_en = now() where id = p_factura;
  return r || jsonb_build_object('liquidada', true);
end $$;
