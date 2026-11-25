import 'package:flutter/material.dart';
import '../../core/idioma.dart';
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
          title: const Tx('Puntuación'),
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
          decoration:  InputDecoration(labelText: tr('Puntos'), helperText: tr('Puede ser negativo')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Tx('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text.replaceAll(',', '.'))),
            child: const Tx('Guardar'),
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
        title: const Tx('Nuevo aspecto'),
        content: TextField(controller: ctrl, autofocus: true, decoration:  InputDecoration(labelText: tr('Nombre'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Tx('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Tx('Añadir')),
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
        tooltip: tr('Añadir aspecto'),
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
                'del 1 al 5. Se aplican a todos los jugadores por igual, porque no hay posiciones fijas.'),
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


/// Cómo se vota tras el partido: podio Top 3 (0053), notas del 1 al 5 o detallada por aspectos.
class _ModoValoracion extends ConsumerWidget {
  const _ModoValoracion();

  Future<void> _cambiar(BuildContext context, WidgetRef ref, MiLiga mi, String modo) async {
    final ok = await ejecutar(context, () => LigasRepo.actualizarLiga(mi.liga.id, {'modo_valoracion': modo}),
        ok: tr('Votación cambiada'));
    if (ok) ref.invalidate(misLigasProvider);
  }

  Future<void> _puntos(BuildContext context, WidgetRef ref, MiLiga mi) async {
    final c = [for (final p in mi.liga.puntosPodio) TextEditingController(text: '$p')];
    final r = await showDialog<List<int>>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Tx('Puntos del podio'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            TextField(
              controller: c[i],
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: ['🥇 1.º', '🥈 2.º', '🥉 3.º'][i]),
            ),
          const SizedBox(height: 8),
          const Tx('Son puntos de votación y también puntos Fantasy según el puesto final. Máximo 20.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Tx('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(d, [for (final x in c) int.tryParse(x.text.trim()) ?? -1]),
            child: const Tx('Guardar'),
          ),
        ],
      ),
    );
    if (r == null || !context.mounted) return;
    if (r.any((x) => x < 0 || x > 20) || r[0] < r[1] || r[1] < r[2]) {
      mostrarError(context, tr('Pon números de 0 a 20, de mayor a menor.'));
      return;
    }
    final ok = await ejecutar(context, () => LigasRepo.actualizarLiga(mi.liga.id, {'puntos_podio': r}), ok: tr('Guardado'));
    if (ok) ref.invalidate(misLigasProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const SizedBox.shrink();
    final modo = mi.liga.modoValoracion == 'detallada' && !mi.liga.valoracionAvanzada ? 'rapida' : mi.liga.modoValoracion;
    final opciones = [
      ('podio', 'Podio Top 3 (recomendado)', 'Cada uno elige a los 3 mejores por orden. Rápido: 3 toques.'),
      ('rapida', 'Notas del 1 al 5', 'Una nota a cada compañero (3 = normal) y estrella MVP.'),
      if (mi.liga.valoracionAvanzada) ('detallada', 'Detallada por aspectos', 'Nota del 1 al 5 en cada aspecto (más lento).'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const ListTile(title: Tx('Votación tras el partido')),
      for (final (valor, titulo, texto) in opciones)
        RadioListTile<String>(
          value: valor,
          groupValue: modo,
          title: Tx(titulo),
          subtitle: Tx(texto),
          onChanged: mi.soyAdmin && valor != modo ? (v) => _cambiar(context, ref, mi, v!) : null,
        ),
      if (modo == 'podio')
        ListTile(
          leading: const Icon(Icons.emoji_events_outlined),
          title: const Tx('Puntos del podio'),
          subtitle: Text('🥇 ${mi.liga.puntosPodio[0]} · 🥈 ${mi.liga.puntosPodio[1]} · 🥉 ${mi.liga.puntosPodio[2]}'),
          trailing: mi.soyAdmin ? const Icon(Icons.edit_outlined) : null,
          onTap: mi.soyAdmin ? () => _puntos(context, ref, mi) : null,
        ),
    ]);
  }
}
