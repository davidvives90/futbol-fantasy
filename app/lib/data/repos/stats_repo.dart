import '../../core/supabase.dart';
import '../models.dart';

class StatsRepo {
  static Future<List<Rendimiento>> rendimiento(String ligaId) async {
    final rows = await sb.from('v_rendimiento').select().eq('liga_id', ligaId);
    return [for (final r in rows) Rendimiento.fromMap(r)];
  }

  /// Historial de puntos de un miembro, del más reciente al más antiguo.
  static Future<List<PuntosFantasy>> historial(String miembroId) async {
    final rows = await sb.from('puntos_fantasy').select('*, partido:partidos(fecha_hora)').eq('miembro_id', miembroId);
    final lista = [for (final r in rows) PuntosFantasy.fromMap(r)];
    lista.sort((a, b) => (b.fecha ?? DateTime(0)).compareTo(a.fecha ?? DateTime(0)));
    return lista;
  }
}
