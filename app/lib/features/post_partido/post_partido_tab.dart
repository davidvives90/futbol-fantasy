import 'package:flutter/material.dart';
import '../../core/ventajas.dart';
import '../../core/idioma.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../../data/repos/post_partido_repo.dart';
import '../../core/avatar.dart';
import '../../core/equipaciones.dart';
import '../../core/info.dart';
import '../../core/anuncios.dart';
import '../../core/guias.dart';
import '../shell/sincronizacion.dart';
import 'parte_widgets.dart';

/// Encuentros que definió el admin (quién contra quién); cada asistente solo pone el marcador.
final _encuentrosDefProvider = FutureProvider.autoDispose.family<List<Encuentro>, String>(
  (ref, partidoId) {
    ref.watch(latidoProvider('partido:$partidoId')); // 0062: en vivo
    return PartidosRepo.encuentros(partidoId);
  },
);

final _numReportesProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, partidoId) {
    ref.watch(latidoProvider('partido:$partidoId')); // 0062: en vivo
    return PostPartidoRepo.numReportes(partidoId);
  },
);

/// Lo que ya envié (vacío si nada): sirve para saber si ya envié y para precargar al corregir.
final _puedoActaProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, partidoId) {
    ref.watch(latidoProvider('partido:$partidoId')); // 0062: en vivo
    return PostPartidoRepo.puedoRellenarActa(partidoId);
  },
);

final _miEnvioProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, partidoId) {
    ref.watch(latidoProvider('partido:$partidoId')); // 0062: en vivo
    return PostPartidoRepo.miPostPartido(partidoId);
  },
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

  /// Nota general de 1 a 5 (3 = normal). Se envía ×2 (escala 2–10 del servidor).
  final notas = <String, int>{};

  /// Notas por aspecto (modo detallado).
  final aspectos = <String, Map<String, int>>{};
  final destacados = <String, Set<String>>{};
  final sinValorar = <String>{};
  final abiertos = <String>{};
  String? mvp;

  /// Modo podio (0053): 1.º, 2.º y 3.º mejor del partido.
  final podio = <String?>[null, null, null];

  /// 0063: el resultado se calcula solo con los goles de cada equipo hasta que lo toques a mano.
  bool marcadorManual = false;
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
      b.notas[a.miembroId] = n?['nota'] == null ? 3 : _a5(toInt(n!['nota']));
      b.aspectos[a.miembroId] = {
        for (final e in ((n?['aspectos'] as Map?) ?? const {}).entries) e.key as String: _a5(toInt(e.value)),
      };
      b.destacados[a.miembroId] = {for (final d in (n?['destacados'] as List? ?? const [])) d as String};
      if (notasPrevias.isNotEmpty && n == null) b.sinValorar.add(a.miembroId);
    }
    b.mvp = previo['mvp'] as String?;
    final pp = previo['podio'] as List? ?? const [];
    for (var i = 0; i < 3 && i < pp.length; i++) {
      b.podio[i] = pp[i] as String?;
    }
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
        final asist = _equipoDe.entries.where((x) => x.value == eq).fold<int>(0, (s, x) => s + (b.asistencias[x.key] ?? 0));
        if (fijado && asist > resultado - autogolesDe(rival)) {
          error ??= trf('{e}: hay más asistencias ({a}) que goles ({g}). Cada asistencia es de un gol.',
              {'e': nombreEquipo(context, eq), 'a': asist, 'g': resultado - autogolesDe(rival)});
        }
        if (suma > resultado) {
          error ??= '${nombreEquipo(context, eq)}: hay $suma goles asignados y el resultado dice $resultado.';
        } else if (exigido && suma < resultado) {
          error ??= '${nombreEquipo(context, eq)}: faltan ${resultado - suma} goles por asignar '
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
      final asist = b.asistencias.values.fold<int>(0, (s, v) => s + v);
      if (asist > total) {
        error ??= trf('Hay más asistencias ({a}) que goles ({g}). Cada asistencia es de un gol.', {'a': asist, 'g': total});
      }
      if (suma > total) {
        error = 'Hay $suma goles asignados y los marcadores suman $total.';
      } else if (todos && suma < total) {
        error = 'Faltan ${total - suma} goles por asignar (o marca «No me fijé» en algún equipo).';
      }
    }
    return (equipos: equipos, error: error);
  }

  /// 0063: con un solo encuentro, el marcador = goles de cada equipo + autogoles del rival (salvo que lo hayas tocado).
  void _autoMarcador() {
    final b = _b!;
    if (b.marcadorManual || b.encuentros.length != 1) return;
    final e = b.encuentros.first;
    int goles(int eq) => _equipoDe.entries.where((x) => x.value == eq).fold<int>(0, (s, x) => s + (b.goles[x.key] ?? 0));
    int autogoles(int eq) => _equipoDe.entries.where((x) => x.value == eq).fold<int>(0, (s, x) => s + (b.autogoles[x.key] ?? 0));
    final local = goles(e.equipoLocal) + autogoles(e.equipoVisitante);
    final visitante = goles(e.equipoVisitante) + autogoles(e.equipoLocal);
    e.golesLocal = local;
    e.golesVisitante = visitante;
  }

  /// Goles que marcó el equipo [eq] según el resultado que has puesto (null si hay varios encuentros: tope total).
  int? _topeAsistencias(int eq) {
    final b = _b!;
    final enc = b.encuentros;
    if (enc.isEmpty) return null;
    if (enc.length > 1) {
      return enc.fold<int>(0, (s, e) => s + e.golesLocal + e.golesVisitante);
    }
    final e = enc.first;
    final rival = eq == e.equipoLocal ? e.equipoVisitante : e.equipoLocal;
    final aFavor = eq == e.equipoLocal ? e.golesLocal : e.golesVisitante;
    final autogolesRival = _equipoDe.entries
        .where((x) => x.value == rival)
        .fold<int>(0, (s, x) => s + (b.autogoles[x.key] ?? 0));
    return aFavor - autogolesRival;
  }

  // ---------------------------------------------------------------- envío

  Future<void> _enviar(List<Inscripcion> asistentes, List<Aspecto> listaAspectos,
      {required bool acta, required bool notas}) async {
    final b = _b!;
    final detallada = widget.mi.liga.valoracionDetallada;
    final avanzado = widget.mi.liga.valoracionAvanzada;
    final masDatos = avanzado && b.masDatos;
    final sinValorar = avanzado ? b.sinValorar : const <String>{};
    final esPodio = widget.mi.liga.modoValoracion == 'podio';
    final podio = b.podio.whereType<String>().toList();
    setState(() => _enviando = true);
    final ok = await ejecutar(
      context,
      () => PostPartidoRepo.enviarPostPartido(
        partidoId: widget.partido.id,
        resultados: !acta
            ? null
            : [
          for (final e in b.encuentros) {'n': e.n, 'goles_local': e.golesLocal, 'goles_visitante': e.golesVisitante},
        ],
        jugadores: !acta
            ? null
            : [
          for (final a in asistentes)
            if (a.equipo != null && !b.noMeFije.contains(a.equipo))
              {
                'sujeto_id': a.miembroId,
                'goles': b.goles[a.miembroId] ?? 0,
                'asistencias': b.asistencias[a.miembroId] ?? 0,
                'autogoles': b.autogoles[a.miembroId] ?? 0,
                // Sin «Más datos» no se envían (null = no sé): no cuentan para el consenso.
                'paradas_clave': masDatos ? (b.paradas[a.miembroId] ?? 0) : null,
                'penaltis_parados': masDatos ? (b.penParados[a.miembroId] ?? 0) : null,
                'penaltis_fallados': masDatos ? (b.penFallados[a.miembroId] ?? 0) : null,
              },
        ],
        notas: !notas || esPodio
            ? null
            : [
          for (final id in b.notas.keys)
            if (!sinValorar.contains(id))
              {
                'votado_id': id,
                if (detallada)
                  'aspectos': {for (final a in listaAspectos) a.clave: (b.aspectos[id]?[a.clave] ?? 3) * 2}
                else
                  'nota': (b.notas[id] ?? 3) * 2,
                'destacados': avanzado ? (b.destacados[id] ?? const <String>{}).toList() : const <String>[],
              },
        ],
        mvp: !esPodio && notas && b.mvp != null && !sinValorar.contains(b.mvp) ? b.mvp : null,
        podio: esPodio && notas && podio.isNotEmpty ? podio : null,
      ),
      ok: widget.mi.liga.quienRellena == 'jugadores' ? '¡Enviado! Se cruzará con lo que pongan los demás' : '¡Enviado!',
    );
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) _editando = false;
    });
    if (ok) {
      Anuncios.instancia.pausaNatural(); // acaba de terminar: buen momento, nunca a mitad del formulario
      ref.invalidate(_miEnvioProvider(widget.partido.id));
      ref.invalidate(_numReportesProvider(widget.partido.id));
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) => SinPublicidad(child: _contenido(context));

  Widget _contenido(BuildContext context) {
    final p = widget.partido;
    final conv = ref.watch(convocatoriaProvider(p.id)).valueOrNull;
    final miembros = ref.watch(miembrosPorIdProvider(widget.mi.liga.id));
    final aspectos = ref.watch(aspectosActivosProvider(widget.mi.liga.id));
    final miEnvio = ref.watch(_miEnvioProvider(p.id));
    final numReportes = ref.watch(_numReportesProvider(p.id)).valueOrNull;
    final definidos = ref.watch(_encuentrosDefProvider(p.id));
    final puedoActa = ref.watch(_puedoActaProvider(p.id));

    if (conv == null || aspectos.isLoading || definidos.isLoading || puedoActa.isLoading) return const Cargando();
    // 0050: el acta (resultado, goles, asistencias) la rellenan todos, el árbitro o los capitanes, según la liga
    final hagoActa = puedoActa.valueOrNull ?? false;
    final modoActa = widget.mi.liga.quienRellena;
    final asistentes = conv.where((i) => i.estado == EstadoInscripcion.confirmado && i.equipo != null).toList()
      ..sort((a, b) => a.equipo!.compareTo(b.equipo!));
    final asisto = asistentes.any((i) => i.miembroId == widget.mi.yo.id);

    if (!asisto && !hagoActa) {
      return Vacio(
        'Solo los que jugaron envían el resultado y las notas.'
        '${numReportes == null || modoActa != 'jugadores' ? '' : '\nEnviados: $numReportes de ${asistentes.length}.'}',
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
        (previo['notas'] as List? ?? const []).isNotEmpty ||
        (previo['podio'] as List? ?? const []).isNotEmpty;

    if (yaEnviado && !_editando) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        Icon(Icons.check_circle, size: 64, color: AppColores.of(context).exito),
        const SizedBox(height: 12),
        Tx(
            hagoActa && asisto
                ? '¡Listo! Ya has enviado el resultado y tus notas.'
                : hagoActa
                    ? '¡Listo! Ya has enviado el acta.'
                    : '¡Listo! Ya has enviado tus notas.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (numReportes != null && modoActa == 'jugadores')
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
            label: const Tx('Corregir'),
          ),
        ),
      ]);
    }

    _inicializar(definidos.valueOrNull ?? const <Encuentro>[], asistentes, previo);
    final b = _b!;
    final detallada = widget.mi.liga.valoracionDetallada;
    // Post-partido simple (por defecto): goles y asistencias, nota 1–5 a todos y estrella MVP. Lo demás lo activa el admin.
    final avanzado = widget.mi.liga.valoracionAvanzada;
    final listaAspectos = (aspectos.valueOrNull ?? const <Aspecto>[]).where((a) => a.clave != 'general').toList();
    final cotejo = _cotejo();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final equipos = asistentes.map((a) => a.equipo!).toSet().toList()..sort();
    final companeros = asistentes.where((a) => a.miembroId != widget.mi.yo.id).toList();
    final esPodio = widget.mi.liga.modoValoracion == 'podio';
    final sinNadaQueEnviar = !hagoActa && esPodio && b.podio.every((x) => x == null);

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          const AvisoGuia('post_partido'),
          // 0063: participación transparente
          ParticipacionParte(partidoId: widget.partido.id),
          Row(children: [
            Icon(Icons.timer_outlined, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Tx(
                  modoActa == 'jugadores'
                      ? 'Menos de 1 minuto · anónimo · se cruza con el resto'
                      : hagoActa
                          ? 'Te toca el acta: lo que pongas es lo que cuenta'
                          : 'Menos de 1 minuto · anónimo',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ]),
          const SizedBox(height: 8),

          if (!hagoActa)
            Card(
              color: cs.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: Tx(modoActa == 'arbitro'
                    ? 'El resultado y los goles los pone el árbitro'
                    : 'El resultado y los goles los ponen los capitanes'),
                subtitle: const Tx('Tú solo pones las notas de tus compañeros.'),
              ),
            ),
          if (hagoActa) ...[
          // ───── 1. Resultado
          _Titulo('1', 'Resultado'),
          if (b.encuentros.length == 1 && !b.marcadorManual)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Tx('Se calcula solo con los goles que pongas abajo. Si quieres, cámbialo aquí.', style: t.bodySmall),
            ),
          if (b.encuentros.isEmpty) const Tx('El administrador aún no ha definido los equipos de este partido.'),
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
                      onCambio: (v) => setState(() {
                        b.marcadorManual = true;
                        e.golesLocal = v;
                      }),
                    ),
                    Text('–', style: t.headlineMedium),
                    _Marcador(
                      equipo: e.equipoVisitante,
                      valor: e.golesVisitante,
                      onCambio: (v) => setState(() {
                        b.marcadorManual = true;
                        e.golesVisitante = v;
                      }),
                    ),
                  ]),
                ]),
              ),
            ),
          const SizedBox(height: 12),

          // ───── 2. Goles y asistencias
          _Titulo('2', '¿Quién marcó y asistió?', ayuda: Ayuda.cotejo),
          Row(children: [
            Expanded(
              child: Tx('Toca para sumar · mantén pulsado para restar',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
            TextButton.icon(
              onPressed: () => mostrarAyuda(context, Ayuda.noMeFije),
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Tx('¿No te fijaste?'),
            ),
          ]),
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
                    miembro: miembros[a.miembroId],
                    nombre: '${miembros[a.miembroId]?.nombre ?? '…'}${a.miembroId == widget.mi.yo.id ? ' (tú)' : ''}',
                    goles: b.goles[a.miembroId] ?? 0,
                    asistencias: b.asistencias[a.miembroId] ?? 0,
                    onGoles: (v) => setState(() {
                      b.goles[a.miembroId] = v;
                      _autoMarcador();
                    }),
                    onAsistencias: (v) {
                      // Cada asistencia es de un gol: no deja pasar de los goles del equipo
                      if (v > (b.asistencias[a.miembroId] ?? 0) && v > 0) {
                        final tope = _topeAsistencias(a.equipo!);
                        final usadas = _equipoDe.entries
                            .where((x) => x.value == a.equipo)
                            .fold<int>(0, (s, x) => s + (b.asistencias[x.key] ?? 0));
                        if (tope != null && usadas >= tope) {
                          mostrarError(context, trf('Tu equipo marcó {g} y ya hay {g} asistencias. Cada asistencia es de un gol.', {'g': tope}));
                          return;
                        }
                      }
                      setState(() => b.asistencias[a.miembroId] = v);
                    },
                    extras: avanzado && b.masDatos
                        ? [
                            _Mini('Autogol', b.autogoles[a.miembroId] ?? 0,
                                (v) => setState(() {
                                      b.autogoles[a.miembroId] = v;
                                      _autoMarcador();
                                    })),
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
          if (avanzado)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => b.masDatos = !b.masDatos),
              icon: Icon(b.masDatos ? Icons.expand_less : Icons.expand_more),
              label: Text(b.masDatos ? 'Menos datos' : 'Más datos (autogoles, paradas, penaltis)'),
            ),
          ),
          const SizedBox(height: 12),
          ],

          // ───── 3. Podio (modo Top 3): solo quien jugó
          if (asisto && esPodio) ...[
            _Titulo(hagoActa ? '3' : '1', 'Los 3 mejores del partido', ayuda: Ayuda.podio),
            Text(
              trf('Elige por orden. 1.º = {a} pts, 2.º = {b}, 3.º = {c}. No puedes votarte. El que más sume es el MVP.', {
                'a': widget.mi.liga.puntosPodio[0],
                'b': widget.mi.liga.puntosPodio[1],
                'c': widget.mi.liga.puntosPodio[2],
              }),
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('podio-$i-${b.podio[i]}'),
                  value: b.podio[i],
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: ['🥇 1.º mejor', '🥈 2.º mejor', '🥉 3.º mejor'].map(tr).toList()[i],
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Tx('— Sin elegir —')),
                    for (final a in companeros)
                      if (b.podio[i] == a.miembroId || !b.podio.contains(a.miembroId))
                        DropdownMenuItem<String?>(
                          value: a.miembroId,
                          child: Row(children: [
                            AvatarMiembro(miembros[a.miembroId], radio: 12),
                            const SizedBox(width: 8),
                            Expanded(child: Text(miembros[a.miembroId]?.nombre ?? '…', overflow: TextOverflow.ellipsis)),
                            PuntoEquipo(a.equipo!),
                          ]),
                        ),
                  ],
                  onChanged: (v) => setState(() => b.podio[i] = v),
                ),
              ),
          ],

          // ───── 3. Notas (solo quien jugó)
          if (asisto && !esPodio) ...[
          _Titulo(hagoActa ? '3' : '1', detallada ? 'Valora a tus compañeros' : 'Notas de tus compañeros', ayuda: Ayuda.notas),
          Text(
            detallada
                ? 'Del 1 al 5 en cada aspecto (3 = normal).'
                : 'Puntúa a todos del 1 al 5 (empiezan en 3, normal) y marca con la estrella a tu MVP.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 4, children: [
              TextButton.icon(
                onPressed: () => mostrarAyuda(context, Ayuda.mvp),
                icon: const Icon(Icons.star_border, size: 16),
                label: const Tx('¿Cómo se elige el MVP?'),
              ),
              if (avanzado && !detallada)
                TextButton.icon(
                  onPressed: () => mostrarAyuda(context, Ayuda.destacados),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Tx('«Destacó en»'),
                ),
            ]),
          ),
          for (final a in companeros)
            _TarjetaNota(
              miembro: miembros[a.miembroId],
              nombre: miembros[a.miembroId]?.nombre ?? '…',
              equipo: a.equipo!,
              nota: b.notas[a.miembroId] ?? 3,
              detallada: detallada,
              avanzado: avanzado,
              aspectos: listaAspectos,
              notasAspecto: b.aspectos.putIfAbsent(a.miembroId, () => {}),
              destacados: b.destacados.putIfAbsent(a.miembroId, () => {}),
              esMvp: b.mvp == a.miembroId,
              sinValorar: avanzado && b.sinValorar.contains(a.miembroId),
              abierto: b.abiertos.contains(a.miembroId),
              onNota: (v) => setState(() => b.notas[a.miembroId] = v),
              onMvp: () => setState(() {
                if (b.mvp == a.miembroId) {
                  b.mvp = null;
                } else {
                  b.mvp = a.miembroId;
                  if ((b.notas[a.miembroId] ?? 3) < 5) b.notas[a.miembroId] = 5;
                }
              }),
              onSinValorar: (v) => setState(() => v ? b.sinValorar.add(a.miembroId) : b.sinValorar.remove(a.miembroId)),
              onAbrir: () => setState(() =>
                  b.abiertos.contains(a.miembroId) ? b.abiertos.remove(a.miembroId) : b.abiertos.add(a.miembroId)),
              onCambio: () => setState(() {}),
            ),
          ],
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
              if (hagoActa && cotejo.error != null)
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
                      child: const Tx('Cancelar'),
                    ),
                  ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _enviando || sinNadaQueEnviar || (hagoActa && (cotejo.error != null || b.encuentros.isEmpty))
                        ? null
                        : () => _enviar(asistentes, listaAspectos, acta: hagoActa, notas: asisto),
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
  const _Titulo(this.numero, this.texto, {this.ayuda});
  final String numero, texto;
  final (String, String)? ayuda;

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
        Flexible(child: Text(texto, style: Theme.of(context).textTheme.titleMedium)),
        if (ayuda != null) InfoBoton(ayuda!),
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
    final color = colorTextoEquipo(context, equipo);
    return Column(children: [
      EtiquetaEquipo(equipo),
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
            EtiquetaEquipo(equipo),
            const SizedBox(width: 8),
            if (contador != null) contador,
            const Spacer(),
            FilterChip(
              label: const Tx('No me fijé'),
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
    required this.miembro,
    required this.nombre,
    required this.goles,
    required this.asistencias,
    required this.onGoles,
    required this.onAsistencias,
    this.extras = const [],
  });
  final Miembro? miembro;
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
          AvatarMiembro(miembro, radio: 15),
          const SizedBox(width: 8),
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
        onTap: valor < 50
            ? () {
                HapticFeedback.selectionClick();
                onCambio(valor + 1);
              }
            : null,
        onLongPress: valor > 0
            ? () {
                HapticFeedback.mediumImpact();
                onCambio(valor - 1);
              }
            : null,
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
    required this.miembro,
    required this.nombre,
    required this.equipo,
    required this.nota,
    required this.detallada,
    required this.avanzado,
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
  final Miembro? miembro;
  final String nombre;
  final int equipo, nota;
  final bool detallada, avanzado, esMvp, sinValorar, abierto;
  final List<Aspecto> aspectos;
  final Map<String, int> notasAspecto;
  final Set<String> destacados;
  final ValueChanged<int> onNota;
  final VoidCallback onMvp, onAbrir, onCambio;
  final ValueChanged<bool> onSinValorar;

  static const _rapidas = [1, 2, 3, 4, 5];
  static const _textos = {1: 'Mal', 2: 'Flojo', 3: 'Normal', 4: 'Bien', 5: 'Crack'};

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
            AvatarMiembro(miembro, radio: 16, anillo: colorEquipo(context, equipo)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(nombre,
                  style: t.titleSmall?.copyWith(
                      decoration: sinValorar ? TextDecoration.lineThrough : null,
                      color: sinValorar ? cs.onSurfaceVariant : null)),
            ),
            TextButton.icon(
              onPressed: sinValorar ? null : onMvp,
              style: TextButton.styleFrom(
                foregroundColor: esMvp ? cs.onTertiaryContainer : cs.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: Icon(esMvp ? Icons.star : Icons.star_border, color: esMvp ? cs.tertiary : null),
              label: Tx('MVP', style: TextStyle(fontWeight: esMvp ? FontWeight.w800 : FontWeight.w600)),
            ),
            if (avanzado)
            PopupMenuButton<String>(
              tooltip: tr('Más'),
              onSelected: (v) {
                if (v == 'novi') onSinValorar(!sinValorar);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'novi', child: Text(sinValorar ? 'Sí le vi: valorar' : 'No le vi (no valorar)')),
              ],
            ),
          ]),
          if (!sinValorar) ...[
            if (!detallada)
              Row(children: [
                for (final n in _rapidas)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _BotonNota(n: n, texto: _textos[n]!, elegida: nota == n, onTap: () => onNota(n)),
                    ),
                  ),
              ])
            else
              for (final a in aspectos)
                Row(children: [
                  SizedBox(width: 96, child: Text(a.nombre, style: t.bodySmall)),
                  Expanded(
                    child: Slider(
                      value: (notasAspecto[a.clave] ?? 3).toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '${notasAspecto[a.clave] ?? 3}',
                      onChanged: (v) {
                        notasAspecto[a.clave] = v.round();
                        onCambio();
                      },
                    ),
                  ),
                  SizedBox(width: 24, child: Text('${notasAspecto[a.clave] ?? 3}', textAlign: TextAlign.end)),
                ]),
            if (avanzado && !detallada)
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
            if (avanzado && !detallada && abierto)
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

}

/// Nota del 1 al 5 con su palabra debajo (1 Mal · 3 Normal · 5 Crack).
class _BotonNota extends StatelessWidget {
  const _BotonNota({required this.n, required this.texto, required this.elegida, required this.onTap});
  final int n;
  final String texto;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: elegida ? cs.primary : cs.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            Text('$n',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: elegida ? cs.onPrimary : cs.onSurface)),
            Text(texto,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: TextStyle(fontSize: 10.5, color: elegida ? cs.onPrimary : cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// Nota del servidor (2–10) a la escala de la app (1–5).
int _a5(int n) => (n / 2).round().clamp(1, 5);
