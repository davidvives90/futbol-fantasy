import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../models_fantasy.dart';

/// Mercado Fantasy: encuesta inicial, mercado, plantillas, alineaciones y clasificación de mánagers.
/// Contrato: docs/mercado_fantasy.md §8 (migración 0008_mercado_fantasy.sql).
class FantasyRepo {
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

  static Future<void> comprar(String ligaId, String jugadorId) async {
    await sb.rpc('comprar_jugador', params: {'p_liga': ligaId, 'p_jugador': jugadorId});
  }

  static Future<void> vender(String ligaId, String jugadorId) async {
    await sb.rpc('vender_jugador', params: {'p_liga': ligaId, 'p_jugador': jugadorId});
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
        .order('creado_en');
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

  /// La base de datos valida tamaño (plazas / num_equipos), pertenencia a la plantilla y hora de cierre.
  static Future<void> guardarAlineacion(String partidoId, List<String> jugadores) async {
    await sb.rpc('guardar_alineacion', params: {'p_partido': partidoId, 'p_jugadores': jugadores});
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
        .order('creada_en');
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
}
