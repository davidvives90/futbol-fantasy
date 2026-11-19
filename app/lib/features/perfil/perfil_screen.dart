import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/liga_activa.dart';
import '../../core/supabase.dart';
import '../../core/tema.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../master/master_screen.dart';
import '../shell/home_shell.dart';
import '../stats/ficha_screen.dart';

class PerfilScreen extends ConsumerWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    final perfil = ref.watch(miPerfilProvider).valueOrNull;
    final ligas = ref.watch(misLigasProvider).valueOrNull ?? const <MiLiga>[];
    if (mi == null || perfil == null) return const Scaffold(body: Cargando());

    return Scaffold(
      appBar: LigaAppBar(mostrarPerfil: false, actions: [
        IconButton(tooltip: 'Editar perfil', icon: const Icon(Icons.edit_outlined), onPressed: () => context.push('/perfil/editar')),
      ]),
      body: ListView(children: [
        // Mis estadísticas en la liga activa (misma vista que la ficha).
        SizedBox(height: 520, child: FichaScreen(miembroId: mi.yo.id, conAppBar: false)),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Mis ligas', style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final l in ligas)
          ListTile(
            leading: Icon(l.liga.id == mi.liga.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            title: Text(l.liga.nombre),
            subtitle: Text('${l.liga.formato}${l.soyAdmin ? ' · Admin' : ''}'),
            onTap: () => ref.read(ligaActivaIdProvider.notifier).elegir(l.liga.id),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Crear o unirse a otra liga'),
          onTap: () => context.push('/onboarding'),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Opciones', style: Theme.of(context).textTheme.titleSmall),
        ),
        if (ref.watch(esMasterProvider).valueOrNull == true)
          ListTile(
            leading: Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.tertiary),
            title: const Text('Panel máster'),
            subtitle: const Text('Control interno, códigos promocionales y registro'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/master'),
          ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Apariencia'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Oscuro')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistema')),
              ],
              selected: {ref.watch(temaProvider)},
              onSelectionChanged: (s) => ref.read(temaProvider.notifier).elegir(s.first),
            ),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(sb.auth.currentUser?.email ?? ''),
          subtitle: Text(etiquetaPosicion(perfil.posicion)),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Cerrar sesión'),
          onTap: () async {
            if (!await confirmar(context, 'Cerrar sesión', '¿Seguro que quieres salir?')) return;
            await ref.read(ligaActivaIdProvider.notifier).elegir(null);
            await sb.auth.signOut();
          },
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
