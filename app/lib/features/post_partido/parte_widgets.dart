import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/equipaciones.dart';
import '../../core/idioma.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../shell/sincronizacion.dart';

/// 0063: quién ha votado y quién falta, y el podio con su desglose.
final participacionProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, partidoId) async {
  ref.watch(latidoProvider('partido:$partidoId'));
  return Map<String, dynamic>.from(await sb.rpc('participacion_post_partido', params: {'p_partido': partidoId}) as Map);
});

final resumenJornadaProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, partidoId) async {
  ref.watch(latidoProvider('partido:$partidoId'));
  return Map<String, dynamic>.from(await sb.rpc('resumen_jornada', params: {'p_partido': partidoId}) as Map);
});

/// Cabecera del parte: «Han votado 8 de 10», quién falta y botón para recordárselo.
class ParticipacionParte extends ConsumerWidget {
  const ParticipacionParte({super.key, required this.partidoId, this.abierto = true});
  final String partidoId;
  final bool abierto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(participacionProvider(partidoId)).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final total = (d['jugadores'] as num?)?.toInt() ?? 0;
    final votaron = (d['votaron'] as num?)?.toInt() ?? 0;
    if (total == 0) return const SizedBox.shrink();
    final faltan = [for (final x in (d['faltan'] as List? ?? const [])) '${(x as Map)['nombre']}'];
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.how_to_vote_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(trf('Han votado {v} de {t} jugadores', {'v': votaron, 't': total}), style: t.titleSmall)),
            Text('${(100 * votaron / total).round()} %', style: AppTheme.tabular(t.titleSmall)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: votaron / total, minHeight: 10, backgroundColor: cs.surfaceContainerHighest),
          ),
          if (faltan.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(trf('Faltan: {n}', {'n': faltan.join(', ')}), style: t.bodySmall),
            if (abierto)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                  label: const Tx('Recordar a los que faltan'),
                  onPressed: () async {
                    final ok = await ejecutar(context, () => sb.rpc('recordar_votar', params: {'p_partido': partidoId}),
                        ok: tr('Aviso enviado a los que faltan'));
                    if (ok) ref.invalidate(participacionProvider(partidoId));
                  },
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Tx('¡Ya ha votado todo el mundo! 🎉', style: t.bodySmall),
            ),
        ]),
      ),
    );
  }
}

/// Podio con desglose: votos de 1.º, 2.º y 3.º de cada uno (3, 2 y 1 puntos). Se ve con la votación cerrada.
class PodioDesglose extends ConsumerWidget {
  const PodioDesglose({super.key, required this.partidoId});
  final String partidoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(participacionProvider(partidoId)).valueOrNull;
    final podio = [for (final x in (d?['podio'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    if (podio.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    const medallas = ['🥇', '🥈', '🥉'];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Tx('Podio de la votación', style: t.titleMedium),
          Tx('Cada voto de 1.º vale 3 puntos, de 2.º 2 y de 3.º 1.', style: t.bodySmall),
          const SizedBox(height: 6),
          for (final (i, x) in podio.take(6).indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(i < 3 ? medallas[i] : '${i + 1}', style: const TextStyle(fontSize: 20)),
              title: Text('${x['nombre']}'),
              subtitle: Text(trf('{a} de 1.º · {b} de 2.º · {c} de 3.º', {'a': x['primero'], 'b': x['segundo'], 'c': x['tercero']})),
              trailing: Text(trf('{p} pts', {'p': x['puntos']}), style: AppTheme.tabular(t.titleSmall)),
            ),
        ]),
      ),
    );
  }
}

/// Explicación legible de por qué un jugador sumó sus puntos.
String explicarPuntos(Map<String, dynamic> j) {
  final d = Map<String, dynamic>.from((j['desglose'] as Map?) ?? const {});
  num v(String k) => (d[k] as num?) ?? 0;
  String p(num x) => '${x > 0 ? '+' : ''}${x.toStringAsFixed(x == x.roundToDouble() ? 0 : 1).replaceAll('.', ',')}';
  final partes = <String>[
    if (v('jugado') != 0) '${tr('jugar')} ${p(v('jugado'))}',
    if (v('resultado') != 0)
      '${tr(((j['victorias'] as num?) ?? 0) > 0 ? 'ganar' : ((j['empates'] as num?) ?? 0) > 0 ? 'empatar' : 'resultado')} ${p(v('resultado'))}',
    if (v('goles') != 0) '${tr('goles')} ${p(v('goles'))}',
    if (v('asistencias') != 0) '${tr('asistencias')} ${p(v('asistencias'))}',
    if (v('valoracion') != 0) '${tr('nota')} ${p(v('valoracion'))}',
    if (v('podio') != 0) '${tr('podio')} ${p(v('podio'))}',
    if (v('mvp') != 0) 'MVP ${p(v('mvp'))}',
    if (v('paradas') != 0) '${tr('paradas')} ${p(v('paradas'))}',
    if (v('penaltis_parados') != 0) '${tr('penaltis parados')} ${p(v('penaltis_parados'))}',
    if (v('autogoles') != 0) '${tr('autogoles')} ${p(v('autogoles'))}',
    if (v('penaltis_fallados') != 0) '${tr('penaltis fallados')} ${p(v('penaltis_fallados'))}',
    if (v('porteria_cero') != 0) '${tr('portería a cero')} ${p(v('porteria_cero'))}',
  ];
  return partes.isEmpty ? tr('Sin puntos extra') : partes.join(' · ');
}

/// «Resumen de la jornada»: qué ha pasado y por qué cada uno sumó sus puntos.
class ResumenJornadaScreen extends ConsumerWidget {
  const ResumenJornadaScreen({super.key, required this.partidoId});
  final String partidoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(resumenJornadaProvider(partidoId));
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    String m(num x) => '${x.toStringAsFixed(x == x.roundToDouble() ? 0 : 1).replaceAll('.', ',')} M';
    return Scaffold(
      appBar: AppBar(title: const Tx('Resumen de la jornada')),
      body: datos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(resumenJornadaProvider(partidoId))),
        data: (d) {
          final enc = [for (final x in (d['encuentros'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
          final jug = [for (final x in (d['jugadores'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
          final man = [for (final x in (d['managers'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
          final mvp = [for (final x in (d['mvp'] as List? ?? const [])) '$x'];
          final porra = d['porra'] == null ? null : Map<String, dynamic>.from(d['porra'] as Map);
          final bote = d['bote'] == null ? null : Map<String, dynamic>.from(d['bote'] as Map);
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (d['estado'] != 'cerrado')
              Card(
                color: cs.tertiaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.hourglass_top),
                  title: Tx('La jornada aún no está cerrada'),
                  subtitle: Tx('Los puntos se calculan al cerrar el partido.'),
                ),
              ),
            for (final e in enc)
              Center(
                child: Text('${nombreEquipo(context, (e['local'] as num).toInt())}  ${e['goles_local'] ?? '-'} – ${e['goles_visitante'] ?? '-'}  ${nombreEquipo(context, (e['visitante'] as num).toInt())}',
                    style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
            if (mvp.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(child: Text('⭐ MVP: ${mvp.join(' y ')}', style: t.titleMedium)),
              ),
            const SizedBox(height: 16),
            Tx('Así sumó cada uno', style: t.titleMedium),
            const SizedBox(height: 4),
            for (final j in jug)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  title: Row(children: [
                    Expanded(child: Text('${j['nombre']}${j['es_mvp'] == true ? '  ⭐' : ''}', style: t.titleSmall)),
                    Text(trf('{p} pts', {'p': j['total']}), style: AppTheme.tabular(t.titleMedium)),
                  ]),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(explicarPuntos(j)),
                    if (j['variacion'] != null && (j['variacion'] as num) != 0)
                      Text(
                        trf('Precio: {p} ({v})', {
                          'p': m(j['precio'] as num),
                          'v': '${(j['variacion'] as num) > 0 ? '▲' : '▼'} ${m((j['variacion'] as num).abs())}',
                        }),
                        style: TextStyle(color: (j['variacion'] as num) > 0 ? Colors.green.shade700 : cs.error),
                      ),
                  ]),
                ),
              ),
            if (man.isNotEmpty) ...[
              const SizedBox(height: 16),
              Tx('Fantasy: mánagers de la jornada', style: t.titleMedium),
              for (final (i, x) in man.indexed)
                ListTile(
                  dense: true,
                  leading: Text(i < 3 ? const ['🥇', '🥈', '🥉'][i] : '${i + 1}', style: const TextStyle(fontSize: 18)),
                  title: Text('${x['nombre']}'),
                  trailing: Text(trf('{p} pts · +{d}', {'p': x['puntos'], 'd': m((x['ingreso'] as num?) ?? 0)})),
                ),
            ],
            if ((porra != null && ((porra['boletos'] as num?) ?? 0) > 0) || bote != null) ...[
              const SizedBox(height: 16),
              Tx('Porra', style: t.titleMedium),
              if (porra != null && ((porra['boletos'] as num?) ?? 0) > 0)
                Text(trf('{g} de {b} boletos acertados · se pagaron {x}',
                    {'g': porra['ganados'], 'b': porra['boletos'], 'x': m((porra['pagado'] as num?) ?? 0)})),
              if (bote != null)
                Text(trf('Bote de {x}: {p} plenos y {s} aciertos del 1X2. Pasan {a} al siguiente.', {
                  'x': m(bote['bote'] as num),
                  'p': bote['plenos'],
                  's': bote['signos'],
                  'a': m(bote['arrastre'] as num),
                })),
            ],
          ]);
        },
      ),
    );
  }
}

/// Confirmación y cierre en un solo toque. Devuelve true si se cerró.
Future<bool> cerrarPartidoConResumen(BuildContext context, String partidoId, Future<Object?> Function() cerrar) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Tx('Cerrar partido'),
      content: const Tx('Con un toque la app:\n'
          '• cierra la votación y cruza los partes,\n'
          '• proclama al MVP,\n'
          '• aplica capitán, ariete y bonus por puesto (portería a cero incluida),\n'
          '• mete a los suplentes de quien no jugó,\n'
          '• actualiza los precios del mercado,\n'
          '• reparte la porra y el bote.\n\n'
          'Si hay datos sin acuerdo, se quedan para que los revises.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Tx('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Tx('Cerrar partido')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  Object? estado;
  final hecho = await ejecutar(context, () async => estado = await cerrar());
  if (!hecho || !context.mounted) return false;
  if ('$estado'.contains('revision')) {
    mostrarOk(context, tr('Hay datos sin acuerdo: revísalos en la pestaña Revisión'));
    return true;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResumenJornadaScreen(partidoId: partidoId)));
  return true;
}

