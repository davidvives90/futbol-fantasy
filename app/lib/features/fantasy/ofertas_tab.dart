import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';
import 'fantasy_providers.dart';
import 'widgets_fantasy.dart';

/// Pestaña "Ofertas": ofertas recibidas y enviadas, y cesiones disponibles para el próximo partido.
class OfertasTab extends ConsumerWidget {
  const OfertasTab({super.key, required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ligaId = mi.liga.id;
    final k = (ligaId: ligaId, miembroId: mi.yo.id);
    final ofertas = ref.watch(misOfertasProvider(ligaId));
    final cesiones = ref.watch(cesionesDisponiblesProvider(ligaId));
    final plantilla = ref.watch(miPlantillaProvider(k)).valueOrNull ?? const <JugadorPlantilla>[];
    final miembros = ref.watch(miembrosPorIdProvider(ligaId));
    final saldo = ref.watch(miManagerProvider(k)).valueOrNull?.saldo;
    final t = Theme.of(context).textTheme;

    final yaRecibida = plantilla.any((j) => j.cedidaAMi);
    final yaCedida = plantilla.any((j) => j.cedidaAOtro || j.enCesionOfrecida);

    return RefreshIndicator(
      onRefresh: () async => refrescarFantasy(ref, k),
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
        ofertas.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Cargando()),
          error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(misOfertasProvider(ligaId))),
          data: (lista) {
            final recibidas = lista.where((o) => o.recibida).toList();
            final enviadas = lista.where((o) => !o.recibida).toList();
            int orden(Oferta o) => o.pendiente ? 0 : 1;
            recibidas.sort((a, b) => orden(a).compareTo(orden(b)));
            enviadas.sort((a, b) => orden(a).compareTo(orden(b)));
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ofertas recibidas', style: t.titleMedium),
              if (recibidas.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: Text('Nadie ha pujado por tus jugadores.')),
              for (final o in recibidas) _TarjetaOferta(oferta: o, mi: mi, saldo: saldo),
              const SizedBox(height: 16),
              Text('Ofertas enviadas', style: t.titleMedium),
              if (enviadas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Cuando un jugador no tenga fichas libres, puedes ofertar por la de un rival desde su ficha de mercado.'),
                ),
              for (final o in enviadas) _TarjetaOferta(oferta: o, mi: mi, saldo: saldo),
            ]);
          },
        ),
        const Divider(height: 32),
        Text('Cesiones para el próximo partido', style: t.titleMedium),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Cada mánager puede ceder 1 ficha y recibir 1 por jornada. La cedida ocupa una plaza extra, '
            'solo tú puedes alinearla ese partido y después vuelve a su dueño.'
            '${yaRecibida ? ' Ya tienes una cedida esta jornada.' : ''}'
            '${yaCedida ? ' Ya has ofrecido o cedido una ficha esta jornada.' : ''}',
            style: t.bodySmall,
          ),
        ),
        cesiones.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Cargando()),
          error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(cesionesDisponiblesProvider(ligaId))),
          data: (lista) {
            if (lista.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No hay cesiones ofrecidas. Para ceder una ficha tuya, usa su menú en Mi equipo.'),
              );
            }
            return Column(children: [
              for (final c in lista)
                Card(
                  child: ListTile(
                    leading: AvatarMiembro(miembros[c.jugadorId]),
                    title: Row(children: [
                      Flexible(
                        child: Text(c.jugadorNombre ?? miembros[c.jugadorId]?.nombre ?? '…',
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (c.noHabitual) ...[
                        const SizedBox(width: 6),
                        InsigniaNoHabitual(bonus: mi.liga.fantasy.bonusNoHabitual, corta: true),
                      ],
                    ]),
                    subtitle: Text([
                      c.esMia ? 'Tu ficha' : 'De ${c.propietarioNombre ?? '…'}',
                      '${pctTexto(c.pct)} de ${millones(c.precioMercado)}',
                      if (c.cierre != null) 'hasta ${fechaHora(c.cierre!)}',
                    ].join(' · ')),
                    onTap: () => context.push('/fantasy/jugador/${c.jugadorId}'),
                    trailing: c.esMia
                        ? TextButton(
                            onPressed: () async {
                              final ok = await ejecutar(context, () => FantasyRepo.cancelarCesion(c.id),
                                  ok: 'Cesión retirada');
                              if (ok) refrescarFantasy(ref, k);
                            },
                            child: const Text('Retirar'),
                          )
                        : FilledButton(
                            onPressed: yaRecibida || (saldo != null && saldo < c.importe)
                                ? null
                                : () async {
                                    if (!await confirmar(
                                      context,
                                      'Aceptar la cesión',
                                      'Pagas ${millones(c.importe)} a ${c.propietarioNombre ?? 'su dueño'} y podrás alinear a '
                                          '${c.jugadorNombre ?? 'este jugador'} en el próximo partido. Después vuelve a su dueño.',
                                      accion: 'Aceptar',
                                    )) {
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    final ok = await ejecutar(context, () => FantasyRepo.aceptarCesion(c.id),
                                        ok: 'Cesión aceptada: ya puedes alinearlo');
                                    if (ok) refrescarFantasy(ref, k);
                                  },
                            child: Text(millones(c.importe)),
                          ),
                  ),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _TarjetaOferta extends ConsumerWidget {
  const _TarjetaOferta({required this.oferta, required this.mi, required this.saldo});
  final Oferta oferta;
  final MiLiga mi;
  final double? saldo;

  String _estado(Oferta o) {
    if (o.pendiente) {
      final exp = o.expiraEn;
      return exp == null ? 'Pendiente' : 'Pendiente · caduca ${fechaHora(exp)}';
    }
    return switch (o.estado) {
      EstadoOferta.pendiente => 'Caducada',
      EstadoOferta.aceptada => 'Aceptada',
      EstadoOferta.rechazada => 'Rechazada',
      EstadoOferta.cancelada => 'Cancelada',
      EstadoOferta.caducada => 'Caducada',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = oferta;
    final k = (ligaId: mi.liga.id, miembroId: mi.yo.id);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final contraparte = o.recibida ? o.compradorNombre : o.vendedorNombre;

    return Card(
      color: o.pendiente && o.recibida ? cs.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                o.recibida
                    ? '${contraparte ?? '…'} ofrece por ${o.jugadorNombre ?? 'tu jugador'}'
                    : 'Por ${o.jugadorNombre ?? '…'} a ${contraparte ?? '…'}',
                style: t.titleSmall,
              ),
            ),
            Text(millones(o.importe), style: t.titleMedium),
          ]),
          Text(
            [
              _estado(o),
              if (o.precioMercado != null) 'valor ${millones(o.precioMercado)}',
              if (o.clausulaActual != null) 'cláusula ${millones(o.clausulaActual)}',
            ].join(' · '),
            style: t.bodySmall,
          ),
          if (o.pendiente)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (o.recibida) ...[
                TextButton(
                  onPressed: () => _responder(context, ref, k, false),
                  child: const Text('Rechazar'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => _responder(context, ref, k, true),
                  child: const Text('Aceptar'),
                ),
              ] else
                TextButton(
                  onPressed: () async {
                    final ok = await ejecutar(context, () => FantasyRepo.cancelarOferta(o.id), ok: 'Oferta cancelada');
                    if (ok) refrescarFantasy(ref, k);
                  },
                  child: const Text('Cancelar oferta'),
                ),
            ]),
        ]),
      ),
    );
  }

  Future<void> _responder(BuildContext context, WidgetRef ref, LigaMiembro k, bool aceptar) async {
    final o = oferta;
    if (aceptar &&
        !await confirmar(
          context,
          'Aceptar la oferta',
          'Vendes tu ficha de ${o.jugadorNombre ?? 'este jugador'} a ${o.compradorNombre ?? 'este mánager'} '
              'por ${millones(o.importe)}.',
          accion: 'Aceptar',
        )) {
      return;
    }
    if (!context.mounted) return;
    String? resultado;
    final ok = await ejecutar(context, () async {
      resultado = await FantasyRepo.responderOferta(o.id, aceptar);
    });
    if (!context.mounted) return;
    if (ok) {
      mostrarOk(context, switch (resultado) {
        'aceptada' => 'Oferta aceptada: has cobrado ${millones(o.importe)}',
        'rechazada' => 'Oferta rechazada',
        'caducada' => 'La oferta ya había caducado',
        _ => 'Hecho',
      });
      refrescarFantasy(ref, k);
    }
  }
}
