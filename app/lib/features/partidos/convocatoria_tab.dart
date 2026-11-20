import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../liga/chip_rango.dart';
import '../../core/avatar.dart';
import 'selector_asistencia.dart';
import '../../core/info.dart';

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
        final todos = ref.watch(partidosProvider(mi.liga.id)).valueOrNull ?? const <Partido>[];
        final abreEn = mi.liga.abreConvocatoria(partido, todos);
        final abierta = partido.estado.antesDeJugar && abreEn == null;
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
          if (abreEn != null)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.lock_clock),
                title: Text('La convocatoria se abre el ${fechaHora(abreEn)}'),
                subtitle: Text('${mi.liga.horasAperturaConvocatoria} h después de acabar el partido anterior. '
                    'Te avisaremos para que pulses «Voy».'),
              ),
            ),
          if (abierta)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                liga.conApertura
                    ? (soyFijo
                        ? 'Eres fijo: tienes plaza guardada hasta el ${fechaHora(liga.finReservaFijos(partido))}. '
                            'Pulsa «Voy» o «No voy» antes; después tu plaza pasa a la lista de espera.'
                        : 'Los fijos tienen plaza guardada hasta el ${fechaHora(liga.finReservaFijos(partido))}. '
                            'Si pulsas «Voy» y no queda hueco, entras en la lista de espera y te avisamos si hay plaza.')
                    : (soyFijo
                        ? 'Eres fijo: ya estás dentro. Si no puedes ir, marca "No voy" y entrará el primero de la lista de espera.'
                        : 'Los fijos ya están dentro. Si quieres jugar, pulsa "Voy": entrarás en la lista de espera '
                            'y pasarás a la convocatoria en cuanto un fijo se dé de baja.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (abierta)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SelectorAsistencia(partido: partido, mi: mi, actual: mia?.estado),
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
          _Seccion('Confirmados', conf, nombre, rangoDeIns, numerar: true, mi: mi, partido: partido, miembros: miembros),
          _Seccion('En duda', duda, nombre, rangoDeIns, mi: mi, partido: partido, miembros: miembros),
          _Seccion(
            liga.esperaPorPrioridad ? 'Lista de espera · por prioridad' : 'Lista de espera · por orden de apuntarse',
            espera,
            nombre,
            rangoDeIns,
            numerar: true,
            mi: mi,
            partido: partido,
            miembros: miembros,
          ),
          _Seccion('No van', baja, nombre, rangoDeIns, mi: mi, partido: partido, miembros: miembros),
          if (mi.soyAdmin && partido.estado.antesDeJugar)
            _AnadirJugador(
              partido: partido,
              mi: mi,
              yaInscritos: lista.where((i) => i.estado != EstadoInscripcion.baja).map((i) => i.miembroId).toSet(),
            ),
        ]);
      },
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo, this.lista, this.nombre, this.rango,
      {this.numerar = false, required this.mi, required this.partido, required this.miembros});
  final Map<String, Miembro> miembros;
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
        child: Row(children: [
          Flexible(child: Text('$titulo (${lista.length})', style: Theme.of(context).textTheme.titleSmall)),
          if (titulo.startsWith('Lista de espera')) const InfoBoton(Ayuda.listaEspera),
        ]),
      ),
      for (final (i, ins) in lista.indexed)
        ListTile(
          dense: true,
          leading: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 22,
              child: numerar
                  ? Text('${i + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant))
                  : null,
            ),
            const SizedBox(width: 6),
            AvatarMiembro(miembros[ins.miembroId], radio: 16),
          ]),
          selected: ins.miembroId == mi.yo.id,
          title: Row(children: [
            Flexible(
              child: Text(nombre(ins.miembroId) + (ins.miembroId == mi.yo.id ? ' (tú)' : ''), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            ChipRango(rango(ins), corto: true),
          ]),
          // El admin puede dar de baja a otro (p. ej. avisó por WhatsApp).
          // El admin puede dar de baja a otro (p. ej. avisó por WhatsApp) y volver a apuntarlo.
          trailing: !(mi.soyAdmin && partido.estado.antesDeJugar)
              ? null
              : ins.estado == EstadoInscripcion.baja
                  ? IconButton(
                      tooltip: 'Volver a apuntar',
                      icon: Icon(Icons.person_add_alt_1_outlined, color: Theme.of(context).colorScheme.primary),
                      onPressed: () => ejecutar(
                        context,
                        () => PartidosRepo.cambiarEstado(partido.id, ins.miembroId, EstadoInscripcion.confirmado),
                        ok: 'Apuntado (si no hay plaza, entra en la lista de espera)',
                      ),
                    )
                  : IconButton(
                      tooltip: 'Dar de baja',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () async {
                        final antes = ins.estado;
                        final ok = await ejecutar(
                          context,
                          () => PartidosRepo.cambiarEstado(partido.id, ins.miembroId, EstadoInscripcion.baja),
                        );
                        if (ok && context.mounted) {
                          avisoDeshacer(context, '${nombre(ins.miembroId)} ya no va',
                              () => PartidosRepo.cambiarEstado(partido.id, ins.miembroId, antes));
                        }
                      },
                    ),
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
