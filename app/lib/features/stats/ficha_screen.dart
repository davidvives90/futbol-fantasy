import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/stats_repo.dart';

final historialProvider = FutureProvider.autoDispose.family<List<PuntosFantasy>, String>(
  (ref, miembroId) => StatsRepo.historial(miembroId),
);

/// Ficha de un jugador: totales y puntos por partido.
class FichaScreen extends ConsumerWidget {
  const FichaScreen({super.key, required this.miembroId, this.conAppBar = true});
  final String miembroId;
  final bool conAppBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final miembro = ref.watch(miembrosPorIdProvider(mi.liga.id))[miembroId];
    final rend = (ref.watch(rendimientoProvider(mi.liga.id)).valueOrNull ?? const <Rendimiento>[])
        .where((r) => r.miembroId == miembroId)
        .firstOrNull;
    final historial = ref.watch(historialProvider(miembroId));

    final cuerpo = ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        CircleAvatar(radius: 32, child: Text(miembro?.inicial ?? '?', style: const TextStyle(fontSize: 28))),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(miembro?.nombre ?? '…', style: Theme.of(context).textTheme.headlineSmall),
            Text(etiquetaPosicion(miembro?.posicion)),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      if (rend == null)
        const Text('Aún no ha jugado ningún partido cerrado.')
      else
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.4,
          children: [
            _Dato('Puntos', rend.puntosTotal.toStringAsFixed(0)),
            _Dato('Partidos', '${rend.partidos}'),
            _Dato('Media', rend.puntosMedia.toStringAsFixed(1)),
            _Dato('Goles', '${rend.goles}'),
            _Dato('Asistencias', '${rend.asistencias}'),
            _Dato('MVPs', '${rend.mvps}'),
            _Dato('Nota media', rend.notaMedia?.toStringAsFixed(1) ?? '—'),
            _Dato('Goles/partido', rend.golesPartido.toStringAsFixed(2)),
            _Dato('% victorias', rend.pctVictorias == null ? '—' : '${rend.pctVictorias!.toStringAsFixed(0)} %'),
          ],
        ),
      const SizedBox(height: 16),
      Text('Puntos por partido', style: Theme.of(context).textTheme.titleMedium),
      ...historial.when(
        loading: () => [const Padding(padding: EdgeInsets.all(24), child: Cargando())],
        error: (e, _) => [ErrorVista(e)],
        data: (lista) {
          if (lista.isEmpty) return [const Padding(padding: EdgeInsets.all(16), child: Text('Sin partidos todavía.'))];
          final maximo = lista.map((p) => p.total.abs()).fold<double>(1, (a, b) => b > a ? b : a);
          return [
            for (final p in lista)
              ListTile(
                dense: true,
                leading: p.esMvp ? const Icon(Icons.star, color: Colors.amber) : const Icon(Icons.sports_soccer),
                title: Text(p.fecha == null ? 'Partido' : fechaCorta(p.fecha!)),
                subtitle: LinearProgressIndicator(value: (p.total.abs() / maximo).clamp(0.0, 1.0).toDouble()),
                trailing: Text(p.total.toStringAsFixed(p.total % 1 == 0 ? 0 : 1)),
              ),
          ];
        },
      ),
    ]);

    if (!conAppBar) return cuerpo;
    return Scaffold(appBar: AppBar(title: Text(miembro?.nombre ?? 'Jugador')), body: cuerpo);
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);
  final String etiqueta, valor;

  @override
  Widget build(BuildContext context) => Card(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(valor, style: Theme.of(context).textTheme.titleLarge),
          Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
