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

/// Ficha de mercado de un jugador: precio, valoración por atributos, historial y comprar/vender.
class JugadorMercadoScreen extends ConsumerWidget {
  const JugadorMercadoScreen({super.key, required this.miembroId});
  final String miembroId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final ligaId = mi.liga.id;
    final kJugador = (ligaId: ligaId, miembroId: miembroId);
    final kYo = (ligaId: ligaId, miembroId: mi.yo.id);
    final p = mi.liga.fantasy;

    final miembro = ref.watch(miembrosPorIdProvider(ligaId))[miembroId];
    final mercado = ref.watch(mercadoProvider(ligaId)).valueOrNull ?? const <JugadorMercado>[];
    final fila = mercado.where((j) => j.miembroId == miembroId).firstOrNull;
    final valoracion = ref.watch(valoracionProvider(kJugador));
    final historial = ref.watch(historialPreciosProvider(kJugador));
    final plantilla = ref.watch(miPlantillaProvider(kYo)).valueOrNull ?? const <JugadorPlantilla>[];
    final saldo = ref.watch(miManagerProvider(kYo)).valueOrNull?.saldo;
    final abierto = ref.watch(mercadoAbiertoProvider(ligaId)).valueOrNull ?? false;
    final enPlantilla = plantilla.where((j) => j.jugadorId == miembroId).firstOrNull;
    final t = Theme.of(context).textTheme;

    // Validaciones locales (el backend las repite y su mensaje es el que se muestra si falla).
    String? motivoNoCompra;
    if (fila != null && enPlantilla == null) {
      if (!abierto) {
        motivoNoCompra = 'El mercado está cerrado.';
      } else if (plantilla.length >= p.maxPlantilla) {
        motivoNoCompra = 'Tu plantilla ya tiene ${p.maxPlantilla} jugadores: vende uno antes.';
      } else if (fila.noHabitual && plantilla.any((j) => j.noHabitual)) {
        motivoNoCompra = 'Solo puedes tener un no habitual en la plantilla.';
      } else if (saldo != null && saldo < fila.precio) {
        motivoNoCompra = 'Saldo insuficiente (${millones(saldo)}).';
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(miembro?.nombre ?? 'Jugador')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          AvatarMiembro(miembro, radio: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(miembro?.nombre ?? '…', style: t.titleLarge),
              Text(etiquetaPosicion(miembro?.posicion)),
              if (fila?.noHabitual ?? false) ...[
                const SizedBox(height: 4),
                InsigniaNoHabitual(bonus: p.bonusNoHabitual),
              ],
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(millones(fila?.precio), style: t.headlineSmall),
            VariacionTexto(fila?.variacion),
          ]),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (fila?.rating != null) Chip(label: Text('Valoración ${fila!.rating!.round()}/100')),
          if (fila?.pctFichado != null) Chip(label: Text('En el ${fila!.pctFichado!.round()} % de plantillas')),
        ]),
        const SizedBox(height: 16),
        Text('Valoración de la liga', style: t.titleMedium),
        valoracion.when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Cargando()),
          error: (e, _) => Text(mensajeError(e)),
          data: (v) => v == null
              ? const Padding(padding: EdgeInsets.all(8), child: Text('Todavía no ha sido valorado en una encuesta.'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final a in Atributo.values) BarraAtributo(etiqueta: a.etiqueta, valor: v.atributos[a]),
                  const Divider(),
                  BarraAtributo(etiqueta: 'Media', valor: v.general),
                  Text('${v.numEvaluadores} evaluadores', style: t.bodySmall),
                ]),
        ),
        const SizedBox(height: 16),
        Text('Historial de precio', style: t.titleMedium),
        const SizedBox(height: 8),
        historial.when(
          loading: () => const SizedBox(height: 60, child: Cargando()),
          error: (e, _) => Text(mensajeError(e)),
          data: (h) => GraficoPrecios(puntos: h),
        ),
        const SizedBox(height: 24),
        if (enPlantilla != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.sell_outlined),
            label: Text('Vender por ${millones(p.precioVenta(enPlantilla.precio))}'),
            onPressed: !abierto
                ? null
                : () async {
                    if (!await confirmar(
                      context,
                      'Vender a ${miembro?.nombre ?? 'jugador'}',
                      'Precio actual ${millones(enPlantilla.precio)} − ${(p.comisionVenta * 100).toStringAsFixed(0)} % '
                          'de comisión: recibes ${millones(p.precioVenta(enPlantilla.precio))}.',
                      accion: 'Vender',
                    )) {
                      return;
                    }
                    if (!context.mounted) return;
                    final ok = await ejecutar(context, () => FantasyRepo.vender(ligaId, miembroId), ok: 'Vendido');
                    if (ok) refrescarFantasy(ref, kYo);
                  },
          )
        else if (fila != null) ...[
          FilledButton.icon(
            icon: const Icon(Icons.add_shopping_cart),
            label: Text('Comprar por ${millones(fila.precio)}'),
            onPressed: motivoNoCompra != null
                ? null
                : () async {
                    final ok = await ejecutar(context, () => FantasyRepo.comprar(ligaId, miembroId),
                        ok: '${miembro?.nombre ?? 'Jugador'} fichado');
                    if (ok) {
                      refrescarFantasy(ref, kYo);
                      if (context.mounted) context.pop();
                    }
                  },
          ),
          if (motivoNoCompra != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(motivoNoCompra, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
        if (miembroId == mi.yo.id && enPlantilla == null && fila != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Sí, puedes ficharte a ti mismo.'),
          ),
      ]),
    );
  }
}
