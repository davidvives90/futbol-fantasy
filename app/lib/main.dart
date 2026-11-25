import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'features/privacidad/consentimiento.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/liga_activa.dart';
import 'core/anuncios.dart';
import 'core/equipaciones.dart';
import 'core/idioma.dart';
import 'core/marco_web.dart';
import 'core/ventajas.dart';
import 'core/errores.dart';
import 'core/push.dart';
import 'data/providers.dart';
import 'data/models.dart';
import 'core/router.dart';
import 'core/supabase.dart';
import 'core/tema.dart';
import 'core/theme.dart';

Future<void> main() async {
  // Si algo falla al arrancar, la app se abre igual y muestra el error (en vez de cerrarse).
  await runZonedGuarded(_arrancar, (e, s) {
    Errores.registrar(e, s);
    _fallosArranque.add('$e');
  });
}

final _fallosArranque = <String>[];

/// Ejecuta un paso del arranque sin dejar que tumbe la app.
Future<void> _paso(String nombre, Future<void> Function() f) async {
  try {
    await f().timeout(const Duration(seconds: 10));
  } catch (e, s) {
    _fallosArranque.add('$nombre: $e');
    Errores.registrar(e, s);
  }
}

Future<void> _arrancar() async {
  WidgetsFlutterBinding.ensureInitialized();
  Errores.instalar();
  // En vez de una pantalla gris, se ve qué ha fallado (para poder enviarlo)
  ErrorWidget.builder = (d) => Material(
        color: const Color(0xFFFFF4F2),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text('Error: ${d.exceptionAsString()}', style: const TextStyle(color: Color(0xFF8A1C1C), fontSize: 13)),
        ),
      );
  await _paso('Fechas', () => initializeDateFormatting()); // todos los idiomas de la app
  await _paso('Supabase', () => Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey));
  final prefs = await SharedPreferences.getInstance();
  await _paso('Push', Push.iniciar);
  try {
    unawaited(Anuncios.instancia.iniciar(prefs).catchError((_) {}));
  } catch (_) {}
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const FutbolFantasyApp(),
  ));
  if (_fallosArranque.isNotEmpty) debugPrint('Arranque: ${_fallosArranque.join(' | ')}');
}

class FutbolFantasyApp extends ConsumerStatefulWidget {
  const FutbolFantasyApp({super.key});

  @override
  ConsumerState<FutbolFantasyApp> createState() => _FutbolFantasyAppState();
}

class _FutbolFantasyAppState extends ConsumerState<FutbolFantasyApp> {
  StreamSubscription<Uri>? _links;
  StreamSubscription<AuthState>? _auth;
  final _mensajes = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Push: al haber sesión, registra este móvil y atiende los avisos.
    void activarPush() => Push.activar(
          alAbrir: (ruta) => ref.read(routerProvider).go(ruta),
          enPrimerPlano: (titulo, cuerpo, ruta) {
            final router = ref.read(routerProvider);
            // Si ya estás en esa pantalla, no se ofrece «Ver»: abrirla otra vez borraría lo que estés rellenando
            final aqui = router.routerDelegate.currentConfiguration.uri.path;
            final ofrecerVer = ruta != null && ruta.isNotEmpty && aqui != ruta;
            _mensajes.currentState
              ?..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(cuerpo.isEmpty ? titulo : '$titulo\n$cuerpo'),
                duration: const Duration(seconds: 5),
                // Con acción, Flutter lo deja fijo hasta cerrarlo y tapa los botones de abajo
                persist: false,
                action: ofrecerVer ? SnackBarAction(label: tr('Ver'), onPressed: () => router.go(ruta)) : null,
              ));
          },
        );
    if (sb.auth.currentSession != null) {
      activarPush();
      unawaited(sincronizarIdioma());
    }
    _auth = sb.auth.onAuthStateChange.listen((e) {
      if (e.event == AuthChangeEvent.signedIn) {
        activarPush();
        unawaited(sincronizarIdioma());
      }
    }, onError: (_) {});
    if (_fallosArranque.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _mensajes.currentState?.showSnackBar(SnackBar(
            duration: const Duration(seconds: 12),
            content: Text('Aviso al arrancar: ${_fallosArranque.join(' · ')}'),
          )));
    }
    // uriLinkStream también emite el enlace con el que se abrió la app.
    _links = AppLinks().uriLinkStream.listen(_alRecibirEnlace);
  }

  /// io.futbolfantasy://invite/<token>  o  https://futbolfantasy.app/i/<token>
  void _alRecibirEnlace(Uri uri) {
    String? token;
    if (uri.scheme == Env.scheme && uri.host == 'invite' && uri.pathSegments.isNotEmpty) {
      token = uri.pathSegments.first;
    } else if (uri.scheme == 'https' && uri.pathSegments.length >= 2 && uri.pathSegments.first == 'i') {
      token = uri.pathSegments[1];
    }
    if (token == null) return; // p. ej. la vuelta del login, que gestiona Supabase

    if (sb.auth.currentSession != null) {
      ref.read(routerProvider).go('/unirse?codigo=${Uri.encodeComponent(token)}');
    } else {
      // Se usará tras iniciar sesión (lo recoge HomeShell).
      ref.read(invitacionPendienteProvider.notifier).state = token;
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ventajasProvider); // «sin anuncios» del usuario (lo leen los anuncios y la web)
    return MaterialApp.router(
      title: 'Pachanga Fantasy',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _mensajes,
      // Accesibilidad: respeta el tamaño de letra del móvil, con un tope para que nada se rompa
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.35)),
          child: EquipacionesScope(
            equipaciones: ref.watch(ligaActualProvider)?.liga.equipaciones ?? Equipacion.porDefecto,
            // Al cambiar de idioma se reconstruye toda la interfaz (fechas y textos incluidos)
            child: PuertaConsentimiento(
              child: MarcoWeb(
              onQuitarAnuncios: () => ref.read(routerProvider).push('/tienda'),
              // Android dibuja de borde a borde: sin esto, los botones de abajo quedan bajo la barra del sistema.
              // La app termina encima de la barra (el hueco se pinta con el color de fondo).
              child: kIsWeb
                  ? KeyedSubtree(key: ValueKey(ref.watch(idiomaProvider)), child: child!)
                  : ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: SafeArea(
                        top: false,
                        left: false,
                        right: false,
                        child: KeyedSubtree(key: ValueKey(ref.watch(idiomaProvider)), child: child!),
                      ),
                    ),
              ),
            ),
          ),
        );
      },
      theme: AppTheme.claro(),
      darkTheme: AppTheme.oscuro(),
      themeMode: ref.watch(temaProvider),
      locale: Locale(ref.watch(idiomaProvider)),
      supportedLocales: [for (final c in idiomas.keys) Locale(c)],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
