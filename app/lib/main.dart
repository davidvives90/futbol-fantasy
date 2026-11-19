import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/liga_activa.dart';
import 'core/router.dart';
import 'core/supabase.dart';
import 'core/tema.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const FutbolFantasyApp(),
  ));
}

class FutbolFantasyApp extends ConsumerStatefulWidget {
  const FutbolFantasyApp({super.key});

  @override
  ConsumerState<FutbolFantasyApp> createState() => _FutbolFantasyAppState();
}

class _FutbolFantasyAppState extends ConsumerState<FutbolFantasyApp> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Fútbol Fantasy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro(),
      darkTheme: AppTheme.oscuro(),
      themeMode: ref.watch(temaProvider),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
