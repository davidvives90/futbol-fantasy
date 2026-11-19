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

  /// Envía el parte completo: resultados, estadísticas y valoraciones.
  /// [valoraciones]: votadoId → aspecto → nota (1..10).
  static Future<void> enviar({
    required String partidoId,
    required String reporteroId,
    required List<ReporteEncuentro> encuentros,
    required List<ReporteJugador> jugadores,
    required Map<String, Map<String, int>> valoraciones,
  }) async {
    await sb.from('reportes_encuentro').upsert([
      for (final e in encuentros)
        {
          'partido_id': partidoId,
          'reportero_id': reporteroId,
          'n': e.n, // los equipos de cada encuentro los fija el admin; aquí solo el marcador
          'goles_local': e.golesLocal,
          'goles_visitante': e.golesVisitante,
        }
    ]);

    final filas = [
      for (final j in jugadores.where((j) => !j.noSe))
        {
          'partido_id': partidoId,
          'reportero_id': reporteroId,
          'sujeto_id': j.sujetoId,
          'goles': j.goles,
          'asistencias': j.asistencias,
          'autogoles': j.autogoles,
          'paradas_clave': j.paradasClave,
          'penaltis_parados': j.penaltisParados,
          'penaltis_fallados': j.penaltisFallados,
        }
    ];
    if (filas.isNotEmpty) await sb.from('reportes_jugador').upsert(filas);

    final notas = [
      for (final v in valoraciones.entries)
        for (final a in v.value.entries)
          {
            'partido_id': partidoId,
            'votante_id': reporteroId,
            'votado_id': v.key,
            'aspecto': a.key,
            'nota': a.value,
          }
    ];
    if (notas.isNotEmpty) await sb.from('valoraciones').upsert(notas);
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
