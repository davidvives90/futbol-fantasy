import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import 'alineacion_lista.dart';
import 'fantasy_providers.dart';
import 'widgets_fantasy.dart';
import 'tarjetas_jugador.dart';
import '../../core/info.dart';


/// Saldo, plantilla (fichas propias + la recibida en cesión) y alineación del próximo partido.
class MiEquipoTab extends ConsumerWidget {
  const MiEquipoTab({super.key, required this.mi});
  final MiLiga mi;

  LigaMiembro get _k => (ligaId: mi.liga.id, miembroId: mi.yo.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = _k;
    final resumen = ref.watch(resumenFantasyProvider(mi.liga.id)).valueOrNull ?? const <String, ResumenFantasy>{};
    final manager = ref.watch(miManagerProvider(k));
    // La primera visita crea el mánager (y puede arrancar el Fantasy): hay que volver a mirar el mercado
    ref.listen(miManagerProvider(k), (antes, ahora) {
      if (antes?.isLoading == true && ahora.hasValue) {
        ref.invalidate(mercadoAbiertoProvider(mi.liga.id));
        ref.invalidate(mercadoProvider(mi.liga.id));
      }
    });
    final plantilla = ref.watch(miPlantillaProvider(k));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final abierto = ref.watch(mercadoAbiertoProvider(mi.liga.id)).valueOrNull ?? false;
    final proximo = ref.watch(proximoPartidoProvider(mi.liga.id));
    final params = mi.liga.fantasy;
    final t = Theme.of(context).textTheme;

    if (manager.isLoading || plantilla.isLoading) return const Cargando();
    if (manager.hasError) return ErrorVista(manager.error!, onRetry: () => refrescarFantasy(ref, k));
    if (manager.value == null) {
      return Vacio(
        'No se ha podido preparar tu equipo. Desliza hacia abajo para reintentarlo.',
        icono: Icons.sports_soccer,
        accion: 'Reintentar',
        onAccion: () => refrescarFantasy(ref, k),
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
        if (m.puntosTotales == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(children: [
              Icon(Icons.lightbulb_outline, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Tx('Todos empiezan con un valor parecido. Después de cada partido, quien juega bien sube '
                    'de precio y quien no, baja. Si no haces la alineación, juegan tus mejores jugadores.'),
              ),
            ]),
          ),
        if (mi.liga.comprasDinero)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push('/tienda'),
              icon: const Icon(Icons.add_card_outlined, size: 18),
              label: const Tx('Conseguir dinero'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Row(children: [
            Text('Plantilla (${propias.length}/${params.maxPlantilla})', style: t.titleMedium),
            const Spacer(),
            PopupMenuButton<(String, String)>(
              tooltip: tr('Ayuda del Fantasy'),
              icon: const Icon(Icons.help_outline),
              onSelected: (a) => mostrarAyuda(context, a),
              itemBuilder: (_) => [
                const PopupMenuItem(value: Ayuda.alineacion, child: Tx('Alineación')),
                PopupMenuItem(value: Ayuda.clausula, child: Tx('Cláusula')),
                if (mi.liga.fantasy.cesionesActivas) const PopupMenuItem(value: Ayuda.cesion, child: Tx('Cesión')),
                PopupMenuItem(value: Ayuda.valorMercado, child: Tx('Valor de mercado')),
                PopupMenuItem(value: Ayuda.fichas, child: Tx('Copias de cada jugador')),
                PopupMenuItem(value: Ayuda.rolesBonus, child: Tx('Bonus por rol')),
                PopupMenuItem(value: Ayuda.multiplicadorInvitado, child: Tx('Invitados')),
              ],
            ),
            if (!abierto) const Chip(avatar: Icon(Icons.lock_clock, size: 16), label: Tx('Mercado cerrado')),
          ]),
        ),
        if (propias.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Tx('Aún no tienes jugadores. Ficha en la pestaña Mercado.'),
          ),
        // Toca un jugador para ver su ficha con todas las opciones: cláusula, vender, subasta y cesión
        for (final j in propias)
          TarjetaJugadorLista(
            miembro: miembros[j.jugadorId],
            precio: j.precio,
            variacion: j.variacion,
            resumen: resumen[j.jugadorId],
            insignia: j.noHabitual ? InsigniaNoHabitual(bonus: params.bonusNoHabitual, corta: true) : null,
            extra: [
              trf('Cláusula {x}', {'x': millones(j.clausula)}),
              trf('{v} desde la compra', {'v': variacionM(j.plusvalia)}),
              if (j.protegida) tr('protegida'),
              if (j.cedidaAOtro) tr('cedida esta jornada'),
              if (j.enCesionOfrecida) tr('ofrecida en cesión'),
            ].join(' · '),
            onTap: () => context.push('/fantasy/jugador/${j.jugadorId}'),
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
                subtitle: const Tx('Solo para alinearlo en el próximo partido; luego vuelve a su dueño.'),
                trailing: Text(millones(j.precio), style: t.titleSmall),
                onTap: () => context.push('/fantasy/jugador/${j.jugadorId}'),
              ),
            ),
        ],
        const SizedBox(height: 16),
        if (proximo == null)
          const Card(child: ListTile(leading: Icon(Icons.event_busy), title: Tx('No hay ningún partido convocado para alinear.')))
        else
          AlineacionLista(mi: mi, partido: proximo, plantilla: lista),
      ]),
    );
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

