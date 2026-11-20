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

  /// Clasificación de un periodo (temporada en curso: desde el cierre de la anterior).
  static Future<List<Rendimiento>> rendimientoPeriodo(String ligaId, {DateTime? desde}) async {
    final rows = await sb.rpc('rendimiento_periodo',
        params: {'p_liga': ligaId, 'p_desde': desde?.toUtc().toIso8601String(), 'p_hasta': null});
    return [for (final r in (rows as List)) Rendimiento.fromMap(Map<String, dynamic>.from(r as Map))];
  }

  static Future<List<TemporadaCerrada>> temporadas(String ligaId) async {
    final rows = await sb.from('temporadas_cerradas').select().eq('liga_id', ligaId).order('numero', ascending: false);
    final premios = await sb.from('premios').select().eq('liga_id', ligaId);
    return [
      for (final r in rows)
        TemporadaCerrada(r, [for (final p in premios) if (p['temporada_id'] == r['id']) Premio(p)]),
    ];
  }

  static Future<List<Premio>> premiosDe(String miembroId) async {
    final rows = await sb.from('premios').select('*, temporada:temporadas_cerradas(nombre)').eq('miembro_id', miembroId);
    return [for (final r in rows) Premio(r)];
  }

  static Future<List<Map<String, dynamic>>> logrosDe(String miembroId) async =>
      List<Map<String, dynamic>>.from(
          await sb.from('logros').select().eq('miembro_id', miembroId).order('conseguido_en', ascending: false));

  static Future<void> cerrarTemporada(String ligaId, String? nombre) =>
      sb.rpc('cerrar_temporada', params: {'p_liga': ligaId, 'p_nombre': nombre});

  static Future<void> reabrirTemporada(String ligaId) => sb.rpc('reabrir_temporada', params: {'p_liga': ligaId});
}

class TemporadaCerrada {
  TemporadaCerrada(this.m, this.premios);
  final Map<String, dynamic> m;
  final List<Premio> premios;
  String get id => m['id'] as String;
  String get nombre => m['nombre'] as String;
  int get numero => (m['numero'] as num).toInt();
  int get partidos => (m['partidos'] as num?)?.toInt() ?? 0;
  DateTime get desde => DateTime.parse(m['desde'] as String).toLocal();
  DateTime get hasta => DateTime.parse(m['hasta'] as String).toLocal();
  List<Rendimiento> get clasificacion =>
      [for (final r in (m['clasificacion'] as List? ?? const [])) Rendimiento.fromMap(Map<String, dynamic>.from(r as Map))];
}

class Premio {
  Premio(this.m);
  final Map<String, dynamic> m;
  String get tipo => m['tipo'] as String;
  String get miembroId => m['miembro_id'] as String;
  num? get valor => m['valor'] as num?;
  String? get temporada => (m['temporada'] as Map?)?['nombre'] as String?;
  ({String icono, String titulo, String Function(num?) dato}) get info => premiosInfo[tipo] ??
      (icono: '🏅', titulo: tipo, dato: (v) => '${v ?? ''}');
}

String _n(num? v) => v == null ? '' : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

final premiosInfo = <String, ({String icono, String titulo, String Function(num?) dato})>{
  'campeon': (icono: '🏆', titulo: 'Campeón', dato: (v) => '${_n(v)} pts'),
  'pichichi': (icono: '⚽', titulo: 'Pichichi', dato: (v) => '${_n(v)} goles'),
  'asistente': (icono: '🎯', titulo: 'Máximo asistente', dato: (v) => '${_n(v)} asistencias'),
  'mvp': (icono: '⭐', titulo: 'Más MVPs', dato: (v) => '${_n(v)} MVP'),
  'fiel': (icono: '🛡️', titulo: 'El más fiel', dato: (v) => '${_n(v)} partidos'),
  'mejor_nota': (icono: '📈', titulo: 'Mejor nota', dato: (v) => v == null ? '' : 'nota ${v.toStringAsFixed(1)}'),
  'ganador': (icono: '🥇', titulo: 'Más ganador', dato: (v) => '${_n(v)} % victorias'),
};

/// Insignias: icono y nombre de cada logro (el servidor decide cuándo se consigue).
const logrosInfo = <String, (String, String)>{
  'primer_gol': ('⚽', 'Primer gol'),
  'hat_trick': ('🎩', 'Hat-trick'),
  'manita': ('🖐️', 'Manita'),
  'goles_10': ('🔟', '10 goles'),
  'goles_25': ('🎯', '25 goles'),
  'goles_50': ('💥', '50 goles'),
  'goles_100': ('👑', '100 goles'),
  'mvp_1': ('⭐', 'Primer MVP'),
  'mvp_5': ('🌟', '5 MVPs'),
  'mvp_10': ('💫', '10 MVPs'),
  'partidos_10': ('👟', '10 partidos'),
  'partidos_25': ('🏃', '25 partidos'),
  'partidos_50': ('🎖️', '50 partidos'),
  'partidos_100': ('🏛️', '100 partidos'),
  'racha_10': ('🔥', '10 seguidos sin faltar'),
  'invicto_5': ('🛡️', '5 sin perder'),
  'muro_5': ('🧱', '5 porterías a cero'),
};
