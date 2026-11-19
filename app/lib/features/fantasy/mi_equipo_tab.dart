import 'dart:async';

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

/// Saldo, plantilla (hasta 6) y alineación del próximo partido.
class MiEquipoTab extends ConsumerWidget {
  const MiEquipoTab({super.key, required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = (ligaId: mi.liga.id, miembroId: mi.yo.id);
    final manager = ref.watch(miManagerProvider(k));
    final plantilla = ref.watch(miPlantillaProvider(k));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final abierto = ref.watch(mercadoAbiertoProvider(mi.liga.id)).valueOrNull ?? false;
    final proximo = ref.watch(proximoPartidoProvider(mi.liga.id));
    final params = mi.liga.fantasy;

    if (manager.isLoading || plantilla.isLoading) return const Cargando();
    if (manager.hasError) return ErrorVista(manager.error!, onRetry: () => refrescarFantasy(ref, k));
    if (manager.value == null) {
      return const Vacio(
        'El Fantasy empieza cuando un admin cierre la encuesta inicial de valoración: '
        'entonces se fijan los precios y recibes tu presupuesto.',
        icono: Icons.hourglass_empty,
      );
    }
    final m = manager.value!;
    final lista = plantilla.valueOrNull ?? const <JugadorPlantilla>[];
    final valor = lista.fold<double>(0, (s, j) => s + j.precio);

    return RefreshIndicator(
      onRefresh: () async {
        refrescarFantasy(ref, k);
        ref.invalidate(partidosProvider(mi.liga.id));
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _Cifra('Saldo', millones(m.saldo)),
              _Cifra('Valor plantilla', millones(valor)),
              _Cifra('Puntos', m.puntosTotales.toStringAsFixed(m.puntosTotales % 1 == 0 ? 0 : 1)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Row(children: [
            Text('Plantilla (${lista.length}/${params.maxPlantilla})', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (!abierto) const Chip(avatar: Icon(Icons.lock_clock, size: 16), label: Text('Mercado cerrado')),
          ]),
        ),
        if (lista.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Aún no tienes jugadores. Ficha en la pestaña Mercado.'),
          ),
        for (final j in lista)
          Card(
            child: ListTile(
              leading: AvatarMiembro(miembros[j.jugadorId]),
              title: Row(children: [
                Flexible(child: Text(miembros[j.jugadorId]?.nombre ?? '…', overflow: TextOverflow.ellipsis)),
                if (j.noHabitual) ...[const SizedBox(width: 6), InsigniaNoHabitual(bonus: params.bonusNoHabitual)],
              ]),
              subtitle: Text('Comprado a ${millones(j.precioCompra)} · ${variacionM(j.plusvalia)}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(millones(j.precio), style: Theme.of(context).textTheme.titleSmall),
                VariacionTexto(j.variacion),
              ]),
              onTap: () => context.push('/fantasy/jugador/${j.jugadorId}'),
              onLongPress: abierto ? () => _vender(context, ref, j, miembros[j.jugadorId]?.nombre ?? 'jugador') : null,
            ),
          ),
        if (lista.isNotEmpty && abierto)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('Mantén pulsado un jugador para venderlo.', style: TextStyle(fontSize: 12)),
          ),
        const SizedBox(height: 16),
        if (proximo == null)
          const Card(child: ListTile(leading: Icon(Icons.event_busy), title: Text('No hay ningún partido convocado para alinear.')))
        else
          _Alineacion(mi: mi, partido: proximo, plantilla: lista),
      ]),
    );
  }

  Future<void> _vender(BuildContext context, WidgetRef ref, JugadorPlantilla j, String nombre) async {
    final p = mi.liga.fantasy;
    final recibes = p.precioVenta(j.precio);
    if (!await confirmar(
      context,
      'Vender a $nombre',
      'Precio actual ${millones(j.precio)} − ${(p.comisionVenta * 100).toStringAsFixed(0)} % de comisión: '
          'recibes ${millones(recibes)} (lo compraste a ${millones(j.precioCompra)}).',
      accion: 'Vender',
    )) {
      return;
    }
    if (!context.mounted) return;
    final ok = await ejecutar(context, () => FantasyRepo.vender(mi.liga.id, j.jugadorId), ok: '$nombre vendido');
    if (ok) refrescarFantasy(ref, (ligaId: mi.liga.id, miembroId: mi.yo.id));
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.etiqueta, this.valor);
  final String etiqueta, valor;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(valor, style: Theme.of(context).textTheme.titleLarge),
        Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

/// Selección de la alineación del próximo partido, con cuenta atrás hasta el cierre.
class _Alineacion extends ConsumerStatefulWidget {
  const _Alineacion({required this.mi, required this.partido, required this.plantilla});
  final MiLiga mi;
  final Partido partido;
  final List<JugadorPlantilla> plantilla;

  @override
  ConsumerState<_Alineacion> createState() => _AlineacionState();
}

class _AlineacionState extends ConsumerState<_Alineacion> {
  Set<String>? _sel; // null = aún no cargada
  Set<String> _guardada = {};
  bool _guardando = false;
  Timer? _timer;

  int get _tam => widget.partido.plazas ~/ widget.partido.numEquipos;
  DateTime get _cierre => widget.mi.liga.fantasy.cierre(widget.partido.fechaHora);
  bool get _bloqueada => !DateTime.now().isBefore(_cierre);

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _Alineacion old) {
    super.didUpdateWidget(old);
    if (old.partido.id != widget.partido.id) _cargar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final a = await FantasyRepo.alineacion(widget.partido.id, widget.mi.yo.id);
      if (!mounted) return;
      setState(() {
        _guardada = {for (final x in a) x.jugadorId};
        _sel = {..._guardada};
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sel = {});
      mostrarError(context, e);
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final ok = await ejecutar(
      context,
      () => FantasyRepo.guardarAlineacion(widget.partido.id, _sel!.toList()),
      ok: 'Alineación guardada',
    );
    if (!mounted) return;
    setState(() {
      _guardando = false;
      if (ok) _guardada = {..._sel!};
    });
  }

  String _cuentaAtras() {
    final d = _cierre.difference(DateTime.now());
    if (d.isNegative) return 'Cerrada desde ${fechaHora(_cierre)}';
    if (d.inDays > 0) return 'Cierra en ${d.inDays} d ${d.inHours % 24} h';
    if (d.inHours > 0) return 'Cierra en ${d.inHours} h ${d.inMinutes % 60} min';
    return 'Cierra en ${d.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final miembros = ref.watch(miembrosPorIdProvider(widget.mi.liga.id));
    final conv = ref.watch(convocatoriaProvider(widget.partido.id)).valueOrNull ?? const <Inscripcion>[];
    final estado = {for (final i in conv) i.miembroId: i.estado};
    final sel = _sel;
    final bloqueada = _bloqueada;
    final cambiada = sel != null && (sel.length != _guardada.length || !sel.containsAll(_guardada));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(bloqueada ? Icons.lock : Icons.lock_open, size: 20, color: bloqueada ? cs.error : cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Alineación · ${fechaHora(widget.partido.fechaHora)}', style: t.titleMedium)),
          ]),
          const SizedBox(height: 4),
          Text('${_cuentaAtras()} · elige hasta $_tam jugadores', style: t.bodySmall),
          const SizedBox(height: 12),
          if (sel == null)
            const LinearProgressIndicator()
          else if (widget.plantilla.isEmpty)
            const Text('Ficha jugadores para poder alinearlos.')
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final j in widget.plantilla)
                FilterChip(
                  // Sin check: el avatar muestra si está confirmado en la convocatoria.
                  showCheckmark: false,
                  avatar: IconoConvocatoria(estado[j.jugadorId]),
                  label: Text([
                    miembros[j.jugadorId]?.nombre ?? '…',
                    if (j.noHabitual) '×${widget.mi.liga.fantasy.bonusNoHabitual.toStringAsFixed(1).replaceAll('.', ',')}',
                  ].join(' ')),
                  selected: sel.contains(j.jugadorId),
                  onSelected: bloqueada
                      ? null
                      : (v) {
                          if (v && sel.length >= _tam) {
                            mostrarError(context, 'Máximo $_tam jugadores en la alineación');
                            return;
                          }
                          setState(() => v ? sel.add(j.jugadorId) : sel.remove(j.jugadorId));
                        },
                ),
            ]),
          const SizedBox(height: 8),
          if (sel != null)
            ...[
              for (final id in sel)
                if (estado[id] != EstadoInscripcion.confirmado)
                  Text(
                    '⚠ ${miembros[id]?.nombre ?? '…'} '
                    '${switch (estado[id]) {
                      EstadoInscripcion.duda => 'está en duda',
                      EstadoInscripcion.baja => 'se ha dado de baja',
                      EstadoInscripcion.espera => 'está en lista de espera',
                      _ => 'no está apuntado',
                    }}: si no juega, puntúa 0.',
                    style: t.bodySmall?.copyWith(color: cs.error),
                  ),
            ],
          const SizedBox(height: 8),
          Row(children: [
            Text('${sel?.length ?? 0}/$_tam', style: t.titleSmall),
            const Spacer(),
            FilledButton.icon(
              onPressed: bloqueada || !cambiada || _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar alineación'),
            ),
          ]),
          if (!bloqueada && _guardada.isEmpty)
            Text('Si no guardas ninguna, se repetirá la del partido anterior.', style: t.bodySmall),
        ]),
      ),
    );
  }
}
