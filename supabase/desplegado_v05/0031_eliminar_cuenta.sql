-- 0031 · Eliminar mi cuenta (requisito de Google Play) y limpieza del registro de errores.
-- El historial de partidos se conserva: cada membresía pasa a «Exjugador» anónimo y abandonada,
-- y al borrar el usuario de auth el perfil desaparece (miembros.perfil_id → null).
create or replace function eliminar_mi_cuenta(p_confirmacion text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); r record;
begin
  if v_uid is null then raise exception 'Sesión no válida'; end if;
  if p_confirmacion is distinct from 'ELIMINAR' then raise exception 'Escribe ELIMINAR para confirmar'; end if;
  if exists (select 1 from masters where perfil_id = v_uid) then
    raise exception 'Una cuenta máster no se puede eliminar desde la app';
  end if;
  -- no dejar ligas activas sin administrador
  for r in select m.liga_id, l.nombre from miembros m join ligas l on l.id = m.liga_id
            where m.perfil_id = v_uid and m.rol = 'admin' and m.estado = 'activo' loop
    if not exists (select 1 from miembros o where o.liga_id = r.liga_id and o.rol = 'admin' and o.estado = 'activo'
                     and o.perfil_id is distinct from v_uid)
       and exists (select 1 from miembros o where o.liga_id = r.liga_id and o.estado = 'activo'
                     and o.perfil_id is distinct from v_uid) then
      raise exception 'Eres el único administrador de «%»: nombra otro administrador antes de eliminar tu cuenta', r.nombre;
    end if;
  end loop;

  update miembros set nombre_provisional = 'Exjugador', contacto = null,
         estado = case when estado = 'activo' then 'abandonado'::estado_miembro else estado end
   where perfil_id = v_uid;
  delete from errores_app where perfil_id = v_uid;
  delete from auth.users where id = v_uid;
end $$;

revoke execute on function eliminar_mi_cuenta(text) from public, anon;
grant execute on function eliminar_mi_cuenta(text) to authenticated;
