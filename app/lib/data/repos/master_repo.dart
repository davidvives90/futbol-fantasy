import '../../core/supabase.dart';

/// Cuenta máster (soporte interno) y códigos promocionales (0021). Todas las RPC master_* comprueban
/// en el servidor que el usuario es máster y quedan auditadas.
class MasterRepo {
  static Future<bool> soyMaster() async => (await sb.rpc('es_master')) == true;

  static Future<Map<String, dynamic>> resumen() async =>
      ((await sb.rpc('master_resumen')) as Map).cast<String, dynamic>();

  static Future<List<Map<String, dynamic>>> _lista(String fn, [Map<String, dynamic>? p]) async {
    final r = await sb.rpc(fn, params: p);
    return [for (final x in (r as List? ?? const [])) (x as Map).cast<String, dynamic>()];
  }

  static Future<List<Map<String, dynamic>>> ligas() => _lista('master_ligas');
  static Future<List<Map<String, dynamic>>> usuarios([String? buscar]) =>
      _lista('master_usuarios', {'p_buscar': (buscar ?? '').trim().isEmpty ? null : buscar!.trim()});
  static Future<List<Map<String, dynamic>>> codigos() => _lista('master_codigos');
  static Future<List<Map<String, dynamic>>> managers(String ligaId) => _lista('master_managers', {'p_liga': ligaId});
  static Future<List<Map<String, dynamic>>> partidos(String ligaId) => _lista('master_partidos', {'p_liga': ligaId});
  static Future<List<Map<String, dynamic>>> auditoria() => _lista('master_auditoria', {'p_limite': 200});

  static Future<void> crearCodigo({
    required String codigo,
    required double importe,
    String? ligaId,
    int? usosMax,
    DateTime? caduca,
    String? nota,
  }) async {
    await sb.rpc('master_crear_codigo', params: {
      'p_codigo': codigo,
      'p_importe': importe,
      'p_liga': ligaId,
      'p_usos_max': usosMax,
      'p_caduca': caduca?.toUtc().toIso8601String(),
      'p_nota': nota,
    });
  }

  static Future<void> activarCodigo(String id, bool activo) async {
    await sb.rpc('master_activar_codigo', params: {'p_id': id, 'p_activo': activo});
  }

  static Future<void> ajustarSaldo(String ligaId, String miembroId, double importe, String motivo) async {
    await sb.rpc('master_ajustar_saldo',
        params: {'p_liga': ligaId, 'p_miembro': miembroId, 'p_importe': importe, 'p_motivo': motivo});
  }

  static Future<void> forzarEstado(String partidoId, String estado, String motivo) async {
    await sb.rpc('master_forzar_estado', params: {'p_partido': partidoId, 'p_estado': estado, 'p_motivo': motivo});
  }

  /// Para cualquier mánager: canjea un código en su liga. Devuelve el saldo nuevo.
  static Future<double> canjear(String ligaId, String codigo) async {
    final r = await sb.rpc('canjear_codigo', params: {'p_liga': ligaId, 'p_codigo': codigo});
    return (r as num).toDouble();
  }
}
