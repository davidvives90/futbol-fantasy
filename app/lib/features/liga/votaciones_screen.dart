import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/avatar.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/reglamento_repo.dart';
import 'reglamento_screen.dart';

final votacionesProvider = FutureProvider.autoDispose.family<List<Votacion>, String>(
  (ref, ligaId) => ReglamentoRepo.votaciones(ligaId),
);
final resultadoVotacionProvider = FutureProvider.autoDispose.family<ResultadoVotacion, String>(
  (ref, id) => ReglamentoRepo.resultados(id),
);

/// Votaciones de la liga: las crea el admin (preguntas libres o cambios del reglamento) y votan todos.
class VotacionesScreen extends ConsumerWidget {
  const VotacionesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final lista = ref.watch(votacionesProvider(mi.liga.id));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Votaciones')),
      floatingActionButton: mi.soyAdmin
          ? FloatingActionButton.extended(
              onPressed: () => nuevaVotacion(context, ref, mi),
              icon: const Icon(Icons.add),
              label: const Text('Nueva votación'),
            )
          : null,
      body: lista.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(votacionesProvider(mi.liga.id))),
        data: (vs) {
          if (vs.isEmpty) {
            return Vacio(
              mi.soyAdmin
                  ? 'Pregunta a la liga lo que quieras o somete a votación un cambio del reglamento.'
                  : 'Cuando el administrador abra una votación, aparecerá aquí.',
              icono: Icons.how_to_vote_outlined,
              titulo: 'Sin votaciones',
            );
          }
          final abiertas = vs.where((v) => v.abierta).toList();
          final cerradas = vs.where((v) => !v.abierta).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(votacionesProvider(mi.liga.id)),
            child: ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 96), children: [
              if (abiertas.isNotEmpty)
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Abiertas', style: t.titleMedium)),
              for (final v in abiertas) _TarjetaVotacion(v: v, mi: mi),
              if (cerradas.isNotEmpty)
                Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Cerradas', style: t.titleMedium)),
              for (final v in cerradas) _TarjetaVotacion(v: v, mi: mi),
            ]),
          );
        },
      ),
    );
  }
}

class _TarjetaVotacion extends ConsumerWidget {
  const _TarjetaVotacion({required this.v, required this.mi});
  final Votacion v;
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final res = ref.watch(resultadoVotacionProvider(v.id)).valueOrNull;
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final abierta = v.abierta;
    // Mientras está abierta, los resultados se ven después de votar (para no condicionar)
    final verResultados = !abierta || res?.miVoto != null;

    Future<void> votar(int i) async {
      final ok = await ejecutar(context, () => ReglamentoRepo.votar(v.id, i), ok: 'Voto guardado');
      if (ok) ref.invalidate(resultadoVotacionProvider(v.id));
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(v.titulo, style: t.titleMedium)),
            if (mi.soyAdmin && abierta)
              PopupMenuButton<String>(
                onSelected: (a) async {
                  final cancelar = a == 'cancelar';
                  if (!await confirmar(context, cancelar ? 'Cancelar votación' : 'Cerrar ya',
                      cancelar ? 'Se anula sin resultado.' : 'Se cierra ahora con los votos que hay${v.reglaClave != null ? ' y, si gana una opción, se aplica al reglamento' : ''}.',
                      accion: cancelar ? 'Cancelar votación' : 'Cerrar',
                      tipo: cancelar ? TipoConfirmacion.peligro : TipoConfirmacion.normal)) {
                    return;
                  }
                  if (!context.mounted) return;
                  final ok = await ejecutar(context, () => ReglamentoRepo.cerrar(v.id, cancelar: cancelar));
                  if (ok) {
                    ref.invalidate(votacionesProvider(mi.liga.id));
                    ref.invalidate(reglamentoProvider(mi.liga.id));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'cerrar', child: Text('Cerrar ya')),
                  PopupMenuItem(value: 'cancelar', child: Text('Cancelar votación')),
                ],
              ),
          ]),
          if (v.descripcion != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(v.descripcion!)),
          const SizedBox(height: 4),
          Text(
            [
              if (v.reglaClave != null) 'Cambia el reglamento',
              v.anonima ? 'Anónima' : 'Voto público',
              abierta ? 'Cierra ${fechaHora(v.cierraEn)}' : (v.estado == 'cerrada' ? 'Cerrada' : 'Cancelada'),
              if (res != null) '${res.total} de ${res.censo} han votado',
            ].join(' · '),
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < v.opciones.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 8),
              child: _Opcion(
                texto: v.opciones[i],
                elegida: res?.miVoto == i,
                ganadora: !abierta && v.ganadora == i,
                pct: verResultados && res != null && res.total > 0 ? res.votos(i) / res.total : null,
                votos: verResultados ? res?.votos(i) : null,
                quien: verResultados && !v.anonima && res != null
                    ? [for (final id in res.quien(i)) miembros[id]]
                    : const [],
                onTap: abierta ? () => votar(i) : null,
              ),
            ),
          if (!abierta && v.estado == 'cerrada')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                v.ganadora == null
                    ? 'Sin ganadora (empate o sin votos): no cambia nada.'
                    : v.aplicada
                        ? 'Ganó «${v.opciones[v.ganadora!]}» y ya está en el reglamento.'
                        : 'Ganó «${v.opciones[v.ganadora!]}».',
                style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({required this.texto, required this.elegida, required this.ganadora, this.pct, this.votos,
      this.quien = const [], this.onTap});
  final String texto;
  final bool elegida, ganadora;
  final double? pct;
  final int? votos;
  final List<Miembro?> quien;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borde = elegida || ganadora ? cs.primary : cs.outlineVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: borde, width: elegida ? 2 : 1), borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          if (pct != null)
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct!.clamp(0.0, 1.0),
                child: ColoredBox(color: cs.primary.withValues(alpha: ganadora ? 0.22 : 0.10)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(elegida ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20, color: elegida ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: Text(texto, style: TextStyle(fontWeight: ganadora ? FontWeight.w700 : null))),
              if (quien.isNotEmpty) PilaAvatares(quien.whereType<Miembro>().toList(), radio: 10, max: 4),
              if (votos != null) ...[
                const SizedBox(width: 8),
                Text('$votos${pct != null ? ' · ${(pct! * 100).round()} %' : ''}'),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Formulario de nueva votación (admin). Con [regla], las opciones salen de los valores posibles de la regla.
Future<void> nuevaVotacion(BuildContext context, WidgetRef ref, MiLiga mi, {ReglaJuego? regla}) async {
  final titulo = TextEditingController(text: regla == null ? '' : '¿Cómo jugamos: ${regla.titulo.toLowerCase()}?');
  final descripcion = TextEditingController(
      text: regla == null ? '' : 'Ahora: ${regla.textoValor}. La opción ganadora pasará al reglamento.');
  final opciones = regla == null
      ? [TextEditingController(text: 'Sí'), TextEditingController(text: 'No')]
      : <TextEditingController>[];
  var horas = 48;
  var anonima = true;
  final creada = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(regla == null ? 'Nueva votación' : 'Votar: ${regla.titulo}', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: titulo, maxLength: 140, decoration: const InputDecoration(labelText: 'Pregunta')),
            TextField(controller: descripcion, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Detalle (opcional)')),
            const SizedBox(height: 12),
            Text('Opciones', style: Theme.of(ctx).textTheme.labelLarge),
            if (regla != null)
              for (final v in regla.valoresPosibles)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.radio_button_unchecked, size: 18),
                  title: Text(regla.texto(v)),
                  trailing: v == regla.valor ? const Text('actual') : null,
                )
            else ...[
              for (var i = 0; i < opciones.length; i++)
                Row(children: [
                  Expanded(child: TextField(controller: opciones[i], decoration: InputDecoration(hintText: 'Opción ${i + 1}'))),
                  if (opciones.length > 2)
                    IconButton(onPressed: () => setState(() => opciones.removeAt(i)), icon: const Icon(Icons.close)),
                ]),
              if (opciones.length < 6)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => opciones.add(TextEditingController())),
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir opción'),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text('Duración', style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              for (final h in const [24, 48, 72, 168])
                ChoiceChip(
                  label: Text(h == 168 ? '1 semana' : (h == 24 ? '1 día' : '${h ~/ 24} días')),
                  selected: horas == h,
                  onSelected: (_) => setState(() => horas = h),
                ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Voto anónimo'),
              subtitle: Text(anonima ? 'Solo se ve el recuento' : 'Se ve quién votó qué'),
              value: anonima,
              onChanged: (v) => setState(() => anonima = v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                final ops = regla == null
                    ? [for (final c in opciones) c.text.trim()].where((s) => s.isNotEmpty).toList()
                    : [for (final v in regla.valoresPosibles) regla.texto(v)];
                if (titulo.text.trim().length < 3 || ops.length < 2) {
                  mostrarError(ctx, 'Escribe la pregunta y al menos dos opciones');
                  return;
                }
                final ok = await ejecutar(
                  ctx,
                  () => ReglamentoRepo.crearVotacion(
                    ligaId: mi.liga.id,
                    titulo: titulo.text.trim(),
                    descripcion: descripcion.text.trim(),
                    opciones: ops,
                    cierraEn: DateTime.now().add(Duration(hours: horas)),
                    reglaClave: regla?.clave,
                    reglaValores: regla?.valoresPosibles,
                    anonima: anonima,
                  ),
                );
                if (ok && ctx.mounted) Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.send),
              label: const Text('Abrir votación'),
            ),
          ]),
        ),
      ),
    ),
  );
  if (creada == true && context.mounted) {
    mostrarOk(context, 'Votación abierta: se ha avisado a la liga');
    ref.invalidate(votacionesProvider(mi.liga.id));
  }
}
