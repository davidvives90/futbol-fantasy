import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/liga_activa.dart';
import '../../core/utils.dart';
import '../../data/providers.dart';
import '../auth/perfil_form_screen.dart';
import '../onboarding/onboarding_screen.dart';
import 'notificaciones_screen.dart';

/// Barra inferior + "puerta" de sesión: sin perfil → completar perfil;
/// sin liga → crear o unirse.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _revisandoInvitacion = false;

  void _usarInvitacionPendiente() {
    final token = ref.read(invitacionPendienteProvider);
    if (token == null || _revisandoInvitacion) return;
    _revisandoInvitacion = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(invitacionPendienteProvider.notifier).state = null;
      _revisandoInvitacion = false;
      if (mounted) context.push('/unirse?codigo=${Uri.encodeComponent(token)}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(miPerfilProvider);
    final ligas = ref.watch(misLigasProvider);

    if (perfil.isLoading || ligas.isLoading) return const Scaffold(body: Cargando());
    if (perfil.hasError) {
      return Scaffold(body: ErrorVista(perfil.error!, onRetry: () => ref.invalidate(miPerfilProvider)));
    }
    if (perfil.value == null) return const PerfilFormScreen(inicial: true);

    _usarInvitacionPendiente();

    if (ligas.hasError) {
      return Scaffold(body: ErrorVista(ligas.error!, onRetry: () => ref.invalidate(misLigasProvider)));
    }
    if (ligas.value!.isEmpty) return const OnboardingScreen();

    // Con el Fantasy desactivado en la liga, su pestaña desaparece (rama 1 del shell)
    final fantasy = ref.watch(ligaActualProvider)?.liga.fantasyActivo ?? true;
    final ramas = [0, if (fantasy) 1, 2, 3, 4];
    const destinos = [
      NavigationDestination(icon: Icon(Icons.sports_soccer_outlined), selectedIcon: Icon(Icons.sports_soccer), label: 'Partidos'),
      NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Fantasy'),
      NavigationDestination(icon: Icon(Icons.leaderboard_outlined), selectedIcon: Icon(Icons.leaderboard), label: 'Clasificación'),
      NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Caja'),
      NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Liga'),
    ];
    final visible = ramas.indexOf(widget.shell.currentIndex);
    if (visible < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.shell.goBranch(0));
    }
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: visible < 0 ? 0 : visible,
        onDestinationSelected: (i) => widget.shell.goBranch(ramas[i], initialLocation: ramas[i] == widget.shell.currentIndex),
        destinations: [for (final r in ramas) destinos[r]],
      ),
    );
  }
}

/// AppBar de las pestañas principales con el selector de liga activa.
class LigaAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const LigaAppBar({super.key, this.actions, this.bottom, this.mostrarPerfil = true});
  final List<Widget>? actions;

  /// false en la propia pantalla de perfil.
  final bool mostrarPerfil;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actual = ref.watch(ligaActualProvider);
    final ligas = ref.watch(misLigasProvider).valueOrNull ?? const [];
    final avatar = ref.watch(miPerfilProvider).valueOrNull?.avatarUrl;

    return AppBar(
      title: PopupMenuButton<String>(
        tooltip: 'Cambiar de liga',
        onSelected: (v) {
          switch (v) {
            case '_crear':
              context.push('/crear-liga');
            case '_unirse':
              context.push('/unirse');
            case '_buscar':
              context.push('/buscar-ligas');
            default:
              ref.read(ligaActivaIdProvider.notifier).elegir(v);
          }
        },
        itemBuilder: (_) => [
          for (final l in ligas)
            CheckedPopupMenuItem(value: l.liga.id, checked: l.liga.id == actual?.liga.id, child: Text(l.liga.nombre)),
          const PopupMenuDivider(),
          const PopupMenuItem(value: '_crear', child: ListTile(leading: Icon(Icons.add), title: Text('Crear liga'))),
          const PopupMenuItem(value: '_unirse', child: ListTile(leading: Icon(Icons.vpn_key_outlined), title: Text('Unirse con código'))),
          const PopupMenuItem(value: '_buscar', child: ListTile(leading: Icon(Icons.search), title: Text('Buscar ligas'))),
        ],
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(actual?.liga.nombre ?? 'Fútbol Fantasy', overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
      actions: [
        ...?actions,
        const CampanaAvisos(),
        // Perfil: fuera de la barra inferior para dejarla en 5 destinos (guía de Material 3).
        if (mostrarPerfil)
          Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: 'Mi perfil',
            onPressed: () => context.push('/perfil'),
            icon: CircleAvatar(
              radius: 15,
              backgroundImage: (avatar == null || avatar.isEmpty) ? null : NetworkImage(avatar),
              child: (avatar == null || avatar.isEmpty) ? const Icon(Icons.person, size: 18) : null,
            ),
          ),
        ),
      ],
      bottom: bottom,
    );
  }
}
