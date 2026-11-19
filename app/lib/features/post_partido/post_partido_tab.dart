import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../../data/repos/post_partido_repo.dart';

final _yaEnviadoProvider = FutureProvider.autoDispose.family<bool, (String, String)>(
  (ref, k) => PostPartidoRepo.yaEnviado(k.$1, k.$2),
);

/// Encuentros que definió el admin (quién contra quién); cada asistente solo pone el marcador.
final _encuentrosDefProvider = FutureProvider.autoDispose.family<List<Encuentro>, String>(
  (ref, partidoId) => PartidosRepo.encuentros(partidoId),
);

final _numReportesProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, partidoId) => PostPartidoRepo.numReportes(partidoId),
);

/// Asistente post-partido en 3 pasos: resultado, estadísticas y valoraciones.
/// Cada asistente envía su "parte"; el servidor cruza todos los partes
/// (consolidar_acta) y marca como disputa lo que no cuadre.
class PostPartidoTab extends ConsumerStatefulWidget {
  const PostPartidoTab({super.key, required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  @override
  ConsumerState<PostPartidoTab> createState() => _PostPartidoTabState();
}

class _PostPartidoTabState extends ConsumerState<PostPartidoTab> {
  int _paso = 0;
  bool _editando = false;
  bool _enviando = false;

  List<ReporteEncuentro>? _encuentros;
  final _jugadores = <String, ReporteJugador>{};

  /// votadoId → aspecto → nota. Si un votado no está, no se le valora.
  final _notas = <String, Map<String, int>>{};
  final _sinValorar = <String>{};

  void _inicializar(
    List<Encuentro> definidos,
    List<Inscripcion> asistentes,
    List<Aspecto> aspectos,
    Map<String, Miembro> miembros,
  ) {
    if (_encuentros != null) return;
    _encuentros = [
      for (final e in definidos) ReporteEncuentro(n: e.n, equipoLocal: e.equipoLocal, equipoVisitante: e.equipoVisitante),
    ];
    for (final a in asistentes) {
      _jugadores[a.miembroId] = ReporteJugador(a.miembroId);
      if (a.miembroId != widget.mi.yo.id) {
        final portero = miembros[a.miembroId]?.esPortero ?? false;
        _notas[a.miembroId] = {for (final asp in _aspectosPara(aspectos, portero)) asp.clave: 6};
      }
    }
  }

  /// Según `aspectos_valoracion.aplica_a` (p. ej. a los porteros se les valora "portería" en vez de "ataque").
  List<Aspecto> _aspectosPara(List<Aspecto> aspectos, bool portero) =>
      aspectos.where((a) => a.aplicaAJugador(portero: portero)).toList();

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final ok = await ejecutar(
      context,
      () => PostPartidoRepo.enviar(
        partidoId: widget.partido.id,
        reporteroId: widget.mi.yo.id,
        encuentros: _encuentros!,
        jugadores: _jugadores.values.toList(),
        valoraciones: {
          for (final e in _notas.entries)
            if (!_sinValorar.contains(e.key)) e.key: e.value,
        },
      ),
      ok: '¡Gracias! Tu parte se cruzará con el del resto',
    );
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) _editando = false;
    });
    if (ok) {
      ref.invalidate(_yaEnviadoProvider((widget.partido.id, widget.mi.yo.id)));
      ref.invalidate(_numReportesProvider(widget.partido.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.partido;
    final conv = ref.watch(convocatoriaProvider(p.id)).valueOrNull;
    final miembros = ref.watch(miembrosPorIdProvider(widget.mi.liga.id));
    final aspectos = ref.watch(aspectosActivosProvider(widget.mi.liga.id));
    final yaEnviado = ref.watch(_yaEnviadoProvider((p.id, widget.mi.yo.id)));
    final numReportes = ref.watch(_numReportesProvider(p.id)).valueOrNull;
    final definidos = ref.watch(_encuentrosDefProvider(p.id));

    if (conv == null || aspectos.isLoading || yaEnviado.isLoading || definidos.isLoading) return const Cargando();
    // Envían parte y se valoran los que jugaron: confirmados con equipo asignado.
    final asistentes = conv.where((i) => i.estado == EstadoInscripcion.confirmado && i.equipo != null).toList();
    final asisto = asistentes.any((i) => i.miembroId == widget.mi.yo.id);

    if (!asisto) {
      return Vacio(
        'Solo los que jugaron envían el parte del partido.'
        '${numReportes == null ? '' : '\nPartes recibidos: $numReportes de ${asistentes.length}.'}',
        icono: Icons.lock_outline,
      );
    }
    if (p.estado != EstadoPartido.post_partido) {
      return Vacio(
        p.estado == EstadoPartido.jugado
            ? 'El administrador aún no ha abierto el post-partido.'
            : 'El plazo para enviar partes ha terminado. El administrador está revisando el acta.',
        icono: Icons.hourglass_bottom,
      );
    }
    if ((yaEnviado.valueOrNull ?? false) && !_editando) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.check_circle, size: 64, color: Colors.green),
        const SizedBox(height: 12),
        const Text('Has enviado tu parte del partido.', textAlign: TextAlign.center),
        if (numReportes != null)
          Text('Partes recibidos: $numReportes de ${asistentes.length}', textAlign: TextAlign.center),
        if (p.votacionCierra != null)
          Text('Plazo hasta: ${fechaHora(p.votacionCierra!)}', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: () => setState(() => _editando = true), child: const Text('Corregir mi parte')),
      ]);
    }

    final listaAspectos = aspectos.valueOrNull ?? const <Aspecto>[];
    _inicializar(definidos.valueOrNull ?? const <Encuentro>[], asistentes, listaAspectos, miembros);

    return Stepper(
      currentStep: _paso,
      onStepTapped: (i) => setState(() => _paso = i),
      onStepCancel: _paso == 0 ? null : () => setState(() => _paso--),
      onStepContinue: _enviando
          ? null
          : () {
              if (_paso < 2) {
                setState(() => _paso++);
              } else {
                _enviar();
              }
            },
      controlsBuilder: (context, details) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          FilledButton(onPressed: details.onStepContinue, child: Text(_paso == 2 ? 'Enviar parte' : 'Siguiente')),
          const SizedBox(width: 8),
          if (details.onStepCancel != null) TextButton(onPressed: details.onStepCancel, child: const Text('Atrás')),
        ]),
      ),
      steps: [
        Step(
          title: const Text('Resultado'),
          subtitle: const Text('Lo que recuerdes; se cruza con el resto'),
          isActive: _paso >= 0,
          content: _PasoResultado(encuentros: _encuentros!, numEquipos: p.numEquipos, onCambio: () => setState(() {})),
        ),
        Step(
          title: const Text('Goles y asistencias'),
          subtitle: const Text('Marca "No sé" si no te fijaste'),
          isActive: _paso >= 1,
          content: Column(children: [
            for (final a in asistentes)
              _FilaEstadisticas(
                reporte: _jugadores[a.miembroId]!,
                miembro: miembros[a.miembroId],
                equipo: a.equipo,
                soyYo: a.miembroId == widget.mi.yo.id,
                onCambio: () => setState(() {}),
              ),
          ]),
        ),
        Step(
          title: const Text('Valora a tus compañeros'),
          subtitle: const Text('Del 1 al 10, anónimo'),
          isActive: _paso >= 2,
          content: Column(children: [
            for (final a in asistentes.where((a) => a.miembroId != widget.mi.yo.id))
              _TarjetaValoracion(
                nombre: miembros[a.miembroId]?.nombre ?? '…',
                aspectos: _aspectosPara(listaAspectos, miembros[a.miembroId]?.esPortero ?? false),
                notas: _notas[a.miembroId]!,
                omitido: _sinValorar.contains(a.miembroId),
                onOmitir: (v) => setState(() => v ? _sinValorar.add(a.miembroId) : _sinValorar.remove(a.miembroId)),
                onCambio: () => setState(() {}),
              ),
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Contador extends StatelessWidget {
  const _Contador({required this.valor, required this.onCambio, this.etiqueta, this.habilitado = true});
  final int valor;
  final ValueChanged<int> onCambio;
  final String? etiqueta;
  final bool habilitado;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (etiqueta != null) Text(etiqueta!),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: habilitado && valor > 0 ? () => onCambio(valor - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(width: 24, child: Text('$valor', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: habilitado && valor < 99 ? () => onCambio(valor + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]);
}

class _PasoResultado extends StatelessWidget {
  const _PasoResultado({required this.encuentros, required this.numEquipos, required this.onCambio});
  final List<ReporteEncuentro> encuentros;
  final int numEquipos;
  final VoidCallback onCambio;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (encuentros.isEmpty)
        const Text('El administrador aún no ha definido los encuentros de este partido.'),
      if (numEquipos > 2)
        const Text('Pon el marcador de cada minipartido que recuerdes.'),
      for (final e in encuentros)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              if (encuentros.length > 1) Text('Encuentro #${e.n}', style: Theme.of(context).textTheme.labelLarge),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                Column(children: [
                  Text('Equipo ${e.equipoLocal}', style: TextStyle(color: AppTheme.colorEquipo(e.equipoLocal))),
                  _Contador(valor: e.golesLocal, onCambio: (v) {
                    e.golesLocal = v;
                    onCambio();
                  }),
                ]),
                const Text('—'),
                Column(children: [
                  Text('Equipo ${e.equipoVisitante}', style: TextStyle(color: AppTheme.colorEquipo(e.equipoVisitante))),
                  _Contador(valor: e.golesVisitante, onCambio: (v) {
                    e.golesVisitante = v;
                    onCambio();
                  }),
                ]),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

class _FilaEstadisticas extends StatelessWidget {
  const _FilaEstadisticas({
    required this.reporte,
    required this.miembro,
    required this.equipo,
    required this.soyYo,
    required this.onCambio,
  });
  final ReporteJugador reporte;
  final Miembro? miembro;
  final int? equipo;
  final bool soyYo;
  final VoidCallback onCambio;

  @override
  Widget build(BuildContext context) {
    final r = reporte;
    final portero = miembro?.esPortero ?? false;
    final activo = !r.noSe;
    void set(void Function() f) {
      f();
      onCambio();
    }

    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: equipo == null ? null : AppTheme.colorEquipo(equipo!),
          foregroundColor: Colors.white,
          child: Text(miembro?.inicial ?? '?'),
        ),
        title: Text('${miembro?.nombre ?? '…'}${soyYo ? ' (tú)' : ''}'),
        subtitle: Text(r.noSe ? 'No sé' : '${r.goles} goles · ${r.asistencias} asist.'),
        children: [
          CheckboxListTile(
            title: const Text('No sé / no me fijé'),
            value: r.noSe,
            onChanged: (v) => set(() => r.noSe = v ?? false),
          ),
          _filaContador('Goles', r.goles, activo, (v) => set(() => r.goles = v)),
          _filaContador('Asistencias', r.asistencias, activo, (v) => set(() => r.asistencias = v)),
          _filaContador('Autogoles', r.autogoles, activo, (v) => set(() => r.autogoles = v)),
          _filaContador('Penaltis fallados', r.penaltisFallados, activo, (v) => set(() => r.penaltisFallados = v)),
          // La portería a cero no se pregunta: se deduce del resultado consolidado.
          if (portero) ...[
            _filaContador('Paradas clave', r.paradasClave, activo, (v) => set(() => r.paradasClave = v)),
            _filaContador('Penaltis parados', r.penaltisParados, activo, (v) => set(() => r.penaltisParados = v)),
          ],
        ],
      ),
    );
  }

  Widget _filaContador(String etiqueta, int valor, bool activo, ValueChanged<int> alCambiar) => ListTile(
        dense: true,
        title: Text(etiqueta),
        trailing: _Contador(valor: valor, habilitado: activo, onCambio: alCambiar),
      );
}

class _TarjetaValoracion extends StatelessWidget {
  const _TarjetaValoracion({
    required this.nombre,
    required this.aspectos,
    required this.notas,
    required this.omitido,
    required this.onOmitir,
    required this.onCambio,
  });
  final String nombre;
  final List<Aspecto> aspectos;
  final Map<String, int> notas;
  final bool omitido;
  final ValueChanged<bool> onOmitir;
  final VoidCallback onCambio;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(nombre, style: Theme.of(context).textTheme.titleMedium)),
            FilterChip(label: const Text('No le vi'), selected: omitido, onSelected: onOmitir),
          ]),
          if (!omitido)
            for (final a in aspectos)
              Row(children: [
                SizedBox(width: 110, child: Text(a.nombre)),
                Expanded(
                  child: Slider(
                    value: (notas[a.clave] ?? 6).toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '${notas[a.clave] ?? 6}',
                    onChanged: (v) {
                      notas[a.clave] = v.round();
                      onCambio();
                    },
                  ),
                ),
                SizedBox(width: 24, child: Text('${notas[a.clave] ?? 6}', textAlign: TextAlign.end)),
              ]),
        ]),
      ),
    );
  }
}
