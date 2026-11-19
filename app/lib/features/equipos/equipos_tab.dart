import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../fantasy/fantasy_providers.dart';
import 'balanceo.dart';

/// Generador de equipos nivelados (admin) y vista de equipos (todos).
class EquiposTab extends ConsumerStatefulWidget {
  const EquiposTab({super.key, required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  @override
  ConsumerState<EquiposTab> createState() => _EquiposTabState();
}

class _EquiposTabState extends ConsumerState<EquiposTab> {
  final _rng = Random();
  List<Reparto> _opciones = [];
  int _opcion = 0;

  /// Equipos en edición (copia mutable del reparto elegido).
  List<List<JugadorBalanceo>>? _equipos;
  bool _guardando = false;

  int get _k => widget.partido.numEquipos;

  /// Construye los jugadores del algoritmo a partir de confirmados + rendimiento.
  /// [mercado]: rating R (0–100) del mercado Fantasy (encuesta + rendimiento). Si existe para un jugador
  /// tiene prioridad; si no, se usa la fórmula de rendimiento de `calcularRatings`.
  /// [porteria]: habilidad bajo palos 0–100 de la encuesta (vacío si no hay encuesta).
  List<JugadorBalanceo> _jugadores(List<Inscripcion> conf, Map<String, Miembro> miembros, List<Rendimiento> rend,
      Map<String, double> mercado, Map<String, double> porteria) {
    final porId = {for (final r in rend) r.miembroId: r};
    // Con encuesta cerrada, v_rating_balanceo da un rating 0–100 para todos: se usa para todos los
    // convocados (50 si faltara alguno) y no se mezcla con la fórmula normalizada de rendimiento.
    final ratings = mercado.isNotEmpty
        ? {for (final i in conf) i.miembroId: mercado[i.miembroId] ?? 50.0}
        : _ratingsRendimiento(conf, porId);
    return [
      for (final i in conf)
        JugadorBalanceo(
          id: i.miembroId,
          nombre: miembros[i.miembroId]?.nombre ?? '…',
          rating: ratings[i.miembroId] ?? 50,
          habilidadPortero: porteria[i.miembroId],
        ),
    ];
  }

  /// Sin mercado: fórmula de rendimiento normalizada a 0–100 entre los convocados.
  Map<String, double> _ratingsRendimiento(List<Inscripcion> conf, Map<String, Rendimiento> porId) {
    return calcularRatings({
      for (final i in conf)
        i.miembroId: () {
          final r = porId[i.miembroId];
          return MetricasJugador(
            partidos: r?.partidos ?? 0,
            puntosMedia: r?.puntosMedia,
            notaMedia: r?.notaMedia,
            golesPartido: r?.golesPartido,
          );
        }(),
    });
  }

  void _generar(List<JugadorBalanceo> js) {
    final opciones = balancear(js, _k, rng: _rng);
    final elegido = elegirConVariedad(opciones, rng: _rng);
    setState(() {
      _opciones = opciones;
      _opcion = opciones.indexOf(elegido);
      _equipos = [for (final e in elegido.equipos) [...e]];
    });
  }

  void _otraOpcion() {
    if (_opciones.length < 2) return;
    setState(() {
      _opcion = (_opcion + 1) % _opciones.length;
      _equipos = [for (final e in _opciones[_opcion].equipos) [...e]];
    });
  }

  void _mover(JugadorBalanceo j, int destino) {
    setState(() {
      for (final e in _equipos!) {
        e.removeWhere((x) => x.id == j.id);
      }
      _equipos![destino].add(j);
    });
  }

  Future<void> _confirmar() async {
    final equipos = _equipos;
    if (equipos == null) return;
    setState(() => _guardando = true);
    await ejecutar(
      context,
      () => PartidosRepo.guardarEquipos(widget.partido.id, Reparto(equipos, 0).asignacion,
          numEquipos: widget.partido.numEquipos),
      ok: 'Equipos confirmados',
    );
    if (mounted) setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(convocatoriaProvider(widget.partido.id)).valueOrNull;
    final miembros = ref.watch(miembrosPorIdProvider(widget.mi.liga.id));
    final rend = ref.watch(rendimientoProvider(widget.mi.liga.id));
    final mercado = ref.watch(ratingsMercadoProvider(widget.mi.liga.id));
    if (conv == null || rend.isLoading || mercado.isLoading) return const Cargando();

    final conf = conv.where((i) => i.estado == EstadoInscripcion.confirmado).toList();
    final porteria = ref.watch(habilidadPorteriaProvider(widget.mi.liga.id)).valueOrNull ?? const <String, double>{};
    final js = _jugadores(conf, miembros, rend.valueOrNull ?? const [], mercado.valueOrNull ?? const {}, porteria);
    final editable = widget.mi.soyAdmin && widget.partido.estado.antesDeJugar;

    // Equipos ya guardados en la base de datos.
    final guardados = <List<JugadorBalanceo>>[
      for (var e = 1; e <= _k; e++) [for (final j in js) if (conf.firstWhere((i) => i.miembroId == j.id).equipo == e) j],
    ];
    final hayGuardados = guardados.any((e) => e.isNotEmpty);
    final mostrar = _equipos ?? (hayGuardados ? guardados : null);

    if (conf.length < _k * 2) {
      return Vacio('Hacen falta al menos ${_k * 2} confirmados para hacer equipos (hay ${conf.length}).',
          icono: Icons.group_off);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (editable)
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => _generar(js),
            icon: const Icon(Icons.auto_awesome),
            label: Text(mostrar == null ? 'Generar equipos' : 'Volver a generar'),
          ),
          if (_opciones.length > 1)
            OutlinedButton.icon(onPressed: _otraOpcion, icon: const Icon(Icons.shuffle), label: const Text('Otra opción')),
        ]),
      if (mostrar == null)
        const Padding(
          padding: EdgeInsets.only(top: 32),
          child: Vacio('Aún no se han hecho los equipos.', icono: Icons.groups_2_outlined),
        )
      else ...[
        const SizedBox(height: 16),
        _BarraEquilibrio(equipos: mostrar),
        const SizedBox(height: 12),
        for (var e = 0; e < mostrar.length; e++)
          _TarjetaEquipo(
            numero: e + 1,
            jugadores: mostrar[e],
            numEquipos: mostrar.length,
            onMover: editable && _equipos != null ? _mover : null,
          ),
        if (editable && _equipos != null) ...[
          const SizedBox(height: 8),
          const Text('Toca un jugador para moverlo a otro equipo.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _guardando ? null : _confirmar, child: const Text('Confirmar equipos')),
        ],
        if (editable && _equipos == null && hayGuardados)
          TextButton(
            onPressed: () => setState(() => _equipos = [for (final e in guardados) [...e]]),
            child: const Text('Ajustar a mano'),
          ),
      ],
    ]);
  }
}

class _BarraEquilibrio extends StatelessWidget {
  const _BarraEquilibrio({required this.equipos});
  final List<List<JugadorBalanceo>> equipos;

  @override
  Widget build(BuildContext context) {
    final r = Reparto(equipos, costeReparto(equipos));
    final sumas = r.sumas;
    final total = sumas.fold<double>(0, (a, b) => a + b);
    final dif = r.diferenciaPct;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          for (var i = 0; i < sumas.length; i++)
            Expanded(
              flex: max(1, (1000 * (total == 0 ? 1 : sumas[i] / total)).round()),
              child: Container(height: 12, color: AppTheme.colorEquipo(i + 1)),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Text(
        '${[for (var i = 0; i < sumas.length; i++) 'E${i + 1} ${sumas[i].toStringAsFixed(0)}'].join(' · ')}'
        '  —  diferencia ${dif.toStringAsFixed(1)} %',
        style: TextStyle(color: dif < 5 ? Colors.green : (dif < 10 ? Colors.orange : Colors.red)),
      ),
    ]);
  }
}

class _TarjetaEquipo extends StatelessWidget {
  const _TarjetaEquipo({required this.numero, required this.jugadores, required this.numEquipos, this.onMover});
  final int numero, numEquipos;
  final List<JugadorBalanceo> jugadores;
  final void Function(JugadorBalanceo, int destino)? onMover;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.colorEquipo(numero);
    final ordenados = [...jugadores]..sort((a, b) => b.rating.compareTo(a.rating));
    return Card(
      shape: RoundedRectangleBorder(side: BorderSide(color: color, width: 2), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Equipo $numero (${jugadores.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
          ),
          for (final j in ordenados)
            ListTile(
              dense: true,
              leading: Icon(Icons.person, color: color),
              title: Text(j.nombre),
              trailing: Text(j.rating.toStringAsFixed(0)),
              onTap: onMover == null
                  ? null
                  : () async {
                      final destino = await showDialog<int>(
                        context: context,
                        builder: (c) => SimpleDialog(
                          title: Text('Mover a ${j.nombre}'),
                          children: [
                            for (var e = 0; e < numEquipos; e++)
                              if (e != numero - 1)
                                SimpleDialogOption(
                                  onPressed: () => Navigator.pop(c, e),
                                  child: Text('Equipo ${e + 1}'),
                                ),
                          ],
                        ),
                      );
                      if (destino != null) onMover!(j, destino);
                    },
            ),
        ]),
      ),
    );
  }
}
