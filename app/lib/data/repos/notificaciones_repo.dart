import '../../core/supabase.dart';
import '../../core/tiempo_real.dart';

class Notificacion {
  Notificacion.fromMap(Map<String, dynamic> m)
      : id = (m['id'] as num).toInt(),
        ligaId = m['liga_id'] as String?,
        tipo = m['tipo'] as String,
        titulo = m['titulo'] as String,
        cuerpo = (m['cuerpo'] ?? '') as String,
        ruta = m['ruta'] as String?,
        leida = m['leida'] == true,
        creadoEn = DateTime.parse(m['creado_en'] as String);

  final int id;
  final String? ligaId, ruta;
  final String tipo, titulo, cuerpo;
  final bool leida;
  final DateTime creadoEn;
}

/// Bandeja de avisos (0022). La base de datos los crea; aquí solo se leen (en tiempo real) y se marcan.
class NotificacionesRepo {
  static Stream<List<Notificacion>> stream() {
    final uid = uidActual;
    if (uid == null) return Stream.value(const []);
    return datoVivo(
      cargar: () async {
        final rows = await sb.from('notificaciones').select().eq('perfil_id', uid).order('creado_en', ascending: false).limit(60);
        return [for (final r in rows) Notificacion.fromMap(r)];
      },
      tabla: 'notificaciones',
      columna: 'perfil_id',
      valor: uid,
      respaldo: const Duration(seconds: 90),
    );
  }

  static Future<void> marcarLeidas([List<int>? ids]) async {
    await sb.rpc('marcar_notificaciones_leidas', params: {'p_ids': ids});
  }

  static Future<void> registrarDispositivo(String token) async {
    // 'android_botones': esta versión pinta las notificaciones de convocatoria con «Voy / No voy» (0040)
    await sb.rpc('registrar_dispositivo', params: {'p_token': token, 'p_plataforma': 'android_botones'});
  }

  static Future<void> borrarDispositivo(String token) async {
    await sb.rpc('borrar_dispositivo', params: {'p_token': token});
  }
}
