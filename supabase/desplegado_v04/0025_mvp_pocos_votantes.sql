-- 0025 · MVP con pocos votantes: el mínimo baja a los que votaron ese día (máx. 3). Antes, con menos de 3
-- votantes no había MVP y el ranking de MVPs quedaba vacío.

-- MVP: mejor nota media de los compañeros; desempate: votos «Mi MVP», luego goles + asistencias (si persiste, compartido).
-- Optan quienes tienen al menos min(3, máximo de votantes de ese partido) votantes. Si nadie llega a 3 votantes,
-- la nota oficial (nota_media) es null y no da puntos, pero para el MVP se usa la media en bruto.
create or replace function decidir_mvp(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_min int; v_liga uuid; v_bonus numeric; k int;
begin
  select liga_id into v_liga from partidos where id = p_partido;
  select least(3, greatest(1, coalesce(max(num_votantes), 0))) into v_min from puntos_fantasy where partido_id = p_partido;
  v_bonus := regla(v_liga, 'mvp');

  with c as (
    select pf.miembro_id,
           coalesce(pf.nota_media,
                    (select round(avg(x.m), 2) from (select avg(v.nota) m from valoraciones v
                                                       where v.partido_id = p_partido and v.votado_id = pf.miembro_id
                                                       group by v.votante_id) x)) as nota,
           coalesce((pf.desglose ->> 'votos_mvp')::int, 0) as votos,
           aj.goles + aj.asistencias as ga
      from puntos_fantasy pf join acta_jugador aj using (partido_id, miembro_id)
     where pf.partido_id = p_partido and pf.num_votantes >= v_min and not pf.es_mvp),
  mejor as (select nota, votos, ga from c where nota is not null order by nota desc, votos desc, ga desc limit 1)
  update puntos_fantasy pf
     set es_mvp = true,
         desglose = jsonb_set(pf.desglose, '{mvp}', to_jsonb(v_bonus)),
         total = pf.total + v_bonus
    from c, mejor
   where pf.partido_id = p_partido and pf.miembro_id = c.miembro_id
     and c.nota = mejor.nota and c.votos = mejor.votos and c.ga = mejor.ga;
  get diagnostics k = row_count;
  return k;
end $$;
revoke execute on function decidir_mvp(uuid) from public, anon, authenticated;

create or replace function calcular_puntos(p_partido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; a record; v_v int; v_e int; v_d int; v_nota record; d jsonb; v_total numeric;
        v_dest jsonb; v_votos int;
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado not in ('post_partido', 'en_revision') then
    raise exception 'El partido no está pendiente de puntuar (estado: %)', p.estado;
  end if;
  if exists (select 1 from disputas where partido_id = p_partido and not resuelta) then
    raise exception 'Quedan datos en disputa por resolver';
  end if;
  if exists (select 1 from encuentros where partido_id = p_partido and goles_local is null) then
    raise exception 'El acta no está consolidada';
  end if;
  select * into l from ligas where id = p.liga_id;

  delete from puntos_fantasy where partido_id = p_partido;

  for a in select aj.*, c.equipo from acta_jugador aj
             join convocatorias c on c.partido_id = aj.partido_id and c.miembro_id = aj.miembro_id
            where aj.partido_id = p_partido loop
    select count(*) filter (where gf > gc), count(*) filter (where gf = gc), count(*) filter (where gf < gc)
      into v_v, v_e, v_d
      from (select case when e.equipo_local = a.equipo then e.goles_local else e.goles_visitante end gf,
                   case when e.equipo_local = a.equipo then e.goles_visitante else e.goles_local end gc
              from encuentros e
             where e.partido_id = p_partido and a.equipo in (e.equipo_local, e.equipo_visitante)) t;

    v_nota := nota_partido(p_partido, a.miembro_id);

    d := jsonb_build_object(
      'jugado',            regla(l.id, 'jugado'),
      'resultado',         v_v * regla(l.id, 'victoria') + v_e * regla(l.id, 'empate'),
      'goles',             a.goles * regla(l.id, 'gol'),
      'asistencias',       a.asistencias * regla(l.id, 'asistencia'),
      'paradas',           floor(a.paradas_clave / 2.0) * regla(l.id, 'parada_clave_2'),
      'penaltis_parados',  a.penaltis_parados * regla(l.id, 'penalti_parado'),
      'penaltis_fallados', a.penaltis_fallados * regla(l.id, 'penalti_fallado'),
      'autogoles',         a.autogoles * regla(l.id, 'autogol'),
      'valoracion',        puntos_por_nota(v_nota.nota, regla(l.id, 'valoracion_max')),
      'mvp',               0);

    select sum(value::numeric) into v_total from jsonb_each_text(d);

    -- Datos informativos (no suman): notas por aspecto, destacados y votos MVP. Solo con ≥ 3 votantes.
    select coalesce(jsonb_object_agg(aspecto, n), '{}') into v_dest
      from (select aspecto, count(*) n from valoracion_destacados
             where partido_id = p_partido and votado_id = a.miembro_id group by aspecto) t;
    select count(*) into v_votos from votos_mvp where partido_id = p_partido and votado_id = a.miembro_id;
    if coalesce(v_nota.votantes, 0) < 3 then v_dest := '{}'; end if;
    d := d || jsonb_build_object('notas', v_nota.por_aspecto, 'destacados', v_dest, 'votos_mvp', v_votos);

    insert into puntos_fantasy (partido_id, miembro_id, posicion, victorias, empates, derrotas,
                                nota_media, num_votantes, es_mvp, desglose, total)
    values (p_partido, a.miembro_id, posicion_de(a.miembro_id), v_v, v_e, v_d, v_nota.nota, v_nota.votantes,
            false, d, v_total);
  end loop;

  -- MVP: mayor nota (≥ 3 votantes); desempate: votos «Mi MVP», luego goles + asistencias; si persiste, compartido
  perform decidir_mvp(p_partido);

  update partidos set estado = 'cerrado' where id = p_partido;
end $$;


-- Partidos ya cerrados sin MVP (antes hacían falta 3 votantes). Solo se corrige puntos_fantasy:
-- el dinero Fantasy de esas jornadas ya se liquidó y no se toca.
do $$
declare p record;
begin
  for p in select pa.id from partidos pa where pa.estado = 'cerrado'
            and not exists (select 1 from puntos_fantasy x where x.partido_id = pa.id and x.es_mvp)
            and exists (select 1 from puntos_fantasy x where x.partido_id = pa.id and x.num_votantes > 0) loop
    perform decidir_mvp(p.id);
  end loop;
end $$;
