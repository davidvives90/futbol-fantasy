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
import 'tarjetas_jugador.dart';
import 'subastas_draft.dart';

enum _Orden { media, precio, variacion, forma, fichado, libres }

extension on _Orden {
  String get etiqueta => tr(switch (this) {
        _Orden.media => 'Media',
        _Orden.precio => 'Precio',
        _Orden.variacion => 'Variación',
        _Orden.forma => 'En forma',
        _Orden.fichado => 'Más fichados',
        _Orden.libres => 'Disponibles',
      });
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
  _Orden _orden = _Orden.media;
  bool _soloNoHabituales = false;

  @override
  Widget build(BuildContext context) {
    final ligaId = widget.mi.liga.id;
    final k = (ligaId: ligaId, miembroId: widget.mi.yo.id);
    final mercado = ref.watch(mercadoProvider(ligaId));
    final resumen = ref.watch(resumenFantasyProvider(ligaId)).valueOrNull ?? const <String, ResumenFantasy>{};
    final abierto = ref.watch(mercadoAbiertoProvider(ligaId)).valueOrNull ?? true;
    final miembros = ref.watch(miembrosPorIdProvider(ligaId));
    final mios = {
      for (final j in ref.watch(miPlantillaProvider(k)).valueOrNull ?? const <JugadorPlantilla>[])
        if (j.propia) j.jugadorId,
    };
    final saldo = ref.watch(miManagerProvider(k)).valueOrNull?.saldo;

    final modo = widget.mi.liga.fantasy.modoInicio;
    // 0059: jugadores puestos en subasta por sus mánagers (en cualquier modo de inicio)
    final hayVentas = (ref.watch(subastasProvider(widget.mi.liga.id)).valueOrNull ?? const [])
        .any((s) => s.abierta && s.vendedorId != null);
    return Column(children: [
      if (!abierto) BannerMercadoCerrado(mi: widget.mi),
      // 0054: subasta diaria o draft por turnos
      if (modo == 'subasta' || modo == 'draft' || hayVentas)
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
          child: SingleChildScrollView(
            child: modo == 'draft' && !hayVentas ? DraftPanel(mi: widget.mi) : SubastasPanel(mi: widget.mi),
          ),
        ),
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
                  _Orden.media => resumen[j.miembroId]?.media ?? -1,
                  // En forma: media de sus 3 últimos partidos
                  _Orden.forma => () {
                      final u = resumen[j.miembroId]?.ultimos ?? const [];
                      if (u.isEmpty) return -1.0;
                      final t = u.take(3).toList();
                      return t.fold<double>(0, (a, x) => a + x.total) / t.length;
                    }(),
                  _Orden.fichado => j.pctFichado ?? 0,
                  _Orden.libres => j.fichasLibres.toDouble(),
                };
            filtrada.sort((a, b) => clave(b).compareTo(clave(a)));
            if (filtrada.isEmpty) {
              return Vacio(lista.isEmpty ? 'Todavía no hay jugadores en el mercado.' : 'Ningún jugador coincide.');
            }
            return RefreshIndicator(
              onRefresh: () async => refrescarFantasy(ref, k),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: filtrada.length,
                itemBuilder: (_, i) {
                  final j = filtrada[i];
                  final m = miembros[j.miembroId];
                  // Tarjeta: foto, rango, posición, valor, media por partido y últimas 5
                  return TarjetaJugadorLista(
                    miembro: m,
                    precio: j.precio,
                    variacion: j.variacion,
                    resumen: resumen[j.miembroId],
                    mio: mios.contains(j.miembroId),
                    insignia: j.noHabitual
                        ? InsigniaNoHabitual(bonus: widget.mi.liga.fantasy.bonusNoHabitual, corta: true)
                        : null,
                    extra: j.fichasTotales == 0
                        ? null
                        : j.hayLibres
                            ? trf('{l} de {t} disponibles', {'l': j.fichasLibres, 't': j.fichasTotales})
                            : j.clausulaMinima != null
                                ? trf('Agotado · cláusula desde {x}', {'x': millones(j.clausulaMinima)})
                                : tr('Agotado'),
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
