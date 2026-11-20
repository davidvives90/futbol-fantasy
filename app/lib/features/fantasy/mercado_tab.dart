import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import 'fantasy_providers.dart';
import 'widgets_fantasy.dart';

enum _Orden { precio, variacion, rating, fichado, libres }

extension on _Orden {
  String get etiqueta => switch (this) {
        _Orden.precio => 'Precio',
        _Orden.variacion => 'Variación',
        _Orden.rating => 'Valoración',
        _Orden.fichado => '% fichado',
        _Orden.libres => 'Fichas libres',
      };
}

/// Lista del mercado (v_mercado) con búsqueda, orden y filtro de no habituales.
class MercadoTab extends ConsumerStatefulWidget {
  const MercadoTab({super.key, required this.mi});
  final MiLiga mi;

  @override
  ConsumerState<MercadoTab> createState() => _MercadoTabState();
}

class _MercadoTabState extends ConsumerState<MercadoTab> {
  String _texto = '';
  _Orden _orden = _Orden.precio;
  bool _soloNoHabituales = false;

  @override
  Widget build(BuildContext context) {
    final ligaId = widget.mi.liga.id;
    final k = (ligaId: ligaId, miembroId: widget.mi.yo.id);
    final mercado = ref.watch(mercadoProvider(ligaId));
    final abierto = ref.watch(mercadoAbiertoProvider(ligaId)).valueOrNull ?? true;
    final miembros = ref.watch(miembrosPorIdProvider(ligaId));
    final mios = {
      for (final j in ref.watch(miPlantillaProvider(k)).valueOrNull ?? const <JugadorPlantilla>[])
        if (j.propia) j.jugadorId,
    };
    final saldo = ref.watch(miManagerProvider(k)).valueOrNull?.saldo;

    return Column(children: [
      if (!abierto) BannerMercadoCerrado(mi: widget.mi),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          decoration:  InputDecoration(prefixIcon: Icon(Icons.search), hintText: tr('Buscar jugador'), isDense: true),
          onChanged: (v) => setState(() => _texto = v.trim().toLowerCase()),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (final o in _Orden.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(o.etiqueta), selected: _orden == o, onSelected: (_) => setState(() => _orden = o)),
            ),
          FilterChip(
            label: const Tx('Invitados ×1,5'),
            selected: _soloNoHabituales,
            onSelected: (v) => setState(() => _soloNoHabituales = v),
          ),
        ]),
      ),
      if (saldo != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(alignment: Alignment.centerRight, child: Text('Tu saldo: ${millones(saldo)}')),
        ),
      Expanded(
        child: mercado.when(
          loading: () => const Cargando(),
          error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(mercadoProvider(ligaId))),
          data: (lista) {
            final filtrada = lista.where((j) {
              final nombre = miembros[j.miembroId]?.nombre.toLowerCase() ?? '';
              return (_texto.isEmpty || nombre.contains(_texto)) && (!_soloNoHabituales || j.noHabitual);
            }).toList();
            double clave(JugadorMercado j) => switch (_orden) {
                  _Orden.precio => j.precio,
                  _Orden.variacion => j.variacion ?? 0,
                  _Orden.rating => j.rating ?? 0,
                  _Orden.fichado => j.pctFichado ?? 0,
                  _Orden.libres => j.fichasLibres.toDouble(),
                };
            filtrada.sort((a, b) => clave(b).compareTo(clave(a)));
            if (filtrada.isEmpty) {
              return Vacio(lista.isEmpty ? 'El mercado se abre al cerrar la encuesta inicial.' : 'Ningún jugador coincide.');
            }
            return RefreshIndicator(
              onRefresh: () async => refrescarFantasy(ref, k),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: filtrada.length,
                itemBuilder: (_, i) {
                  final j = filtrada[i];
                  final m = miembros[j.miembroId];
                  return ListTile(
                    leading: AvatarMiembro(m),
                    title: Row(children: [
                      Flexible(child: Text(m?.nombre ?? '…', overflow: TextOverflow.ellipsis)),
                      if (mios.contains(j.miembroId)) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle, size: 16),
                      ],
                      if (j.noHabitual) ...[
                        const SizedBox(width: 6),
                        InsigniaNoHabitual(bonus: widget.mi.liga.fantasy.bonusNoHabitual, corta: true),
                      ],
                    ]),
                    subtitle: Text([
                      if (j.rating != null) 'valoración ${j.rating!.round()}',
                      if (j.fichasTotales > 0)
                        j.hayLibres
                            ? '${j.fichasLibres}/${j.fichasTotales} fichas libres'
                            : j.clausulaMinima != null
                                ? 'agotado · cláusula desde ${millones(j.clausulaMinima)}'
                                : 'agotado',
                    ].join(' · ')),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(millones(j.precio), style: Theme.of(context).textTheme.titleSmall),
                      VariacionTexto(j.variacion),
                    ]),
                    onTap: () => context.push('/fantasy/jugador/${j.miembroId}'),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// "Mercado cerrado hasta…": desde el cierre de alineaciones hasta que se liquida el partido.
class BannerMercadoCerrado extends ConsumerWidget {
  const BannerMercadoCerrado({super.key, required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proximo = ref.watch(proximoPartidoProvider(mi.liga.id));
    final sinLiquidar = ref.watch(partidoSinLiquidarProvider(mi.liga.id));
    final p = sinLiquidar ?? proximo;
    final texto = p == null
        ? 'Mercado cerrado.'
        : 'Mercado cerrado hasta que se calculen los puntos del partido del ${fechaHora(p.fechaHora)}.';
    return MaterialBanner(
      leading: const Icon(Icons.lock_clock),
      content: Text(texto),
      actions: const [SizedBox.shrink()],
    );
  }
}
