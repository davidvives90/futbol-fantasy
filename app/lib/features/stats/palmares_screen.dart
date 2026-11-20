import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/avatar.dart';
import '../../core/compartir.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/stats_repo.dart';
import 'clasificacion_screen.dart';

final temporadasProvider = FutureProvider.autoDispose.family<List<TemporadaCerrada>, String>(
  (ref, ligaId) => StatsRepo.temporadas(ligaId),
);

/// Palmarés: temporadas cerradas con sus premios y su clasificación final.
class PalmaresScreen extends ConsumerWidget {
  const PalmaresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final datos = ref.watch(temporadasProvider(mi.liga.id));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));

    return Scaffold(
      appBar: AppBar(
        title: const Tx('Palmarés'),
        actions: [
          if (mi.soyAdmin && (datos.valueOrNull?.isNotEmpty ?? false))
            PopupMenuButton<String>(
              onSelected: (_) => _reabrir(context, ref, mi),
              itemBuilder: (_) => const [PopupMenuItem(value: 'reabrir', child: Tx('Reabrir la última temporada'))],
            ),
        ],
      ),
      floatingActionButton: mi.soyAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _cerrar(context, ref, mi),
              icon: const Icon(Icons.flag_outlined),
              label: const Tx('Cerrar temporada'),
            )
          : null,
      body: datos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(temporadasProvider(mi.liga.id))),
        data: (lista) {
          if (lista.isEmpty) {
            return Vacio(
              mi.soyAdmin
                  ? 'Cuando acabe la temporada, ciérrala: se guarda la clasificación, se reparten los premios '
                      '(campeón, pichichi, MVP, el más fiel…) y la clasificación empieza de cero.'
                  : 'Cuando el administrador cierre la temporada, aquí quedarán los campeones y sus premios.',
              icono: Icons.emoji_events_outlined,
              titulo: 'Aún no hay temporadas cerradas',
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 96), children: [
            for (final t in lista) _TarjetaTemporada(t: t, miembros: miembros, liga: mi.liga),
          ]);
        },
      ),
    );
  }

  Future<void> _cerrar(BuildContext context, WidgetRef ref, MiLiga mi) async {
    final nombre = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Tx('Cerrar temporada'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Se guarda la clasificación, se reparten los premios y la clasificación de la nueva temporada '
              'empieza de cero (el histórico se conserva).'),
          const SizedBox(height: 12),
          TextField(
            controller: nombre,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'p. ej. Temporada 25/26'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Tx('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cerrar y dar premios')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final hecho = await ejecutar(context, () => StatsRepo.cerrarTemporada(mi.liga.id, nombre.text.trim()),
        ok: '🏆 Temporada cerrada');
    if (hecho) {
      ref.invalidate(temporadasProvider(mi.liga.id));
      ref.invalidate(inicioTemporadaProvider(mi.liga.id));
    }
  }

  Future<void> _reabrir(BuildContext context, WidgetRef ref, MiLiga mi) async {
    if (!await confirmar(context, 'Reabrir la última temporada',
        'Se borran sus premios y su clasificación guardada, y sus partidos vuelven a contar en la temporada en curso.',
        accion: 'Reabrir', tipo: TipoConfirmacion.peligro)) {
      return;
    }
    if (!context.mounted) return;
    final ok = await ejecutar(context, () => StatsRepo.reabrirTemporada(mi.liga.id));
    if (ok) {
      ref.invalidate(temporadasProvider(mi.liga.id));
      ref.invalidate(inicioTemporadaProvider(mi.liga.id));
    }
  }
}

class _TarjetaTemporada extends StatelessWidget {
  const _TarjetaTemporada({required this.t, required this.miembros, required this.liga});
  final TemporadaCerrada t;
  final Map<String, Miembro> miembros;
  final Liga liga;

  String _texto() {
    final b = StringBuffer('🏆 *${liga.nombre} · ${t.nombre}*\n${t.partidos} partidos\n\n');
    for (final tipo in premiosInfo.keys) {
      final ps = t.premios.where((p) => p.tipo == tipo).toList();
      if (ps.isEmpty) continue;
      final i = premiosInfo[tipo]!;
      b.writeln('${i.icono} ${i.titulo}: ${ps.map((p) => miembros[p.miembroId]?.nombre ?? '…').join(', ')} (${i.dato(ps.first.valor)})');
    }
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final t2 = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final clasif = t.clasificacion;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.nombre, style: t2.titleLarge),
                Text('${fechaCorta(t.desde)} – ${fechaCorta(t.hasta)} · ${t.partidos} partidos',
                    style: t2.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            IconButton(
              tooltip: 'Compartir premios',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => compartirTexto(context, _texto()),
            ),
          ]),
          const SizedBox(height: 8),
          for (final tipo in premiosInfo.keys)
            if (t.premios.any((p) => p.tipo == tipo))
              _FilaPremio(
                info: premiosInfo[tipo]!,
                premios: t.premios.where((p) => p.tipo == tipo).toList(),
                miembros: miembros,
              ),
          if (clasif.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Tx('Clasificación final'),
              children: [
                for (var i = 0; i < clasif.length && i < 20; i++)
                  ListTile(
                    dense: true,
                    leading: SizedBox(width: 24, child: Text('${i + 1}', textAlign: TextAlign.center)),
                    title: Text(miembros[clasif[i].miembroId]?.nombre ?? 'Exjugador'),
                    subtitle: Text('${clasif[i].partidos} PJ · ${clasif[i].goles} goles · ${clasif[i].mvps} MVP'),
                    trailing: Text('${clasif[i].puntosTotal.toStringAsFixed(0)} pts'),
                    onTap: () => context.push('/clasificacion/jugador/${clasif[i].miembroId}'),
                  ),
              ],
            ),
        ]),
      ),
    );
  }
}

class _FilaPremio extends StatelessWidget {
  const _FilaPremio({required this.info, required this.premios, required this.miembros});
  final ({String icono, String titulo, String Function(num?) dato}) info;
  final List<Premio> premios;
  final Map<String, Miembro> miembros;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 32, child: Text(info.icono, style: const TextStyle(fontSize: 22))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(info.titulo, style: Theme.of(context).textTheme.labelMedium),
              Text(premios.map((p) => miembros[p.miembroId]?.nombre ?? 'Exjugador').join(', '),
                  style: Theme.of(context).textTheme.titleSmall),
            ]),
          ),
          PilaAvatares([for (final p in premios) miembros[p.miembroId]], radio: 12, max: 3),
          const SizedBox(width: 8),
          Text(info.dato(premios.first.valor), style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
