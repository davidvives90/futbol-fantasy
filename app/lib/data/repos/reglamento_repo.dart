import '../../core/supabase.dart';

/// Una regla del reglamento con su valor en la liga (RPC reglamento_liga).
class ReglaJuego {
  ReglaJuego(this.m);
  final Map<String, dynamic> m;

  String get clave => m['clave'] as String;
  String get grupo => m['grupo'] as String;
  String get titulo => m['titulo'] as String;
  String? get descripcion => m['descripcion'] as String?;
  String get tipo => m['tipo'] as String; // si_no | opcion | numero
  String? get unidad => m['unidad'] as String?;
  int get minimo => (m['minimo'] as num?)?.toInt() ?? 0;
  int get maximo => (m['maximo'] as num?)?.toInt() ?? 99;
  dynamic get valor => m['valor'];
  bool get personalizada => (m['personalizada'] ?? false) as bool;
  List<({String valor, String texto})> get opciones => [
        for (final o in (m['opciones'] as List?) ?? const [])
          (valor: (o as Map)['valor'] as String, texto: o['texto'] as String),
      ];

  /// Texto de un valor cualquiera de esta regla («Sí», «Con la mano», «25 min»…).
  String texto(dynamic v) {
    if (v == null) return '—';
    switch (tipo) {
      case 'si_no':
        return v == true ? 'Sí' : 'No';
      case 'numero':
        return '$v${unidad == null ? '' : ' $unidad'}';
      default:
        return opciones.where((o) => o.valor == v).firstOrNull?.texto ?? '$v';
    }
  }

  String get textoValor => texto(valor);

  /// Valores posibles para una votación sobre esta regla (para números: el actual ±).
  List<dynamic> get valoresPosibles => switch (tipo) {
        'si_no' => [true, false],
        'opcion' => [for (final o in opciones) o.valor],
        _ => <dynamic>[],
      };
}

class Votacion {
  Votacion(this.m);
  final Map<String, dynamic> m;
  String get id => m['id'] as String;
  String get titulo => m['titulo'] as String;
  String? get descripcion => m['descripcion'] as String?;
  List<String> get opciones => [for (final o in (m['opciones'] as List)) o as String];
  String? get reglaClave => m['regla_clave'] as String?;
  bool get anonima => (m['anonima'] ?? true) as bool;
  DateTime get cierraEn => DateTime.parse(m['cierra_en'] as String).toLocal();
  String get estado => m['estado'] as String;
  int? get ganadora => (m['ganadora'] as num?)?.toInt();
  bool get aplicada => (m['aplicada'] ?? false) as bool;
  bool get abierta => estado == 'abierta' && cierraEn.isAfter(DateTime.now());
}

class ResultadoVotacion {
  ResultadoVotacion(this.m);
  final Map<String, dynamic> m;
  int? get miVoto => (m['mi_voto'] as num?)?.toInt();
  int get total => (m['total'] as num?)?.toInt() ?? 0;
  int get censo => (m['censo'] as num?)?.toInt() ?? 0;
  int votos(int opcion) =>
      ((m['votos'] as List).cast<Map>().where((v) => v['opcion'] == opcion).firstOrNull?['n'] as num?)?.toInt() ?? 0;
  List<String> quien(int opcion) => [
        for (final id in ((m['votos'] as List).cast<Map>().where((v) => v['opcion'] == opcion).firstOrNull?['miembros'] as List?) ??
            const [])
          id as String,
      ];
}

class Ausencia {
  Ausencia(this.m);
  final Map<String, dynamic> m;
  String get id => m['id'] as String;
  DateTime get desde => DateTime.parse(m['desde'] as String);
  DateTime? get hasta => m['hasta'] == null ? null : DateTime.parse(m['hasta'] as String);
  String get motivo => (m['motivo'] ?? 'otro') as String;
  String? get nota => m['nota'] as String?;
  String get miembroId => m['miembro_id'] as String;

  /// ¿La baja cubre el día [d]?
  bool cubre(DateTime d) {
    final dia = DateTime(d.year, d.month, d.day);
    return !desde.isAfter(dia) && (hasta == null || !hasta!.isBefore(dia));
  }

  bool get actual {
    final hoy = DateTime.now();
    final h = DateTime(hoy.year, hoy.month, hoy.day);
    return !desde.isAfter(h) && (hasta == null || !hasta!.isBefore(h));
  }
}

const motivosAusencia = <String, String>{
  'lesion': 'Lesión',
  'viaje': 'Viaje',
  'trabajo': 'Trabajo',
  'personal': 'Personal',
  'otro': 'Otro',
};

class ReglamentoRepo {
  // ---- Reglamento
  static Future<List<ReglaJuego>> reglamento(String ligaId) async {
    final r = await sb.rpc('reglamento_liga', params: {'p_liga': ligaId});
    return [for (final x in (r as List)) ReglaJuego(Map<String, dynamic>.from(x as Map))];
  }

  static Future<void> cambiarRegla(String ligaId, String clave, dynamic valor) =>
      sb.rpc('cambiar_regla', params: {'p_liga': ligaId, 'p_clave': clave, 'p_valor': valor});

  static Future<void> cambiarModalidad(String ligaId, String modalidad) =>
      sb.rpc('cambiar_modalidad', params: {'p_liga': ligaId, 'p_modalidad': modalidad});

  // ---- Votaciones
  static Future<List<Votacion>> votaciones(String ligaId) async {
    final rows = await sb.from('votaciones').select().eq('liga_id', ligaId).neq('estado', 'cancelada')
        .order('creada_en', ascending: false).limit(50);
    return [for (final r in rows) Votacion(r)];
  }

  static Future<ResultadoVotacion> resultados(String votacionId) async =>
      ResultadoVotacion(Map<String, dynamic>.from(
          await sb.rpc('votacion_resultados', params: {'p_votacion': votacionId}) as Map));

  static Future<void> crearVotacion({
    required String ligaId,
    required String titulo,
    String? descripcion,
    required List<String> opciones,
    required DateTime cierraEn,
    String? reglaClave,
    List<dynamic>? reglaValores,
    bool anonima = true,
  }) =>
      sb.rpc('crear_votacion', params: {
        'p_liga': ligaId,
        'p_titulo': titulo,
        'p_descripcion': descripcion,
        'p_opciones': opciones,
        'p_cierra_en': cierraEn.toUtc().toIso8601String(),
        'p_regla_clave': reglaClave,
        'p_regla_valores': reglaValores,
        'p_anonima': anonima,
      });

  static Future<void> votar(String votacionId, int opcion) =>
      sb.rpc('votar_votacion', params: {'p_votacion': votacionId, 'p_opcion': opcion});

  static Future<void> cerrar(String votacionId, {bool cancelar = false}) =>
      sb.rpc('cerrar_votacion', params: {'p_votacion': votacionId, 'p_cancelar': cancelar});

  // ---- Asistencia y bajas
  static Future<Map<String, dynamic>> historial(String ligaId, {int partidos = 12}) async =>
      Map<String, dynamic>.from(
          await sb.rpc('historial_asistencia', params: {'p_liga': ligaId, 'p_partidos': partidos}) as Map);

  static Future<List<Ausencia>> ausenciasDe(String miembroId) async {
    final r = await sb.rpc('ausencias_miembro', params: {'p_miembro': miembroId});
    return [for (final x in (r as List)) Ausencia(Map<String, dynamic>.from(x as Map))];
  }

  static String _fecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<void> registrarAusencia(String miembroId, DateTime desde, DateTime? hasta, String motivo, String? nota) =>
      sb.rpc('registrar_ausencia', params: {
        'p_miembro': miembroId,
        'p_desde': _fecha(desde),
        'p_hasta': hasta == null ? null : _fecha(hasta),
        'p_motivo': motivo,
        'p_nota': nota,
      });

  /// Bajas en curso o por venir de toda la liga.
  static Future<List<Ausencia>> bajasLiga(String ligaId) async {
    final h = DateTime.now();
    final rows = await sb.from('ausencias').select().eq('liga_id', ligaId)
        .or('hasta.is.null,hasta.gte.${_fecha(DateTime(h.year, h.month, h.day))}');
    return [for (final r in rows) Ausencia(r)];
  }

  static Future<void> terminarAusencia(String id) => sb.rpc('terminar_ausencia', params: {'p_ausencia': id});
  static Future<void> borrarAusencia(String id) => sb.rpc('borrar_ausencia', params: {'p_ausencia': id});
}
