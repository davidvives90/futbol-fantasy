import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';
import 'fantasy_dialogs.dart';
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
    final plantillaTodo = ref.watch(miPlantillaProvider(kYo)).valueOrNull ?? const <JugadorPlantilla>[];
    // La ficha recibida en cesión ocupa una plaza extra: no cuenta para el límite.
    final plantilla = plantillaTodo.where((j) => j.propia).toList();
    final saldo = ref.watch(miManagerProvider(kYo)).valueOrNull?.saldo;
    final abierto = ref.watch(mercadoAbiertoProvider(ligaId)).valueOrNull ?? false;
    final enPlantilla = plantillaTodo.where((j) => j.jugadorId == miembroId).firstOrNull;
    final t = Theme.of(context).textTheme;

    // Validaciones locales (el backend las repite y su mensaje es el que se muestra si falla).
    String? motivoNoCompra;
    if (fila != null && (enPlantilla == null || !enPlantilla.propia)) {
      if (!abierto) {
        motivoNoCompra = 'El mercado está cerrado.';
      } else if (plantilla.length >= p.maxPlantilla) {
        motivoNoCompra = 'Tu plantilla ya tiene ${p.maxPlantilla} jugadores: vende uno antes.';
      } else if (fila.noHabitual && plantilla.any((j) => j.noHabitual)) {
        motivoNoCompra = 'Solo 1 invitado por plantilla.';
      } else if (fila.hayLibres && saldo != null && saldo < fila.precio) {
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
              Text('Posición preferida: ${etiquetaPosicion(miembro?.posicion).toLowerCase()}'),
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
          if (fila != null && fila.fichasTotales > 0)
            Chip(label: Text('${fila.fichasLibres}/${fila.fichasTotales} fichas libres')),
          if (enPlantilla != null && enPlantilla.propia)
            Chip(avatar: const Icon(Icons.gavel, size: 16), label: Text('Tu cláusula ${millones(enPlantilla.clausula)}')),
          if (enPlantilla != null && enPlantilla.cedidaAMi) const Chip(label: Text('Cedido a ti esta jornada')),
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
        if (enPlantilla != null && enPlantilla.propia)
          OutlinedButton.icon(
            style: AppButtons.peligro(context),
            icon: const Icon(Icons.sell_outlined),
            label: Text('Vender por ${millones(p.precioVenta(enPlantilla.precio))}'),
            onPressed: !abierto || enPlantilla.cedidaAOtro || enPlantilla.enCesionOfrecida
                ? null
                : () async {
                    if (!await confirmar(
                      context,
                      'Vender a ${miembro?.nombre ?? 'jugador'}',
                      'La ficha vuelve al mercado. Precio actual ${millones(enPlantilla.precio)} − '
                          '${(p.comisionVenta * 100).toStringAsFixed(0)} % de comisión: '
                          'recibes ${millones(p.precioVenta(enPlantilla.precio))}.',
                      accion: 'Vender',
                      tipo: TipoConfirmacion.peligro,
                    )) {
                      return;
                    }
                    if (!context.mounted) return;
                    final ok = await ejecutar(
                        context, () => FantasyRepo.vender(ligaId, miembroId, fichaId: enPlantilla.fichaId),
                        ok: 'Vendido');
                    if (ok) refrescarFantasy(ref, kYo);
                  },
          )
        else if (fila != null) ...[
          Text('Fichas', style: t.titleMedium),
          Text(
            '${fila.fichasLibres} libres de ${fila.fichasTotales}. '
            '${fila.hayLibres ? 'Puedes comprar una al precio de mercado.' : 'Están todas cogidas: paga la cláusula de un dueño o hazle una oferta.'}',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          if (fila.hayLibres)
            FilledButton.icon(
              style: AppButtons.premium(context),
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
          const SizedBox(height: 8),
          _DuenosFichas(
            mi: mi,
            jugadorId: miembroId,
            jugadorNombre: miembro?.nombre ?? 'jugador',
            precio: fila.precio,
            saldo: saldo,
            bloqueado: motivoNoCompra != null,
          ),
        ],
        if (miembroId == mi.yo.id && (enPlantilla == null || !enPlantilla.propia) && fila != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Sí, puedes ficharte a ti mismo.'),
          ),
      ]),
    );
  }
}

/// Dueños de las fichas del jugador: pagar su cláusula o hacerles una oferta.
class _DuenosFichas extends ConsumerWidget {
  const _DuenosFichas({
    required this.mi,
    required this.jugadorId,
    required this.jugadorNombre,
    required this.precio,
    required this.saldo,
    required this.bloqueado,
  });
  final MiLiga mi;
  final String jugadorId, jugadorNombre;
  final double precio;
  final double? saldo;

  /// Mercado cerrado, plantilla llena o límite de no habituales.
  final bool bloqueado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = (ligaId: mi.liga.id, miembroId: jugadorId);
    final kYo = (ligaId: mi.liga.id, miembroId: mi.yo.id);
    final fichas = ref.watch(fichasJugadorProvider(k));
    final t = Theme.of(context).textTheme;
    final p = mi.liga.fantasy;

    return fichas.when(
      loading: () => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
      error: (e, _) => Text(mensajeError(e)),
      data: (lista) {
        final conDueno = lista.where((f) => !f.libre && !f.esMia).toList()
          ..sort((a, b) => (a.clausula ?? 0).compareTo(b.clausula ?? 0));
        if (conDueno.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          Text('Dueños', style: t.titleSmall),
          for (final f in conDueno)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(f.propietarioNombre ?? '…', style: t.titleSmall)),
                    Text('Cláusula ${millones(f.clausula)}'),
                  ]),
                  if (f.protegida || f.cedida)
                    Text(
                      f.cedida
                          ? 'Cedida esta jornada: no se puede clausular ni ofertar.'
                          : 'Protegida hasta que se cierre el próximo partido.',
                      style: t.bodySmall,
                    ),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.handshake_outlined),
                      label: const Text('Hacer oferta'),
                      onPressed: f.cedida
                          ? null
                          : () async {
                              final importe = await dialogoOferta(context,
                                  jugador: jugadorNombre,
                                  propietario: f.propietarioNombre ?? 'su dueño',
                                  precioMercado: precio,
                                  clausula: f.clausula,
                                  saldo: saldo,
                                  horasCaducidad: p.horasCaducidadOferta);
                              if (importe == null || !context.mounted) return;
                              final ok = await ejecutar(context, () => FantasyRepo.hacerOferta(f.fichaId, importe),
                                  ok: 'Oferta enviada a ${f.propietarioNombre ?? 'su dueño'}');
                              if (ok) refrescarFantasy(ref, kYo);
                            },
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      style: AppButtons.premium(context),
                      icon: const Icon(Icons.gavel),
                      label: const Text('Pagar cláusula'),
                      onPressed: !f.clausulable || bloqueado || (saldo != null && saldo! < (f.clausula ?? 0))
                          ? null
                          : () async {
                              if (!await confirmar(
                                context,
                                'Pagar la cláusula',
                                'Pagas ${millones(f.clausula)} a ${f.propietarioNombre ?? 'su dueño'} y te llevas su ficha de '
                                    '$jugadorNombre al instante. No puede negarse. Quedará protegida para ti hasta '
                                    'que se cierre el próximo partido.',
                                accion: 'Pagar',
                                tipo: TipoConfirmacion.premium,
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              final ok = await ejecutar(context, () => FantasyRepo.pagarClausula(f.fichaId),
                                  ok: '¡$jugadorNombre es tuyo!');
                              if (ok) refrescarFantasy(ref, kYo);
                            },
                    ),
                  ]),
                ]),
              ),
            ),
          if (saldo != null && conDueno.any((f) => f.clausulable && (f.clausula ?? 0) > saldo!))
            Text('Tu saldo (${millones(saldo)}) no llega para alguna cláusula.', style: t.bodySmall),
        ]);
      },
    );
  }
}
