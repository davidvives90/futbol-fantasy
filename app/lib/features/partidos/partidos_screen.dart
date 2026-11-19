import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../fantasy/fantasy_screen.dart';
import '../shell/home_shell.dart';

class PartidosScreen extends ConsumerWidget {
  const PartidosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final partidos = ref.watch(partidosProvider(mi.liga.id));

    return Scaffold(
      appBar: LigaAppBar(actions: [
        if (mi.soyAdmin)
          IconButton(
            tooltip: 'Programar temporada',
            icon: const Icon(Icons.event_repeat),
            onPressed: () => context.push('/temporada'),
          ),
      ]),
      floatingActionButton: mi.soyAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/partidos/nuevo'),
              icon: const Icon(Icons.add),
              label: const Text('Partido'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(partidosProvider(mi.liga.id).future),
        child: partidos.when(
          loading: () => const Cargando(),
          error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(partidosProvider(mi.liga.id))),
          data: (lista) {
            if (lista.isEmpty) {
              return ListView(children: [
                SizedBox(
                  height: 400,
                  child: Vacio(
                    mi.soyAdmin ? 'Aún no hay partidos. Crea el primero con el botón +.' : 'Aún no hay partidos convocados.',
                    icono: Icons.sports_soccer,
                  ),
                ),
              ]);
            }
            final ahora = DateTime.now();
            final proximos = lista
                .where((p) => p.fechaHora.isAfter(ahora.subtract(const Duration(hours: 3))) && p.estado.antesDeJugar)
                .toList()
              ..sort((a, b) => a.fechaHora.compareTo(b.fechaHora));
            final resto = lista.where((p) => !proximos.contains(p)).toList();

            return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              EncuestaPendienteCard(mi: mi),
              if (proximos.isNotEmpty) _ProximoPartido(partido: proximos.first, mi: mi),
              for (final p in proximos.skip(1)) _FilaPartido(p),
              if (resto.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text('Anteriores', style: Theme.of(context).textTheme.titleSmall),
                ),
              for (final p in resto) _FilaPartido(p),
            ]);
          },
        ),
      ),
    );
  }
}

class _ProximoPartido extends ConsumerWidget {
  const _ProximoPartido({required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(convocatoriaProvider(partido.id)).valueOrNull ?? const [];
    final confirmados = conv.where((i) => i.estado == EstadoInscripcion.confirmado).length;
    final mio = conv.where((i) => i.miembroId == mi.yo.id).firstOrNull?.estado;
    final importe = confirmados == 0 ? null : partido.costeTotal / confirmados;
    final t = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/partidos/${partido.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Próximo partido', style: t.labelLarge),
            const SizedBox(height: 4),
            Text(fechaHora(partido.fechaHora), style: t.headlineSmall),
            if (!partido.horaConfirmada)
              Text('Hora pendiente de confirmar', style: TextStyle(color: AppColores.of(context).aviso)),
            const SizedBox(height: 8),
            Text(mi.liga.campoNombre ?? 'Campo sin indicar'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: partido.plazas == 0 ? 0 : (confirmados / partido.plazas).clamp(0.0, 1.0).toDouble()),
            const SizedBox(height: 8),
            Row(children: [
              Text('$confirmados/${partido.plazas} confirmados'),
              const Spacer(),
              if (importe != null) Text('${euros(importe)}/jugador') else if (mi.liga.precioEstimado != null) Text('~${euros(mi.liga.precioEstimado)}/jugador'),
            ]),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(switch (mio) {
                EstadoInscripcion.confirmado => Icons.check_circle,
                EstadoInscripcion.espera => Icons.hourglass_top,
                EstadoInscripcion.duda => Icons.help,
                EstadoInscripcion.baja => Icons.cancel,
                null => Icons.radio_button_unchecked,
              }),
              label: Text(switch (mio) {
                EstadoInscripcion.confirmado => 'Vas',
                EstadoInscripcion.espera => 'En lista de espera',
                EstadoInscripcion.duda => 'En duda',
                EstadoInscripcion.baja => 'No vas',
                null => 'Sin responder: toca para apuntarte',
              }),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FilaPartido extends StatelessWidget {
  const _FilaPartido(this.p);
  final Partido p;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.event),
        title: Text(fechaHora(p.fechaHora)),
        subtitle: Text(p.estado.etiqueta + (!p.horaConfirmada && p.estado.antesDeJugar ? ' · hora por confirmar' : '')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/partidos/${p.id}'),
      );
}
