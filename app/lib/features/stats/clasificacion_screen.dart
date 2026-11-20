import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../shell/home_shell.dart';
import '../../core/avatar.dart';

/// Una pestaña del ranking: cómo ordenar y qué valor mostrar.
class _Ranking {
  const _Ranking(this.titulo, this.valor, this.texto, {this.minPartidos = 0});
  final String titulo;
  final double Function(Rendimiento) valor;
  final String Function(Rendimiento) texto;

  /// Para porcentajes y medias, exige un mínimo de partidos para no premiar a quien jugó uno.
  final int minPartidos;
}

final _rankings = [
  _Ranking('Fantasy', (r) => r.puntosTotal, (r) => '${r.puntosTotal.toStringAsFixed(0)} pts'),
  _Ranking('Pichichi', (r) => r.goles.toDouble(), (r) => '${r.goles} goles'),
  _Ranking('Asistencias', (r) => r.asistencias.toDouble(), (r) => '${r.asistencias} asist.'),
  _Ranking('MVPs', (r) => r.mvps.toDouble(), (r) => '${r.mvps} MVP'),
  _Ranking('% victorias', (r) => r.pctVictorias ?? 0, (r) => '${(r.pctVictorias ?? 0).toStringAsFixed(0)} %',
      minPartidos: 3),
];

class ClasificacionScreen extends ConsumerWidget {
  const ClasificacionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final rend = ref.watch(rendimientoProvider(mi.liga.id));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));

    return DefaultTabController(
      length: _rankings.length,
      child: Scaffold(
        appBar: LigaAppBar(
          bottom: TabBar(isScrollable: true, tabs: [for (final r in _rankings) Tab(text: r.titulo)]),
        ),
        body: rend.when(
          loading: () => const Cargando(),
          error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(rendimientoProvider(mi.liga.id))),
          data: (lista) => TabBarView(children: [
            for (final rk in _rankings)
              RefreshIndicator(
                onRefresh: () => ref.refresh(rendimientoProvider(mi.liga.id).future),
                child: _Lista(ranking: rk, datos: lista, miembros: miembros, yo: mi.yo.id),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.ranking, required this.datos, required this.miembros, required this.yo});
  final _Ranking ranking;
  final List<Rendimiento> datos;
  final Map<String, Miembro> miembros;
  final String yo;

  @override
  Widget build(BuildContext context) {
    final filas = datos.where((r) => r.partidos >= ranking.minPartidos && ranking.valor(r) > 0).toList()
      ..sort((a, b) => ranking.valor(b).compareTo(ranking.valor(a)));
    if (filas.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 360, child: Vacio('Se rellena sola al cerrar el primer partido: puntos, goles, MVP y racha de cada uno.', titulo: 'Aún no hay clasificación', icono: Icons.leaderboard_outlined)),
      ]);
    }

    // Posición con empates: mismo valor = misma posición (calculada antes: el builder es perezoso).
    final posiciones = <int>[];
    for (var i = 0; i < filas.length; i++) {
      final igual = i > 0 && ranking.valor(filas[i]) == ranking.valor(filas[i - 1]);
      posiciones.add(igual ? posiciones[i - 1] : i + 1);
    }
    return ListView.builder(
      itemCount: filas.length + (ranking.minPartidos > 0 ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == filas.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Mínimo ${ranking.minPartidos} partidos jugados.', style: Theme.of(context).textTheme.bodySmall),
          );
        }
        final r = filas[i];
        final pos = posiciones[i];
        final m = miembros[r.miembroId];
        final esYo = r.miembroId == yo;
        return ListTile(
          selected: esYo,
          leading: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 26,
              child: Text('$pos',
                  textAlign: TextAlign.center,
                  style: AppTheme.tabular(Theme.of(context).textTheme.titleMedium)
                      ?.copyWith(fontWeight: FontWeight.w800, color: pos <= 3 ? null : Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 6),
            // Podio: anillo oro (premium), plata y bronce sobrios
            AvatarMiembro(m, anillo: switch (pos) {
              1 => Theme.of(context).colorScheme.tertiary,
              2 => const Color(0xFFB9BDBC),
              3 => const Color(0xFFC79A74),
              _ => null,
            }),
          ]),
          title: Text(m?.nombre ?? '…'),
          subtitle: Text('${r.partidos} partidos · media ${r.puntosMedia.toStringAsFixed(1)} pts'),
          trailing: Text(ranking.texto(r), style: AppTheme.numero(context, size: 20)),
          onTap: () => context.push('/clasificacion/jugador/${r.miembroId}'),
        );
      },
    );
  }
}
