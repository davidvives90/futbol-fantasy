import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget de la pantalla de inicio (Android): guarda el próximo partido y pide al widget que se repinte.
class WidgetInicio {
  static const _canal = MethodChannel('ff/widget');
  static String? _ultimo;

  static Future<void> actualizar(SharedPreferences prefs,
      {required String titulo, required String linea, required String estado}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final clave = '$titulo|$linea|$estado';
    if (clave == _ultimo) return;
    _ultimo = clave;
    try {
      await prefs.setString('widget_titulo', titulo);
      await prefs.setString('widget_linea', linea);
      await prefs.setString('widget_estado', estado);
      await _canal.invokeMethod('actualizar');
    } catch (_) {}
  }
}
