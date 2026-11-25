import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/idioma.dart';
import '../../core/utils.dart';
import '../../data/repos/stats_repo.dart';

/// 0056: los 150 logros de un jugador (30 familias × 5 niveles), con progreso.
final logrosProvider = FutureProvider.autoDispose.family<Logros, String>((ref, miembroId) {
  ref.watch(idiomaProvider); // nombres en el idioma de la app
  return StatsRepo.logrosDe(miembroId);
});

/// Categorías en el orden en que se muestran.
const categoriasLogros = <(String, String)>[
  ('ataque', 'Ataque'),
  ('porteria', 'Portería'),
  ('constancia', 'Constancia'),
  ('resultados', 'Resultados'),
  ('reconocimiento', 'Reconocimiento'),
  ('fantasy', 'Fantasy'),
  ('porra', 'Porra'),
  ('humor', 'Con humor'),
];

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class LogrosScreen extends ConsumerStatefulWidget {
  const LogrosScreen({super.key, required this.miembroId, this.nombre});
  final String miembroId;
  final String? nombre;

  @override
  ConsumerState<LogrosScreen> createState() => _LogrosScreenState();
}

class _LogrosScreenState extends ConsumerState<LogrosScreen> {
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(logrosProvider(widget.miembroId));
    return Scaffold(
      appBar: AppBar(title: Text(widget.nombre == null ? tr('Logros') : '${tr('Logros')} · ${widget.nombre}')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(mensajeError(e)))),
        data: (l) {
          // Familias en orden, con sus 5 niveles
          final familias = <String, List<Logro>>{};
          for (final x in l.lista) {
            if (_cat != null && x.categoria != _cat) continue;
            familias.putIfAbsent(x.familia, () => []).add(x);
          }
          final cs = Theme.of(context).colorScheme;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(logrosProvider(widget.miembroId).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const Text('🏅', style: TextStyle(fontSize: 36)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(trf('{x} de {y} logros', {'x': l.conseguidos, 'y': l.total}),
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: l.total == 0 ? 0 : l.conseguidos / l.total, minHeight: 8,
                              borderRadius: BorderRadius.circular(4)),
                          const SizedBox(height: 6),
                          Tx('Bronce, Plata, Oro, Diamante y Leyenda. Los de humor son secretos hasta que los consigues.',
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: const Tx('Todos'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
                    ),
                    for (final c in categoriasLogros)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                            label: Text(tr(c.$2)), selected: _cat == c.$1, onSelected: (_) => setState(() => _cat = c.$1)),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                for (final f in familias.values) _Familia(niveles: f, colores: cs),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Familia extends StatelessWidget {
  const _Familia({required this.niveles, required this.colores});
  final List<Logro> niveles;
  final ColorScheme colores;

  @override
  Widget build(BuildContext context) {
    final hechos = niveles.where((x) => x.conseguido).length;
    final primero = niveles.first;
    final secreto = primero.oculto && hechos == 0;
    final siguiente = niveles.where((x) => !x.conseguido).firstOrNull;
    final valor = primero.valor;
    final desde = hechos == 0 ? 0.0 : niveles[hechos - 1].umbral;
    final progreso = siguiente == null
        ? 1.0
        : ((valor - desde) / (siguiente.umbral - desde)).clamp(0.0, 1.0).toDouble();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: secreto ? null : () => _detalle(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Text(secreto ? '❓' : primero.emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(secreto ? tr('Logro secreto') : primero.nombre,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  secreto
                      ? tr('Se desvela cuando lo consigues')
                      : siguiente == null
                          ? tr('¡Todos los niveles conseguidos!')
                          : '${siguiente.descripcion} · ${tr('llevas')} ${_num(valor)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                if (!secreto)
                  LinearProgressIndicator(value: progreso, minHeight: 5, borderRadius: BorderRadius.circular(3)),
              ]),
            ),
            const SizedBox(width: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (final n in niveles)
                Opacity(
                  opacity: n.conseguido ? 1 : 0.22,
                  child: Text(n.medalla, style: const TextStyle(fontSize: 16)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _detalle(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Row(children: [
            Text(niveles.first.emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(child: Text(niveles.first.nombre, style: Theme.of(context).textTheme.titleLarge)),
          ]),
          const SizedBox(height: 8),
          for (final n in niveles)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Opacity(opacity: n.conseguido ? 1 : 0.3, child: Text(n.medalla, style: const TextStyle(fontSize: 26))),
              title: Text('${n.nivelNombre} · ${n.descripcion}'),
              subtitle: Text(n.conseguido
                  ? '${trf('Conseguido el {x}', {'x': fechaCorta(n.conseguidoEn!)})} · ${trf('lo tiene el {x} % de la liga', {'x': n.pct})}'
                  : '${trf('Llevas {x}', {'x': _num(n.valor)})} · ${trf('lo tiene el {x} % de la liga', {'x': n.pct})}'),
              trailing: n.conseguido ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32)) : null,
            ),
        ]),
      ),
    );
  }
}
