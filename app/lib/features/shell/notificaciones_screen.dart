import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/liga_activa.dart';
import '../../core/utils.dart';
import '../../data/providers.dart';
import '../../data/repos/notificaciones_repo.dart';

final notificacionesProvider =
    StreamProvider.autoDispose<List<Notificacion>>((ref) {
  ref.watch(authStateProvider); // se renueva al iniciar o cerrar sesión
  return NotificacionesRepo.stream();
});

final noLeidasProvider = Provider.autoDispose<int>(
  (ref) => (ref.watch(notificacionesProvider).valueOrNull ?? const []).where((n) => !n.leida).length,
);

/// Campana de la barra superior con el número de avisos sin leer.
class CampanaAvisos extends ConsumerWidget {
  const CampanaAvisos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(noLeidasProvider);
    return IconButton(
      tooltip: tr('Avisos'),
      onPressed: () => context.push('/avisos'),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text(n > 9 ? '9+' : '$n'),
        child: Icon(n > 0 ? Icons.notifications : Icons.notifications_none),
      ),
    );
  }
}

IconData _icono(String tipo) => switch (tipo) {
      'post_partido' || 'recordatorio_votar' => Icons.how_to_vote_outlined,
      'puntos' => Icons.emoji_events_outlined,
      'oferta' || 'oferta_respuesta' || 'clausula' => Icons.handshake_outlined,
      'recordatorio_alineacion' => Icons.shield_outlined,
      'cancelado' => Icons.event_busy_outlined,
      'cambio_hora' => Icons.schedule,
      'disputas' => Icons.report_outlined,
      _ => Icons.sports_soccer,
    };

class NotificacionesScreen extends ConsumerWidget {
  const NotificacionesScreen({super.key});

  Future<void> _abrir(BuildContext context, WidgetRef ref, Notificacion n) async {
    if (!n.leida) NotificacionesRepo.marcarLeidas([n.id]).ignore();
    if (n.ligaId != null) await ref.read(ligaActivaIdProvider.notifier).elegir(n.ligaId);
    if (!context.mounted || n.ruta == null || n.ruta!.isEmpty) return;
    context.go(n.ruta!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(notificacionesProvider);
    final hayNoLeidas = ref.watch(noLeidasProvider) > 0;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Tx('Avisos'),
        actions: [
          if (hayNoLeidas)
            TextButton(
              onPressed: () => ejecutar(context, () => NotificacionesRepo.marcarLeidas()),
              child: const Tx('Marcar todo leído'),
            ),
        ],
      ),
      body: lista.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(notificacionesProvider)),
        data: (l) => l.isEmpty
            ? const Vacio('Aquí verás convocatorias, post-partidos, ofertas y recordatorios.',
                icono: Icons.notifications_none)
            : ListView.separated(
                itemCount: l.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final n = l[i];
                  return ListTile(
                    tileColor: n.leida ? null : cs.primaryContainer.withValues(alpha: 0.35),
                    leading: Icon(_icono(n.tipo), color: n.leida ? cs.onSurfaceVariant : cs.primary),
                    title: Text(n.titulo, style: TextStyle(fontWeight: n.leida ? FontWeight.w500 : FontWeight.w800)),
                    subtitle: Text('${n.cuerpo}\n${fechaHora(n.creadoEn)}'),
                    isThreeLine: true,
                    onTap: () => _abrir(context, ref, n),
                  );
                },
              ),
      ),
    );
  }
}
