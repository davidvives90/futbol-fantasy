-- 0035 · Revisión técnica (avisos del analizador de Supabase).

-- 1) RLS: auth.uid() evaluado una vez por consulta, no por fila
alter policy perfil_crear on perfiles with check (id = (select auth.uid()));
alter policy perfil_editar on perfiles using (id = (select auth.uid())) with check (id = (select auth.uid()));
alter policy perfil_leer on perfiles using (id = (select auth.uid()) or comparte_liga(id));
alter policy liga_leer on ligas using (
  visibilidad = 'publica'::visibilidad_liga or es_miembro(id)
  or exists (select 1 from miembros m where m.liga_id = ligas.id and m.perfil_id = (select auth.uid())
                                       and m.estado = 'solicitud'::estado_miembro));
alter policy miembro_leer on miembros using (perfil_id = (select auth.uid()) or es_miembro(liga_id));
alter policy miembro_posicion on miembros using (perfil_id = (select auth.uid()) or es_admin(liga_id))
  with check (perfil_id = (select auth.uid()) or es_admin(liga_id));
alter policy notif_propias on notificaciones using (perfil_id = (select auth.uid()));

-- 2) search_path fijo
alter function modalidad_por_jugadores(int) set search_path = public;

-- 3) Índices para todas las claves foráneas que no tienen uno (borrados en cascada y joins más rápidos)
do $$
declare r record; v_nombre text;
begin
  for r in
    select c.conrelid::regclass as tabla, c.conname,
           string_agg(quote_ident(a.attname), ', ' order by k.ord) as columnas
      from pg_constraint c
      cross join lateral unnest(c.conkey) with ordinality k(attnum, ord)
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
     where c.contype = 'f' and c.connamespace = 'public'::regnamespace
       and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1])
     group by c.conrelid, c.conname
  loop
    v_nombre := left(r.conname, 58) || '_ix';
    execute format('create index if not exists %I on %s (%s)', v_nombre, r.tabla, r.columnas);
  end loop;
end $$;

-- 4) Funciones internas: solo las usan otras funciones del servidor, no la app
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.prosecdef
              and p.proname in ('jugadores_liga', 'precio_base', 'regla', 'num_admins', 'plazas_reservadas_fijos',
                                'clausula_efectiva', 'es_no_habitual', 'comprar_jugador', 'convocatoria_abre_en',
                                'exigir_admin', 'esta_de_baja')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
end $$;

-- 5) Vistas: nada para usuarios sin sesión
do $$
declare v record;
begin
  for v in select c.oid::regclass as vista from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'v' loop
    execute format('revoke all on %s from anon', v.vista);
  end loop;
end $$;
