import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';
import '../../data/repos/master_repo.dart';
import 'alineacion_campo.dart';
import 'fantasy_dialogs.dart';
import 'fantasy_providers.dart';
import 'widgets_fantasy.dart';
import '../../core/info.dart';

enum _Accion { clausula, vender, ceder, retirarCesion, ficha }

/// Saldo, plantilla (fichas propias + la recibida en cesión) y alineación del próximo partido.
class MiEquipoTab extends ConsumerWidget {
  const MiEquipoTab({super.key, required this.mi});
  final MiLiga mi;

  LigaMiembro get _k => (ligaId: mi.liga.id, miembroId: mi.yo.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = _k;
    final manager = ref.watch(miManagerProvider(k));
    final plantilla = ref.watch(miPlantillaProvider(k));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final abierto = ref.watch(mercadoAbiertoProvider(mi.liga.id)).valueOrNull ?? false;
    final proximo = ref.watch(proximoPartidoProvider(mi.liga.id));
    final params = mi.liga.fantasy;
    final t = Theme.of(context).textTheme;

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
    final propias = lista.where((j) => j.propia).toList();
    final recibida = lista.where((j) => j.cedidaAMi).toList();
    final valor = propias.fold<double>(0, (s, j) => s + j.precio);

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
              _Cifra('Saldo', millones(m.saldo), premium: true),
              _Cifra('Valor plantilla', millones(valor)),
              _Cifra('Puntos', m.puntosTotales.toStringAsFixed(m.puntosTotales % 1 == 0 ? 0 : 1)),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _canjear(context, ref),
            icon: const Icon(Icons.redeem_outlined, size: 18),
            label: const Text('Canjear código'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Row(children: [
            Text('Plantilla (${propias.length}/${params.maxPlantilla})', style: t.titleMedium),
            const Spacer(),
            PopupMenuButton<(String, String)>(
              tooltip: 'Ayuda del Fantasy',
              icon: const Icon(Icons.help_outline),
              onSelected: (a) => mostrarAyuda(context, a),
              itemBuilder: (_) => const [
                PopupMenuItem(value: Ayuda.alineacion, child: Tx('Alineación')),
                PopupMenuItem(value: Ayuda.clausula, child: Text('Cláusula de rescisión')),
                PopupMenuItem(value: Ayuda.cesion, child: Text('Cesión')),
                PopupMenuItem(value: Ayuda.valorMercado, child: Tx('Valor de mercado')),
                PopupMenuItem(value: Ayuda.fichas, child: Text('Fichas')),
                PopupMenuItem(value: Ayuda.rolesBonus, child: Text('Bonus por rol')),
                PopupMenuItem(value: Ayuda.multiplicadorInvitado, child: Text('Invitados')),
              ],
            ),
            if (!abierto) const Chip(avatar: Icon(Icons.lock_clock, size: 16), label: Tx('Mercado cerrado')),
          ]),
        ),
        if (propias.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Aún no tienes jugadores. Ficha en la pestaña Mercado.'),
          ),
        for (final j in propias)
          Card(
            child: ListTile(
              leading: AvatarMiembro(miembros[j.jugadorId]),
              title: Row(children: [
                Flexible(child: Text(miembros[j.jugadorId]?.nombre ?? '…', overflow: TextOverflow.ellipsis)),
                if (j.noHabitual) ...[const SizedBox(width: 6), InsigniaNoHabitual(bonus: params.bonusNoHabitual)],
              ]),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cláusula ${millones(j.clausula)} · ${variacionM(j.plusvalia)} desde la compra'),
                Wrap(spacing: 6, children: [
                  if (j.protegida) const _Etiqueta(Icons.shield, 'Protegida'),
                  if (j.cedidaAOtro) const _Etiqueta(Icons.swap_horiz, 'Cedida esta jornada'),
                  if (j.enCesionOfrecida) const _Etiqueta(Icons.campaign_outlined, 'Ofrecida en cesión'),
                ]),
              ]),
              isThreeLine: j.protegida || j.cedidaAOtro || j.enCesionOfrecida,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(millones(j.precio), style: t.titleSmall),
                  VariacionTexto(j.variacion),
                ]),
                PopupMenuButton<_Accion>(
                  onSelected: (a) => _accion(context, ref, a, j, miembros[j.jugadorId]?.nombre ?? 'jugador', m.saldo),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _Accion.clausula,
                      enabled: abierto && !j.cedidaAOtro,
                      child: const ListTile(leading: Icon(Icons.gavel), title: Text('Cambiar cláusula')),
                    ),
                    PopupMenuItem(
                      value: _Accion.vender,
                      enabled: abierto && !j.cedidaAOtro && !j.enCesionOfrecida,
                      child: const ListTile(leading: Icon(Icons.sell_outlined), title: Tx('Vender al mercado')),
                    ),
                    if (j.enCesionOfrecida)
                      const PopupMenuItem(
                        value: _Accion.retirarCesion,
                        child: ListTile(leading: Icon(Icons.undo), title: Text('Retirar cesión')),
                      )
                    else
                      PopupMenuItem(
                        value: _Accion.ceder,
                        enabled: !j.cedidaAOtro && proximo != null,
                        child: const ListTile(leading: Icon(Icons.swap_horiz), title: Text('Ofrecer en cesión')),
                      ),
                    const PopupMenuItem(
                      value: _Accion.ficha,
                      child: ListTile(leading: Icon(Icons.insights), title: Text('Ver ficha de mercado')),
                    ),
                  ],
                ),
              ]),
              onTap: () => context.push('/fantasy/jugador/${j.jugadorId}'),
            ),
          ),
        if (recibida.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text('Cedido a ti esta jornada (plaza extra)', style: t.titleMedium),
          ),
          for (final j in recibida)
            Card(
              child: ListTile(
                leading: AvatarMiembro(miembros[j.jugadorId]),
                title: Row(children: [
                  Flexible(child: Text(miembros[j.jugadorId]?.nombre ?? '…', overflow: TextOverflow.ellipsis)),
                  if (j.noHabitual) ...[const SizedBox(width: 6), InsigniaNoHabitual(bonus: params.bonusNoHabitual)],
                ]),
                subtitle: const Text('Solo para alinearlo en el próximo partido; luego vuelve a su dueño.'),
                trailing: Text(millones(j.precio), style: t.titleSmall),
                onTap: () => context.push('/fantasy/jugador/${j.jugadorId}'),
              ),
            ),
        ],
        const SizedBox(height: 16),
        if (proximo == null)
          const Card(child: ListTile(leading: Icon(Icons.event_busy), title: Text('No hay ningún partido convocado para alinear.')))
        else
          AlineacionCampo(mi: mi, partido: proximo, plantilla: lista),
      ]),
    );
  }

  Future<void> _canjear(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Canjear código'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Código promocional'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Tx('Cancelar')),
          FilledButton(
            style: AppButtons.premium(d),
            onPressed: () => Navigator.pop(d, c.text.trim()),
            child: const Text('Canjear'),
          ),
        ],
      ),
    );
    if (codigo == null || codigo.isEmpty || !context.mounted) return;
    double? saldo;
    final ok = await ejecutar(context, () async => saldo = await MasterRepo.canjear(mi.liga.id, codigo));
    if (ok && context.mounted) {
      mostrarOk(context, '¡Código canjeado! Saldo: ${millones(saldo)}');
      refrescarFantasy(ref, _k);
    }
  }

  Future<void> _accion(
      BuildContext context, WidgetRef ref, _Accion a, JugadorPlantilla j, String nombre, double saldo) async {
    final p = mi.liga.fantasy;
    final fichaId = j.fichaId;
    switch (a) {
      case _Accion.ficha:
        context.push('/fantasy/jugador/${j.jugadorId}');
      case _Accion.clausula:
        if (fichaId == null) return;
        final nueva = await dialogoClausula(context,
            jugador: nombre, params: p, actual: j.clausula ?? j.precio, precioMercado: j.precio, saldo: saldo);
        if (nueva == null || !context.mounted) return;
        final ok = await ejecutar(context, () => FantasyRepo.fijarClausula(fichaId, nueva),
            ok: 'Cláusula de $nombre: ${millones(nueva)}');
        if (ok) refrescarFantasy(ref, _k);
      case _Accion.vender:
        final recibes = p.precioVenta(j.precio);
        if (!await confirmar(
          context,
          'Vender a $nombre',
          'La ficha vuelve al mercado. Precio actual ${millones(j.precio)} − '
              '${(p.comisionVenta * 100).toStringAsFixed(0)} % de comisión: recibes ${millones(recibes)}'
              '${j.precioCompra != null ? ' (lo compraste a ${millones(j.precioCompra)})' : ''}.',
          accion: 'Vender',
          tipo: TipoConfirmacion.peligro,
        )) {
          return;
        }
        if (!context.mounted) return;
        final ok = await ejecutar(context, () => FantasyRepo.vender(mi.liga.id, j.jugadorId, fichaId: fichaId),
            ok: '$nombre vendido');
        if (ok) refrescarFantasy(ref, _k);
      case _Accion.ceder:
        if (fichaId == null) return;
        final pct = await dialogoCesion(context, jugador: nombre, params: p, precioMercado: j.precio);
        if (pct == null || !context.mounted) return;
        final ok = await ejecutar(context, () => FantasyRepo.ofrecerCesion(fichaId, pct),
            ok: '$nombre ofrecido en cesión al ${pctTexto(pct)}');
        if (ok) refrescarFantasy(ref, _k);
      case _Accion.retirarCesion:
        if (fichaId == null) return;
        final ok = await ejecutar(context, () async {
          final id = await FantasyRepo.miCesionOfrecida(mi.liga.id, fichaId);
          if (id == null) throw 'La cesión ya no está disponible (aceptada o cerrada).';
          await FantasyRepo.cancelarCesion(id);
        }, ok: 'Cesión retirada');
        if (ok) refrescarFantasy(ref, _k);
    }
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.etiqueta, this.valor, {this.premium = false});
  final String etiqueta, valor;
  final bool premium;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(valor,
            style: AppTheme.numero(context,
                size: 22, color: premium ? Theme.of(context).colorScheme.tertiary : null)),
        Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.icono, this.texto);
  final IconData icono;
  final String texto;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icono, size: 14, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 2),
        Text(texto, style: Theme.of(context).textTheme.labelSmall),
      ]);
}
