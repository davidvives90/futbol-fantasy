import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../shell/home_shell.dart';
import '../../core/avatar.dart';
import '../../core/info.dart';
import '../../data/repos/stats_repo.dart';

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

/// Inicio de la temporada en curso (null = nunca se ha cerrado una temporada).
final inicioTemporadaProvider = FutureProvider.autoDispose.family<DateTime?, String>((ref, ligaId) async {
  final r = await sb.rpc('inicio_temporada', params: {'p_liga': ligaId});
  return r == null ? null : DateTime.parse(r as String);
});
final _verHistoricoProvider = StateProvider<bool>((ref) => false);
final _clasificacionProvider =
    FutureProvider.autoDispose.family<List<Rendimiento>, ({String ligaId, bool historico})>((ref, k) async {
  final inicio = await ref.watch(inicioTemporadaProvider(k.ligaId).future);
  if (k.historico || inicio == null) return ref.watch(rendimientoProvider(k.ligaId).future);
  return StatsRepo.rendimientoPeriodo(k.ligaId, desde: inicio);
});

class ClasificacionScreen extends ConsumerWidget {
  const ClasificacionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final historico = ref.watch(_verHistoricoProvider);
    final inicio = ref.watch(inicioTemporadaProvider(mi.liga.id)).valueOrNull;
    final rend = ref.watch(_clasificacionProvider((ligaId: mi.liga.id, historico: historico)));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    Future<void> refrescar() async {
      ref.invalidate(rendimientoProvider(mi.liga.id));
      ref.invalidate(inicioTemporadaProvider(mi.liga.id));
      await ref.refresh(_clasificacionProvider((ligaId: mi.liga.id, historico: historico)).future);
    }

    return DefaultTabController(
      length: _rankings.length + 1,
      child: Scaffold(
        appBar: LigaAppBar(
          actions: [
            IconButton(
              tooltip: 'Palmarés y temporadas',
              icon: const Icon(Icons.emoji_events_outlined),
              onPressed: () => context.push('/palmares'),
            ),
            const InfoBoton(Ayuda.puntos, tamano: 22),
          ],
          bottom: TabBar(isScrollable: true, tabs: [for (final r in _rankings) Tab(text: r.titulo), const Tab(text: 'Récords')]),
        ),
        body: Column(children: [
          if (inicio != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Tx('Esta temporada')),
                  ButtonSegment(value: true, label: Tx('Histórico')),
                ],
                selected: {historico},
                onSelectionChanged: (v) => ref.read(_verHistoricoProvider.notifier).state = v.first,
              ),
            ),
          Expanded(child: rend.when(
          loading: () => const Cargando(),
          error: (e, _) => ErrorVista(e, onRetry: refrescar),
          data: (lista) => TabBarView(children: [
            for (final rk in _rankings)
              RefreshIndicator(
                onRefresh: refrescar,
                child: _Lista(ranking: rk, datos: lista, miembros: miembros, yo: mi.yo.id),
              ),
            _Records(ligaId: mi.liga.id, miembros: miembros),
          ]),
        )),
        ]),
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

final statsLigaProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, ligaId) => StatsRepo.liga(ligaId),
);

/// Récords y curiosidades de toda la liga.
class _Records extends ConsumerWidget {
  const _Records({required this.ligaId, required this.miembros});
  final String ligaId;
  final Map<String, Miembro> miembros;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(statsLigaProvider(ligaId));
    final t = Theme.of(context).textTheme;
    String n(dynamic id) => miembros[id]?.nombre ?? 'Alguien';
    String marcador(dynamic m) => m == null ? '—' : '${m['local']}–${m['visitante']} · ${fechaCorta(DateTime.parse(m['fecha'] as String))}';
    return datos.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(statsLigaProvider(ligaId))),
      data: (e) {
        if ((e['partidos'] ?? 0) == 0) return const Vacio('Los récords aparecerán cuando se cierre el primer partido', icono: Icons.emoji_events_outlined);
        final parejas = (e['mejores_parejas'] as List?) ?? const [];
        final fieles = (e['mas_fieles'] as List?) ?? const [];
        return RefreshIndicator(
          onRefresh: () => ref.refresh(statsLigaProvider(ligaId).future),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Cifra('Partidos', '${e['partidos']}'),
              _Cifra('Goles', '${e['goles']}'),
              _Cifra('Goles/partido', '${e['goles_partido'] ?? '—'}'),
              _Cifra('Empates', '${e['empates_pct'] ?? 0} %'),
            ]),
            const SizedBox(height: 16),
            ListTile(leading: const Icon(Icons.local_fire_department_outlined), title: const Tx('Mayor goleada'),
                subtitle: Text(marcador(e['mayor_goleada']))),
            ListTile(leading: const Icon(Icons.sports_soccer), title: const Tx('Partido con más goles'),
                subtitle: Text(marcador(e['mas_goles']))),
            if (parejas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Tx('Mejores parejas', style: t.titleMedium),
              for (final p in parejas)
                ListTile(dense: true, leading: const Icon(Icons.handshake_outlined),
                    title: Text('${n(p['a'])} + ${n(p['b'])}'),
                    trailing: Text('${p['pct_victorias']} % · ${p['partidos']} PJ')),
            ],
            if (fieles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Tx('Los que nunca fallan', style: t.titleMedium),
              for (final f in fieles)
                ListTile(dense: true, leading: AvatarMiembro(miembros[f['miembro_id']], radio: 14),
                    title: Text(n(f['miembro_id'])), trailing: Text('${f['partidos']} partidos')),
            ],
          ]),
        );
      },
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.etiqueta, this.valor);
  final String etiqueta, valor;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text(valor, style: Theme.of(context).textTheme.titleLarge),
              Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}
