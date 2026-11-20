import '../../core/supabase.dart';
import '../models.dart';

class StatsRepo {
  static Future<List<Rendimiento>> rendimiento(String ligaId) async {
    final rows = await sb.from('v_rendimiento').select().eq('liga_id', ligaId);
    return [for (final r in rows) Rendimiento.fromMap(r)];
  }

  /// Historial de puntos de un miembro, del más reciente al más antiguo.
  static Future<List<PuntosFantasy>> historial(String miembroId) async {
    final rows = await sb.from('puntos_fantasy').select('*, partido:partidos!puntos_fantasy_partido_id_fkey(fecha_hora)').eq('miembro_id', miembroId);
    final lista = [for (final r in rows) PuntosFantasy.fromMap(r)];
    lista.sort((a, b) => (b.fecha ?? DateTime(0)).compareTo(a.fecha ?? DateTime(0)));
    return lista;
  }

  /// Forma, rachas, compañeros, rival más duro, destacados… (RPC estadisticas_jugador).
  static Future<Map<String, dynamic>> jugador(String miembroId) async =>
      Map<String, dynamic>.from(await sb.rpc('estadisticas_jugador', params: {'p_miembro': miembroId}) as Map);

  /// Récords y curiosidades de la liga (RPC estadisticas_liga).
  static Future<Map<String, dynamic>> liga(String ligaId) async =>
      Map<String, dynamic>.from(await sb.rpc('estadisticas_liga', params: {'p_liga': ligaId}) as Map);
}
