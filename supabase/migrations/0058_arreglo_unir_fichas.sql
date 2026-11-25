-- 0058 · Arreglos
--  · Unir fichas duplicadas fallaba en producción: «permission denied to set parameter session_replication_role».
--    En Supabase el propietario de las funciones (postgres) no es superusuario y no puede cambiar ese parámetro.
--    Ahora se desactivan solo los disparadores propios (no los de las claves foráneas) de las tablas afectadas,
--    dentro de la misma transacción, y se vuelven a activar al terminar.
--  · La vista v_rendimiento (security_invoker) llama a regla() con el usuario que consulta: sin permiso fallaba
--    en las ligas con historial importado («permission denied for function regla»).

grant execute on function regla(uuid, text, posicion_campo) to authenticated;

create or replace function _fusionar_miembros(p_conservar uuid, p_absorber uuid) returns int
language plpgsql security definer set search_path = public as $$
declare a miembros; c miembros; fk record; v_ctid tid; k int := 0; v_tablas text[];
begin
  select * into c from miembros where id = p_conservar for update;
  select * into a from miembros where id = p_absorber for update;
  if c.id is null or a.id is null or c.liga_id <> a.liga_id or c.id = a.id then
    raise exception 'Fichas no válidas para unir';
  end if;

  -- Tablas con referencias a miembros que tienen disparadores propios: se desactivan durante el traspaso
  -- (validaciones de partidos ya cerrados, avisos…). Las claves foráneas siguen comprobándose.
  select array_agg(distinct co.conrelid::regclass::text) into v_tablas
    from pg_constraint co
   where co.contype = 'f' and co.confrelid = 'public.miembros'::regclass
     and exists (select 1 from pg_trigger t where t.tgrelid = co.conrelid and not t.tgisinternal and t.tgenabled <> 'D');
  for i in 1 .. coalesce(array_length(v_tablas, 1), 0) loop
    execute format('alter table %s disable trigger user', v_tablas[i]);
  end loop;

  for fk in select cl.oid::regclass as tabla, att.attname as col
              from pg_constraint co
              join pg_class cl on cl.oid = co.conrelid
              join pg_attribute att on att.attrelid = co.conrelid and att.attnum = co.conkey[1]
             where co.contype = 'f' and co.confrelid = 'public.miembros'::regclass and array_length(co.conkey, 1) = 1 loop
    for v_ctid in execute format('select ctid from %s where %I = $1', fk.tabla, fk.col) using p_absorber loop
      begin
        execute format('update %s set %I = $1 where ctid = $2', fk.tabla, fk.col) using p_conservar, v_ctid;
        k := k + 1;
      exception when unique_violation or check_violation then
        null;   -- ya existe para p_conservar: se borra al eliminar p_absorber
      end;
    end loop;
  end loop;

  for i in 1 .. coalesce(array_length(v_tablas, 1), 0) loop
    execute format('alter table %s enable trigger user', v_tablas[i]);
  end loop;

  delete from miembros where id = p_absorber;   -- arrastra lo que quedó duplicado
  update miembros
     set perfil_id = coalesce(c.perfil_id, a.perfil_id),
         rol = case when 'admin' in (c.rol, a.rol) then 'admin'::rol_liga else 'jugador' end,
         estado = case when a.estado = 'activo' or c.estado = 'activo' or a.perfil_id is not null
                       then 'activo'::estado_miembro else c.estado end,
         posicion = coalesce(c.posicion, a.posicion),
         token_invitacion = null,
         unido_en = least(coalesce(c.unido_en, a.unido_en), coalesce(a.unido_en, c.unido_en))
   where id = p_conservar;
  return k;
end $$;
revoke execute on function _fusionar_miembros(uuid, uuid) from public, anon, authenticated;
