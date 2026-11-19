import '../../core/supabase.dart';
import '../models.dart';

/// Lo que un asistente declara sobre un encuentro.
class ReporteEncuentro {
  ReporteEncuentro({
    required this.n,
    required this.equipoLocal,
    required this.equipoVisitante,
    this.golesLocal = 0,
    this.golesVisitante = 0,
  });
  int n, equipoLocal, equipoVisitante, golesLocal, golesVisitante;
}

/// Lo que un asistente declara sobre las estadísticas de un jugador.
/// Si [noSe] es true no se envía la fila (no cuenta para el consenso).
class ReporteJugador {
  ReporteJugador(this.sujetoId);
  final String sujetoId;
  bool noSe = false;
  int goles = 0, asistencias = 0, autogoles = 0;
  // La portería a cero no se reporta: se deduce del resultado consolidado.
  int paradasClave = 0, penaltisParados = 0, penaltisFallados = 0;
}

class PostPartidoRepo {
  /// ¿Ha enviado ya este miembro su parte del partido?
  static Future<bool> yaEnviado(String partidoId, String miembroId) async {
    final r = await sb
        .from('reportes_encuentro')
        .select('n')
        .eq('partido_id', partidoId)
        .eq('reportero_id', miembroId)
        .limit(1);
    return r.isNotEmpty;
  }

  /// v0.3b: envía parte + notas + destacados + voto MVP en UNA llamada atómica (`enviar_post_partido`).
  /// [jugadores]: filas del parte (sin las de equipos marcados «No me fijé»; null en un campo = no sé).
  /// [notas]: [{votado_id, nota | aspectos, destacados}]. Sustituye todo lo que este jugador enviara antes.
  static Future<void> enviarPostPartido({
    required String partidoId,
    required List<Map<String, dynamic>> resultados,
    required List<Map<String, dynamic>> jugadores,
    required List<Map<String, dynamic>> notas,
    String? mvp,
  }) async {
    await sb.rpc('enviar_post_partido', params: {
      'p_partido': partidoId,
      'p_resultados': resultados,
      'p_jugadores': jugadores,
      'p_notas': notas,
      'p_mvp': mvp,
    });
  }

  /// Lo que este jugador ya envió (solo lo suyo), para reabrir y corregir.
  static Future<Map<String, dynamic>> miPostPartido(String partidoId) async {
    final r = await sb.rpc('mi_post_partido', params: {'p_partido': partidoId});
    return (r as Map).cast<String, dynamic>();
  }

  /// Número de asistentes que ya han enviado su parte (sin revelar qué han puesto).
  static Future<int> numReportes(String partidoId) async {
    final r = await sb
        .from('v_progreso_post_partido')
        .select('partes_resultado')
        .eq('partido_id', partidoId)
        .maybeSingle();
    return (r?['partes_resultado'] as num?)?.toInt() ?? 0;
  }

  static Future<List<Disputa>> disputas(String partidoId) async {
    final rows = await sb.from('disputas').select().eq('partido_id', partidoId).order('resuelta');
    return [for (final r in rows) Disputa.fromMap(r)];
  }

  /// Devuelve el nuevo estado del partido (`cerrado` si era la última disputa).
  static Future<String> resolverDisputa(String disputaId, int valor) async =>
      (await sb.rpc('resolver_disputa', params: {'p_disputa': disputaId, 'p_valor': valor})).toString();

  /// v0.3, admin: fija el valor de un dato del acta (goles de un jugador [sujetoId], o el marcador de un
  /// encuentro [n] con campo goles_local / goles_visitante). Después el backend vuelve a comprobar los
  /// descuadres; uno se cierra solo cuando la suma de goles cuadra con el resultado.
  static Future<void> fijarDato({
    required String partidoId,
    String? sujetoId,
    int? n,
    required String campo,
    required int valor,
  }) async {
    await sb.rpc('fijar_dato', params: {
      'p_partido': partidoId,
      'p_sujeto': sujetoId,
      'p_n': n,
      'p_campo': campo,
      'p_valor': valor,
    });
  }

  static Future<List<PuntosFantasy>> puntos(String partidoId) async {
    final rows = await sb.from('puntos_fantasy').select().eq('partido_id', partidoId).order('total', ascending: false);
    return [for (final r in rows) PuntosFantasy.fromMap(r)];
  }

  /// Acta consolidada: miembroId → fila de acta_jugador.
  static Future<Map<String, Map<String, dynamic>>> acta(String partidoId) async {
    final rows = await sb.from('acta_jugador').select().eq('partido_id', partidoId);
    return {for (final r in rows) r['miembro_id'] as String: r};
  }
}
