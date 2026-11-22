import 'package:flutter/material.dart';
import '../onboarding/bienvenida.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/anuncios.dart';
import '../../core/ventajas.dart';
import '../fantasy/tarjetas_jugador.dart';
import '../partidos/agenda.dart';
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

    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final resumen = ref.watch(resumenFantasyProvider(mi.liga.id)).valueOrNull?[mi.yo.id];
    final ventajas = ref.watch(ventajasProvider).valueOrNull ?? const Ventajas();
    Widget seccion(String texto) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
          child: Text(tr(texto).toUpperCase(),
              style: t.labelMedium?.copyWith(letterSpacing: 1, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Tx('Mi perfil'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/perfil/editar'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Tx('Editar'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(children: [
        // Mi carta de jugador en la liga activa
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: CartaJugador(miembro: mi.yo, resumen: resumen),
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => context.push('/ficha/${mi.yo.id}'),
            icon: const Icon(Icons.insights_outlined, size: 18),
            label: Text(trf('Ver mi ficha completa en {liga}', {'liga': mi.liga.nombre})),
          ),
        ),

        seccion('Mis ligas'),
        for (final l in ligas)
          ListTile(
            leading: CircleAvatar(radius: 8, backgroundColor: colorDeLiga(ligas, l.liga.id)),
            title: Text(l.liga.nombre),
            subtitle: Text('${l.liga.formato}${l.soyAdmin ? ' · ${tr('Administrador')}' : ''}'),
            trailing: l.liga.id == mi.liga.id
                ? Chip(label: Tx('Activa'), visualDensity: VisualDensity.compact)
                : TextButton(
                    onPressed: () => ref.read(ligaActivaIdProvider.notifier).elegir(l.liga.id),
                    child: const Tx('Ver esta'),
                  ),
          ),
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: const Tx('Crear o unirse a otra liga'),
          onTap: () => context.push('/onboarding'),
        ),

        seccion('Tienda'),
        ListTile(
          leading: Icon(ventajas.sinAnuncios ? Icons.verified_rounded : Icons.storefront_outlined,
              color: ventajas.sinAnuncios ? const Color(0xFF2E7D32) : cs.tertiary),
          title: const Tx('Tienda y códigos'),
          subtitle: Tx(ventajas.sinAnuncios ? 'Sin anuncios' : 'Quitar anuncios, dinero Fantasy y canjear códigos'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/tienda'),
        ),

        seccion('Ayuda'),
        if (ref.watch(esMasterProvider).valueOrNull == true)
          ListTile(
            leading: Icon(Icons.shield_outlined, color: cs.tertiary),
            title: const Tx('Panel máster'),
            subtitle: const Text('Control interno, códigos promocionales y registro'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/master'),
          ),
        ListTile(
          leading: const Icon(Icons.lightbulb_outline),
          title: const Tx('Cómo funciona'),
          subtitle: const Tx('Las 3 tarjetas de bienvenida'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => SinPublicidad(child: Bienvenida(fantasy: mi.liga.fantasyActivo)))),
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Tx('Guía y normas'),
          subtitle: const Tx('Palabras de la app, puntos y reglas de tu liga'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/guia'),
        ),

        ListTile(
          leading: const Icon(Icons.rate_review_outlined),
          title: const Tx('Enviar comentarios'),
          subtitle: const Tx('¿Algo no se entiende o falla? Cuéntanoslo'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _comentarios(context),
        ),

        seccion('Preferencias'),
        FutureBuilder<bool>(
          future: Anuncios.hayOpcionesPrivacidad(),
          builder: (_, s) => s.data == true
              ? ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Tx('Privacidad y anuncios'),
                  subtitle: const Tx('Cambia tu consentimiento de anuncios personalizados'),
                  onTap: Anuncios.abrirOpcionesPrivacidad,
                )
              : const SizedBox.shrink(),
        ),
        ListTile(
          leading: const Icon(Icons.translate),
          title: const Text('Idioma · Language'),
          subtitle: Text(idiomas[ref.watch(idiomaProvider)] ?? ''),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showDialog<void>(
            context: context,
            builder: (c) => SimpleDialog(
              title: const Text('Idioma · Language'),
              children: [
                for (final e in idiomas.entries)
                  RadioListTile<String>(
                    value: e.key,
                    groupValue: ref.read(idiomaProvider),
                    title: Text(e.value),
                    onChanged: (v) {
                      Navigator.pop(c);
                      if (v != null) ref.read(idiomaProvider.notifier).elegir(v);
                    },
                  ),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Tx('Apariencia'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Tx('Claro')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Tx('Oscuro')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Tx('Sistema')),
              ],
              selected: {ref.watch(temaProvider)},
              onSelectionChanged: (s) => ref.read(temaProvider.notifier).elegir(s.first),
            ),
          ),
        ),
        seccion('Cuenta'),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(sb.auth.currentUser?.email ?? ''),
          subtitle: Text(etiquetaPosicion(perfil.posicion)),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Tx('Cerrar sesión'),
          onTap: () async {
            if (!await confirmar(context, 'Cerrar sesión', '¿Seguro que quieres salir?')) return;
            await ref.read(ligaActivaIdProvider.notifier).elegir(null);
            await Push.desactivar();
            await sb.auth.signOut();
          },
        ),
        ListTile(
          leading: const Icon(Icons.policy_outlined),
          title: const Tx('Política de privacidad'),
          onTap: () => launchUrl(Uri.parse(urlPrivacidad), mode: LaunchMode.externalApplication),
        ),
        ListTile(
          leading: Icon(Icons.person_remove_outlined, color: Theme.of(context).colorScheme.error),
          title: Tx('Eliminar mi cuenta', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => _eliminarCuenta(context, ref),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// Versión de pruebas: el comentario llega al panel máster (Errores), con la pantalla «comentario».
Future<void> _comentarios(BuildContext context) async {
  final c = TextEditingController();
  final texto = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Tx('Enviar comentarios'),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        maxLength: 2000,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: tr('Qué estabas haciendo, qué esperabas y qué pasó')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Tx('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Tx('Enviar')),
      ],
    ),
  );
  if (texto == null || texto.isEmpty || !context.mounted) return;
  await ejecutar(
    context,
    () => sb.rpc('registrar_error', params: {
      'p_mensaje': 'Comentario: ${texto.length > 480 ? '${texto.substring(0, 480)}…' : texto}',
      'p_traza': texto,
      'p_pantalla': 'comentario',
    }),
    ok: tr('¡Gracias! Lo leeremos.'),
  );
}

const urlPrivacidad = 'https://davidvives90.github.io/futbol-fantasy/privacidad.html';

Future<void> _eliminarCuenta(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Tx('Eliminar mi cuenta'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Se borrarán tu perfil, tu foto y tu acceso. Tus partidos se conservan como «Exjugador» '
              'para no alterar las clasificaciones de tus compañeros. No se puede deshacer.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            onChanged: (_) => setState(() {}),
            decoration:  InputDecoration(labelText: tr('Escribe ELIMINAR para confirmar')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Tx('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: ctrl.text.trim() == 'ELIMINAR' ? () => Navigator.pop(ctx, true) : null,
            child: const Tx('Eliminar'),
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
