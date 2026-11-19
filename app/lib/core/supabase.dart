import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuración inyectada al compilar con --dart-define.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Esquema propio de la app para deep links.
  static const scheme = 'io.futbolfantasy';
  static const loginRedirect = '$scheme://login';

  /// Página web pública que redirige a la descarga del APK y a la app.
  static const webInvitacion = 'https://futbolfantasy.app/i';

  static const bucketFacturas = 'facturas';
}

/// Cliente global de Supabase.
SupabaseClient get sb => Supabase.instance.client;

/// Id del usuario autenticado (o null).
String? get uidActual => sb.auth.currentUser?.id;
