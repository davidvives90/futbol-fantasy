-- 0019 · v0.3 · Seguridad: temporadas, v_mvps y permisos de las funciones nuevas o reemplazadas
-- (en Supabase las funciones nuevas reciben EXECUTE por defecto para authenticated; aquí se ajusta)

alter table temporadas enable row level security;
revoke all on temporadas from anon, public, authenticated;
grant select on temporadas to authenticated;
create policy temporadas_leer on temporadas for select to authenticated using (es_miembro(liga_id));
-- altas y cancelaciones: programar_temporada / cancelar_temporada

revoke all on v_mvps from anon, public, authenticated;
grant select on v_mvps to authenticated;

-- miembros tiene permisos por columna (0006): la app lee el rango; se cambia solo con cambiar_rango
grant select (rango) on miembros to authenticated;

revoke execute on function
  prioridad_espera(uuid, rango_jugador), gestionar_cupo(), proteger_rango_conv(), promover_espera(),
  inscribir_fijos(uuid), tras_crear_partido(), es_no_habitual(uuid), refrescar_no_habitual(uuid),
  alta_jugador_mercado(), cambiar_rango(uuid, text), crear_liga(jsonb),
  precrear_jugadores(uuid, text[], text[], text),
  programar_temporada(uuid, date, date, smallint[], time, boolean, numeric, date[], text),
  cancelar_temporada(uuid, date), cambiar_hora_partido(uuid, timestamptz, boolean),
  generar_cargos(uuid), calculo_factura(uuid), simular_factura(uuid), liquidar_factura(uuid),
  comprobar_descuadres(uuid), consolidar_acta(uuid), resolver_disputa(uuid, smallint),
  fijar_dato(uuid, uuid, smallint, text, smallint), revisar_descuadres(uuid), enviar_parte(uuid, jsonb, jsonb)
  from public, anon;

-- Internas (triggers y piezas de cálculo)
revoke execute on function
  prioridad_espera(uuid, rango_jugador), gestionar_cupo(), proteger_rango_conv(), promover_espera(),
  inscribir_fijos(uuid), tras_crear_partido(), refrescar_no_habitual(uuid), alta_jugador_mercado(),
  calculo_factura(uuid), comprobar_descuadres(uuid), consolidar_acta(uuid)
  from authenticated;

-- RPC de la app
grant execute on function
  cambiar_rango(uuid, text), crear_liga(jsonb), precrear_jugadores(uuid, text[], text[], text),
  programar_temporada(uuid, date, date, smallint[], time, boolean, numeric, date[], text),
  cancelar_temporada(uuid, date), cambiar_hora_partido(uuid, timestamptz, boolean),
  generar_cargos(uuid), simular_factura(uuid), liquidar_factura(uuid),
  resolver_disputa(uuid, smallint), fijar_dato(uuid, uuid, smallint, text, smallint),
  revisar_descuadres(uuid), enviar_parte(uuid, jsonb, jsonb), es_no_habitual(uuid)
  to authenticated;
