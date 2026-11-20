import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/repos/notificaciones_repo.dart';

/// Notificaciones push con Firebase Cloud Messaging.
/// Solo se activa si la APK se compiló con los datos del proyecto de Firebase (--dart-define=FIREBASE_*).
/// Sin ellos la app funciona igual: los avisos se ven en la bandeja (campana) en tiempo real.
class Push {
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  // En la web aún no hay push (falta registrar la app web en Firebase); los avisos se ven en la campana.
  static bool get configurado => !kIsWeb && _appId.isNotEmpty && _apiKey.isNotEmpty && _projectId.isNotEmpty;

  static bool _iniciado = false;
  static String? _token;
  static StreamSubscription<String>? _refresco;
  static bool _escuchando = false;

  /// Llamar una vez al arrancar la app (antes de runApp). No falla nunca.
  static Future<void> iniciar() async {
    if (!configurado || _iniciado) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );
      _iniciado = true;
    } catch (e) {
      debugPrint('Push: no se pudo iniciar Firebase: $e');
    }
  }

  /// Tras iniciar sesión: pide permiso (Android 13+), registra el token y escucha los avisos.
  /// [alAbrir] recibe la ruta de la app al tocar una notificación; [enPrimerPlano] muestra el aviso dentro de la app.
  static Future<void> activar({
    required void Function(String ruta) alAbrir,
    required void Function(String titulo, String cuerpo, String? ruta) enPrimerPlano,
  }) async {
    if (!_iniciado) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      _token = await fm.getToken();
      if (_token != null) await NotificacionesRepo.registrarDispositivo(_token!);
      await _refresco?.cancel();
      _refresco = fm.onTokenRefresh.listen((t) {
        _token = t;
        NotificacionesRepo.registrarDispositivo(t);
      });
      if (_escuchando) return;
      _escuchando = true;
      FirebaseMessaging.onMessage.listen((m) => enPrimerPlano(
            m.notification?.title ?? 'Aviso',
            m.notification?.body ?? '',
            m.data['ruta'] as String?,
          ));
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final r = m.data['ruta'] as String?;
        if (r != null && r.isNotEmpty) alAbrir(r);
      });
      final inicial = await fm.getInitialMessage();
      final r = inicial?.data['ruta'] as String?;
      if (r != null && r.isNotEmpty) alAbrir(r);
    } catch (e) {
      debugPrint('Push: $e');
    }
  }

  /// Al cerrar sesión: el móvil deja de recibir avisos de esa cuenta.
  static Future<void> desactivar() async {
    if (!_iniciado || _token == null) return;
    try {
      await NotificacionesRepo.borrarDispositivo(_token!);
    } catch (_) {}
  }
}
