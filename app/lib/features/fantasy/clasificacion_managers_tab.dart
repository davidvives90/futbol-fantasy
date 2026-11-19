import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';
import 'fantasy_providers.dart';
import 'widgets_fantasy.dart';

/// Clasificación de mánagers (v_clasificacion_managers).
class ClasificacionManagersTab extends ConsumerWidget {
  const ClasificacionManagersTab({super.key, required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clas = ref.watch(clasificacionManagersProvider(mi.liga.id));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final t = Theme.of(context).textTheme;

    return clas.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(clasificacionManagersProvider(mi.liga.id))),
      data: (lista) {
        if (lista.isEmpty) return const Vacio('Aún no hay mánagers con puntos.', icono: Icons.emoji_events_outlined);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(clasificacionManagersProvider(mi.liga.id).future),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: lista.length,
            itemBuilder: (_, i) {
              final c = lista[i];
              final m = miembros[c.managerId];
              final yo = c.managerId == mi.yo.id;
              return ListTile(
                selected: yo,
                leading: CircleAvatar(child: Text('${c.posicion ?? i + 1}')),
                title: Text(m?.nombre ?? '…'),
                subtitle: Text([
                  if (c.puntosUltima != null) 'última jornada ${c.puntosUltima!.toStringAsFixed(0)}',
                  if (c.valorPlantilla != null) 'plantilla ${millones(c.valorPlantilla)}',
                ].join(' · ')),
                trailing: Text(c.puntos.toStringAsFixed(c.puntos % 1 == 0 ? 0 : 1), style: t.titleLarge),
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => _DetalleManager(mi: mi, managerId: c.managerId),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DatosManager {
  _DatosManager(this.ultima, this.alineados);
  final PuntosManager? ultima;
  final List<Alineado> alineados;
}

/// Las plantillas ajenas son privadas (RLS); solo se ve la alineación de la última jornada liquidada,
/// que ya es pública porque pasó su hora de cierre.
final _detalleProvider =
    FutureProvider.autoDispose.family<_DatosManager, LigaMiembro>((ref, k) async {
  final ultima = await FantasyRepo.ultimaJornada(k.ligaId, k.miembroId);
  final alineados = ultima == null ? <Alineado>[] : await FantasyRepo.alineacion(ultima.partidoId, k.miembroId);
  return _DatosManager(ultima, alineados);
});

/// Alineación de la última jornada de otro mánager (su plantilla es privada).
class _DetalleManager extends ConsumerWidget {
  const _DetalleManager({required this.mi, required this.managerId});
  final MiLiga mi;
  final String managerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(_detalleProvider((ligaId: mi.liga.id, miembroId: managerId)));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final t = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, scroll) => datos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e),
        data: (d) => ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
          Text(miembros[managerId]?.nombre ?? 'Mánager', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('La plantilla de cada mánager es privada; aquí ves su última alineación.', style: t.bodySmall),
          const SizedBox(height: 12),
          Text(
            d.ultima == null
                ? 'Sin jornadas liquidadas'
                : 'Última jornada: ${d.ultima!.puntos.toStringAsFixed(0)} puntos',
            style: t.titleMedium,
          ),
          for (final a in d.alineados)
            ListTile(
              dense: true,
              leading: AvatarMiembro(miembros[a.jugadorId], radio: 16),
              title: Text(miembros[a.jugadorId]?.nombre ?? '…'),
              trailing: a.multiplicador != 1 ? InsigniaNoHabitual(bonus: a.multiplicador, corta: true) : null,
            ),
        ]),
      ),
    );
  }
}
