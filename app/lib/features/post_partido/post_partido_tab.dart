import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../../data/repos/post_partido_repo.dart';

/// Encuentros que definió el admin (quién contra quién); cada asistente solo pone el marcador.
final _encuentrosDefProvider = FutureProvider.autoDispose.family<List<Encuentro>, String>(
  (ref, partidoId) => PartidosRepo.encuentros(partidoId),
);

final _numReportesProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, partidoId) => PostPartidoRepo.numReportes(partidoId),
);

/// Lo que ya envié (vacío si nada): sirve para saber si ya envié y para precargar al corregir.
final _miEnvioProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, partidoId) => PostPartidoRepo.miPostPartido(partidoId),
);

/// Borrador del post-partido (vive mientras la app esté abierta, aunque cambies de pestaña).
class _Borrador {
  final encuentros = <ReporteEncuentro>[];
  final goles = <String, int>{};
  final asistencias = <String, int>{};
  final autogoles = <String, int>{};
  final paradas = <String, int>{};
  final penParados = <String, int>{};
  final penFallados = <String, int>{};

  /// Equipos en los que el usuario no se fijó: no se envían sus datos ni se exige cuadre.
  final noMeFije = <int>{};
  bool masDatos = false;

  /// Nota general (modo rápido): 6 = normal.
  final notas = <String, int>{};

  /// Notas por aspecto (modo detallado).
  final aspectos = <String, Map<String, int>>{};
  final destacados = <String, Set<String>>{};
  final sinValorar = <String>{};
  final abiertos = <String>{};
  String? mvp;
}

final _borradores = <String, _Borrador>{};

/// Post-partido en UNA pantalla (v0.3b, objetivo < 1 minuto):
/// 1. Resultado · 2. Quién marcó y asistió (tocar suma) · 3. Una nota por compañero (6 por defecto) + «Mi MVP».
/// Todo se envía de una vez con `enviar_post_partido`; el servidor cruza los partes de todos.
class PostPartidoTab extends ConsumerStatefulWidget {
  const PostPartidoTab({super.key, required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  @override
  ConsumerState<PostPartidoTab> createState() => _PostPartidoTabState();
}

class _PostPartidoTabState extends ConsumerState<PostPartidoTab> {
  bool _editando = false;
  bool _enviando = false;
  final _equipoDe = <String, int>{};

  String get _clave => '${widget.partido.id}/${widget.mi.yo.id}';
  _Borrador? get _b => _borradores[_clave];

  void _inicializar(List<Encuentro> definidos, List<Inscripcion> asistentes, Map<String, dynamic> previo) {
    for (final a in asistentes) {
      if (a.equipo != null) _equipoDe[a.miembroId] = a.equipo!;
    }
    if (_b != null) return;
    final b = _Borrador();
    final res = {for (final r in (previo['resultados'] as List? ?? const [])) toInt((r as Map)['n']): r};
    for (final e in definidos) {
      final r = res[e.n];
      b.encuentros.add(ReporteEncuentro(
        n: e.n,
        equipoLocal: e.equipoLocal,
        equipoVisitante: e.equipoVisitante,
        golesLocal: r == null ? 0 : toInt(r['goles_local']),
        golesVisitante: r == null ? 0 : toInt(r['goles_visitante']),
      ));
    }
    final jug = {for (final j in (previo['jugadores'] as List? ?? const [])) (j as Map)['sujeto_id'] as String: j};
    for (final a in asistentes) {
      final j = jug[a.miembroId];
      if (j == null) continue;
      if (j['goles'] != null) b.goles[a.miembroId] = toInt(j['goles']);
      if (j['asistencias'] != null) b.asistencias[a.miembroId] = toInt(j['asistencias']);
      if (j['autogoles'] != null) b.autogoles[a.miembroId] = toInt(j['autogoles']);
      for (final (campo, mapa) in [
        ('paradas_clave', b.paradas),
        ('penaltis_parados', b.penParados),
        ('penaltis_fallados', b.penFallados),
      ]) {
        if (j[campo] != null) {
          mapa[a.miembroId] = toInt(j[campo]);
          b.masDatos = true;
        }
      }
    }
    // Si ya envié y un equipo no tiene ninguna fila, es que marqué «No me fijé».
    if (jug.isNotEmpty) {
      for (final eq in asistentes.map((a) => a.equipo).whereType<int>().toSet()) {
        if (!asistentes.any((a) => a.equipo == eq && jug.containsKey(a.miembroId))) b.noMeFije.add(eq);
      }
    }
    final notasPrevias = {for (final n in (previo['notas'] as List? ?? const [])) (n as Map)['votado_id'] as String: n};
    for (final a in asistentes.where((a) => a.miembroId != widget.mi.yo.id)) {
      final n = notasPrevias[a.miembroId];
      b.notas[a.miembroId] = n?['nota'] == null ? 6 : toInt(n!['nota']);
      b.aspectos[a.miembroId] = {
        for (final e in ((n?['aspectos'] as Map?) ?? const {}).entries) e.key as String: toInt(e.value),
      };
      b.destacados[a.miembroId] = {for (final d in (n?['destacados'] as List? ?? const [])) d as String};
      if (notasPrevias.isNotEmpty && n == null) b.sinValorar.add(a.miembroId);
    }
    b.mvp = previo['mvp'] as String?;
    _borradores[_clave] = b;
  }

  // ---------------------------------------------------------------- cotejo

  /// Igual que `enviar_parte` en el servidor: goles a favor de un equipo = goles de sus jugadores +
  /// autogoles de los rivales. Nunca puede superar el resultado; si te fijaste en los dos equipos, debe ser igual.
  ({List<_EstadoEquipo> equipos, String? error}) _cotejo() {
    final b = _b!;
    final enc = b.encuentros;
    final equipos = <_EstadoEquipo>[];
    String? error;
    int golesDe(int eq) => _equipoDe.entries
        .where((e) => e.value == eq)
        .fold<int>(0, (s, e) => s + (b.goles[e.key] ?? 0));
    int autogolesDe(int eq) => b.noMeFije.contains(eq)
        ? 0
        : _equipoDe.entries.where((e) => e.value == eq).fold<int>(0, (s, e) => s + (b.autogoles[e.key] ?? 0));

    if (enc.length == 1) {
      final e = enc.first;
      for (final (eq, rival, resultado) in [
        (e.equipoLocal, e.equipoVisitante, e.golesLocal),
        (e.equipoVisitante, e.equipoLocal, e.golesVisitante),
      ]) {
        final fijado = !b.noMeFije.contains(eq);
        final suma = (fijado ? golesDe(eq) : 0) + autogolesDe(rival);
        final exigido = fijado && !b.noMeFije.contains(rival);
        equipos.add(_EstadoEquipo(eq, suma, resultado, fijado));
        if (suma > resultado) {
          error ??= 'Equipo ${letraEquipo(eq)}: hay $suma goles asignados y el resultado dice $resultado.';
        } else if (exigido && suma < resultado) {
          error ??= 'Equipo ${letraEquipo(eq)}: faltan ${resultado - suma} goles por asignar '
              '(o marca «No me fijé»).';
        }
      }
    } else if (enc.length > 1) {
      final total = enc.fold<int>(0, (s, e) => s + e.golesLocal + e.golesVisitante);
      final eqs = _equipoDe.values.toSet().toList()..sort();
      var suma = 0;
      for (final eq in eqs) {
        final g = b.noMeFije.contains(eq) ? 0 : golesDe(eq) + autogolesDe(eq);
        suma += g;
        equipos.add(_EstadoEquipo(eq, b.noMeFije.contains(eq) ? 0 : golesDe(eq), null, !b.noMeFije.contains(eq)));
      }
      final todos = eqs.every((eq) => !b.noMeFije.contains(eq));
      if (suma > total) {
        error = 'Hay $suma goles asignados y los marcadores suman $total.';
      } else if (todos && suma < total) {
        error = 'Faltan ${total - suma} goles por asignar (o marca «No me fijé» en algún equipo).';
      }
    }
    return (equipos: equipos, error: error);
  }

  // ---------------------------------------------------------------- envío

  Future<void> _enviar(List<Inscripcion> asistentes, List<Aspecto> listaAspectos) async {
    final b = _b!;
    final detallada = widget.mi.liga.valoracionDetallada;
    setState(() => _enviando = true);
    final ok = await ejecutar(
      context,
      () => PostPartidoRepo.enviarPostPartido(
        partidoId: widget.partido.id,
        resultados: [
          for (final e in b.encuentros) {'n': e.n, 'goles_local': e.golesLocal, 'goles_visitante': e.golesVisitante},
        ],
        jugadores: [
          for (final a in asistentes)
            if (a.equipo != null && !b.noMeFije.contains(a.equipo))
              {
                'sujeto_id': a.miembroId,
                'goles': b.goles[a.miembroId] ?? 0,
                'asistencias': b.asistencias[a.miembroId] ?? 0,
                'autogoles': b.autogoles[a.miembroId] ?? 0,
                // Sin «Más datos» no se envían (null = no sé): no cuentan para el consenso.
                'paradas_clave': b.masDatos ? (b.paradas[a.miembroId] ?? 0) : null,
                'penaltis_parados': b.masDatos ? (b.penParados[a.miembroId] ?? 0) : null,
                'penaltis_fallados': b.masDatos ? (b.penFallados[a.miembroId] ?? 0) : null,
              },
        ],
        notas: [
          for (final id in b.notas.keys)
            if (!b.sinValorar.contains(id))
              {
                'votado_id': id,
                if (detallada)
                  'aspectos': {for (final a in listaAspectos) a.clave: b.aspectos[id]?[a.clave] ?? 6}
                else
                  'nota': b.notas[id],
                'destacados': (b.destacados[id] ?? const <String>{}).toList(),
              },
        ],
        mvp: b.mvp != null && !b.sinValorar.contains(b.mvp) ? b.mvp : null,
      ),
      ok: '¡Enviado! Se cruzará con lo que pongan los demás',
    );
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) _editando = false;
    });
    if (ok) {
      ref.invalidate(_miEnvioProvider(widget.partido.id));
      ref.invalidate(_numReportesProvider(widget.partido.id));
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final p = widget.partido;
    final conv = ref.watch(convocatoriaProvider(p.id)).valueOrNull;
    final miembros = ref.watch(miembrosPorIdProvider(widget.mi.liga.id));
    final aspectos = ref.watch(aspectosActivosProvider(widget.mi.liga.id));
    final miEnvio = ref.watch(_miEnvioProvider(p.id));
    final numReportes = ref.watch(_numReportesProvider(p.id)).valueOrNull;
    final definidos = ref.watch(_encuentrosDefProvider(p.id));

    if (conv == null || aspectos.isLoading || definidos.isLoading) return const Cargando();
    final asistentes = conv.where((i) => i.estado == EstadoInscripcion.confirmado && i.equipo != null).toList()
      ..sort((a, b) => a.equipo!.compareTo(b.equipo!));
    final asisto = asistentes.any((i) => i.miembroId == widget.mi.yo.id);

    if (!asisto) {
      return Vacio(
        'Solo los que jugaron envían el resultado y las notas.'
        '${numReportes == null ? '' : '\nEnviados: $numReportes de ${asistentes.length}.'}',
        icono: Icons.lock_outline,
      );
    }
    if (p.estado != EstadoPartido.post_partido) {
      return Vacio(
        p.estado == EstadoPartido.jugado
            ? 'El administrador aún no ha abierto el post-partido.'
            : 'El plazo ha terminado. El administrador está revisando el acta.',
        icono: Icons.hourglass_bottom,
      );
    }
    if (miEnvio.isLoading) return const Cargando();
    if (miEnvio.hasError) {
      return ErrorVista(miEnvio.error!, onRetry: () => ref.invalidate(_miEnvioProvider(p.id)));
    }
    final previo = miEnvio.value ?? const <String, dynamic>{};
    final yaEnviado = (previo['resultados'] as List? ?? const []).isNotEmpty ||
        (previo['notas'] as List? ?? const []).isNotEmpty;

    if (yaEnviado && !_editando) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        Icon(Icons.check_circle, size: 64, color: AppColores.of(context).exito),
        const SizedBox(height: 12),
        Text('¡Listo! Ya has enviado el resultado y tus notas.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (numReportes != null)
          Text('Enviados: $numReportes de ${asistentes.length}', textAlign: TextAlign.center),
        if (p.votacionCierra != null)
          Text('Puedes corregirlo hasta: ${fechaHora(p.votacionCierra!)}', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _borradores.remove(_clave); // se precarga lo enviado
              _editando = true;
            }),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Corregir'),
          ),
        ),
      ]);
    }

    _inicializar(definidos.valueOrNull ?? const <Encuentro>[], asistentes, previo);
    final b = _b!;
    final detallada = widget.mi.liga.valoracionDetallada;
    final listaAspectos = (aspectos.valueOrNull ?? const <Aspecto>[]).where((a) => a.clave != 'general').toList();
    final cotejo = _cotejo();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final equipos = asistentes.map((a) => a.equipo!).toSet().toList()..sort();
    final companeros = asistentes.where((a) => a.miembroId != widget.mi.yo.id).toList();

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Row(children: [
            Icon(Icons.timer_outlined, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Menos de 1 minuto · anónimo · se cruza con el resto',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ]),
          const SizedBox(height: 8),

          // ───── 1. Resultado
          _Titulo('1', 'Resultado'),
          if (b.encuentros.isEmpty) const Text('El administrador aún no ha definido los equipos de este partido.'),
          for (final e in b.encuentros)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Column(children: [
                  if (b.encuentros.length > 1) Text('Encuentro ${e.n}', style: t.labelLarge),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _Marcador(
                      equipo: e.equipoLocal,
                      valor: e.golesLocal,
                      onCambio: (v) => setState(() => e.golesLocal = v),
                    ),
                    Text('–', style: t.headlineMedium),
                    _Marcador(
                      equipo: e.equipoVisitante,
                      valor: e.golesVisitante,
                      onCambio: (v) => setState(() => e.golesVisitante = v),
                    ),
                  ]),
                ]),
              ),
            ),
          const SizedBox(height: 12),

          // ───── 2. Goles y asistencias
          _Titulo('2', '¿Quién marcó y asistió?'),
          Text('Toca para sumar · mantén pulsado para restar', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          for (final eq in equipos)
            _BloqueEquipo(
              equipo: eq,
              estado: cotejo.equipos.where((x) => x.equipo == eq).firstOrNull,
              noMeFije: b.noMeFije.contains(eq),
              onNoMeFije: (v) => setState(() => v ? b.noMeFije.add(eq) : b.noMeFije.remove(eq)),
              jugadores: [
                for (final a in asistentes.where((a) => a.equipo == eq))
                  _FilaGoles(
                    nombre: '${miembros[a.miembroId]?.nombre ?? '…'}${a.miembroId == widget.mi.yo.id ? ' (tú)' : ''}',
                    goles: b.goles[a.miembroId] ?? 0,
                    asistencias: b.asistencias[a.miembroId] ?? 0,
                    onGoles: (v) => setState(() => b.goles[a.miembroId] = v),
                    onAsistencias: (v) => setState(() => b.asistencias[a.miembroId] = v),
                    extras: b.masDatos
                        ? [
                            _Mini('Autogol', b.autogoles[a.miembroId] ?? 0,
                                (v) => setState(() => b.autogoles[a.miembroId] = v)),
                            _Mini('Paradas', b.paradas[a.miembroId] ?? 0,
                                (v) => setState(() => b.paradas[a.miembroId] = v)),
                            _Mini('Penalti parado', b.penParados[a.miembroId] ?? 0,
                                (v) => setState(() => b.penParados[a.miembroId] = v)),
                            _Mini('Penalti fallado', b.penFallados[a.miembroId] ?? 0,
                                (v) => setState(() => b.penFallados[a.miembroId] = v)),
                          ]
                        : const [],
                  ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => b.masDatos = !b.masDatos),
              icon: Icon(b.masDatos ? Icons.expand_less : Icons.expand_more),
              label: Text(b.masDatos ? 'Menos datos' : 'Más datos (autogoles, paradas, penaltis)'),
            ),
          ),
          const SizedBox(height: 12),

          // ───── 3. Notas
          _Titulo('3', detallada ? 'Valora a tus compañeros' : 'Notas de tus compañeros'),
          Text(
            detallada
                ? 'Del 1 al 10 en cada aspecto. ⭐ = tu MVP.'
                : 'Todos empiezan en 6 (normal): toca solo a quien se salió de lo normal. ⭐ = tu MVP.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          for (final a in companeros)
            _TarjetaNota(
              nombre: miembros[a.miembroId]?.nombre ?? '…',
              equipo: a.equipo!,
              nota: b.notas[a.miembroId] ?? 6,
              detallada: detallada,
              aspectos: listaAspectos,
              notasAspecto: b.aspectos.putIfAbsent(a.miembroId, () => {}),
              destacados: b.destacados.putIfAbsent(a.miembroId, () => {}),
              esMvp: b.mvp == a.miembroId,
              sinValorar: b.sinValorar.contains(a.miembroId),
              abierto: b.abiertos.contains(a.miembroId),
              onNota: (v) => setState(() => b.notas[a.miembroId] = v),
              onMvp: () => setState(() {
                if (b.mvp == a.miembroId) {
                  b.mvp = null;
                } else {
                  b.mvp = a.miembroId;
                  if ((b.notas[a.miembroId] ?? 6) < 9) b.notas[a.miembroId] = 9;
                }
              }),
              onSinValorar: (v) => setState(() => v ? b.sinValorar.add(a.miembroId) : b.sinValorar.remove(a.miembroId)),
              onAbrir: () => setState(() =>
                  b.abiertos.contains(a.miembroId) ? b.abiertos.remove(a.miembroId) : b.abiertos.add(a.miembroId)),
              onCambio: () => setState(() {}),
            ),
        ]),
      ),

      // ───── Barra fija de envío
      Material(
        elevation: 8,
        color: cs.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (cotejo.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: cs.error, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(cotejo.error!, style: t.bodySmall?.copyWith(color: cs.error))),
                  ]),
                ),
              Row(children: [
                if (_editando)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton(
                      onPressed: () => setState(() {
                        _borradores.remove(_clave);
                        _editando = false;
                      }),
                      child: const Text('Cancelar'),
                    ),
                  ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _enviando || cotejo.error != null || b.encuentros.isEmpty
                        ? null
                        : () => _enviar(asistentes, listaAspectos),
                    icon: _enviando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: Text(_editando ? 'Guardar cambios' : 'Enviar'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------

String letraEquipo(int eq) => String.fromCharCode(64 + eq);

class _EstadoEquipo {
  _EstadoEquipo(this.equipo, this.asignados, this.resultado, this.fijado);
  final int equipo, asignados;
  final int? resultado; // null con varios encuentros (se coteja el total)
  final bool fijado;
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.numero, this.texto);
  final String numero, texto;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          child: Text(numero, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Text(texto, style: Theme.of(context).textTheme.titleMedium),
      ]),
    );
  }
}

/// Marcador grande de un equipo: − número +.
class _Marcador extends StatelessWidget {
  const _Marcador({required this.equipo, required this.valor, required this.onCambio});
  final int equipo, valor;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.colorEquipo(equipo);
    return Column(children: [
      Text('Equipo ${letraEquipo(equipo)}', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          onPressed: valor > 0 ? () => onCambio(valor - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          iconSize: 30,
        ),
        SizedBox(
          width: 44,
          child: Text('$valor', textAlign: TextAlign.center, style: AppTheme.numero(context, size: 34)),
        ),
        IconButton(
          onPressed: valor < 99 ? () => onCambio(valor + 1) : null,
          icon: Icon(Icons.add_circle, color: color),
          iconSize: 30,
        ),
      ]),
    ]);
  }
}

class _BloqueEquipo extends StatelessWidget {
  const _BloqueEquipo({
    required this.equipo,
    required this.estado,
    required this.noMeFije,
    required this.onNoMeFije,
    required this.jugadores,
  });
  final int equipo;
  final _EstadoEquipo? estado;
  final bool noMeFije;
  final ValueChanged<bool> onNoMeFije;
  final List<Widget> jugadores;

  @override
  Widget build(BuildContext context) {
    final colores = AppColores.of(context);
    final cs = Theme.of(context).colorScheme;
    final e = estado;
    Widget? contador;
    if (e != null && e.resultado != null && !noMeFije) {
      final ok = e.asignados == e.resultado;
      final sobra = e.asignados > e.resultado!;
      final color = ok ? colores.exito : (sobra ? cs.error : colores.aviso);
      contador = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Text('⚽ ${e.asignados} / ${e.resultado}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: AppTheme.colorEquipo(equipo), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text('Equipo ${letraEquipo(equipo)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            if (contador != null) contador,
            const Spacer(),
            FilterChip(
              label: const Text('No me fijé'),
              selected: noMeFije,
              visualDensity: VisualDensity.compact,
              onSelected: onNoMeFije,
            ),
          ]),
          if (noMeFije)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('No envías datos de este equipo: cuentan los del resto.',
                  style: Theme.of(context).textTheme.bodySmall),
            )
          else
            ...jugadores,
        ]),
      ),
    );
  }
}

class _FilaGoles extends StatelessWidget {
  const _FilaGoles({
    required this.nombre,
    required this.goles,
    required this.asistencias,
    required this.onGoles,
    required this.onAsistencias,
    this.extras = const [],
  });
  final String nombre;
  final int goles, asistencias;
  final ValueChanged<int> onGoles, onAsistencias;
  final List<Widget> extras;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(nombre, overflow: TextOverflow.ellipsis)),
          _ChipContador(icono: '⚽', valor: goles, onCambio: onGoles),
          const SizedBox(width: 6),
          _ChipContador(icono: '🅰️', valor: asistencias, onCambio: onAsistencias),
        ]),
        if (extras.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(spacing: 6, runSpacing: 4, children: extras),
          ),
      ]),
    );
  }
}

/// Chip que suma al tocar y resta al mantener pulsado.
class _ChipContador extends StatelessWidget {
  const _ChipContador({required this.icono, required this.valor, required this.onCambio});
  final String icono;
  final int valor;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activo = valor > 0;
    return Material(
      color: activo ? cs.primaryContainer : cs.surfaceContainerHighest,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: valor < 50 ? () => onCambio(valor + 1) : null,
        onLongPress: valor > 0 ? () => onCambio(valor - 1) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('$icono $valor',
              style: TextStyle(
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w400,
                  color: activo ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.etiqueta, this.valor, this.onCambio);
  final String etiqueta;
  final int valor;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) => InputChip(
        label: Text('$etiqueta $valor'),
        visualDensity: VisualDensity.compact,
        selected: valor > 0,
        showCheckmark: false,
        onPressed: () => onCambio(valor + 1),
        onDeleted: valor > 0 ? () => onCambio(valor - 1) : null,
        deleteIcon: const Icon(Icons.remove, size: 16),
      );
}

const _nombresDestacado = {
  'ataque': 'Ataque',
  'defensa': 'Defensa',
  'pase_vision': 'Pase',
  'esfuerzo': 'Esfuerzo',
  'juego_limpio': 'Juego limpio',
  'porteria': 'Portería',
};

class _TarjetaNota extends StatelessWidget {
  const _TarjetaNota({
    required this.nombre,
    required this.equipo,
    required this.nota,
    required this.detallada,
    required this.aspectos,
    required this.notasAspecto,
    required this.destacados,
    required this.esMvp,
    required this.sinValorar,
    required this.abierto,
    required this.onNota,
    required this.onMvp,
    required this.onSinValorar,
    required this.onAbrir,
    required this.onCambio,
  });
  final String nombre;
  final int equipo, nota;
  final bool detallada, esMvp, sinValorar, abierto;
  final List<Aspecto> aspectos;
  final Map<String, int> notasAspecto;
  final Set<String> destacados;
  final ValueChanged<int> onNota;
  final VoidCallback onMvp, onAbrir, onCambio;
  final ValueChanged<bool> onSinValorar;

  static const _rapidas = [4, 5, 6, 7, 8, 9, 10];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      color: esMvp ? cs.tertiaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: AppTheme.colorEquipo(equipo), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(nombre,
                  style: t.titleSmall?.copyWith(
                      decoration: sinValorar ? TextDecoration.lineThrough : null,
                      color: sinValorar ? cs.onSurfaceVariant : null)),
            ),
            IconButton(
              tooltip: esMvp ? 'Quitar mi MVP' : 'Mi MVP',
              onPressed: sinValorar ? null : onMvp,
              icon: Icon(esMvp ? Icons.star : Icons.star_border, color: esMvp ? cs.tertiary : null),
            ),
            PopupMenuButton<String>(
              tooltip: 'Más',
              onSelected: (v) {
                if (v == 'novi') onSinValorar(!sinValorar);
                if (v == 'baja') _elegirNotaBaja(context);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'novi', child: Text(sinValorar ? 'Sí le vi: valorar' : 'No le vi (no valorar)')),
                if (!detallada && !sinValorar) const PopupMenuItem(value: 'baja', child: Text('Nota 1–3')),
              ],
            ),
          ]),
          if (!sinValorar) ...[
            if (!detallada)
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final n in _rapidas)
                  ChoiceChip(
                    label: Text('$n'),
                    selected: nota == n,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    onSelected: (_) => onNota(n),
                  ),
                if (nota < 4)
                  ChoiceChip(label: Text('$nota'), selected: true, showCheckmark: false, onSelected: (_) {}),
              ])
            else
              for (final a in aspectos)
                Row(children: [
                  SizedBox(width: 96, child: Text(a.nombre, style: t.bodySmall)),
                  Expanded(
                    child: Slider(
                      value: (notasAspecto[a.clave] ?? 6).toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '${notasAspecto[a.clave] ?? 6}',
                      onChanged: (v) {
                        notasAspecto[a.clave] = v.round();
                        onCambio();
                      },
                    ),
                  ),
                  SizedBox(width: 24, child: Text('${notasAspecto[a.clave] ?? 6}', textAlign: TextAlign.end)),
                ]),
            if (!detallada)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                  onPressed: onAbrir,
                  child: Text(destacados.isEmpty
                      ? (abierto ? 'Ocultar' : '+ Destacó en…')
                      : 'Destacó en: ${destacados.map((d) => _nombresDestacado[d] ?? d).join(', ')}'),
                ),
              ),
            if (!detallada && abierto)
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final a in aspectos)
                  FilterChip(
                    label: Text(_nombresDestacado[a.clave] ?? a.nombre),
                    visualDensity: VisualDensity.compact,
                    selected: destacados.contains(a.clave),
                    onSelected: (v) {
                      if (v && destacados.length >= 2) {
                        mostrarError(context, 'Máximo 2 por jugador');
                        return;
                      }
                      v ? destacados.add(a.clave) : destacados.remove(a.clave);
                      onCambio();
                    },
                  ),
              ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _elegirNotaBaja(BuildContext context) async {
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Nota para $nombre'),
        children: [
          for (final n in [1, 2, 3])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, n), child: Text('$n')),
        ],
      ),
    );
    if (v != null) onNota(v);
  }
}
