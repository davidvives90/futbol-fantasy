import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repos/notificaciones_repo.dart';
import 'idioma.dart';

// ───────────── Avisos de convocatoria con botones «Voy / No voy» (0040) ─────────────
// El servidor manda un mensaje solo de datos con dos enlaces firmados; la app pinta la notificación con
// botones y, al pulsar uno, llama al enlace (Edge Function «responder») sin abrir la app.

final _local = FlutterLocalNotificationsPlugin();
bool _localIniciado = false;
void Function(String ruta)? _alAbrirLocal;

Future<void> _idiomaGuardado() async {
  try {
    final p = await SharedPreferences.getInstance();
    final c = p.getString('idioma_app');
    if (c != null && idiomas.containsKey(c)) idiomaActual = c;
  } catch (_) {}
}

Future<void> _iniciarLocal() async {
  if (_localIniciado) return;
  await _local.initialize(
    const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveNotificationResponse: (r) {
      if (r.actionId == null) {
        final ruta = (jsonDecode(r.payload ?? '{}') as Map)['ruta'] as String?;
        if (ruta != null && ruta.isNotEmpty) _alAbrirLocal?.call(ruta);
      } else {
        _responder(r);
      }
    },
    onDidReceiveBackgroundNotificationResponse: respuestaAvisoEnSegundoPlano,
  );
  _localIniciado = true;
}

NotificationDetails _detalles({bool botones = true}) => NotificationDetails(
      android: AndroidNotificationDetails(
        'convocatorias',
        tr('Convocatorias'),
        importance: Importance.high,
        priority: Priority.high,
        actions: botones
            ? [
                AndroidNotificationAction('voy', tr('Voy'), cancelNotification: false),
                AndroidNotificationAction('no', tr('No voy'), cancelNotification: false),
              ]
            : null,
      ),
    );

/// Pinta la notificación con botones (primer plano y segundo plano).
Future<void> mostrarAvisoConBotones(Map<String, dynamic> d) async {
  if (d['accion'] != 'asistencia') return;
  await _idiomaGuardado();
  await _iniciarLocal();
  final id = int.tryParse('${d['id']}') ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await _local.show(
    id,
    d['titulo'] as String? ?? 'Pachanga Fantasy',
    d['cuerpo'] as String? ?? '',
    _detalles(),
    payload: jsonEncode({'id': id, 'ruta': d['ruta'], 'voy': d['url_voy'], 'no': d['url_no']}),
  );
}

Future<void> _responder(NotificationResponse r) async {
  final p = (jsonDecode(r.payload ?? '{}') as Map).cast<String, dynamic>();
  final url = r.actionId == 'voy' ? p['voy'] as String? : p['no'] as String?;
  if (url == null) return;
  await _idiomaGuardado();
  await _iniciarLocal();
  final id = (p['id'] as num?)?.toInt() ?? r.id ?? 0;
  String texto;
  try {
    final res = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
    final estado = (jsonDecode(res.body) as Map)['estado'] as String?;
    texto = tr(switch (estado) {
      'confirmado' => '¡Apuntado! ✅',
      'espera' => 'Estás en lista de espera',
      'baja' => 'Hecho: no vas',
      'cerrado' => 'Este partido ya no admite cambios',
      _ => 'No se ha podido responder: ábrelo en la app',
    });
  } catch (_) {
    texto = tr('No se ha podido responder: ábrelo en la app');
  }
  // Se sustituye la notificación por la confirmación (sin botones)
  await _local.show(id, 'Pachanga Fantasy', texto, _detalles(botones: false), payload: jsonEncode({'ruta': p['ruta']}));
}

/// Mensajes con la app cerrada o en segundo plano (Android).
@pragma('vm:entry-point')
Future<void> avisoEnSegundoPlano(RemoteMessage m) async => mostrarAvisoConBotones(m.data);

/// Botón pulsado con la app cerrada.
@pragma('vm:entry-point')
void respuestaAvisoEnSegundoPlano(NotificationResponse r) {
  _responder(r);
}

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
      FirebaseMessaging.onBackgroundMessage(avisoEnSegundoPlano);
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
      _alAbrirLocal = alAbrir;
      await _iniciarLocal();
      // Si la app se abrió tocando una notificación con botones
      final lanzada = await _local.getNotificationAppLaunchDetails();
      final pl = lanzada?.notificationResponse?.payload;
      if ((lanzada?.didNotificationLaunchApp ?? false) && pl != null && lanzada?.notificationResponse?.actionId == null) {
        final ruta = (jsonDecode(pl) as Map)['ruta'] as String?;
        if (ruta != null && ruta.isNotEmpty) alAbrir(ruta);
      }
      FirebaseMessaging.onMessage.listen((m) {
        if (m.data['accion'] == 'asistencia') {
          mostrarAvisoConBotones(m.data); // también con la app abierta: así se responde igual
          return;
        }
        enPrimerPlano(
          m.notification?.title ?? 'Aviso',
          m.notification?.body ?? '',
          m.data['ruta'] as String?,
        );
      });
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
