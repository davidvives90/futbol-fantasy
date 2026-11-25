import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../models_fantasy.dart';

/// Mercado Fantasy: encuesta inicial, mercado, plantillas, alineaciones y clasificación de mánagers.
/// Contrato: docs/mercado_fantasy.md §8–10 y docs/contrato_app_backend.md (migraciones 0008–0014).
class FantasyRepo {
  /// Admin: empieza el Fantasy de cero con reparto de equipos compensados (0027). Devuelve nº de mánagers.
  /// [igualar]: todos vuelven a empezar con un valor parecido (como al principio).
  static Future<int> reiniciar(String ligaId, {bool igualar = false}) async =>
      ((await sb.rpc('reiniciar_fantasy', params: {'p_liga': ligaId, 'p_igualar': igualar})) as num).toInt();

  /// Entra al Fantasy (0038): si la liga aún no había empezado, empieza ya (sin encuesta, todos con un valor
  /// parecido) y me crea el equipo con dinero y jugadores. Se puede llamar siempre.
  static Future<bool> entrar(String ligaId) async =>
      (await sb.rpc('entrar_fantasy', params: {'p_liga': ligaId})) as bool? ?? false;

  /// Resultado esperado (xG) de un partido con equipos hechos (0028). null si está desactivado.
  static Future<Map<String, dynamic>?> prediccion(String partidoId) async {
    final r = await sb.rpc('prediccion_partido', params: {'p_partido': partidoId});
    return r == null ? null : (r as Map).cast<String, dynamic>();
  }

  // ---- Mánager y plantilla --------------------------------------------------

  /// Mi ficha de mánager (saldo y puntos).
  /// Quien llega después de la encuesta no tiene fila hasta su primera operación (el backend se la crea
  /// con el presupuesto inicial en `asegurar_manager`): se muestra ese presupuesto.
  /// null = la liga aún no tiene encuesta general cerrada (no hay precios ni presupuesto).
  static Future<Manager?> miManager(String ligaId, String miembroId) async {
    final r = await sb
        .from('fantasy_managers')
        .select()
        .eq('liga_id', ligaId)
        .eq('miembro_id', miembroId)
        .maybeSingle();
    if (r != null) return Manager.fromMap(r);
    // Sin equipo todavía: se entra (y si hace falta arranca el Fantasy) sin esperar a nadie
    try {
      if (await entrar(ligaId)) {
        final r2 = await sb.from('fantasy_managers').select().eq('liga_id', ligaId).eq('miembro_id', miembroId).maybeSingle();
        if (r2 != null) return Manager.fromMap(r2);
      }
    } catch (_) {}
    final l = await sb.from('ligas').select('presupuesto_inicial').eq('id', ligaId).maybeSingle();
    final presu = toDouble(l?['presupuesto_inicial']);
    return presu == null ? null : Manager(miembroId: miembroId, saldo: presu, puntosTotales: 0);
  }

  /// `v_mi_plantilla` ya filtra por el mánager autenticado (no tiene columna manager_id).
  /// La variación de la última jornada sale de `v_mercado`.
  static Future<List<JugadorPlantilla>> miPlantilla(String ligaId) async {
    final rows = await sb.from('v_mi_plantilla').select().eq('liga_id', ligaId);
    if (rows.isEmpty) return const [];
    final ids = [for (final r in rows) r['jugador_id'] as String];
    final varRows =
        await sb.from('v_mercado').select('miembro_id, variacion').eq('liga_id', ligaId).inFilter('miembro_id', ids);
    final variacion = {for (final v in varRows) v['miembro_id'] as String: toDouble(v['variacion'])};
    return [for (final r in rows) JugadorPlantilla.fromMap({...r, 'variacion': variacion[r['jugador_id']]})];
  }

  /// Compra una ficha libre al precio de mercado (falla si no quedan: entonces cláusula u oferta).
  static Future<void> comprar(String ligaId, String jugadorId, {int? numero}) async {
    await sb.rpc('comprar_ficha', params: {'p_liga': ligaId, 'p_jugador': jugadorId, if (numero != null) 'p_numero': numero});
  }

  // ---- Fase 2 (0054) ----------------------------------------------------------

  /// Copias libres con su precio (rareza y escasez), la más barata primero.
  static Future<List<CopiaLibre>> copiasLibres(String ligaId, String jugadorId) async {
    final r = await sb.rpc('copias_libres', params: {'p_liga': ligaId, 'p_jugador': jugadorId});
    return [for (final x in (r as List? ?? const [])) CopiaLibre.fromMap(Map<String, dynamic>.from(x as Map))];
  }

  static Future<List<Subasta>> subastas(String ligaId) async {
    final r = await sb.rpc('subastas_liga', params: {'p_liga': ligaId});
    return [for (final x in (r as List? ?? const [])) Subasta.fromMap(Map<String, dynamic>.from(x as Map))];
  }

  static Future<void> pujar(String subastaId, double importe) =>
      sb.rpc('pujar', params: {'p_subasta': subastaId, 'p_importe': importe});

  static Future<void> retirarPuja(String subastaId) => sb.rpc('retirar_puja', params: {'p_subasta': subastaId});

  static Future<int> lanzarSubasta(String ligaId) async =>
      toInt(await sb.rpc('lanzar_subasta', params: {'p_liga': ligaId}));

  static Future<EstadoDraft?> draft(String ligaId) async {
    final r = await sb.rpc('estado_draft', params: {'p_liga': ligaId});
    return r == null ? null : EstadoDraft.fromMap(Map<String, dynamic>.from(r as Map));
  }

  static Future<void> iniciarDraft(String ligaId, {int? rondas}) =>
      sb.rpc('iniciar_draft', params: {'p_liga': ligaId, if (rondas != null) 'p_rondas': rondas});

  static Future<void> draftElegir(String ligaId, String jugadorId) =>
      sb.rpc('draft_elegir', params: {'p_liga': ligaId, 'p_jugador': jugadorId});

  static Future<void> draftPasar(String ligaId) => sb.rpc('draft_pasar', params: {'p_liga': ligaId});

  static Future<void> cambiarEscala(String ligaId, double valorBase) =>
      sb.rpc('cambiar_escala', params: {'p_liga': ligaId, 'p_valor_base': valorBase});

  static Future<void> fijarEventoEspecial(String partidoId, String? evento) =>
      sb.rpc('fijar_evento_especial', params: {'p_partido': partidoId, 'p_evento': evento});

  static Future<int> valorarPorHistorial(String ligaId) async =>
      toInt(await sb.rpc('valorar_por_historial', params: {'p_liga': ligaId}));

  /// Vende mi ficha al mercado (precio − comisión). Si no se conoce la ficha, usa la firma 0.1.
  static Future<void> vender(String ligaId, String jugadorId, {String? fichaId}) async {
    if (fichaId != null) {
      await sb.rpc('vender_ficha', params: {'p_ficha': fichaId});
    } else {
      await sb.rpc('vender_jugador', params: {'p_liga': ligaId, 'p_jugador': jugadorId});
    }
  }

  // ---- Fichas, cláusulas, ofertas y cesiones (0.2) --------------------------

  /// Todas las fichas de un jugador (`v_fichas_jugador`), libres primero.
  static Future<List<FichaJugador>> fichasJugador(String ligaId, String jugadorId) async {
    final rows = await sb
        .from('v_fichas_jugador')
        .select()
        .eq('liga_id', ligaId)
        .eq('jugador_id', jugadorId)
        .order('numero', ascending: true);
    return [for (final r in rows) FichaJugador.fromMap(r)];
  }

  /// Devuelve la cláusula resultante.
  static Future<double?> fijarClausula(String fichaId, double importe) async {
    final r = await sb.rpc('fijar_clausula', params: {'p_ficha': fichaId, 'p_importe': importe});
    return toDouble(r);
  }

  static Future<void> pagarClausula(String fichaId) async {
    await sb.rpc('pagar_clausula', params: {'p_ficha': fichaId});
  }

  static Future<void> hacerOferta(String fichaId, double importe) async {
    await sb.rpc('hacer_oferta', params: {'p_ficha': fichaId, 'p_importe': importe});
  }

  /// Devuelve 'aceptada' | 'rechazada' | 'caducada'.
  static Future<String?> responderOferta(String ofertaId, bool aceptar) async {
    final r = await sb.rpc('responder_oferta', params: {'p_oferta': ofertaId, 'p_aceptar': aceptar});
    return r as String?;
  }

  static Future<void> cancelarOferta(String ofertaId) async {
    await sb.rpc('cancelar_oferta', params: {'p_oferta': ofertaId});
  }

  /// Enviadas y recibidas (`v_mis_ofertas`), más recientes primero.
  static Future<List<Oferta>> misOfertas(String ligaId) async {
    final rows =
        await sb.from('v_mis_ofertas').select().eq('liga_id', ligaId).order('creada_en', ascending: false);
    return [for (final r in rows) Oferta.fromMap(r)];
  }

  /// [pct] como fracción 0–1 (entre cesion_pct_min y cesion_pct_max de la liga).
  static Future<void> ofrecerCesion(String fichaId, double pct) async {
    await sb.rpc('ofrecer_cesion', params: {'p_ficha': fichaId, 'p_pct': pct});
  }

  static Future<void> aceptarCesion(String cesionId) async {
    await sb.rpc('aceptar_cesion', params: {'p_cesion': cesionId});
  }

  static Future<void> cancelarCesion(String cesionId) async {
    await sb.rpc('cancelar_cesion', params: {'p_cesion': cesionId});
  }

  /// Cesiones ofrecidas en la liga para el próximo partido (también las mías, marcadas con es_mia).
  static Future<List<CesionDisponible>> cesionesDisponibles(String ligaId) async {
    final rows = await sb.from('v_cesiones_disponibles').select().eq('liga_id', ligaId).order('importe', ascending: true);
    return [for (final r in rows) CesionDisponible.fromMap(r)];
  }

  /// Id de la cesión que tengo ofrecida para una ficha (para poder retirarla).
  static Future<String?> miCesionOfrecida(String ligaId, String fichaId) async {
    final r = await sb
        .from('v_cesiones_disponibles')
        .select('cesion_id')
        .eq('liga_id', ligaId)
        .eq('ficha_id', fichaId)
        .maybeSingle();
    return r?['cesion_id'] as String?;
  }

  /// Bonus de rol de la liga (claves `rol_*` de reglas_puntuacion).
  static Future<Map<String, double>> reglasRol(String ligaId) async {
    final rows = await sb
        .from('reglas_puntuacion')
        .select('clave, puntos')
        .eq('liga_id', ligaId)
        .like('clave', 'rol_%');
    return {for (final r in rows) r['clave'] as String: toDouble(r['puntos']) ?? 0};
  }

  // ---- Mercado --------------------------------------------------------------

  static Future<List<JugadorMercado>> mercado(String ligaId) async {
    final rows = await sb.from('v_mercado').select().eq('liga_id', ligaId);
    return [for (final r in rows) JugadorMercado.fromMap(r)];
  }

  static Future<bool> mercadoAbierto(String ligaId) async =>
      (await sb.rpc('mercado_abierto', params: {'p_liga': ligaId})) as bool? ?? true;

  static Future<ValoracionJugador?> valoracion(String ligaId, String miembroId) async {
    final r = await sb
        .from('valoracion_jugador')
        .select()
        .eq('liga_id', ligaId)
        .eq('miembro_id', miembroId)
        .maybeSingle();
    return r == null ? null : ValoracionJugador.fromMap(r);
  }

  static Future<List<ValoracionJugador>> valoraciones(String ligaId) async {
    final rows = await sb.from('valoracion_jugador').select().eq('liga_id', ligaId);
    return [for (final r in rows) ValoracionJugador.fromMap(r)];
  }

  static Future<List<PuntoPrecio>> historialPrecios(String ligaId, String miembroId) async {
    final rows = await sb
        .from('historial_precios')
        .select('precio, rating, creado_en')
        .eq('liga_id', ligaId)
        .eq('miembro_id', miembroId)
        .order('creado_en', ascending: true);
    return [for (final r in rows) PuntoPrecio.fromMap(r)];
  }

  /// Rating 0–100 de cada jugador para el generador de equipos (`v_rating_balanceo`: rating del mercado,
  /// o el de la encuesta, o 50). Mientras no se haya cerrado ninguna encuesta todos valdrían 50, así que
  /// se devuelve vacío y el balanceo usa su fórmula de rendimiento.
  static Future<Map<String, double>> ratings(String ligaId) async {
    final rows =
        await sb.from('v_rating_balanceo').select('miembro_id, rating, rating_encuesta').eq('liga_id', ligaId);
    if (!rows.any((r) => r['rating_encuesta'] != null)) return const {};
    return {
      for (final r in rows)
        if (r['rating'] != null) r['miembro_id'] as String: toDouble(r['rating'])!,
    };
  }

  // ---- Alineación -----------------------------------------------------------

  static Future<List<Alineado>> alineacion(String partidoId, String managerId) async {
    final rows = await sb.from('alineaciones').select().eq('partido_id', partidoId).eq('manager_id', managerId);
    return [for (final r in rows) Alineado.fromMap(r)];
  }

  /// La base de datos valida tamaño (plazas / num_equipos), pertenencia a la plantilla (o cesión recibida),
  /// hora de cierre y que haya exactamente un POR. [roles] va en el mismo orden que [jugadores].
  static Future<void> guardarAlineacion(String partidoId, List<String> jugadores, List<RolAlineacion> roles,
      {String? capitan, String? ariete, List<String> suplentes = const []}) async {
    await sb.rpc('guardar_alineacion', params: {
      'p_partido': partidoId,
      'p_jugadores': jugadores,
      'p_roles': [for (final r in roles) r.name],
      'p_capitan': capitan,
      'p_ariete': ariete,
      'p_suplentes': suplentes,
    });
  }

  static Future<PuntosManager?> puntosManager(String partidoId, String managerId) async {
    final r = await sb
        .from('puntos_manager')
        .select()
        .eq('partido_id', partidoId)
        .eq('manager_id', managerId)
        .maybeSingle();
    return r == null ? null : PuntosManager.fromMap(r);
  }

  /// Última jornada liquidada de un mánager (`v_jornada_managers`), para ver su alineación desde la
  /// clasificación. Las plantillas ajenas son privadas; las alineaciones se ven desde la hora de cierre.
  static Future<PuntosManager?> ultimaJornada(String ligaId, String managerId) async {
    final r = await sb
        .from('v_jornada_managers')
        .select()
        .eq('liga_id', ligaId)
        .eq('manager_id', managerId)
        .order('fecha_hora', ascending: false)
        .limit(1)
        .maybeSingle();
    return r == null ? null : PuntosManager.fromMap(r);
  }

  /// Plantilla de cualquier mánager (desde 0.2 es visible para la liga: hace falta para pagar cláusulas).
  /// Devuelve (jugador, cláusula guardada) de sus fichas.
  static Future<List<({String jugadorId, double? clausula})>> plantillaDe(String ligaId, String managerId) async {
    final rows = await sb
        .from('plantillas')
        .select('jugador_id, clausula')
        .eq('liga_id', ligaId)
        .eq('manager_id', managerId);
    return [for (final r in rows) (jugadorId: r['jugador_id'] as String, clausula: toDouble(r['clausula']))];
  }

  // ---- Clasificación --------------------------------------------------------

  static Future<List<ClasManager>> clasificacion(String ligaId) async {
    final rows = await sb.from('v_clasificacion_managers').select().eq('liga_id', ligaId);
    final lista = [for (final r in rows) ClasManager.fromMap(r)];
    lista.sort((a, b) => (a.posicion ?? 9999).compareTo(b.posicion ?? 9999) != 0
        ? (a.posicion ?? 9999).compareTo(b.posicion ?? 9999)
        : b.puntos.compareTo(a.puntos));
    return lista;
  }

  // ---- Encuesta inicial -----------------------------------------------------

  /// Encuestas abiertas de la liga (general y mini-encuestas).
  static Future<List<Encuesta>> encuestasAbiertas(String ligaId) async {
    final rows = await sb
        .from('encuestas_valoracion')
        .select()
        .eq('liga_id', ligaId)
        .eq('estado', 'abierta')
        .order('creada_en', ascending: true);
    return [for (final r in rows) Encuesta.fromMap(r)];
  }

  /// Atributos que ya he enviado en una encuesta (mis propias respuestas son legibles).
  static Future<Set<Atributo>> atributosEnviados(String encuestaId, String evaluadorId) async {
    final rows = await sb
        .from('respuestas_ranking')
        .select('atributo')
        .eq('encuesta_id', encuestaId)
        .eq('evaluador_id', evaluadorId);
    return {
      for (final r in rows)
        ...Atributo.values.where((a) => a.name == r['atributo']),
    };
  }

  /// [orden]: ids de miembro del mejor al peor.
  static Future<void> enviarRanking(String encuestaId, Atributo atributo, List<String> orden) async {
    await sb.rpc('enviar_ranking', params: {
      'p_encuesta': encuestaId,
      'p_atributo': atributo.name,
      'p_orden': orden,
    });
  }

  /// [sujetoId] null = encuesta general; un miembro = mini-encuesta para un jugador nuevo.
  static Future<void> abrirEncuesta(String ligaId, {String? sujetoId}) async {
    await sb.rpc('abrir_encuesta', params: {'p_liga': ligaId, if (sujetoId != null) 'p_sujeto': sujetoId});
  }

  static Future<void> cerrarEncuesta(String encuestaId) async {
    await sb.rpc('cerrar_encuesta', params: {'p_encuesta': encuestaId});
  }

  /// Progreso de una encuesta (`v_progreso_encuesta`): mánagers que han enviado los 6 rankings y total
  /// de mánagers activos. null si no se puede leer.
  static Future<({int completadas, int managers})?> progresoEncuesta(String encuestaId) async {
    try {
      final r = await sb
          .from('v_progreso_encuesta')
          .select('completadas, managers')
          .eq('encuesta_id', encuestaId)
          .maybeSingle();
      if (r == null) return null;
      return (completadas: toInt(r['completadas']), managers: toInt(r['managers']));
    } catch (_) {
      return null;
    }
  }

  /// 0053: crea los equipos Fantasy de los jugadores indicados (null = todos los registrados activos).
  static Future<int> crearManagers(String ligaId, [List<String>? miembros]) async =>
      toInt(await sb.rpc('crear_managers', params: {'p_liga': ligaId, 'p_miembros': miembros}));
}
