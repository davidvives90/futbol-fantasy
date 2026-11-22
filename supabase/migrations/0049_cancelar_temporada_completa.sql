-- 0049 · Cancelar temporada: incluye los partidos futuros que quedaron en estado 'cerrado'
--  · Antes solo se cancelaban abierto / completo / equipos_hechos. Un partido con fecha futura en estado
--    'cerrado' no se ha jugado, así que también se cancela. Los jugados o en revisión no se tocan.

create or replace function cancelar_temporada(p_temporada uuid, p_desde date default current_date) returns int
language plpgsql security definer set search_path = public as $$
declare t temporadas; k int;
begin
  select * into t from temporadas where id = p_temporada;
  if not found then raise exception 'Temporada no encontrada'; end if;
  perform exigir_admin(t.liga_id);
  update partidos set estado = 'cancelado'
   where temporada_id = p_temporada
     and (fecha_hora at time zone 'Europe/Madrid')::date >= coalesce(p_desde, current_date)
     and (estado in ('abierto', 'completo', 'equipos_hechos')
          or (estado = 'cerrado' and fecha_hora > now()));
  get diagnostics k = row_count;
  return k;
end $$;
