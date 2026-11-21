-- 0043 · Mi agenda: los próximos partidos de TODAS mis ligas, con mi estado, en una sola llamada (Inicio).
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
               and ((m2.rango = 'fijo')::int > (m.rango = 'fijo')::int
                    or ((m2.rango = 'fijo') = (m.rango = 'fijo') and c2.inscrito_en < c.inscrito_en))) end,
         convocatoria_abre_en(p.id), m.rol = 'admin'
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
revoke execute on function mi_agenda(int) from public, anon;
grant execute on function mi_agenda(int) to authenticated;
