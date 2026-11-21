import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/compartir.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../fantasy/fantasy_providers.dart';
import 'balanceo.dart';
import '../../core/equipaciones.dart';
import 'prediccion_card.dart';

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
  bool _propuestaAuto = false;

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
    final ok = await ejecutar(
      context,
      () => PartidosRepo.guardarEquipos(widget.partido.id, Reparto(equipos, 0).asignacion,
          numEquipos: widget.partido.numEquipos),
      ok: 'Equipos confirmados',
    );
    if (!mounted) return;
    setState(() {
      _guardando = false;
      if (ok) _equipos = null; // se muestran los guardados y el resultado esperado
    });
    if (ok) ref.invalidate(prediccionProvider(widget.partido.id));
  }

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(convocatoriaProvider(widget.partido.id)).valueOrNull;
    final miembros = ref.watch(miembrosPorIdProvider(widget.mi.liga.id));
    final rend = ref.watch(rendimientoProvider(widget.mi.liga.id));
    final mercado = ref.watch(ratingsMercadoProvider(widget.mi.liga.id));
    if (conv == null || rend.isLoading || mercado.isLoading) return const Cargando();

    // 0042: juegan los que ocupan plaza (confirmados, fijos sin confirmar y en duda)
    final conf = conv.where((i) => i.estado.ocupaPlaza).toList();
    final liga = widget.mi.liga;
    final capitanes = conf.where((i) => i.capitan).toList();
    final soyCapitan = capitanes.any((i) => i.miembroId == widget.mi.yo.id);
    final porteria = ref.watch(habilidadPorteriaProvider(widget.mi.liga.id)).valueOrNull ?? const <String, double>{};
    final js = _jugadores(conf, miembros, rend.valueOrNull ?? const [], mercado.valueOrNull ?? const {}, porteria);
    // Hace los equipos el admin o, en ligas con capitanes, los capitanes del partido
    final editable = widget.partido.estado.antesDeJugar && (widget.mi.soyAdmin || (liga.conCapitanes && soyCapitan));

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

    // Lista completa y sin equipos: la app propone unos equilibrados sola; el admin solo confirma
    if (editable && widget.mi.soyAdmin && liga.modoEquipos == 'admin' && mostrar == null && !_propuestaAuto &&
        conf.length >= widget.partido.plazas) {
      _propuestaAuto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _equipos == null) _generar(js);
      });
    }

    String nombre(String id) => miembros[id]?.nombre ?? '…';
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Capitanes (ligas con capitanes): quiénes son y, para el admin, sortearlos o elegirlos
      if (liga.conCapitanes)
        Card(
          color: soyCapitan ? cs.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.military_tech_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    capitanes.isEmpty
                        ? tr('Aún no hay capitanes')
                        : trf('Capitanes: {c}', {
                            'c': capitanes.map((i) => '${nombre(i.miembroId)} (${nombreEquipo(context, i.equipo ?? 1)})').join(', ')
                          }),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ]),
              if (soyCapitan && widget.partido.estado.antesDeJugar)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Tx('Eres capitán: haz los equipos, confírmalos y pásalos al grupo.', style: Theme.of(context).textTheme.bodySmall),
                ),
              if (widget.mi.soyAdmin && widget.partido.estado.antesDeJugar)
                Wrap(spacing: 8, children: [
                  TextButton.icon(
                    icon: const Icon(Icons.casino_outlined),
                    label: Tx(capitanes.isEmpty ? 'Sortear capitanes' : 'Volver a sortear'),
                    onPressed: () => ejecutar(context, () => PartidosRepo.sortearCapitanes(widget.partido.id),
                        ok: 'Capitanes avisados'),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.how_to_reg_outlined),
                    label: const Tx('Elegir capitanes'),
                    onPressed: () => _elegirCapitanes(context, conf, nombre),
                  ),
                ]),
            ]),
          ),
        ),
      if (editable && _equipos != null && !hayGuardados)
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.auto_awesome),
              SizedBox(width: 10),
              Expanded(child: Tx('Propuesta de equipos equilibrados. Si te parecen bien, pulsa «Confirmar equipos».')),
            ]),
          ),
        ),
      if (editable)
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: () => _generar(js),
            icon: const Icon(Icons.auto_awesome),
            label: Text(mostrar == null ? 'Generar equipos' : 'Volver a generar'),
          ),
          if (_opciones.length > 1)
            OutlinedButton.icon(onPressed: _otraOpcion, icon: const Icon(Icons.shuffle), label: const Tx('Otra opción')),
        ]),
      if (mostrar == null)
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Vacio(
            switch (liga.modoEquipos) {
              'capitanes' => 'Los capitanes harán los equipos cuando la lista esté cerrada.',
              'automatico' => 'Se harán solos, equilibrados, cuando la lista esté cerrada.',
              _ => 'El administrador los hará equilibrados con las estadísticas de cada uno.',
            },
            titulo: 'Equipos por hacer',
            icono: Icons.groups_2_outlined,
          ),
        )
      else ...[
        if (hayGuardados && _equipos == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.copy),
                  label: const Tx('Copiar equipos'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(
                        text: textoEquipos(liga: liga, partido: widget.partido, lista: conv, nombre: nombre)));
                    if (context.mounted) mostrarOk(context, 'Copiados: pégalos en el grupo');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Tx('WhatsApp'),
                  onPressed: () => compartirTexto(
                      context, textoEquipos(liga: liga, partido: widget.partido, lista: conv, nombre: nombre)),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 16),
        if (hayGuardados && _equipos == null) PrediccionCard(partido: widget.partido, mi: widget.mi),
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
          const Tx('Toca un jugador para moverlo a otro equipo.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _guardando ? null : _confirmar, child: const Tx('Confirmar equipos')),
        ],
        if (editable && _equipos == null && hayGuardados)
          TextButton(
            onPressed: () => setState(() => _equipos = [for (final e in guardados) [...e]]),
            child: const Tx('Ajustar a mano'),
          ),
      ],
    ]);
  }
}

/// El admin elige a los capitanes: se reparten por equipos en el orden en que se marcan.
extension _Capitanes on _EquiposTabState {
  Future<void> _elegirCapitanes(BuildContext context, List<Inscripcion> conf, String Function(String) nombre) async {
    final n = widget.partido.numEquipos * widget.mi.liga.capitanesPorEquipo;
    final elegidos = <String>[for (final i in conf) if (i.capitan) i.miembroId];
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(trf('Marca {n} capitanes', {'n': n}), style: Theme.of(c).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final i in conf)
                  CheckboxListTile(
                    value: elegidos.contains(i.miembroId),
                    title: Text(nombre(i.miembroId)),
                    subtitle: elegidos.contains(i.miembroId)
                        ? Text(nombreEquipo(context, elegidos.indexOf(i.miembroId) % widget.partido.numEquipos + 1))
                        : null,
                    onChanged: (v) => set(() {
                      if (v == true && elegidos.length < n) {
                        elegidos.add(i.miembroId);
                      } else {
                        elegidos.remove(i.miembroId);
                      }
                    }),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: elegidos.isEmpty ? null : () => Navigator.pop(c, true),
                  child: const Tx('Guardar capitanes'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await ejecutar(
      context,
      () => PartidosRepo.asignarCapitanes(widget.partido.id, {
        for (var k = 0; k < elegidos.length; k++) elegidos[k]: k % widget.partido.numEquipos + 1,
      }),
      ok: 'Capitanes avisados',
    );
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
              child: Container(height: 12, color: colorEquipo(context, i + 1)),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Text(
        '${[for (var i = 0; i < sumas.length; i++) '${nombreEquipo(context, i + 1)} ${sumas[i].toStringAsFixed(0)}'].join(' · ')}'
        '  —  diferencia ${dif.toStringAsFixed(1)} %',
        style: AppTheme.tabular(Theme.of(context).textTheme.bodyMedium)?.copyWith(
          fontWeight: FontWeight.w600,
          color: dif < 5
              ? AppColores.of(context).exito
              : (dif < 10 ? AppColores.of(context).aviso : Theme.of(context).colorScheme.error),
        ),
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
    final color = colorEquipo(context, numero);
    final colorTexto = colorTextoEquipo(context, numero);
    final ordenados = [...jugadores]..sort((a, b) => b.rating.compareTo(a.rating));
    return Card(
      shape: RoundedRectangleBorder(side: BorderSide(color: colorTexto, width: 2), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              EtiquetaEquipo(numero, estilo: Theme.of(context).textTheme.titleMedium),
              Text('  ·  ${jugadores.length} jugadores', style: Theme.of(context).textTheme.bodyMedium),
            ]),
          ),
          for (final j in ordenados)
            ListTile(
              dense: true,
              leading: Icon(Icons.person, color: colorTexto),
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
                                  child: EtiquetaEquipo(e + 1),
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
