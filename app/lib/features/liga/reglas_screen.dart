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
          _Reglas(ligaId: ligaId, porPosicion: mi.liga.puntuarPorPosicion),
          _Aspectos(ligaId: ligaId),
        ]),
      ),
    );
  }
}

class _Reglas extends ConsumerWidget {
  const _Reglas({required this.ligaId, required this.porPosicion});
  final String ligaId;
  final bool porPosicion;

  /// Reglas que no aplican según el modo de la liga se muestran atenuadas.
  bool _aplica(String clave) =>
      porPosicion ? clave != 'gol' : !clave.startsWith('gol_') || clave == 'goles_encajados_3';

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
      data: (lista) => ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(porPosicion
              ? 'La liga puntúa los goles según la posición del jugador.'
              : 'La liga puntúa todos los goles igual (regla "Gol").'),
        ),
        for (final r in lista)
          ListTile(
            enabled: _aplica(r.clave),
            title: Text(nombreRegla(r.clave)),
            subtitle: r.posicion == null ? null : Text(etiquetaPosicion(r.posicion)),
            trailing: Text(
              '${r.puntos > 0 ? '+' : ''}${r.puntos % 1 == 0 ? r.puntos.toInt() : r.puntos}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            onTap: () => _editar(context, ref, r),
          ),
      ]),
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
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Aspectos que los compañeros valoran del 1 al 10 tras cada partido. '
                'A los porteros se les valora "Portería" en lugar de "Ataque".'),
          ),
          for (final a in lista)
            SwitchListTile(
              title: Text(a.nombre),
              subtitle: Text(a.clave),
              value: a.activo,
              onChanged: (v) async {
                await ejecutar(
                  context,
                  () => LigasRepo.guardarAspecto(ligaId, Aspecto(clave: a.clave, nombre: a.nombre, orden: a.orden, activo: v, aplicaA: a.aplicaA)),
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
