import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/anuncios.dart';
import '../../core/liga_activa.dart';
import '../../core/push.dart';
import '../../core/supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;
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
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Guía y normas'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/guia'),
        ),
        FutureBuilder<bool>(
          future: Anuncios.hayOpcionesPrivacidad(),
          builder: (_, s) => s.data == true
              ? ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacidad y anuncios'),
                  subtitle: const Text('Cambia tu consentimiento de anuncios personalizados'),
                  onTap: Anuncios.abrirOpcionesPrivacidad,
                )
              : const SizedBox.shrink(),
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
            await Push.desactivar();
            await sb.auth.signOut();
          },
        ),
        ListTile(
          leading: const Icon(Icons.policy_outlined),
          title: const Text('Política de privacidad'),
          onTap: () => launchUrl(Uri.parse(urlPrivacidad), mode: LaunchMode.externalApplication),
        ),
        ListTile(
          leading: Icon(Icons.person_remove_outlined, color: Theme.of(context).colorScheme.error),
          title: Text('Eliminar mi cuenta', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => _eliminarCuenta(context, ref),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

const urlPrivacidad = 'https://davidvives90.github.io/futbol-fantasy/web/privacidad.html';

Future<void> _eliminarCuenta(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Eliminar mi cuenta'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Se borrarán tu perfil, tu foto y tu acceso. Tus partidos se conservan como «Exjugador» '
              'para no alterar las clasificaciones de tus compañeros. No se puede deshacer.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Escribe ELIMINAR para confirmar'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: ctrl.text.trim() == 'ELIMINAR' ? () => Navigator.pop(ctx, true) : null,
            child: const Text('Eliminar'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final uid = sb.auth.currentUser?.id;
  await ejecutar(context, () async {
    // primero la foto (el almacenamiento no se puede borrar desde SQL); si falla, seguimos
    if (uid != null) {
      try {
        final fotos = await sb.storage.from('avatares').list(path: uid);
        if (fotos.isNotEmpty) await sb.storage.from('avatares').remove([for (final f in fotos) '$uid/${f.name}']);
      } catch (_) {}
    }
    await sb.rpc('eliminar_mi_cuenta', params: {'p_confirmacion': 'ELIMINAR'});
    await ref.read(ligaActivaIdProvider.notifier).elegir(null);
    try {
      await Push.desactivar();
    } catch (_) {}
    try {
      await sb.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  });
}
