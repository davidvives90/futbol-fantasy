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

/// Encuesta de valoración: 6 rankings (calidad, velocidad, resistencia, defensa, regate, portería).
/// En una mini-encuesta se parte del orden actual de la liga y solo hay que colocar al jugador nuevo.
class EncuestaScreen extends ConsumerStatefulWidget {
  const EncuestaScreen({super.key, required this.encuestaId});
  final String encuestaId;

  @override
  ConsumerState<EncuestaScreen> createState() => _EncuestaScreenState();
}

class _EncuestaScreenState extends ConsumerState<EncuestaScreen> {
  int _paso = 0;
  bool _cargando = true;
  bool _enviando = false;
  Encuesta? _encuesta;
  Set<Atributo> _hechos = {};

  /// Orden en edición por atributo (ids de miembro, del mejor al peor).
  final Map<Atributo, List<String>> _orden = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final mi = ref.read(ligaActualProvider);
    if (mi == null) return;
    try {
      final abiertas = await FantasyRepo.encuestasAbiertas(mi.liga.id);
      final e = abiertas.where((x) => x.id == widget.encuestaId).firstOrNull;
      final miembros = await ref.read(miembrosProvider(mi.liga.id).future);
      final jugadores = miembros
          .where((m) => m.estado == EstadoMiembro.activo || m.estado == EstadoMiembro.pendiente_registro)
          .toList()
        ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      final ids = [for (final m in jugadores) m.id];
      final hechos = await FantasyRepo.atributosEnviados(widget.encuestaId, mi.yo.id);

      if (e?.esMini ?? false) {
        // Orden actual de la liga por atributo; el jugador nuevo, en medio.
        final vals = {for (final v in await FantasyRepo.valoraciones(mi.liga.id)) v.miembroId: v};
        for (final a in Atributo.values) {
          final resto = ids.where((id) => id != e!.sujetoId).toList()
            ..sort((x, y) => (vals[y]?.atributos[a] ?? 50).compareTo(vals[x]?.atributos[a] ?? 50));
          resto.insert(resto.length ~/ 2, e!.sujetoId!);
          _orden[a] = resto;
        }
      } else {
        for (final a in Atributo.values) {
          _orden[a] = [...ids];
        }
      }
      if (!mounted) return;
      final primero = Atributo.values.indexWhere((a) => !hechos.contains(a));
      setState(() {
        _encuesta = e;
        _hechos = hechos;
        _paso = primero < 0 ? 0 : primero;
        _cargando = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _cargando = false);
      mostrarError(context, err);
    }
  }

  Future<void> _enviar(MiLiga mi) async {
    final a = Atributo.values[_paso];
    setState(() => _enviando = true);
    final ok = await ejecutar(context, () => FantasyRepo.enviarRanking(widget.encuestaId, a, _orden[a]!));
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) _hechos = {..._hechos, a};
    });
    if (!ok) return;
    if (_paso < Atributo.values.length - 1) {
      // El siguiente ranking parte del orden que acabas de enviar si aún no lo has tocado.
      final sig = Atributo.values[_paso + 1];
      if (!_hechos.contains(sig) && !(_encuesta?.esMini ?? false)) _orden[sig] = [..._orden[a]!];
      setState(() => _paso++);
    } else {
      ref.invalidate(encuestasPendientesProvider((ligaId: mi.liga.id, miembroId: mi.yo.id)));
      ref.invalidate(encuestasAbiertasProvider(mi.liga.id));
      mostrarOk(context, '¡Gracias! Encuesta completada');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null || _cargando) return const Scaffold(body: Cargando());
    if (_encuesta == null) {
      return Scaffold(appBar: AppBar(), body: const Vacio('Esta encuesta ya está cerrada.'));
    }
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final a = Atributo.values[_paso];
    final orden = _orden[a]!;
    final cs = Theme.of(context).colorScheme;
    final sujeto = _encuesta!.sujetoId;

    return Scaffold(
      appBar: AppBar(title: Text('${_paso + 1}/6 · ${a.etiqueta}')),
      body: Column(children: [
        LinearProgressIndicator(value: _hechos.length / Atributo.values.length),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(a.pregunta, style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            sujeto != null
                ? 'Arrastra a ${miembros[sujeto]?.nombre ?? 'el jugador nuevo'} hasta el puesto donde lo pondrías.'
                : 'Arrastra para ordenar: arriba el mejor. Tu nota sobre ti mismo no cuenta.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
            itemCount: orden.length,
            onReorder: (de, a2) => setState(() {
              final hasta = a2 > de ? a2 - 1 : a2;
              final id = orden.removeAt(de);
              orden.insert(hasta, id);
            }),
            itemBuilder: (_, i) {
              final id = orden[i];
              final destacado = id == sujeto;
              return Card(
                key: ValueKey(id),
                color: destacado ? cs.tertiaryContainer : null,
                child: ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(miembros[id]?.nombre ?? '…'),
                  subtitle: id == mi.yo.id ? const Text('Tú') : null,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    AvatarMiembro(miembros[id], radio: 14),
                    const SizedBox(width: 8),
                    ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (_paso > 0)
              TextButton(onPressed: () => setState(() => _paso--), child: const Text('Anterior')),
            const Spacer(),
            if (_hechos.contains(a)) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.check)),
            FilledButton(
              onPressed: _enviando ? null : () => _enviar(mi),
              child: Text(_paso == Atributo.values.length - 1 ? 'Enviar y terminar' : 'Enviar y seguir'),
            ),
          ]),
        ),
      ),
    );
  }
}
