-- 0039 · Más sencillo
--  · Cesiones opcionales: desactivadas por defecto (las cláusulas se mantienen).
--  · Alineación automática: quien no alinea juega con la anterior o, si no hay, con sus mejores jugadores.

alter table ligas add column if not exists cesiones_activas boolean not null default false;

create or replace function exigir_cesiones_activas() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not coalesce((select cesiones_activas from ligas where id = new.liga_id), false) then
    raise exception 'Las cesiones están desactivadas en esta liga (el admin puede activarlas en Ajustes Fantasy)';
  end if;
  return new;
end $$;
drop trigger if exists t_cesiones_activas on cesiones;
create trigger t_cesiones_activas before insert on cesiones
  for each row execute function exigir_cesiones_activas();
revoke execute on function exigir_cesiones_activas() from public, anon, authenticated;

create or replace function congelar_alineaciones(p_partido uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_tam int; fm record; v_prev uuid;
begin
  select * into p from partidos where id = p_partido for update;
  if p.alineaciones_congeladas or p.estado = 'cancelado' then return false; end if;
  if now() < hora_cierre_alineacion(p_partido) and p.estado not in ('jugado', 'post_partido', 'en_revision', 'cerrado') then
    return false;
  end if;
  select * into l from ligas where id = p.liga_id;
  v_tam := p.plazas / p.num_equipos;

  -- Se cierra el mercado: cesiones sin aceptar de este partido se retiran y las ofertas pendientes caducan
  update cesiones set estado = 'cancelada' where partido_id = p_partido and estado = 'ofrecida';
  update ofertas set estado = 'caducada', resuelta_en = now() where liga_id = p.liga_id and estado = 'pendiente';

  for fm in select miembro_id from fantasy_managers where liga_id = p.liga_id loop
    if not exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id) then
      select a.partido_id into v_prev
        from alineaciones a join partidos pp on pp.id = a.partido_id
       where a.manager_id = fm.miembro_id and pp.liga_id = p.liga_id and pp.fecha_hora < p.fecha_hora
       order by pp.fecha_hora desc limit 1;
      if v_prev is not null then
        -- Solo jugadores que siguen siendo suyos y que no ha cedido para este partido; se conservan los roles
        insert into alineaciones (partido_id, manager_id, jugador_id, rol, copiada)
        select p_partido, fm.miembro_id, a.jugador_id, a.rol, true
          from alineaciones a
          join fichas f on f.propietario_id = a.manager_id and f.jugador_id = a.jugador_id
         where a.partido_id = v_prev and a.manager_id = fm.miembro_id
           and not exists (select 1 from cesiones c where c.ficha_id = f.id and c.estado = 'aceptada')
         order by (a.rol = 'POR') desc, a.jugador_id
         limit v_tam;
      end if;
      -- Alineación automática: si no ha alineado (o le faltan jugadores), juega con sus mejores jugadores
      insert into alineaciones (partido_id, manager_id, jugador_id, rol, copiada)
      select p_partido, fm.miembro_id, x.jugador_id, 'MED', true
        from (select distinct on (f.jugador_id) f.jugador_id, coalesce(mj.precio, 0) precio
                from fichas f
                left join mercado_jugador mj on mj.liga_id = p.liga_id and mj.miembro_id = f.jugador_id
               where f.liga_id = p.liga_id and f.propietario_id = fm.miembro_id
                 and not exists (select 1 from cesiones c where c.ficha_id = f.id and c.estado = 'aceptada')
                 and not exists (select 1 from alineaciones a2 where a2.partido_id = p_partido
                                    and a2.manager_id = fm.miembro_id and a2.jugador_id = f.jugador_id)
               order by f.jugador_id) x
       order by x.precio desc, x.jugador_id
       limit greatest(0, v_tam - (select count(*) from alineaciones
                                   where partido_id = p_partido and manager_id = fm.miembro_id));
      -- Siempre un portero: el que juegue de portero si lo hay; si no, el primero
      if exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id)
         and not exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id
                                                       and rol = 'POR') then
        update alineaciones set rol = 'POR'
         where partido_id = p_partido and manager_id = fm.miembro_id
           and jugador_id = (select a3.jugador_id from alineaciones a3
                              left join miembros mm on mm.id = a3.jugador_id
                              left join perfiles pf on pf.id = mm.perfil_id
                              where a3.partido_id = p_partido and a3.manager_id = fm.miembro_id
                              order by (coalesce(mm.posicion, pf.posicion)::text = 'portero') desc nulls last,
                                       a3.jugador_id limit 1);
      end if;
    end if;
  end loop;

  update alineaciones a
     set no_habitual = coalesce(mj.no_habitual, false),
         multiplicador = case when coalesce(mj.no_habitual, false) then l.bonus_no_habitual else 1 end
    from mercado_jugador mj
   where a.partido_id = p_partido and mj.liga_id = p.liga_id and mj.miembro_id = a.jugador_id;
  update alineaciones set no_habitual = false, multiplicador = 1
   where partido_id = p_partido and multiplicador is null;

  update partidos set alineaciones_congeladas = true where id = p_partido;
  return true;
end $$;
