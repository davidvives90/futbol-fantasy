import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import '../liga/asistencia_screen.dart';
import '../../data/repos/reglamento_repo.dart';
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
import '../../core/compartir.dart';
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
        final pend = de(EstadoInscripcion.pendiente);
        final duda = de(EstadoInscripcion.duda);
        // Suplentes en su orden real de entrada (como `rellenar_plazas` en el servidor)
        final espera = ordenarEspera(de(EstadoInscripcion.espera), miembros, porPrioridad: mi.liga.fijosPrimero);
        // Los lesionados / de baja larga salen aparte, no en «No van»
        final idsDeBaja = {
          for (final a in ref.watch(bajasLigaProvider(mi.liga.id)).valueOrNull ?? const <Ausencia>[])
            if (a.cubre(partido.fechaHora.toLocal())) a.miembroId
        };
        final baja = de(EstadoInscripcion.baja).where((i) => !idsDeBaja.contains(i.miembroId)).toList();
        final ocupadas = conf.length + pend.length + duda.length;
        final mia = lista.where((i) => i.miembroId == mi.yo.id).firstOrNull;
        final importe = conf.isEmpty ? partido.costeTotal : partido.costeTotal / conf.length;
        final todos = ref.watch(partidosProvider(mi.liga.id)).valueOrNull ?? const <Partido>[];
        // 0050: cada uno puede contestar cuando le toca (en «turnos», fijos → reservas → invitados)
        final abreEn = mi.liga.abreConvocatoriaPara(partido, todos, mi.yo.rango);
        final soyFijo = mi.yo.rango == RangoMiembro.fijo;
        final puedoContestar = partido.estado.antesDeJugar && (abreEn == null || mia != null);
        // Modo «mínimo»: hora a la que se decide si hay partido
        final minimo = mi.liga.modoConvocatoria == 'minimo' ? (mi.liga.minimoJugadores ?? partido.plazas) : null;
        final decide = partido.fechaHora.subtract(Duration(hours: mi.liga.horasDecision));
        String nombre(String id) => miembros[id]?.nombre ?? '…';
        RangoMiembro rangoDeIns(Inscripcion i) => i.rango ?? miembros[i.miembroId]?.rango ?? RangoMiembro.reserva;
        final liga = mi.liga;
        final precioNoFijo = liga.precioInvitado;
        final todosContestaron = pend.isEmpty && duda.isEmpty;
        final puesto = mia?.estado == EstadoInscripcion.espera
            ? espera.indexWhere((i) => i.miembroId == mi.yo.id) + 1
            : null;
        String texto() => textoConvocatoria(liga: liga, partido: partido, lista: lista, suplentes: espera, nombre: nombre);

        return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          ListTile(
            title: Text(trf('Van {n} de {p}', {'n': ocupadas, 'p': partido.plazas}),
                style: Theme.of(context).textTheme.titleLarge),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: partido.plazas == 0 ? 0 : (ocupadas / partido.plazas).clamp(0.0, 1.0).toDouble(),
              ),
            ),
            trailing: liga.facturaMensual
                ? Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(precioNoFijo == null ? tr('Cuota') : euros(precioNoFijo), style: Theme.of(context).textTheme.titleMedium),
                    Text(tr(precioNoFijo == null ? 'reservas: variable' : 'reservas e invitados')),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(euros(importe), style: AppTheme.numero(context, size: 22)),
                    const Tx('por jugador'),
                  ]),
          ),
          if (!partido.horaConfirmada)
            ListTile(
              leading: Icon(Icons.schedule, color: AppColores.of(context).aviso),
              title: const Tx('Hora pendiente de confirmar'),
            ),
          if (abreEn != null && mia == null)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.lock_clock),
                title: Text(trf('Podrás apuntarte el {f}', {'f': fechaHora(abreEn)})),
                subtitle: liga.modoConvocatoria == 'turnos'
                    ? const Tx('Por turnos: primero los fijos, luego las reservas y al final los invitados.')
                    : null,
              ),
            ),
          if (minimo != null && partido.estado.antesDeJugar)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              color: ocupadas >= minimo ? null : Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                leading: Icon(ocupadas >= minimo ? Icons.check_circle_outline : Icons.groups_outlined),
                title: Text(ocupadas >= minimo
                    ? trf('Hay mínimo: {n} de {m}', {'n': ocupadas, 'm': minimo})
                    : trf('Faltan {n} para llegar al mínimo ({m})', {'n': minimo - ocupadas, 'm': minimo})),
                subtitle: decide.isAfter(DateTime.now())
                    ? Text(trf('Si el {f} no se llega, el partido se cancela solo.', {'f': fechaHora(decide)}))
                    : null,
              ),
            ),
          if (puedoContestar)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SelectorAsistencia(partido: partido, mi: mi, actual: mia?.estado, puesto: puesto),
            ),
          if (puedoContestar && soyFijo)
            Align(
              child: TextButton.icon(
                icon: const Icon(Icons.healing, size: 18),
                label: const Tx('¿Lesión o ausencia larga? Avisar de baja'),
                onPressed: () => registrarBaja(context, ref, mi),
              ),
            ),
          // Pasar la convocatoria al grupo de WhatsApp (con negritas)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              color: todosContestaron ? Theme.of(context).colorScheme.primaryContainer : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    tr(todosContestaron
                        ? 'Todos los fijos han contestado: pasa la convocatoria al grupo'
                        : 'Pasa la convocatoria al grupo de WhatsApp'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Tx('Copiar'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: texto()));
                          if (context.mounted) mostrarOk(context, 'Copiada: pégala en el grupo');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.share),
                        label: const Tx('WhatsApp'),
                        onPressed: () => compartirTexto(context, texto()),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
          _Seccion('Van', conf, nombre, rangoDeIns, numerar: true, mi: mi, partido: partido, miembros: miembros),
          _Seccion('Sin confirmar', pend, nombre, rangoDeIns, mi: mi, partido: partido, miembros: miembros),
          _Seccion('En duda', duda, nombre, rangoDeIns, mi: mi, partido: partido, miembros: miembros),
          _Seccion('Suplentes · por orden', espera, nombre, rangoDeIns,
              numerar: true, mi: mi, partido: partido, miembros: miembros),
          _Seccion('No van', baja, nombre, rangoDeIns, mi: mi, partido: partido, miembros: miembros),
          // Lesionados y ausentes en la fecha del partido (no reciben avisos ni ocupan plaza de fijo)
          ...() {
            final enLista = {for (final i in lista) if (i.estado != EstadoInscripcion.baja) i.miembroId};
            final deBaja = (ref.watch(bajasLigaProvider(mi.liga.id)).valueOrNull ?? const <Ausencia>[])
                .where((a) => a.cubre(partido.fechaHora.toLocal()) && !enLista.contains(a.miembroId))
                .toList();
            if (deBaja.isEmpty) return const <Widget>[];
            return <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(trf('De baja ({n})', {'n': deBaja.length}), style: Theme.of(context).textTheme.titleSmall),
              ),
              for (final a in deBaja)
                ListTile(
                  dense: true,
                  leading: AvatarMiembro(miembros[a.miembroId], radio: 14),
                  title: Text(nombre(a.miembroId)),
                  subtitle: Text(textoBaja(a)),
                  trailing: Icon(Icons.healing, color: Colors.amber.shade700, size: 20),
                ),
            ];
          }(),
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

class _Seccion extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    if (lista.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(children: [
          Flexible(child: Text('${tr(titulo)} (${lista.length})', style: Theme.of(context).textTheme.titleSmall)),
          if (titulo.startsWith('Suplentes')) const InfoBoton(Ayuda.listaEspera),
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
              child: Text(nombre(ins.miembroId) + (ins.miembroId == mi.yo.id ? tr(' (tú)') : '') + (ins.capitan ? ' (C)' : ''),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            ChipRango(rango(ins), corto: true),
          ]),
          // El admin puede dar de baja a otro (p. ej. avisó por WhatsApp).
          // El admin puede dar de baja a otro (p. ej. avisó por WhatsApp) y volver a apuntarlo.
          // El admin cambia a otro (avisó por WhatsApp) o le pone una baja larga (lesión…)
          trailing: !(mi.soyAdmin && partido.estado.antesDeJugar)
              ? null
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (op) async {
                    final antes = ins.estado;
                    if (op == 'lesion') {
                      await registrarBaja(context, ref, mi, miembroId: ins.miembroId);
                      return;
                    }
                    final nuevo = switch (op) {
                      'va' => EstadoInscripcion.confirmado,
                      'duda' => EstadoInscripcion.duda,
                      _ => EstadoInscripcion.baja,
                    };
                    final ok = await ejecutar(context, () => PartidosRepo.cambiarEstado(partido.id, ins.miembroId, nuevo));
                    if (ok && context.mounted) {
                      avisoDeshacer(context, tr('Cambiado'),
                          () => PartidosRepo.cambiarEstado(partido.id, ins.miembroId, antes));
                    }
                  },
                  itemBuilder: (_) => [
                    if (ins.estado != EstadoInscripcion.confirmado) PopupMenuItem(value: 'va', child: Text(tr('Va'))),
                    if (ins.estado != EstadoInscripcion.duda && ins.estado.ocupaPlaza)
                      PopupMenuItem(value: 'duda', child: Text(tr('Duda'))),
                    if (ins.estado != EstadoInscripcion.baja) PopupMenuItem(value: 'no', child: Text(tr('No va'))),
                    if (rango(ins) == RangoMiembro.fijo)
                      PopupMenuItem(value: 'lesion', child: Text(tr('Baja larga (lesión…)'))),
                  ],
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
        label: const Tx('Apuntar a otro jugador'),
        onPressed: () async {
          final elegido = await showModalBottomSheet<Miembro>(
            context: context,
            builder: (c) => ListView(children: [
              for (final m in disponibles)
                ListTile(
                  title: Text(m.nombre),
                  subtitle: m.registrado ? null : const Tx('Sin registrar'),
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
