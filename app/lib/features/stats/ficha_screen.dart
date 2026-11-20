import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/stats_repo.dart';
import '../../core/avatar.dart';

final historialProvider = FutureProvider.autoDispose.family<List<PuntosFantasy>, String>(
  (ref, miembroId) => StatsRepo.historial(miembroId),
);

final statsJugadorProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, miembroId) => StatsRepo.jugador(miembroId),
);

/// Ficha de un jugador: totales y puntos por partido.
class FichaScreen extends ConsumerWidget {
  const FichaScreen({super.key, required this.miembroId, this.conAppBar = true});
  final String miembroId;
  final bool conAppBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final miembro = ref.watch(miembrosPorIdProvider(mi.liga.id))[miembroId];
    final rend = (ref.watch(rendimientoProvider(mi.liga.id)).valueOrNull ?? const <Rendimiento>[])
        .where((r) => r.miembroId == miembroId)
        .firstOrNull;
    final historial = ref.watch(historialProvider(miembroId));

    final cuerpo = ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        AvatarMiembro(miembro, radio: 36),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(miembro?.nombre ?? '…', style: Theme.of(context).textTheme.headlineSmall),
            Text([etiquetaPosicion(miembro?.posicion), if (textoEdad(miembro) != null) textoEdad(miembro)!].join(' · ')),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      if (rend == null)
        const Text('Aún no ha jugado ningún partido cerrado.')
      else
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.4,
          children: [
            _Dato('Puntos', rend.puntosTotal.toStringAsFixed(0)),
            _Dato('Partidos', '${rend.partidos}'),
            _Dato('Media', rend.puntosMedia.toStringAsFixed(1)),
            _Dato('Goles', '${rend.goles}'),
            _Dato('Asistencias', '${rend.asistencias}'),
            _Dato('MVPs', '${rend.mvps}'),
            _Dato('Nota media', rend.notaMedia?.toStringAsFixed(1) ?? '—'),
            _Dato('Goles/partido', rend.golesPartido.toStringAsFixed(2)),
            _Dato('% victorias', rend.pctVictorias == null ? '—' : '${rend.pctVictorias!.toStringAsFixed(0)} %'),
          ],
        ),
      ...ref.watch(statsJugadorProvider(miembroId)).maybeWhen(
            data: (e) => [const SizedBox(height: 16), _Extra(e, miembros: ref.watch(miembrosPorIdProvider(mi.liga.id)))],
            orElse: () => const <Widget>[],
          ),
      const SizedBox(height: 16),
      Text('Puntos por partido', style: Theme.of(context).textTheme.titleMedium),
      ...historial.when(
        loading: () => [const Padding(padding: EdgeInsets.all(24), child: Cargando())],
        error: (e, _) => [ErrorVista(e)],
        data: (lista) {
          if (lista.isEmpty) return [const Padding(padding: EdgeInsets.all(16), child: Text('Sin partidos todavía.'))];
          final maximo = lista.map((p) => p.total.abs()).fold<double>(1, (a, b) => b > a ? b : a);
          return [
            for (final p in lista)
              ListTile(
                dense: true,
                leading: p.esMvp
                    ? Icon(Icons.star, color: Theme.of(context).colorScheme.tertiary)
                    : const Icon(Icons.sports_soccer),
                title: Text(p.fecha == null ? 'Partido' : fechaCorta(p.fecha!)),
                subtitle: LinearProgressIndicator(value: (p.total.abs() / maximo).clamp(0.0, 1.0).toDouble()),
                trailing: Text(p.total.toStringAsFixed(p.total % 1 == 0 ? 0 : 1),
                    style: AppTheme.tabular(Theme.of(context).textTheme.titleMedium)),
              ),
          ];
        },
      ),
    ]);

    if (!conAppBar) return cuerpo;
    return Scaffold(appBar: AppBar(title: Text(miembro?.nombre ?? 'Jugador')), body: cuerpo);
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);
  final String etiqueta, valor;

  @override
  Widget build(BuildContext context) => Card(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(valor, style: Theme.of(context).textTheme.titleLarge),
          Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

/// Forma, rachas, porcentaje de asistencia, compañeros y destacados.
class _Extra extends StatelessWidget {
  const _Extra(this.e, {required this.miembros});
  final Map<String, dynamic> e;
  final Map<String, Miembro> miembros;

  String _nombre(dynamic m) => miembros[(m as Map)['miembro_id']]?.nombre ?? 'Alguien';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final forma = (e['forma'] as String?) ?? '';
    final destacados = Map<String, dynamic>.from((e['destacados'] as Map?) ?? const {});
    Color colorForma(String c) => switch (c) { 'V' => Colors.green.shade600, 'D' => cs.error, _ => cs.outline };
    final filas = <Widget>[
      if (e['mejor_companero'] != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.handshake_outlined),
          title: Text('Mejor pareja: ${_nombre(e['mejor_companero'])}'),
          subtitle: Text('${e['mejor_companero']['pct_victorias']} % de victorias juntos '
              '(${e['mejor_companero']['partidos']} partidos)'),
        ),
      if (e['mas_juega_con'] != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.groups_outlined),
          title: Text('Más partidos con: ${_nombre(e['mas_juega_con'])}'),
          subtitle: Text('${e['mas_juega_con']['partidos']} partidos en el mismo equipo'),
        ),
      if (e['bestia_negra'] != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.sentiment_dissatisfied_outlined),
          title: Text('Bestia negra: ${_nombre(e['bestia_negra'])}'),
          subtitle: Text('Pierde el ${e['bestia_negra']['pct_derrotas']} % cuando le tiene enfrente'),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Forma y rachas', style: t.titleMedium),
      const SizedBox(height: 8),
      Row(children: [
        for (final c in forma.split(''))
          Container(
            margin: const EdgeInsets.only(right: 6),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colorForma(c), borderRadius: BorderRadius.circular(8)),
            child: Text(c, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        if (forma.isEmpty) const Text('Sin partidos todavía'),
        const Spacer(),
        if (e['asistencia_pct'] != null) Text('Asistencia ${e['asistencia_pct']} %', style: t.bodySmall),
      ]),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.4,
        children: [
          _Dato('Invicto ahora', '${e['racha_invicto_actual'] ?? 0}'),
          _Dato('Mejor racha invicto', '${e['racha_invicto_max'] ?? 0}'),
          _Dato('Victorias seguidas', '${e['racha_victorias_max'] ?? 0}'),
          _Dato('Porterías a cero', '${e['porterias_cero'] ?? 0}'),
          _Dato('Encajados/partido', '${e['goles_encajados_partido'] ?? '—'}'),
          _Dato('Votos MVP', '${e['votos_mvp'] ?? 0}'),
        ],
      ),
      if (destacados.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Destacó en', style: t.titleSmall),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in destacados.entries)
            Chip(label: Text('${nombresAspectos[d.key] ?? d.key} ×${d.value}'), visualDensity: VisualDensity.compact),
        ]),
      ],
      if (filas.isNotEmpty) ...[const SizedBox(height: 8), ...filas],
    ]);
  }
}
