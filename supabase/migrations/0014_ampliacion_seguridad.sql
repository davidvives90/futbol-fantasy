-- 0014 · Seguridad de la ampliación 0.2 (fichas, ofertas, cesiones, roles)
-- Decisiones:
--  · fichas: dueños y cláusulas visibles para toda la liga (hace falta para poder clausular). Con eso las
--    plantillas dejan de ser privadas: la vista `plantillas` (security_invoker) muestra las de todos.
--  · ofertas: solo las ven comprador y vendedor (también vía v_mis_ofertas).
--  · cesiones: visibles para toda la liga (las ofrecidas son públicas por diseño).
--  · Todas las escrituras pasan por funciones security definer: no hay políticas de insert/update/delete.
--  · En Supabase las funciones y tablas nuevas reciben permisos por defecto: aquí se revocan explícitamente
--    y se conceden solo las RPC que usa la app.

alter table fichas   enable row level security;
alter table ofertas  enable row level security;
alter table cesiones enable row level security;

revoke all on fichas, ofertas, cesiones from anon, public, authenticated;
grant select on fichas, ofertas, cesiones to authenticated;

create policy fichas_leer   on fichas   for select to authenticated using (es_miembro(liga_id));
create policy ofertas_leer  on ofertas  for select to authenticated
  using (mi_miembro(liga_id) in (comprador_id, vendedor_id));
create policy cesiones_leer on cesiones for select to authenticated using (es_miembro(liga_id));

-- Vistas recreadas o nuevas
revoke all on plantillas, v_mercado, v_mi_plantilla, v_clasificacion_managers, v_fichas_jugador,
              v_mis_ofertas, v_cesiones_disponibles from anon, public, authenticated;
grant select on plantillas, v_mercado, v_mi_plantilla, v_clasificacion_managers, v_fichas_jugador,
                v_mis_ofertas, v_cesiones_disponibles to authenticated;

-- ───────────── Funciones ─────────────
revoke execute on function
  media_general(posicion_campo, numeric, numeric, numeric, numeric, numeric, numeric),
  sembrar_liga_defecto(uuid), calcular_puntos(uuid),
  copias_formula(uuid), asegurar_fichas(uuid), tras_alta_fichas(),
  mover_saldo(uuid, uuid, numeric, text, uuid, uuid), proximo_partido(uuid), precio_actual(uuid),
  clausula_efectiva(uuid), no_habituales_de(uuid, uuid, uuid), validar_hueco(uuid, uuid, uuid),
  ficha_cedida(uuid), soltar_ficha(uuid), transferir_ficha(uuid, uuid, numeric), exigir_mercado_abierto(uuid),
  comprar_ficha(uuid, uuid), vender_ficha(uuid), comprar_jugador(uuid, uuid), vender_jugador(uuid, uuid),
  fijar_clausula(uuid, numeric), pagar_clausula(uuid),
  caducar_ofertas(uuid), hacer_oferta(uuid, numeric), responder_oferta(uuid, boolean), cancelar_oferta(uuid),
  ofrecer_cesion(uuid, numeric), aceptar_cesion(uuid), cancelar_cesion(uuid),
  guardar_alineacion(uuid, uuid[], text[]), congelar_alineaciones(uuid), bonus_rol(uuid, uuid, text),
  recalcular_precios(uuid, uuid), liquidar_jornada(uuid)
  from public, anon;

-- Internas: dinero, traspasos, triggers y piezas de cálculo. Nunca desde la app.
revoke execute on function
  media_general(posicion_campo, numeric, numeric, numeric, numeric, numeric, numeric),
  sembrar_liga_defecto(uuid),
  copias_formula(uuid), asegurar_fichas(uuid), tras_alta_fichas(),
  mover_saldo(uuid, uuid, numeric, text, uuid, uuid), proximo_partido(uuid),
  no_habituales_de(uuid, uuid, uuid), validar_hueco(uuid, uuid, uuid),
  soltar_ficha(uuid), transferir_ficha(uuid, uuid, numeric), exigir_mercado_abierto(uuid),
  caducar_ofertas(uuid), congelar_alineaciones(uuid), bonus_rol(uuid, uuid, text)
  from authenticated;

-- RPC de la app y ayudantes que leen las vistas con el rol del usuario
grant execute on function
  calcular_puntos(uuid),
  comprar_ficha(uuid, uuid), vender_ficha(uuid), comprar_jugador(uuid, uuid), vender_jugador(uuid, uuid),
  fijar_clausula(uuid, numeric), pagar_clausula(uuid),
  hacer_oferta(uuid, numeric), responder_oferta(uuid, boolean), cancelar_oferta(uuid),
  ofrecer_cesion(uuid, numeric), aceptar_cesion(uuid), cancelar_cesion(uuid),
  guardar_alineacion(uuid, uuid[], text[]), recalcular_precios(uuid, uuid), liquidar_jornada(uuid),
  ficha_cedida(uuid), precio_actual(uuid), clausula_efectiva(uuid)
  to authenticated;
