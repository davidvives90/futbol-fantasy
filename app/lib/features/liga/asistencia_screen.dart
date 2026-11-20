import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/avatar.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/reglamento_repo.dart';

final historialAsistenciaProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, ligaId) => ReglamentoRepo.historial(ligaId),
);
final ausenciasMiembroProvider = FutureProvider.autoDispose.family<List<Ausencia>, String>(
  (ref, miembroId) => ReglamentoRepo.ausenciasDe(miembroId),
);

final bajasLigaProvider = FutureProvider.autoDispose.family<List<Ausencia>, String>(
  (ref, ligaId) => ReglamentoRepo.bajasLiga(ligaId),
);

final _dia = DateFormat('d MMM', 'es');
String textoBaja(Ausencia a) =>
    '${motivosAusencia[a.motivo] ?? a.motivo} · ${a.hasta == null ? 'desde el ${_dia.format(a.desde)}, sin fecha de vuelta' : 'del ${_dia.format(a.desde)} al ${_dia.format(a.hasta!)}'}';

/// Historial de asistencia (últimos 12 partidos) y bajas temporales (lesión, viaje…).
class AsistenciaScreen extends ConsumerWidget {
  const AsistenciaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final datos = ref.watch(historialAsistenciaProvider(mi.liga.id));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Tx('Asistencia y bajas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => registrarBaja(context, ref, mi),
        icon: const Icon(Icons.event_busy_outlined),
        label: Text(mi.soyAdmin ? 'Registrar baja' : 'Me voy a ausentar'),
      ),
      body: datos.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(historialAsistenciaProvider(mi.liga.id))),
        data: (h) {
          final partidos = [for (final p in (h['partidos'] as List)) DateTime.parse((p as Map)['fecha'] as String).toLocal()];
          final filas = [for (final x in (h['miembros'] as List)) Map<String, dynamic>.from(x as Map)];
          final bajas = [
            for (final f in filas)
              if (f['baja'] != null) (miembroId: f['miembro_id'] as String, a: Ausencia(Map<String, dynamic>.from(f['baja'] as Map))),
          ];
          return RefreshIndicator(
            onRefresh: () => ref.refresh(historialAsistenciaProvider(mi.liga.id).future),
            child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              if (bajas.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Tx('De baja', style: t.titleMedium)),
                for (final b in bajas)
                  ListTile(
                    leading: AvatarMiembro(miembros[b.miembroId], radio: 18),
                    title: Text(miembros[b.miembroId]?.nombre ?? '…'),
                    subtitle: Text([textoBaja(b.a), if (!b.a.actual) 'próximamente', if (b.a.nota != null) b.a.nota!].join(' · ')),
                    trailing: (mi.soyAdmin || b.miembroId == mi.yo.id) && b.a.actual
                        ? TextButton(
                            onPressed: () async {
                              final ok = await ejecutar(context, () => ReglamentoRepo.terminarAusencia(b.a.id),
                                  ok: '¡Bienvenido de vuelta!');
                              if (ok) ref.invalidate(historialAsistenciaProvider(mi.liga.id));
                            },
                            child: const Tx('Ha vuelto'),
                          )
                        : null,
                    onTap: () => _detalle(context, ref, mi, b.miembroId),
                  ),
                const Divider(),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Últimos ${partidos.length} partidos', style: t.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(spacing: 12, runSpacing: 4, children: [
                  for (final e in _leyenda.entries)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      _Punto(e.key, cs),
                      const SizedBox(width: 4),
                      Text(e.value, style: t.bodySmall),
                    ]),
                ]),
              ),
              if (partidos.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('Aún no se ha jugado ningún partido.')),
              for (final f in filas)
                InkWell(
                  onTap: () => _detalle(context, ref, mi, f['miembro_id'] as String),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(children: [
                      AvatarMiembro(miembros[f['miembro_id']], radio: 14),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 96,
                        child: Text(miembros[f['miembro_id']]?.nombre ?? '…', overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        child: Wrap(spacing: 3, runSpacing: 3, children: [
                          for (final e in (f['estados'] as List)) _Punto(e as String?, cs),
                        ]),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(f['pct'] == null ? '—' : '${f['pct']} %', textAlign: TextAlign.end, style: t.labelLarge),
                      ),
                    ]),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('El % no cuenta los partidos en los que estaba de baja. Del más reciente (izquierda) al más antiguo.',
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ]),
          );
        },
      ),
    );
  }

  void _detalle(BuildContext context, WidgetRef ref, MiLiga mi, String miembroId) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _DetalleBajas(miembroId: miembroId, mi: mi),
    );
  }
}

const _leyenda = {'J': 'Jugó', 'D': 'Dijo que no', 'N': 'No se apuntó', 'B': 'De baja', null: 'Aún no estaba'};

class _Punto extends StatelessWidget {
  const _Punto(this.e, this.cs);
  final String? e;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final (color, borde) = switch (e) {
      'J' => (Colors.green.shade600, null),
      'D' => (cs.error.withValues(alpha: 0.75), null),
      'N' => (cs.surfaceContainerHighest, cs.outline),
      'B' => (Colors.amber.shade600, null),
      _ => (Colors.transparent, cs.outlineVariant),
    };
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: borde == null ? null : Border.all(color: borde),
      ),
      child: e == 'B' ? const Icon(Icons.healing, size: 9, color: Colors.white) : null,
    );
  }
}

class _DetalleBajas extends ConsumerWidget {
  const _DetalleBajas({required this.miembroId, required this.mi});
  final String miembroId;
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(miembrosPorIdProvider(mi.liga.id))[miembroId];
    final bajas = ref.watch(ausenciasMiembroProvider(miembroId));
    final puedo = mi.soyAdmin || miembroId == mi.yo.id;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AvatarMiembro(m, radio: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(m?.nombre ?? '…', style: Theme.of(context).textTheme.titleLarge)),
          ]),
          const SizedBox(height: 8),
          Tx('Bajas', style: Theme.of(context).textTheme.labelLarge),
          ...bajas.when(
            loading: () => [const Padding(padding: EdgeInsets.all(16), child: Cargando())],
            error: (e, _) => [ErrorVista(e)],
            data: (l) => l.isEmpty
                ? [const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Tx('Ninguna registrada.'))]
                : [
                    for (final a in l)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(a.actual ? Icons.healing : Icons.history),
                        title: Text(textoBaja(a)),
                        subtitle: a.nota == null ? null : Text(a.nota!),
                        trailing: puedo
                            ? IconButton(
                                tooltip: 'Borrar',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await ejecutar(context, () => ReglamentoRepo.borrarAusencia(a.id));
                                  if (ok) {
                                    ref.invalidate(ausenciasMiembroProvider(miembroId));
                                    ref.invalidate(historialAsistenciaProvider(mi.liga.id));
                                  }
                                },
                              )
                            : null,
                      ),
                  ],
          ),
          if (puedo)
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await registrarBaja(context, ref, mi, miembroId: miembroId);
              },
              icon: const Icon(Icons.add),
              label: const Tx('Añadir baja'),
            ),
        ]),
      ),
    );
  }
}

/// Registrar una baja temporal. Un jugador, la suya; el admin, la de cualquiera.
Future<void> registrarBaja(BuildContext context, WidgetRef ref, MiLiga mi, {String? miembroId}) async {
  final todos = (ref.read(miembrosProvider(mi.liga.id)).valueOrNull ?? const <Miembro>[])
      .where((m) => m.estado == EstadoMiembro.activo)
      .toList()
    ..sort((a, b) => a.nombre.compareTo(b.nombre));
  var quien = miembroId ?? mi.yo.id;
  final hoy = DateTime.now();
  var desde = DateTime(hoy.year, hoy.month, hoy.day);
  DateTime? hasta = desde.add(const Duration(days: 30));
  var motivo = 'lesion';
  final nota = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<DateTime?> elegir(DateTime inicial, DateTime primera) => showDatePicker(
              context: ctx,
              initialDate: inicial.isBefore(primera) ? primera : inicial,
              firstDate: primera,
              lastDate: DateTime(hoy.year + 2),
            );
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Tx('Baja temporal', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Mientras dure no recibe avisos de convocatoria, no ocupa plaza de fijo y esos partidos no le cuentan como faltas.'),
              const SizedBox(height: 12),
              if (mi.soyAdmin)
                DropdownButtonFormField<String>(
                  value: quien,
                  decoration: const InputDecoration(labelText: 'Jugador'),
                  items: [for (final m in todos) DropdownMenuItem(value: m.id, child: Text(m.nombre))],
                  onChanged: (v) => setState(() => quien = v ?? quien),
                ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final e in motivosAusencia.entries)
                  ChoiceChip(label: Text(e.value), selected: motivo == e.key, onSelected: (_) => setState(() => motivo = e.key)),
              ]),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Tx('Desde'),
                trailing: Text(_dia.format(desde)),
                onTap: () async {
                  final d = await elegir(desde, DateTime(hoy.year - 1));
                  if (d != null) setState(() => desde = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available),
                title: const Tx('Vuelve'),
                trailing: Text(hasta == null ? 'No se sabe' : 'después del ${_dia.format(hasta!)}'),
                onTap: () async {
                  final d = await elegir(hasta ?? desde, desde);
                  if (d != null) setState(() => hasta = d);
                },
              ),
              Wrap(spacing: 6, children: [
                for (final s in const [7, 30, 90])
                  ActionChip(
                    label: Text(s == 7 ? '1 semana' : (s == 30 ? '1 mes' : '3 meses')),
                    onPressed: () => setState(() => hasta = desde.add(Duration(days: s))),
                  ),
                ActionChip(label: const Tx('Sin fecha'), onPressed: () => setState(() => hasta = null)),
              ]),
              TextField(controller: nota, maxLength: 200, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
              FilledButton(
                onPressed: () async {
                  final r = await ejecutar(
                    ctx,
                    () => ReglamentoRepo.registrarAusencia(quien, desde, hasta, motivo, nota.text.trim()),
                    ok: 'Baja registrada',
                  );
                  if (r && ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Tx('Guardar'),
              ),
            ]),
          ),
        );
      },
    ),
  );
  if (ok == true) {
    ref.invalidate(bajasLigaProvider(mi.liga.id));
    ref.invalidate(historialAsistenciaProvider(mi.liga.id));
    ref.invalidate(ausenciasMiembroProvider(quien));
  }
}
