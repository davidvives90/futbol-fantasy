import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/anuncios.dart';
import '../../core/liga_activa.dart';
import '../../core/utils.dart';
import '../../data/providers.dart';
import '../auth/perfil_form_screen.dart';
import '../onboarding/bienvenida.dart';
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

    // Primer uso: 3 pantallas de bienvenida, una sola vez por móvil
    mostrarBienvenidaSiToca(context, ref.read(prefsProvider),
        fantasy: ref.read(ligaActualProvider)?.liga.fantasyActivo ?? true);

    // Solo 3 pestañas: Inicio · Fantasy · Liga. Clasificación (rama 2) y Caja (rama 3) se abren desde Liga.
    // Con el Fantasy desactivado en la liga, su pestaña desaparece (rama 1 del shell).
    final fantasy = ref.watch(ligaActualProvider)?.liga.fantasyActivo ?? true;
    final ramas = [0, if (fantasy) 1, 4];
    const destinos = [
      (Icons.home_outlined, Icons.home, 'Inicio'),
      (Icons.shield_outlined, Icons.shield, 'Fantasy'),
      (Icons.leaderboard_outlined, Icons.leaderboard, 'Clasificación'),
      (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Caja'),
      (Icons.groups_outlined, Icons.groups, 'Liga'),
    ];
    final actual = widget.shell.currentIndex;
    // Clasificación y Caja cuelgan de Liga: se marca Liga
    final visible = (actual == 2 || actual == 3) ? ramas.indexOf(4) : ramas.indexOf(actual);
    if (visible < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.shell.goBranch(0));
    }
    void ir(int i) {
      widget.shell.goBranch(ramas[i], initialLocation: ramas[i] == widget.shell.currentIndex);
      Anuncios.instancia.pausaNatural(); // cambiar de pestaña es una pausa natural
    }

    // Pantallas anchas (tableta horizontal, ordenador): menú lateral en vez de barra inferior.
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 720) {
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: visible < 0 ? 0 : visible,
              onDestinationSelected: ir,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.9,
              destinations: [
                for (final r in ramas)
                  NavigationRailDestination(
                    icon: Icon(destinos[r].$1),
                    selectedIcon: Icon(destinos[r].$2),
                    label: Text(tr(destinos[r].$3)),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: widget.shell),
          ]),
        );
      }
      return Scaffold(
        body: widget.shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: visible < 0 ? 0 : visible,
          onDestinationSelected: ir,
          destinations: [
            for (final r in ramas)
              NavigationDestination(icon: Icon(destinos[r].$1), selectedIcon: Icon(destinos[r].$2), label: tr(destinos[r].$3)),
          ],
        ),
      );
    });
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
        tooltip: tr('Cambiar de liga'),
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
          const PopupMenuItem(value: '_crear', child: ListTile(leading: Icon(Icons.add), title: Tx('Crear liga'))),
          const PopupMenuItem(value: '_unirse', child: ListTile(leading: Icon(Icons.vpn_key_outlined), title: Tx('Unirse con código'))),
          const PopupMenuItem(value: '_buscar', child: ListTile(leading: Icon(Icons.search), title: Tx('Buscar ligas'))),
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
            tooltip: tr('Mi perfil'),
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
