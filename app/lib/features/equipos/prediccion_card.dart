import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/equipaciones.dart';
import '../../core/info.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';

final prediccionProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>(
  (ref, partidoId) => FantasyRepo.prediccion(partidoId),
);

const ayudaXg = ('Goles esperados (xG)',
    'Una estimación de cuántos goles marcará cada equipo según lo que ha pasado en vuestros partidos: '
        'los goles por partido de cada jugador, lo que encaja su equipo cuando juega y su valoración de la encuesta '
        '(que pesa más mientras alguien tiene pocos partidos).\n\n'
        'Con esos goles esperados se calculan las probabilidades de cada resultado. Es orientativo: con pocos '
        'partidos jugados la fiabilidad es baja y el fútbol es fútbol.');

/// «Resultado esperado» con los equipos hechos: xG de cada equipo, probabilidades, marcador más probable,
/// quién tiene más xG y un resumen en una frase. Solo si la liga lo tiene activado.
class PrediccionCard extends ConsumerWidget {
  const PrediccionCard({super.key, required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  String _resumen(BuildContext context, Map e, String? goleador) {
    final a = nombreEquipo(context, (e['local'] as num).toInt());
    final b = nombreEquipo(context, (e['visitante'] as num).toInt());
    final pa = (e['prob_local'] as num).toInt();
    final pb = (e['prob_visitante'] as num).toInt();
    final xa = (e['xg_local'] as num).toDouble();
    final xb = (e['xg_visitante'] as num).toDouble();
    final total = xa + xb;
    final ritmo = total >= 12 ? 'con muchos goles' : (total <= 6 ? 'cerrado, de pocos goles' : 'con goles');
    final quien = (pa - pb).abs() < 10
        ? 'Partido igualado $ritmo'
        : '${pa > pb ? a : b} sale favorito (${pa > pb ? pa : pb} %) en un partido $ritmo';
    return goleador == null ? '$quien.' : '$quien. Más peligroso: $goleador.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!mi.liga.prediccionActiva) return const SizedBox.shrink();
    final pred = ref.watch(prediccionProvider(partido.id)).valueOrNull;
    if (pred == null) return const SizedBox.shrink();
    final encuentros = (pred['encuentros'] as List? ?? const []).cast<Map>();
    if (encuentros.isEmpty) return const SizedBox.shrink();
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fiabilidad = pred['fiabilidad'] as String? ?? 'baja';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.insights, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Resultado esperado', style: t.titleMedium)),
            Text('fiabilidad $fiabilidad', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            const InfoBoton(ayudaXg),
          ]),
          for (final e in encuentros) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: EtiquetaEquipo((e['local'] as num).toInt())),
              Text('${(e['xg_local'] as num).toStringAsFixed(1)}  –  ${(e['xg_visitante'] as num).toStringAsFixed(1)}',
                  style: t.headlineSmall),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: EtiquetaEquipo((e['visitante'] as num).toInt())),
              ),
            ]),
            Center(child: Text('goles esperados · marcador más probable ${e['marcador_probable']}', style: t.bodySmall)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 22,
                child: Row(children: [
                  for (final (clave, color, etiqueta) in [
                    ('prob_local', colorEquipo(context, (e['local'] as num).toInt()), 'Gana'),
                    ('prob_empate', cs.surfaceContainerHighest, 'Empate'),
                    ('prob_visitante', colorEquipo(context, (e['visitante'] as num).toInt()), 'Gana'),
                  ])
                    if ((e[clave] as num) > 0)
                      Expanded(
                        flex: (e[clave] as num).toInt(),
                        child: Container(
                          color: color,
                          alignment: Alignment.center,
                          child: (e[clave] as num) >= 12
                              ? Text('${e[clave]} %',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white))
                              : null,
                        ),
                      ),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Text('Gana ${nombreEquipo(context, (e['local'] as num).toInt())}', style: t.labelSmall),
              const Spacer(),
              Tx('Empate', style: t.labelSmall),
              const Spacer(),
              Text('Gana ${nombreEquipo(context, (e['visitante'] as num).toInt())}', style: t.labelSmall),
            ]),
            Builder(builder: (context) {
              final jugadores = ((e['jugadores'] as List?) ?? const []).cast<Map>().toList()
                ..sort((a, b) => (b['xg'] as num).compareTo(a['xg'] as num));
              final top = jugadores.take(3).toList();
              final goleador = top.isEmpty ? null : miembros[top.first['miembro_id']]?.nombre;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 10),
                Text(_resumen(context, e, goleador), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (top.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final j in top)
                      Chip(
                        avatar: PuntoEquipo((j['equipo'] as num).toInt()),
                        label: Text('${miembros[j['miembro_id']]?.nombre ?? '…'} · ${(j['xg'] as num).toStringAsFixed(2)} xG'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ]),
                ],
              ]);
            }),
          ],
          const SizedBox(height: 6),
          Text('Basado en ${pred['partidos_base']} partidos de la liga.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
