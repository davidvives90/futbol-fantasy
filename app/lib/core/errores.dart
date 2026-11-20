import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registro de errores en Supabase (tabla errores_app, la ve el máster en su panel).
/// Captura errores de Flutter, errores asíncronos no controlados y fallos inesperados del servidor.
class Errores {
  static const version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  static String pantalla = '';
  static int _enviados = 0;

  static void instalar() {
    final anterior = FlutterError.onError;
    FlutterError.onError = (d) {
      anterior?.call(d);
      registrar(d.exception, d.stack);
    };
    PlatformDispatcher.instance.onError = (e, s) {
      registrar(e, s);
      return true; // la app sigue funcionando
    };
  }

  /// Errores de negocio (los que lanza la base de datos con un mensaje para el usuario) no se registran.
  static bool esperado(Object e) =>
      (e is PostgrestException && (e.code == 'P0001' || e.code == '42501' || e.code == '23514' || e.code == '23505')) ||
      e is AuthException;

  static void registrar(Object e, [StackTrace? s]) {
    if (esperado(e) || _enviados > 50) return;
    _enviados++;
    try {
      final c = Supabase.instance.client;
      if (c.auth.currentSession == null) return;
      c.rpc('registrar_error', params: {
        'p_mensaje': e.toString(),
        'p_traza': s?.toString(),
        'p_pantalla': pantalla,
        'p_version': version,
        'p_plataforma': kIsWeb ? 'web-${defaultTargetPlatform.name}' : defaultTargetPlatform.name,
      }).catchError((_) => null);
    } catch (_) {}
  }
}
