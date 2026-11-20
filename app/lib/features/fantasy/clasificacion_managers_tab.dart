import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        if (lista.isEmpty) return const Vacio('Los puntos llegan al cerrar cada jornada. Prepara tu alineación antes del próximo partido.', titulo: 'Aún no hay puntos', icono: Icons.emoji_events_outlined);
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
  _DatosManager(this.ultima, this.alineados, this.plantilla);
  final PuntosManager? ultima;
  final List<Alineado> alineados;
  final List<({String jugadorId, double? clausula})> plantilla;
}

/// Plantilla (pública desde 0.2, por las cláusulas) y última jornada liquidada del mánager.
final _detalleProvider =
    FutureProvider.autoDispose.family<_DatosManager, LigaMiembro>((ref, k) async {
  final ultima = await FantasyRepo.ultimaJornada(k.ligaId, k.miembroId);
  final alineados = ultima == null ? <Alineado>[] : await FantasyRepo.alineacion(ultima.partidoId, k.miembroId);
  List<({String jugadorId, double? clausula})> plantilla;
  try {
    plantilla = await FantasyRepo.plantillaDe(k.ligaId, k.miembroId);
  } catch (_) {
    plantilla = const [];
  }
  return _DatosManager(ultima, alineados, plantilla);
});

/// Detalle de un mánager: su plantilla (con acceso a la ficha de mercado de cada jugador)
/// y el desglose de su última jornada.
class _DetalleManager extends ConsumerWidget {
  const _DetalleManager({required this.mi, required this.managerId});
  final MiLiga mi;
  final String managerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(_detalleProvider((ligaId: mi.liga.id, miembroId: managerId)));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final mercado = ref.watch(mercadoProvider(mi.liga.id)).valueOrNull ?? const <JugadorMercado>[];
    final precio = {for (final j in mercado) j.miembroId: j.precio};
    final t = Theme.of(context).textTheme;
    final nombres = {for (final e in miembros.entries) e.key: e.value.nombre};

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, scroll) => datos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e),
        data: (d) {
          // Desglose del backend (rol, bonus, ×1,5, cedidos) o, si falta, el de la alineación.
          final lineas = (d.ultima?.desglose.isNotEmpty ?? false)
              ? d.ultima!.desglose
              : [
                  for (final a in d.alineados)
                    LineaDesglose(
                      jugadorId: a.jugadorId,
                      rol: a.rol,
                      puntos: 0,
                      bonusRol: a.bonusRol ?? 0,
                      multiplicador: a.multiplicador,
                      total: 0,
                    ),
                ];
          return ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
            Text(miembros[managerId]?.nombre ?? 'Mánager', style: t.titleLarge),
            const SizedBox(height: 12),
            Text('Plantilla', style: t.titleMedium),
            if (d.plantilla.isEmpty) const Text('Sin jugadores.'),
            for (final f in d.plantilla)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: AvatarMiembro(miembros[f.jugadorId], radio: 16),
                title: Text(miembros[f.jugadorId]?.nombre ?? '…'),
                subtitle: Text('Cláusula ${millones(_clausula(f.clausula, precio[f.jugadorId]))}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  router.push('/fantasy/jugador/${f.jugadorId}');
                },
              ),
            const Divider(height: 24),
            Text(
              d.ultima == null
                  ? 'Sin jornadas liquidadas'
                  : 'Última jornada: ${DesgloseManager.fmt(d.ultima!.puntos)} puntos',
              style: t.titleMedium,
            ),
            const SizedBox(height: 4),
            if (lineas.isNotEmpty) DesgloseManager(lineas: lineas, nombres: nombres),
          ]);
        },
      ),
    );
  }

  /// La cláusula efectiva nunca es menor que el valor de mercado.
  static double? _clausula(double? guardada, double? precio) {
    if (guardada == null) return precio;
    if (precio == null) return guardada;
    return guardada > precio ? guardada : precio;
  }
}
