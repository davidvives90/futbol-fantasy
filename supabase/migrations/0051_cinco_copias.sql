-- 0051 · 5 copias de cada jugador (antes: fórmula que daba 7 o más)
--  · Cada jugador tiene 5 copias. Comprar una copia libre no afecta a nadie; pagar la cláusula de la copia de
--    otro mánager se la quita (eso ya lo hacía pagar_clausula).
--  · Solo se pasa de 5 si hace falta para el reparto inicial (más mánagers que jugadores).
--  · Las copias libres que sobran se borran; las que tienen dueño nunca se tocan.

create or replace function copias_formula(p_liga uuid) returns int
language sql stable security definer set search_path = public as $$
  select greatest(5, ceil(
           greatest((select count(*) from fantasy_managers fm join miembros m on m.id = fm.miembro_id
                      where fm.liga_id = p_liga and m.estado = 'activo'),
                    (select count(*) from miembros where liga_id = p_liga and estado in ('activo', 'pendiente_registro')))::numeric
           * least((select reparto_inicial from ligas where id = p_liga),
                   (select max_plantilla from ligas where id = p_liga))
           / nullif((select count(*) from mercado_jugador mj where mj.liga_id = p_liga
                      and mj.miembro_id in (select jugadores_liga(p_liga))), 0)))::int
$$;

-- Ajusta las copias (sube o baja) y crea las que falten. Idempotente.
create or replace function asegurar_fichas(p_liga uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_c int;
begin
  v_c := coalesce(copias_formula(p_liga), 5);
  update ligas set copias_por_jugador = v_c where id = p_liga and copias_por_jugador <> v_c;
  delete from fichas where liga_id = p_liga and numero > v_c and propietario_id is null;
  insert into fichas (liga_id, jugador_id, numero)
  select mj.liga_id, mj.miembro_id, n
    from mercado_jugador mj cross join generate_series(1, v_c) n
   where mj.liga_id = p_liga
  on conflict (liga_id, jugador_id, numero) do nothing;
  return v_c;
end $$;

revoke execute on function copias_formula(uuid), asegurar_fichas(uuid) from public, anon, authenticated;

alter table ligas alter column copias_por_jugador set default 5;
select asegurar_fichas(l.id) from ligas l where exists (select 1 from mercado_jugador where liga_id = l.id);
