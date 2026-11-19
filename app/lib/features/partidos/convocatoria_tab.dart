import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';

/// Lista de inscritos en tiempo real + botones Voy / Duda / No voy.
class ConvocatoriaTab extends ConsumerWidget {
  const ConvocatoriaTab({super.key, required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(convocatoriaProvider(partido.id));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));

    return conv.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(convocatoriaProvider(partido.id))),
      data: (lista) {
        List<Inscripcion> de(EstadoInscripcion e) => lista.where((i) => i.estado == e).toList();
        final conf = de(EstadoInscripcion.confirmado);
        final duda = de(EstadoInscripcion.duda);
        final espera = de(EstadoInscripcion.espera);
        final baja = de(EstadoInscripcion.baja);
        final mia = lista.where((i) => i.miembroId == mi.yo.id).firstOrNull;
        final importe = conf.isEmpty ? partido.costeTotal : partido.costeTotal / conf.length;
        final abierta = partido.estado.antesDeJugar;
        String nombre(String id) => miembros[id]?.nombre ?? '…';

        return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          ListTile(
            title: Text('${conf.length}/${partido.plazas} confirmados'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: partido.plazas == 0 ? 0 : (conf.length / partido.plazas).clamp(0.0, 1.0).toDouble(),
              ),
            ),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(euros(importe), style: Theme.of(context).textTheme.titleMedium),
              const Text('por jugador'),
            ]),
          ),
          if (!partido.horaConfirmada)
            const ListTile(
              leading: Icon(Icons.schedule, color: Colors.orange),
              title: Text('Hora pendiente de confirmar'),
            ),
          if (abierta)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<EstadoInscripcion>(
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: EstadoInscripcion.confirmado, label: Text('Voy'), icon: Icon(Icons.check)),
                  ButtonSegment(value: EstadoInscripcion.duda, label: Text('Duda'), icon: Icon(Icons.help_outline)),
                  ButtonSegment(value: EstadoInscripcion.baja, label: Text('No voy'), icon: Icon(Icons.close)),
                ],
                selected: {
                  if (mia != null)
                    mia.estado == EstadoInscripcion.espera ? EstadoInscripcion.confirmado : mia.estado,
                },
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  ejecutar(context, () => PartidosRepo.cambiarEstado(partido.id, mi.yo.id, s.first));
                },
              ),
            ),
          if (mia?.estado == EstadoInscripcion.espera)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.hourglass_top),
                  title: Text('Estás en lista de espera (puesto ${espera.indexWhere((i) => i.miembroId == mi.yo.id) + 1})'),
                  subtitle: const Text('Entrarás automáticamente si alguien se da de baja.'),
                ),
              ),
            ),
          _Seccion('Confirmados', conf, nombre, numerar: true, mi: mi, partido: partido),
          _Seccion('En duda', duda, nombre, mi: mi, partido: partido),
          _Seccion('Lista de espera', espera, nombre, numerar: true, mi: mi, partido: partido),
          _Seccion('No van', baja, nombre, mi: mi, partido: partido),
          if (mi.soyAdmin && abierta) _AnadirJugador(partido: partido, mi: mi, yaInscritos: lista.map((i) => i.miembroId).toSet()),
        ]);
      },
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo, this.lista, this.nombre, {this.numerar = false, required this.mi, required this.partido});
  final String titulo;
  final List<Inscripcion> lista;
  final String Function(String) nombre;
  final bool numerar;
  final MiLiga mi;
  final Partido partido;

  @override
  Widget build(BuildContext context) {
    if (lista.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('$titulo (${lista.length})', style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final (i, ins) in lista.indexed)
        ListTile(
          dense: true,
          leading: numerar ? CircleAvatar(radius: 14, child: Text('${i + 1}')) : const SizedBox(width: 28),
          title: Text(nombre(ins.miembroId) + (ins.miembroId == mi.yo.id ? ' (tú)' : '')),
          // El admin puede dar de baja a otro (p. ej. avisó por WhatsApp).
          trailing: mi.soyAdmin && partido.estado.antesDeJugar && ins.estado != EstadoInscripcion.baja
              ? IconButton(
                  tooltip: 'Dar de baja',
                  icon: const Icon(Icons.person_remove_outlined),
                  onPressed: () => ejecutar(
                    context,
                    () => PartidosRepo.cambiarEstado(partido.id, ins.miembroId, EstadoInscripcion.baja),
                  ),
                )
              : null,
        ),
    ]);
  }
}

/// El admin apunta a un miembro que no usa la app (o un pre-creado).
class _AnadirJugador extends ConsumerWidget {
  const _AnadirJugador({required this.partido, required this.mi, required this.yaInscritos});
  final Partido partido;
  final MiLiga mi;
  final Set<String> yaInscritos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final miembros = ref.watch(miembrosProvider(mi.liga.id)).valueOrNull ?? const <Miembro>[];
    final disponibles = miembros
        .where((m) =>
            !yaInscritos.contains(m.id) &&
            (m.estado == EstadoMiembro.activo || m.estado == EstadoMiembro.pendiente_registro))
        .toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
    if (disponibles.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Apuntar a otro jugador'),
        onPressed: () async {
          final elegido = await showModalBottomSheet<Miembro>(
            context: context,
            builder: (c) => ListView(children: [
              for (final m in disponibles)
                ListTile(
                  title: Text(m.nombre),
                  subtitle: m.registrado ? null : const Text('Sin registrar'),
                  onTap: () => Navigator.pop(c, m),
                ),
            ]),
          );
          if (elegido != null && context.mounted) {
            await ejecutar(context, () => PartidosRepo.cambiarEstado(partido.id, elegido.id, EstadoInscripcion.confirmado));
          }
        },
      ),
    );
  }
}
