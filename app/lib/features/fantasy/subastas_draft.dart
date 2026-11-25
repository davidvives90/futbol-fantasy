import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/avatar.dart';
import '../../core/idioma.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';
import 'fantasy_providers.dart';

final subastasProvider = FutureProvider.autoDispose.family<List<Subasta>, String>(
  (ref, ligaId) => FantasyRepo.subastas(ligaId),
);
final draftProvider = FutureProvider.autoDispose.family<EstadoDraft?, String>(
  (ref, ligaId) => FantasyRepo.draft(ligaId),
);

String _queda(DateTime cierre) {
  final d = cierre.difference(DateTime.now());
  if (d.isNegative) return tr('Cerrada');
  if (d.inHours > 0) return trf('Cierra en {h} h {m} min', {'h': d.inHours, 'm': d.inMinutes % 60});
  if (d.inMinutes > 0) return trf('Cierra en {m} min', {'m': d.inMinutes});
  return trf('Cierra en {s} s', {'s': d.inSeconds});
}

/// Subastas de la liga (modo «Subasta diaria»): cada día salen N copias y se las lleva la puja más alta.
class SubastasPanel extends ConsumerStatefulWidget {
  const SubastasPanel({super.key, required this.mi});
  final MiLiga mi;

  @override
  ConsumerState<SubastasPanel> createState() => _SubastasPanelState();
}

class _SubastasPanelState extends ConsumerState<SubastasPanel> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _pujar(Subasta s, String nombre) async {
    final c = TextEditingController(text: s.miPuja?.toStringAsFixed(2) ?? s.minimo.toStringAsFixed(2));
    final importe = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(trf('Pujar por {n}', {'n': nombre})),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.ciega
              ? tr('Subasta ciega: nadie ve las pujas de los demás. Puedes cambiar la tuya hasta el cierre.')
              : trf('Subasta abierta: mínimo {m}. Si pujas en los 2 últimos minutos, se alarga 2 minutos.',
                  {'m': millones(s.minimo)})),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(labelText: tr('Tu puja'), suffixText: 'M'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Tx('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(d, double.tryParse(c.text.trim().replaceAll(',', '.'))),
            child: const Tx('Pujar'),
          ),
        ],
      ),
    );
    if (importe == null || !mounted) return;
    final ok = await ejecutar(context, () => FantasyRepo.pujar(s.id, importe), ok: tr('Puja enviada'));
    if (ok) ref.invalidate(subastasProvider(widget.mi.liga.id));
  }

  @override
  Widget build(BuildContext context) {
    final ligaId = widget.mi.liga.id;
    final lista = ref.watch(subastasProvider(ligaId));
    final miembros = ref.watch(miembrosPorIdProvider(ligaId));
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = widget.mi.liga.fantasy;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.gavel),
            const SizedBox(width: 8),
            Expanded(child: Tx('Subastas', style: t.titleMedium)),
            IconButton(
              tooltip: tr('Actualizar'),
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(subastasProvider(ligaId)),
            ),
          ]),
          Text(
              trf('Cada día a las {h} salen {n} a subasta {t} durante {d} h. Gana la puja más alta que se pueda pagar.', {
                'h': p.subastaHora,
                'n': p.subastaLote,
                't': p.subastaTipo == 'ciega' ? tr('ciega') : tr('abierta'),
                'd': p.subastaHoras,
              }),
              style: t.bodySmall),
          if (widget.mi.soyAdmin)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Tx('Sacar una subasta ahora'),
                onPressed: () async {
                  final ok = await ejecutar(context, () => FantasyRepo.lanzarSubasta(ligaId), ok: tr('Subasta abierta'));
                  if (ok) ref.invalidate(subastasProvider(ligaId));
                },
              ),
            ),
          lista.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(subastasProvider(ligaId))),
            data: (l) {
              if (l.isEmpty) return Padding(padding: const EdgeInsets.all(8), child: Tx('Hoy aún no ha salido ninguna subasta.', style: t.bodySmall));
              return Column(children: [
                for (final s in l)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: AvatarMiembro(miembros[s.jugadorId], radio: 18),
                    title: Text('${miembros[s.jugadorId]?.nombre ?? '…'} · #${s.numero}'),
                    subtitle: Text(s.abierta
                        ? [
                            _queda(s.cierraEn),
                            trf('salida {x}', {'x': millones(s.precioSalida)}),
                            if (!s.ciega && s.mejor != null) trf('mejor {x}', {'x': millones(s.mejor)}),
                            trf('{n} pujas', {'n': s.numPujas}),
                            if (s.miPuja != null) trf('tu puja {x}', {'x': millones(s.miPuja)}),
                            if (s.voyGanando == true) tr('¡vas ganando!'),
                          ].join(' · ')
                        : s.estado == 'adjudicada'
                            ? trf('Para {g} por {x}', {'g': miembros[s.ganadorId]?.nombre ?? '…', 'x': millones(s.importe)})
                            : tr('Desierta: nadie pujó (o nadie podía pagarlo)')),
                    trailing: s.abierta
                        ? FilledButton.tonal(
                            onPressed: s.voyGanando == true ? null : () => _pujar(s, miembros[s.jugadorId]?.nombre ?? ''),
                            child: Text(s.miPuja == null ? tr('Pujar') : tr('Cambiar')),
                          )
                        : Icon(s.estado == 'adjudicada' ? Icons.check_circle : Icons.remove_circle_outline,
                            color: s.estado == 'adjudicada' ? cs.primary : cs.outline),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

/// Draft por turnos en serpiente: cada mánager elige un jugador en su turno (al precio de su copia).
class DraftPanel extends ConsumerWidget {
  const DraftPanel({super.key, required this.mi});
  final MiLiga mi;

  Future<void> _elegir(BuildContext context, WidgetRef ref) async {
    final ligaId = mi.liga.id;
    final mercado = await ref.read(mercadoProvider(ligaId).future);
    final miembros = ref.read(miembrosPorIdProvider(ligaId));
    final disponibles = mercado.where((j) => j.hayLibres).toList()..sort((a, b) => b.precio.compareTo(a.precio));
    if (!context.mounted) return;
    final elegido = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, sc) => ListView(controller: sc, children: [
          ListTile(title: Tx('Elige tu jugador', style: Theme.of(c).textTheme.titleMedium)),
          for (final j in disponibles)
            ListTile(
              leading: AvatarMiembro(miembros[j.miembroId], radio: 18),
              title: Text(miembros[j.miembroId]?.nombre ?? '…'),
              subtitle: Text(trf('{l} copias libres', {'l': j.fichasLibres})),
              trailing: Text(millones(j.precio)),
              onTap: () => Navigator.pop(c, j.miembroId),
            ),
        ]),
      ),
    );
    if (elegido == null || !context.mounted) return;
    final ok = await ejecutar(context, () => FantasyRepo.draftElegir(ligaId, elegido), ok: tr('¡Elegido!'));
    if (ok) {
      ref.invalidate(draftProvider(ligaId));
      refrescarFantasy(ref, (ligaId: ligaId, miembroId: mi.yo.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ligaId = mi.liga.id;
    final d = ref.watch(draftProvider(ligaId));
    final miembros = ref.watch(miembrosPorIdProvider(ligaId));
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return d.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(draftProvider(ligaId))),
      data: (dr) {
        if (dr != null && !dr.enCurso) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          color: cs.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.casino_outlined),
                const SizedBox(width: 8),
                Expanded(child: Tx('Draft', style: t.titleMedium)),
                IconButton(
                  tooltip: tr('Actualizar'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(draftProvider(ligaId)),
                ),
              ]),
              if (dr == null) ...[
                Tx('Todos empiezan sin jugadores. Cuando el administrador lo inicie, cada mánager elige por turnos '
                    '(1-2-3, 3-2-1…) pagando el precio de la copia.', style: t.bodySmall),
                if (mi.soyAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Tx('Iniciar draft'),
                      onPressed: () async {
                        final ok = await ejecutar(context, () => FantasyRepo.iniciarDraft(ligaId), ok: tr('Draft iniciado'));
                        if (ok) ref.invalidate(draftProvider(ligaId));
                      },
                    ),
                  ),
              ] else ...[
                Text(trf('Ronda {r} de {t} · elección {p} de {n}',
                    {'r': dr.ronda, 't': dr.rondas, 'p': dr.pick + 1, 'n': dr.total})),
                const SizedBox(height: 4),
                Text(
                    dr.turno == mi.yo.id
                        ? tr('¡Te toca!')
                        : trf('Turno de {n}', {'n': miembros[dr.turno]?.nombre ?? '…'}),
                    style: t.titleSmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  if (dr.turno == mi.yo.id)
                    FilledButton.icon(
                      icon: const Icon(Icons.how_to_reg),
                      label: const Tx('Elegir jugador'),
                      onPressed: () => _elegir(context, ref),
                    ),
                  if (dr.turno == mi.yo.id || mi.soyAdmin)
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await ejecutar(context, () => FantasyRepo.draftPasar(ligaId), ok: tr('Turno pasado'));
                        if (ok) ref.invalidate(draftProvider(ligaId));
                      },
                      child: Text(dr.turno == mi.yo.id ? tr('Pasar') : tr('Saltar su turno')),
                    ),
                ]),
                if (dr.picks.isNotEmpty) ...[
                  const Divider(),
                  for (final p in dr.picks.reversed.take(6))
                    Text(
                        '${miembros[p.managerId]?.nombre ?? '…'} → '
                        '${p.jugadorId == null ? tr('pasa') : '${miembros[p.jugadorId]?.nombre ?? '…'} (${millones(p.importe)})'}',
                        style: t.bodySmall),
                ],
              ],
            ]),
          ),
        );
      },
    );
  }
}
