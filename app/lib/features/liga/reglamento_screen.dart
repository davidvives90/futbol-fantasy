import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/reglamento_repo.dart';
import 'votaciones_screen.dart';

final reglamentoProvider = FutureProvider.autoDispose.family<List<ReglaJuego>, String>(
  (ref, ligaId) => ReglamentoRepo.reglamento(ligaId),
);

const _grupos = {'partido': 'El partido', 'juego': 'Reglas de juego', 'convivencia': 'Convivencia'};

/// Reglamento de la liga: modalidad + reglas estandarizadas. Todos lo ven; el admin lo cambia
/// directamente o lo somete a votación.
class ReglamentoScreen extends ConsumerWidget {
  const ReglamentoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final reglas = ref.watch(reglamentoProvider(mi.liga.id));
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Tx('Reglamento')),
      body: reglas.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(reglamentoProvider(mi.liga.id))),
        data: (lista) => RefreshIndicator(
          onRefresh: () => ref.refresh(reglamentoProvider(mi.liga.id).future),
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Tx('Modalidad', style: t.labelLarge),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                for (final e in nombresModalidad.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(tr(e.value)),
                      selected: mi.liga.modalidad == e.key,
                      onSelected: !mi.soyAdmin || mi.liga.modalidad == e.key
                          ? null
                          : (_) async {
                              if (!await confirmar(context, 'Cambiar a ${e.value}',
                                  'Las reglas pasan a las estándar de ${e.value}. Se conservan las que hayáis cambiado y existan en esa modalidad.',
                                  accion: 'Cambiar')) {
                                return;
                              }
                              if (!context.mounted) return;
                              final ok = await ejecutar(context, () => ReglamentoRepo.cambiarModalidad(mi.liga.id, e.key));
                              if (ok) {
                                refrescarLigas(ref);
                                ref.invalidate(reglamentoProvider(mi.liga.id));
                              }
                            },
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '${mi.liga.jugadoresPorEquipo} por equipo · ${mi.liga.numEquipos} equipos. '
                '${mi.soyAdmin ? 'Toca una regla para cambiarla o someterla a votación.' : 'Lo marcado con • lo ha decidido la liga; el resto es lo estándar de la modalidad.'}',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            for (final g in _grupos.entries)
              if (lista.any((r) => r.grupo == g.key)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text(tr(g.value).toUpperCase(),
                      style: t.labelMedium?.copyWith(letterSpacing: 1, color: cs.onSurfaceVariant)),
                ),
                for (final r in lista.where((r) => r.grupo == g.key))
                  ListTile(
                    title: Text(r.titulo),
                    subtitle: r.descripcion == null ? null : Text(r.descripcion!),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (r.personalizada) Text('• ', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(r.textoValor,
                            textAlign: TextAlign.end, style: t.titleSmall?.copyWith(color: cs.primary)),
                      ),
                    ]),
                    onTap: mi.soyAdmin ? () => _editar(context, ref, mi, r) : null,
                  ),
              ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () => context.push('/guia'),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Tx('Otras normas acordadas (texto libre)'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _editar(BuildContext context, WidgetRef ref, MiLiga mi, ReglaJuego r) async {
    dynamic valor = r.valor;
    final accion = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(r.titulo, style: Theme.of(ctx).textTheme.titleLarge),
              if (r.descripcion != null) Text(r.descripcion!),
              const SizedBox(height: 12),
              if (r.tipo == 'si_no')
                SegmentedButton<bool>(
                  segments: const [ButtonSegment(value: true, label: Tx('Sí')), ButtonSegment(value: false, label: Tx('No'))],
                  selected: {valor == true},
                  onSelectionChanged: (s) => setState(() => valor = s.first),
                )
              else if (r.tipo == 'opcion')
                for (final o in r.opciones)
                  RadioListTile<String>(
                    value: o.valor,
                    groupValue: valor as String?,
                    title: Text(o.texto),
                    onChanged: (v) => setState(() => valor = v),
                  )
              else
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton.filledTonal(
                    onPressed: (valor as num) > r.minimo ? () => setState(() => valor = (valor as num).toInt() - 1) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(r.texto(valor), textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.titleLarge),
                  ),
                  IconButton.filledTonal(
                    onPressed: (valor as num) < r.maximo ? () => setState(() => valor = (valor as num).toInt() + 1) : null,
                    icon: const Icon(Icons.add),
                  ),
                ]),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'guardar'), child: const Tx('Guardar cambio')),
              if (r.tipo != 'numero')
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'votar'),
                  icon: const Icon(Icons.how_to_vote_outlined),
                  label: const Tx('Mejor, que vote la liga'),
                ),
              if (r.personalizada)
                TextButton(onPressed: () => Navigator.pop(ctx, 'estandar'), child: const Tx('Volver al valor estándar')),
            ]),
          ),
        ),
      ),
    );
    if (accion == null || !context.mounted) return;
    if (accion == 'votar') {
      await nuevaVotacion(context, ref, mi, regla: r);
      return;
    }
    final ok = await ejecutar(
      context,
      () => ReglamentoRepo.cambiarRegla(mi.liga.id, r.clave, accion == 'estandar' ? null : valor),
      ok: 'Reglamento actualizado',
    );
    if (ok) ref.invalidate(reglamentoProvider(mi.liga.id));
  }
}
