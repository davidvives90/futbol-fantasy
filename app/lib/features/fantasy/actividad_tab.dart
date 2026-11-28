import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/guias.dart';
import '../../core/idioma.dart';
import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../shell/sincronizacion.dart';

/// 0063: registro público y cronológico de los movimientos del mercado de la liga.
final actividadProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, ligaId) async {
  ref.watch(latidoProvider('liga:$ligaId:fantasy')); // en vivo
  final r = await sb.rpc('actividad_fantasy', params: {'p_liga': ligaId, 'p_limite': 100});
  return [for (final x in (r as List)) Map<String, dynamic>.from(x as Map)];
});

class ActividadTab extends ConsumerWidget {
  const ActividadTab({super.key, required this.mi});
  final MiLiga mi;

  static String _m(num v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1).replaceAll('.', ',')} M';

  static (IconData, Color, String) _linea(Map<String, dynamic> x) {
    final m = '${x['manager'] ?? '…'}', j = '${x['jugador'] ?? '…'}', i = _m((x['importe'] as num?) ?? 0);
    return switch (x['tipo']) {
      'compra' => (Icons.shopping_cart_outlined, Colors.green.shade700, trf('{m} ficha a {j} por {i}', {'m': m, 'j': j, 'i': i})),
      'venta' => (Icons.sell_outlined, Colors.red.shade700, trf('{m} vende a {j} por {i}', {'m': m, 'j': j, 'i': i})),
      'clausula_pagada' => (Icons.flash_on, Colors.deepOrange,
          x['otro'] == null
              ? trf('{m} paga la cláusula de {j} ({i})', {'m': m, 'j': j, 'i': i})
              : trf('{m} paga la cláusula de {j} ({i}) y se lo quita a {o}', {'m': m, 'j': j, 'i': i, 'o': x['otro']})),
      'subasta' => (Icons.gavel, Colors.indigo, trf('{m} gana la subasta de {j} por {i}', {'m': m, 'j': j, 'i': i})),
      'subasta_venta' => (Icons.gavel, Colors.indigo, trf('{m} vende a {j} en subasta por {i}', {'m': m, 'j': j, 'i': i})),
      'oferta_pagada' => (Icons.handshake_outlined, Colors.teal, trf('{m} compra a {j} a otro mánager por {i}', {'m': m, 'j': j, 'i': i})),
      'cesion_pagada' => (Icons.swap_horiz, Colors.purple, trf('{m} se lleva cedido a {j} esta jornada ({i})', {'m': m, 'j': j, 'i': i})),
      'draft' => (Icons.format_list_numbered, Colors.blueGrey, trf('{m} elige a {j} en el draft', {'m': m, 'j': j})),
      _ => (Icons.circle_outlined, Colors.grey, '$m · $j'),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(actividadProvider(mi.liga.id));
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(actividadProvider(mi.liga.id).future),
      child: datos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(actividadProvider(mi.liga.id))),
        data: (l) => ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          const ConsejoUnaVez('fantasy_actividad', 'El registro de la liga: quién fichó, vendió, pagó una cláusula o cedió a quién, y por cuánto.'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Icon(Icons.visibility_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Tx('Todos los movimientos del mercado son públicos para la liga.', style: t.bodySmall)),
            ]),
          ),
          if (l.isEmpty)
            const Vacio('Cuando alguien fiche, venda o pague una cláusula, saldrá aquí.',
                titulo: 'Aún no hay movimientos', icono: Icons.history),
          for (final x in l)
            () {
              final (icono, color, texto) = _linea(x);
              final f = DateTime.parse(x['creado_en'] as String).toLocal();
              return ListTile(
                leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icono, color: color, size: 20)),
                title: Text(texto),
                subtitle: Text(fechaCorta(f)),
              );
            }(),
        ]),
      ),
    );
  }
}
