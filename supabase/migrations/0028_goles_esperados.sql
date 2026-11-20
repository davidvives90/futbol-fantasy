-- 0028 · Goles esperados (xG) y resultado esperado de un partido con los equipos hechos
--  · ligas.prediccion_activa: el admin lo activa o desactiva en Ajustes.
--  · prediccion_partido(partido) → jsonb con los goles esperados de cada equipo y de cada jugador, las
--    probabilidades (Poisson) de victoria/empate/derrota, el marcador más probable y un resumen en texto.
-- Modelo (sencillo y explicable):
--  · Ataque de un jugador = sus goles por partido, «encogidos» hacia lo esperable por su valoración
--    (encuesta del Fantasy) mientras tenga pocos partidos: (goles + K·previo) / (partidos + K), K = 3.
--  · Defensa de un jugador = goles que encaja su equipo por partido cuando él juega, encogidos igual hacia la
--    media de la liga y corregidos por su valoración de defensa/portería.
--  · xG de A contra B = suma del ataque de A × (defensa media de B / media de la liga).
--  · Sin historial se usa la media de la liga, y sin ella 8 goles por partido entre los dos equipos.

alter table ligas add column prediccion_activa boolean not null default true;

create or replace function prediccion_partido(p_partido uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_part int; v_media_gol numeric; v_media_enc numeric; v_rating_medio numeric;
        v_def_media numeric; e record; v_res jsonb := '[]'; v_eq jsonb; xa numeric; xb numeric;
        pa numeric[]; pb numeric[]; i int; j int; v_gana numeric; v_emp numeric; v_pierde numeric;
        v_mejor numeric; v_marc text; v_jug jsonb; k constant numeric := 3; v_n_equipo numeric;
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  if not es_miembro(p.liga_id) then raise exception 'No perteneces a esta liga'; end if;
  select * into l from ligas where id = p.liga_id;
  if not l.prediccion_activa then return null; end if;
  if not exists (select 1 from convocatorias where partido_id = p_partido and estado = 'confirmado' and equipo is not null) then
    return null;
  end if;

  -- Medias de la liga (partidos cerrados)
  select count(distinct aj.partido_id),
         avg(aj.goles), avg(aj.goles_encajados::numeric / greatest(1, (select count(*) from encuentros en where en.partido_id = aj.partido_id)))
    into v_part, v_media_gol, v_media_enc
    from acta_jugador aj join partidos pa2 on pa2.id = aj.partido_id
   where pa2.liga_id = p.liga_id and pa2.estado = 'cerrado';
  v_n_equipo := greatest(1, l.jugadores_por_equipo);
  -- sin historial: 8 goles por partido entre los dos equipos
  v_media_gol := coalesce(v_media_gol, 4.0 / v_n_equipo);
  v_media_enc := coalesce(nullif(v_media_enc, 0), v_media_gol * v_n_equipo);
  select coalesce(avg(general), 50), coalesce(avg(greatest(coalesce(defensa, 50), coalesce(portero, 50))), 50)
    into v_rating_medio, v_def_media from valoracion_jugador where liga_id = p.liga_id;

  -- Jugadores de este partido con su ataque y defensa esperados
  create temp table if not exists tmp_xg (miembro_id uuid primary key, equipo smallint, ataque numeric, defensa numeric)
    on commit drop;
  delete from tmp_xg where true;
  insert into tmp_xg
  select c.miembro_id, c.equipo,
         -- ataque: goles/partido encogidos hacia el previo por valoración
         (coalesce(h.goles, 0) + k * v_media_gol * coalesce(vj.general, v_rating_medio) / nullif(v_rating_medio, 0))
           / (coalesce(h.n, 0) + k),
         -- defensa: goles encajados por su equipo/partido, encogidos hacia la media y corregidos por su defensa
         ((coalesce(h.encajados, 0) + k * v_media_enc) / (coalesce(h.n, 0) + k))
           * (1 - 0.3 * (greatest(coalesce(vj.defensa, 50), coalesce(vj.portero, 50)) - v_def_media) / 100)
    from convocatorias c
    left join valoracion_jugador vj on vj.liga_id = p.liga_id and vj.miembro_id = c.miembro_id
    left join lateral (
      select count(*) n, sum(aj.goles) goles,
             sum(aj.goles_encajados::numeric / greatest(1, (select count(*) from encuentros en where en.partido_id = aj.partido_id))) encajados
        from acta_jugador aj join partidos pa2 on pa2.id = aj.partido_id
       where aj.miembro_id = c.miembro_id and pa2.estado = 'cerrado' and pa2.liga_id = p.liga_id) h on true
   where c.partido_id = p_partido and c.estado = 'confirmado' and c.equipo is not null;

  for e in select en.n, en.equipo_local a, en.equipo_visitante b from encuentros en where en.partido_id = p_partido
           union all
           select 1, 1::smallint, 2::smallint where not exists (select 1 from encuentros where partido_id = p_partido)
           order by 1 loop
    -- xG = ataque del equipo × (defensa media del rival / media de la liga)
    select sum(ataque) into xa from tmp_xg where equipo = e.a;
    select sum(ataque) into xb from tmp_xg where equipo = e.b;
    xa := coalesce(xa, 0) * coalesce((select avg(defensa) from tmp_xg where equipo = e.b) / nullif(v_media_enc, 0), 1);
    xb := coalesce(xb, 0) * coalesce((select avg(defensa) from tmp_xg where equipo = e.a) / nullif(v_media_enc, 0), 1);
    xa := greatest(round(xa, 2), 0.1); xb := greatest(round(xb, 2), 0.1);

    -- Poisson independiente para cada equipo (0..30 goles)
    pa := array[exp(-xa)]; pb := array[exp(-xb)];
    for i in 1..30 loop                       -- P(i) = P(i-1) · λ / i
      pa := pa || (pa[i] * xa / i);
      pb := pb || (pb[i] * xb / i);
    end loop;
    v_gana := 0; v_emp := 0; v_pierde := 0; v_mejor := -1;
    for i in 0..30 loop
      for j in 0..30 loop
        if i > j then v_gana := v_gana + pa[i + 1] * pb[j + 1];
        elsif i = j then v_emp := v_emp + pa[i + 1] * pb[j + 1];
        else v_pierde := v_pierde + pa[i + 1] * pb[j + 1]; end if;
        if pa[i + 1] * pb[j + 1] > v_mejor then v_mejor := pa[i + 1] * pb[j + 1]; v_marc := i || '-' || j; end if;
      end loop;
    end loop;

    select coalesce(jsonb_agg(jsonb_build_object('miembro_id', t.miembro_id, 'equipo', t.equipo,
                                                 'xg', round(t.ataque * case when t.equipo = e.a
                                                   then coalesce((select avg(defensa) from tmp_xg where equipo = e.b) / nullif(v_media_enc, 0), 1)
                                                   else coalesce((select avg(defensa) from tmp_xg where equipo = e.a) / nullif(v_media_enc, 0), 1) end, 2))
                              order by t.ataque desc), '[]')
      into v_jug from tmp_xg t where t.equipo in (e.a, e.b);

    v_res := v_res || jsonb_build_object(
      'n', e.n, 'local', e.a, 'visitante', e.b, 'xg_local', xa, 'xg_visitante', xb,
      'prob_local', round(v_gana * 100), 'prob_empate', round(v_emp * 100), 'prob_visitante', round(v_pierde * 100),
      'marcador_probable', v_marc, 'jugadores', v_jug);
  end loop;

  return jsonb_build_object('encuentros', v_res, 'partidos_base', coalesce(v_part, 0),
                            'fiabilidad', case when coalesce(v_part, 0) >= 8 then 'alta'
                                               when coalesce(v_part, 0) >= 3 then 'media' else 'baja' end);
end $$;

revoke execute on function prediccion_partido(uuid) from public, anon;
grant execute on function prediccion_partido(uuid) to authenticated;
