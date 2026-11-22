import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/tienda/tienda_screen.dart';
import 'ventajas.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/perfil_form_screen.dart';
import '../features/caja/caja_screen.dart';
import '../features/fantasy/ajustes_fantasy_screen.dart';
import '../features/fantasy/encuesta_screen.dart';
import '../features/fantasy/fantasy_screen.dart';
import '../features/fantasy/jugador_mercado_screen.dart';
import '../features/liga/convocatoria_cobro_screen.dart';
import '../features/liga/ajustes_liga_screen.dart';
import 'errores.dart';
import '../features/liga/equipaciones_screen.dart';
import '../features/liga/guia_screen.dart';
import '../features/master/master_screen.dart';
import '../features/shell/notificaciones_screen.dart';
import '../features/liga/liga_screen.dart';
import '../features/liga/reglas_screen.dart';
import '../features/onboarding/buscar_ligas_screen.dart';
import '../features/onboarding/crear_liga_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/unirse_screen.dart';
import '../features/partidos/crear_partido_screen.dart';
import '../features/partidos/partido_detalle_screen.dart';
import '../features/partidos/partidos_screen.dart';
import '../features/partidos/temporada_screen.dart';
import '../features/perfil/perfil_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/stats/clasificacion_screen.dart';
import '../features/stats/ficha_screen.dart';
import '../features/liga/reglamento_screen.dart';
import '../features/liga/votaciones_screen.dart';
import '../features/liga/asistencia_screen.dart';
import '../features/stats/palmares_screen.dart';
import '../features/onboarding/asistente_liga_screen.dart';
import 'supabase.dart';

/// Notifica a go_router cada vez que cambia la sesión.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    _sub = sb.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  late final StreamSubscription _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh();
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/partidos',
    refreshListenable: refresh,
    redirect: (context, state) {
      Errores.pantalla = state.matchedLocation; // para saber dónde ocurre cada error
      final logueado = sb.auth.currentSession != null;
      final enLogin = state.matchedLocation == '/login';
      if (!logueado) return enLogin ? null : '/login';
      if (enLogin) return '/partidos';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const SinPublicidad(child: LoginScreen())),
      GoRoute(path: '/perfil/editar', builder: (_, __) => const PerfilFormScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/crear-liga', builder: (_, __) => const SinPublicidad(child: CrearLigaScreen())),
      GoRoute(path: '/liga/editar', builder: (_, __) => const CrearLigaScreen(editar: true)),
      GoRoute(path: '/liga/ajustes', builder: (_, __) => const AjustesLigaScreen()),
      GoRoute(path: '/liga/equipaciones', builder: (_, __) => const EquipacionesScreen()),
      GoRoute(path: '/guia', builder: (_, __) => const GuiaScreen()),
      GoRoute(path: '/liga/asistente', builder: (_, __) => const AsistenteLigaScreen()),
      GoRoute(path: '/palmares', builder: (_, __) => const PalmaresScreen()),
      GoRoute(path: '/reglamento', builder: (_, __) => const ReglamentoScreen()),
      GoRoute(path: '/votaciones', builder: (_, __) => const VotacionesScreen()),
      GoRoute(path: '/asistencia', builder: (_, __) => const AsistenciaScreen()),
      GoRoute(path: '/liga/reglas', builder: (_, __) => const ReglasScreen()),
      GoRoute(path: '/liga/convocatoria', builder: (_, __) => const ConvocatoriaCobroScreen()),
      GoRoute(path: '/temporada', builder: (_, __) => const TemporadaScreen()),
      GoRoute(
        path: '/unirse',
        builder: (_, state) => UnirseScreen(codigoInicial: state.uri.queryParameters['codigo']),
      ),
      GoRoute(path: '/buscar-ligas', builder: (_, __) => const BuscarLigasScreen()),
      // Perfil sale de la barra inferior (se abre desde el avatar de la barra superior).
      GoRoute(path: '/perfil', builder: (_, __) => const PerfilScreen()),
      GoRoute(path: '/liga/fantasy', builder: (_, __) => const AjustesFantasyScreen()),
      GoRoute(path: '/master', builder: (_, __) => const MasterScreen()),
      GoRoute(path: '/avisos', builder: (_, __) => const NotificacionesScreen()),
      GoRoute(path: '/tienda', builder: (_, __) => const TiendaScreen()),
      // Ficha fuera de las pestañas: se abre desde pantallas que están encima (Perfil, avisos…)
      GoRoute(path: '/ficha/:miembroId', builder: (_, state) => FichaScreen(miembroId: state.pathParameters['miembroId']!)),
      GoRoute(
        path: '/master/liga/:ligaId',
        builder: (_, state) => MasterLigaScreen(
          ligaId: state.pathParameters['ligaId']!,
          nombre: state.uri.queryParameters['nombre'] ?? 'Liga',
        ),
      ),
      GoRoute(
        path: '/fantasy/jugador/:miembroId',
        builder: (_, state) => JugadorMercadoScreen(miembroId: state.pathParameters['miembroId']!),
      ),
      GoRoute(
        path: '/fantasy/encuesta/:id',
        builder: (_, state) => EncuestaScreen(encuestaId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/partidos',
              builder: (_, __) => const PartidosScreen(),
              routes: [
                GoRoute(path: 'nuevo', builder: (_, __) => const CrearPartidoScreen()),
                GoRoute(
                  path: ':id',
                  builder: (_, state) => PartidoDetalleScreen(partidoId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/fantasy', builder: (_, __) => const FantasyScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/clasificacion',
              builder: (_, __) => const ClasificacionScreen(),
              routes: [
                GoRoute(
                  path: 'jugador/:miembroId',
                  builder: (_, state) => FichaScreen(miembroId: state.pathParameters['miembroId']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/caja', builder: (_, __) => const CajaScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/liga', builder: (_, __) => const LigaScreen()),
          ]),
        ],
      ),
    ],
  );
});
