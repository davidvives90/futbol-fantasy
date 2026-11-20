import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuración inyectada al compilar con --dart-define.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Esquema propio de la app para deep links.
  static const scheme = 'io.futbolfantasy';
  /// Vuelta del enlace mágico / Google: en la web, la propia página (sin el #/ruta); en el móvil, el esquema propio.
  static String get loginRedirect =>
      kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : '$scheme://login';

  /// Página web pública que redirige a la descarga del APK y a la app.
  static const webInvitacion = 'https://futbolfantasy.app/i';

  static const bucketFacturas = 'facturas';

  /// Dirección de la versión web (enlaces al compartir). Con dominio propio: --dart-define=WEB_APP=https://…/
  static const webApp = String.fromEnvironment('WEB_APP', defaultValue: 'https://davidvives90.github.io/futbol-fantasy/');
}

/// Cliente global de Supabase.
SupabaseClient get sb => Supabase.instance.client;

/// Id del usuario autenticado (o null).
String? get uidActual => sb.auth.currentUser?.id;
