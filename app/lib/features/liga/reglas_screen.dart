import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

final _reglasProvider = FutureProvider.autoDispose.family<List<Regla>, String>((ref, ligaId) => LigasRepo.reglas(ligaId));
final _aspectosProvider = FutureProvider.autoDispose.family<List<Aspecto>, String>((ref, ligaId) => LigasRepo.aspectos(ligaId));

/// Ajustes de puntuación (admin): puntos de cada regla y aspectos de valoración.
class ReglasScreen extends ConsumerWidget {
  const ReglasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final ligaId = mi.liga.id;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Puntuación'),
          bottom: const TabBar(tabs: [Tab(text: 'Reglas'), Tab(text: 'Aspectos')]),
        ),
        body: TabBarView(children: [
          _Reglas(ligaId: ligaId, bonusRoles: mi.liga.fantasy.bonusRoles),
          _Aspectos(ligaId: ligaId),
        ]),
      ),
    );
  }
}

class _Reglas extends ConsumerWidget {
  const _Reglas({required this.ligaId, required this.bonusRoles});
  final String ligaId;

  /// Si es false, las reglas rol_* se muestran atenuadas (el rol de la alineación es solo estético).
  final bool bonusRoles;

  Future<void> _editar(BuildContext context, WidgetRef ref, Regla r) async {
    final ctrl = TextEditingController(text: r.puntos.toString());
    final nuevo = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(nombreRegla(r.clave)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(labelText: 'Puntos', helperText: 'Puede ser negativo'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text.replaceAll(',', '.'))),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nuevo == null || !context.mounted) return;
    await ejecutar(context, () => LigasRepo.guardarRegla(ligaId, r.clave, nuevo));
    ref.invalidate(_reglasProvider(ligaId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reglas = ref.watch(_reglasProvider(ligaId));
    return reglas.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(_reglasProvider(ligaId))),
      data: (lista) {
        final vigentes = lista.where((r) => !reglaObsoleta(r.clave) && r.posicion == null).toList();
        final partido = vigentes.where((r) => !r.clave.startsWith('rol_')).toList();
        final roles = vigentes.where((r) => r.clave.startsWith('rol_')).toList();
        Widget fila(Regla r, {bool enabled = true}) => ListTile(
              enabled: enabled,
              title: Text(nombreRegla(r.clave)),
              trailing: Text(
                '${r.puntos > 0 ? '+' : ''}${r.puntos % 1 == 0 ? r.puntos.toInt() : r.puntos}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () => _editar(context, ref, r),
            );
        return ListView(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Puntos del partido real: iguales para todos, sin importar la posición '
                '(en la liga se rota en la portería).'),
          ),
          for (final r in partido) fila(r),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(bonusRoles
                ? 'Bonus de rol en la alineación Fantasy: solo los suma el mánager que pone a ese jugador en ese rol.'
                : 'Bonus de rol desactivados en Ajustes Fantasy: el rol de la alineación es solo estético.'),
          ),
          for (final r in roles) fila(r, enabled: bonusRoles),
        ]);
      },
    );
  }
}

class _Aspectos extends ConsumerWidget {
  const _Aspectos({required this.ligaId});
  final String ligaId;

  Future<void> _nuevo(BuildContext context, WidgetRef ref, int orden) async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nuevo aspecto'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Añadir')),
        ],
      ),
    );
    ctrl.dispose();
    if (nombre == null || nombre.isEmpty || !context.mounted) return;
    final clave = nombre
        .toLowerCase()
        .replaceAll(RegExp('[áà]'), 'a')
        .replaceAll(RegExp('[éè]'), 'e')
        .replaceAll(RegExp('[íì]'), 'i')
        .replaceAll(RegExp('[óò]'), 'o')
        .replaceAll(RegExp('[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp('[^a-z0-9]+'), '_');
    await ejecutar(context, () => LigasRepo.guardarAspecto(ligaId, Aspecto(clave: clave, nombre: nombre, orden: orden, activo: true)));
    ref.invalidate(_aspectosProvider(ligaId));
    ref.invalidate(aspectosActivosProvider(ligaId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aspectos = ref.watch(_aspectosProvider(ligaId));
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Añadir aspecto',
        onPressed: () => _nuevo(context, ref, (aspectos.valueOrNull?.length ?? 0) + 1),
        child: const Icon(Icons.add),
      ),
      body: aspectos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(_aspectosProvider(ligaId))),
        data: (lista) => ListView(children: [
          const _ModoValoracion(),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Aspectos: en modo rápido son los chips de «Destacó en…»; en modo detallado se puntúan '
                'del 1 al 10. Se aplican a todos los jugadores por igual, porque no hay posiciones fijas.'),
          ),
          for (final a in lista.where((a) => a.clave != 'general'))
            SwitchListTile(
              title: Text(a.nombre),
              subtitle: Text(a.clave),
              value: a.activo,
              onChanged: (v) async {
                await ejecutar(
                  context,
                  () => LigasRepo.guardarAspecto(ligaId, Aspecto(clave: a.clave, nombre: a.nombre, orden: a.orden, activo: v, aplicaA: 'todos')),
                );
                ref.invalidate(_aspectosProvider(ligaId));
                ref.invalidate(aspectosActivosProvider(ligaId));
              },
            ),
        ]),
      ),
    );
  }
}


/// v0.3b: rápida (una nota general por compañero + destacados) o detallada (nota por aspecto).
class _ModoValoracion extends ConsumerWidget {
  const _ModoValoracion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const SizedBox.shrink();
    final detallada = mi.liga.valoracionDetallada;
    return SwitchListTile(
      title: const Text('Valoración detallada'),
      subtitle: Text(detallada
          ? 'Cada compañero se puntúa del 1 al 10 en cada aspecto (más lento).'
          : 'Rápida: una nota general por compañero (6 = normal), «Destacó en…» y voto MVP. ~1 minuto.'),
      value: detallada,
      onChanged: mi.soyAdmin
          ? (v) async {
              final ok = await ejecutar(
                context,
                () => LigasRepo.actualizarLiga(mi.liga.id, {'modo_valoracion': v ? 'detallada' : 'rapida'}),
                ok: v ? 'Valoración detallada activada' : 'Valoración rápida activada',
              );
              if (ok) ref.invalidate(misLigasProvider);
            }
          : null,
    );
  }
}
