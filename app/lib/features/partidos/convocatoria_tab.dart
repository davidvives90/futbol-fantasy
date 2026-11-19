import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../liga/chip_rango.dart';

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
        // Orden real de entrada según la regla de la liga (como `promover_espera` en el servidor).
        final espera = ordenarEspera(de(EstadoInscripcion.espera), miembros, porPrioridad: mi.liga.esperaPorPrioridad);
        final baja = de(EstadoInscripcion.baja);
        final mia = lista.where((i) => i.miembroId == mi.yo.id).firstOrNull;
        final importe = conf.isEmpty ? partido.costeTotal : partido.costeTotal / conf.length;
        final abierta = partido.estado.antesDeJugar;
        String nombre(String id) => miembros[id]?.nombre ?? '…';
        RangoMiembro rangoDeIns(Inscripcion i) => i.rango ?? miembros[i.miembroId]?.rango ?? RangoMiembro.reserva;
        final soyFijo = mi.yo.rango == RangoMiembro.fijo;
        final liga = mi.liga;
        final precioNoFijo = liga.precioInvitado;

        return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          ListTile(
            title: Text('${conf.length}/${partido.plazas} confirmados'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: partido.plazas == 0 ? 0 : (conf.length / partido.plazas).clamp(0.0, 1.0).toDouble(),
              ),
            ),
            trailing: liga.facturaMensual
                ? Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(precioNoFijo == null ? 'Cuota' : euros(precioNoFijo), style: Theme.of(context).textTheme.titleMedium),
                    Text(precioNoFijo == null ? 'reservas: variable' : 'reservas e invitados'),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(euros(importe), style: AppTheme.numero(context, size: 22)),
                    const Text('por jugador'),
                  ]),
          ),
          if (!partido.horaConfirmada)
            ListTile(
              leading: Icon(Icons.schedule, color: AppColores.of(context).aviso),
              title: const Text('Hora pendiente de confirmar'),
            ),
          if (abierta)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                soyFijo
                    ? 'Eres fijo: ya estás dentro. Si no puedes ir, marca "No voy" y entrará el primero de la lista de espera.'
                    : 'Los fijos ya están dentro. Si quieres jugar, pulsa "Voy": entrarás en la lista de espera '
                        'y pasarás a la convocatoria en cuanto un fijo se dé de baja.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (abierta)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<EstadoInscripcion>(
                // Voy = verde éxito · Duda = ámbar · No voy = gris neutro (no es destructivo)
                style: AppButtons.segmentoEstado(context, mia?.estado.name),
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
          _Seccion('Confirmados', conf, nombre, rangoDeIns, numerar: true, mi: mi, partido: partido),
          _Seccion('En duda', duda, nombre, rangoDeIns, mi: mi, partido: partido),
          _Seccion(
            liga.esperaPorPrioridad ? 'Lista de espera · por prioridad' : 'Lista de espera · por orden de apuntarse',
            espera,
            nombre,
            rangoDeIns,
            numerar: true,
            mi: mi,
            partido: partido,
          ),
          _Seccion('No van', baja, nombre, rangoDeIns, mi: mi, partido: partido),
          if (mi.soyAdmin && abierta) _AnadirJugador(partido: partido, mi: mi, yaInscritos: lista.map((i) => i.miembroId).toSet()),
        ]);
      },
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo, this.lista, this.nombre, this.rango,
      {this.numerar = false, required this.mi, required this.partido});
  final String titulo;
  final List<Inscripcion> lista;
  final String Function(String) nombre;
  final RangoMiembro Function(Inscripcion) rango;
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
          title: Row(children: [
            Flexible(
              child: Text(nombre(ins.miembroId) + (ins.miembroId == mi.yo.id ? ' (tú)' : ''), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            ChipRango(rango(ins), corto: true),
          ]),
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
