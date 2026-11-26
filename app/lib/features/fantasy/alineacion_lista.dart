import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/avatar.dart';
import '../../core/idioma.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';
import 'alineacion_campo.dart' show LeyendaBonusRoles;
import 'fantasy_providers.dart';
import 'tarjetas_jugador.dart';
import 'widgets_fantasy.dart';

/// Alineación del próximo partido en forma de lista, sin dibujo del campo: se toca cada jugador para pasarlo
/// de «Banquillo» a «Titular» (como mucho media plantilla del partido, p. ej. 5 en fútbol 7… o 5 en F5).
/// Los del banquillo entran solos, por orden de puntos, si un titular no juega (según los suplentes de la liga).
/// Solo con alineación táctica se elige el rol (POR, DEF, MED, DEL) de cada titular.
class AlineacionLista extends ConsumerStatefulWidget {
  const AlineacionLista({super.key, required this.mi, required this.partido, required this.plantilla});
  final MiLiga mi;
  final Partido partido;
  final List<JugadorPlantilla> plantilla;

  @override
  ConsumerState<AlineacionLista> createState() => _AlineacionListaState();
}

class _AlineacionListaState extends ConsumerState<AlineacionLista> {
  /// Titulares → rol, en orden. null = aún no cargada.
  Map<String, RolAlineacion>? _sel;
  Map<String, RolAlineacion> _guardada = {};
  String? _capitan, _ariete, _capitanG, _arieteG;
  List<String> _suplentesG = [];
  bool _guardando = false;
  Timer? _timer;

  ParamsFantasy get _p => widget.mi.liga.fantasy;
  int get _tam => widget.partido.plazas ~/ widget.partido.numEquipos;
  DateTime get _cierre => _p.cierre(widget.partido.fechaHora);
  bool get _bloqueada => !DateTime.now().isBefore(_cierre);
  bool get _tactica => _p.tactica;

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant AlineacionLista old) {
    super.didUpdateWidget(old);
    if (old.partido.id != widget.partido.id) _cargar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final a = await FantasyRepo.alineacion(widget.partido.id, widget.mi.yo.id);
      if (!mounted) return;
      setState(() {
        _guardada = {for (final x in a.where((x) => x.suplente == null)) x.jugadorId: x.rol};
        _sel = {..._guardada};
        _capitan = _capitanG = a.where((x) => x.capitan).map((x) => x.jugadorId).firstOrNull;
        _ariete = _arieteG = a.where((x) => x.ariete).map((x) => x.jugadorId).firstOrNull;
        _suplentesG = [
          for (final x in [...a.where((x) => x.suplente != null)]..sort((p, q) => p.suplente!.compareTo(q.suplente!)))
            x.jugadorId,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sel = {});
      mostrarError(context, e);
    }
  }

  /// Banquillo: los no titulares que se pueden alinear, por puntos (los primeros son los suplentes que entran).
  List<String> _banquillo(Map<String, ResumenFantasy> resumen) {
    final s = _sel ?? const {};
    final b = [for (final j in widget.plantilla) if (!s.containsKey(j.jugadorId) && j.alineable) j.jugadorId]
      ..sort((a, c) => (resumen[c]?.total ?? -1).compareTo(resumen[a]?.total ?? -1));
    return b;
  }

  List<String> _suplentes(Map<String, ResumenFantasy> resumen) => _banquillo(resumen).take(_p.suplentes).toList();

  String? get _errorRoles {
    final s = _sel;
    if (s == null || s.isEmpty || !_tactica) return null;
    final porteros = s.values.where((r) => r == RolAlineacion.POR).length;
    if (porteros == 0) return 'Elige un portero entre los titulares.';
    if (porteros > 1) return 'Solo puede haber un portero.';
    if (s.length >= 4 && (!s.values.contains(RolAlineacion.DEF) || !s.values.contains(RolAlineacion.DEL))) {
      return 'Con 4 o más jugadores, la alineación táctica lleva al menos un defensa y un delantero.';
    }
    return null;
  }

  bool _cambiada(Map<String, ResumenFantasy> resumen) {
    final s = _sel;
    if (s == null) return false;
    if (s.length != _guardada.length) return true;
    if (_capitan != _capitanG || _ariete != _arieteG) return true;
    if (_suplentes(resumen).join(',') != _suplentesG.join(',')) return true;
    return s.entries.any((e) => _guardada[e.key] != e.value);
  }

  void _alternar(String id) {
    final s = _sel!;
    setState(() {
      if (s.containsKey(id)) {
        s.remove(id);
        if (_capitan == id) _capitan = null;
        if (_ariete == id) _ariete = null;
      } else if (s.length >= _tam) {
        mostrarError(context, trf('Ya tienes {n} titulares: pasa uno al banquillo primero.', {'n': _tam}));
      } else {
        // Rol por defecto: portero si aún no hay (táctica); si no, medio
        final rol = _tactica && !s.values.contains(RolAlineacion.POR) ? RolAlineacion.POR : RolAlineacion.MED;
        s[id] = rol;
      }
    });
  }

  Future<void> _guardar(Map<String, ResumenFantasy> resumen) async {
    final s = _sel!;
    final sup = _suplentes(resumen);
    setState(() => _guardando = true);
    final ok = await ejecutar(
      context,
      () => FantasyRepo.guardarAlineacion(
        widget.partido.id,
        s.keys.toList(),
        _tactica ? s.values.toList() : [for (final _ in s.keys) RolAlineacion.MED],
        capitan: s.containsKey(_capitan) ? _capitan : null,
        ariete: s.containsKey(_ariete) ? _ariete : null,
        suplentes: sup,
      ),
      ok: 'Alineación guardada',
    );
    if (!mounted) return;
    setState(() {
      _guardando = false;
      if (ok) {
        _guardada = {...s};
        _capitanG = _capitan;
        _arieteG = _ariete;
        _suplentesG = sup;
      }
    });
  }

  String _cuentaAtras() {
    final d = _cierre.difference(DateTime.now());
    if (d.isNegative) return trf('Cerrada desde {f}', {'f': fechaHora(_cierre)});
    if (d.inDays > 0) return trf('Cierra en {d} d {h} h', {'d': d.inDays, 'h': d.inHours % 24});
    if (d.inHours > 0) return trf('Cierra en {h} h {m} min', {'h': d.inHours, 'm': d.inMinutes % 60});
    return trf('Cierra en {m} min', {'m': d.inMinutes});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final ligaId = widget.mi.liga.id;
    final miembros = ref.watch(miembrosPorIdProvider(ligaId));
    final resumen = ref.watch(resumenFantasyProvider(ligaId)).valueOrNull ?? const <String, ResumenFantasy>{};
    final conv = ref.watch(convocatoriaProvider(widget.partido.id)).valueOrNull ?? const <Inscripcion>[];
    final estado = {for (final i in conv) i.miembroId: i.estado};
    final bonus = _p.bonusRoles && _tactica
        ? ref.watch(reglasRolProvider(ligaId)).valueOrNull ?? const <String, double>{}
        : const <String, double>{};
    final s = _sel;
    final bloqueada = _bloqueada;
    final errorRoles = _errorRoles;
    String nombre(String id) => miembros[id]?.nombre ?? '…';

    if (s == null) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    }
    final suplentes = _suplentes(resumen);
    final banquillo = _banquillo(resumen);
    final noAlineables = [for (final j in widget.plantilla) if (!j.alineable && !s.containsKey(j.jugadorId)) j];
    final porId = {for (final j in widget.plantilla) j.jugadorId: j};

    Widget fila(String id, {required bool titular}) {
      final j = porId[id];
      final total = resumen[id]?.total;
      final avisoConv = switch (estado[id]) {
        EstadoInscripcion.confirmado || EstadoInscripcion.pendiente => null,
        EstadoInscripcion.duda => tr('en duda'),
        EstadoInscripcion.baja => tr('no va'),
        EstadoInscripcion.espera => tr('en lista de espera'),
        _ => tr('no apuntado'),
      };
      final puesto = suplentes.indexOf(id);
      return Material(
        color: titular ? cs.primaryContainer.withValues(alpha: 0.55) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: bloqueada ? null : () => _alternar(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                AvatarMiembro(miembros[id], radio: 20, dorsal: true),
                Positioned(right: -4, bottom: -4, child: IconoConvocatoria(estado[id])),
              ]),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    [nombre(id), if (j?.cedidaAMi ?? false) tr('(cedido)')].join(' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    [
                      if (total != null) trf('{x} pts', {'x': total.round()}),
                      if (avisoConv != null) '⚠ $avisoConv',
                      if (!titular && puesto >= 0) trf('entra {n}º si falta alguien', {'n': puesto + 1}),
                    ].join(' · '),
                    style: t.bodySmall?.copyWith(color: avisoConv != null ? cs.error : null),
                  ),
                ]),
              ),
              if (titular && _tactica)
                PopupMenuButton<RolAlineacion>(
                  enabled: !bloqueada,
                  tooltip: tr('Rol'),
                  initialValue: s[id],
                  onSelected: (r) => setState(() => s[id] = r),
                  itemBuilder: (_) => [for (final r in RolAlineacion.values) PopupMenuItem(value: r, child: Text(tr(r.etiqueta)))],
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: InsigniaRol(s[id]!)),
                ),
              if (titular && _p.capitanActivo)
                IconButton(
                  tooltip: tr('Capitán (puntos ×2)'),
                  visualDensity: VisualDensity.compact,
                  onPressed: bloqueada ? null : () => setState(() => _capitan = _capitan == id ? null : id),
                  icon: CircleAvatar(
                    radius: 12,
                    backgroundColor: _capitan == id ? Colors.amber : cs.surfaceContainerHighest,
                    child: Text('C', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _capitan == id ? Colors.black : cs.outline)),
                  ),
                ),
              if (titular && _p.arieteActivo)
                IconButton(
                  tooltip: tr('Ariete (+3 si marca)'),
                  visualDensity: VisualDensity.compact,
                  onPressed: bloqueada ? null : () => setState(() => _ariete = _ariete == id ? null : id),
                  icon: CircleAvatar(
                    radius: 12,
                    backgroundColor: _ariete == id ? Colors.deepOrange : cs.surfaceContainerHighest,
                    child: Text('A', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _ariete == id ? Colors.black : cs.outline)),
                  ),
                ),
              const SizedBox(width: 4),
              // Estado claro: Titular / Banquillo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: titular ? cs.primary : Colors.transparent,
                  border: Border.all(color: titular ? cs.primary : cs.outline),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(tr(titular ? 'Titular' : 'Banquillo'),
                    style: t.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: titular ? cs.onPrimary : cs.onSurfaceVariant)),
              ),
            ]),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(bloqueada ? Icons.lock : Icons.lock_open, size: 20, color: bloqueada ? cs.error : cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(trf('Alineación · {f}', {'f': fechaHora(widget.partido.fechaHora)}), style: t.titleMedium)),
          ]),
          const SizedBox(height: 2),
          Text(_cuentaAtras(), style: t.bodySmall),
          const SizedBox(height: 10),
          // Contador grande: cuántos titulares llevo
          Row(children: [
            Text('${s.length}/$_tam', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: s.length == _tam ? cs.primary : null)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                bloqueada
                    ? tr('La alineación ya está cerrada.')
                    : trf('Toca un jugador para ponerlo de titular o mandarlo al banquillo. Elige {n} titulares.', {'n': _tam}),
                style: t.bodySmall,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (widget.plantilla.isEmpty) const Tx('Ficha jugadores para poder alinearlos.'),
          for (final id in s.keys) Padding(padding: const EdgeInsets.only(bottom: 4), child: fila(id, titular: true)),
          if (banquillo.isNotEmpty) ...[
            const Divider(height: 16),
            Row(children: [
              const Icon(Icons.event_seat_outlined, size: 18),
              const SizedBox(width: 6),
              Tx('Banquillo', style: t.labelLarge),
            ]),
            if (_p.suplentes > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                    trf('Si un titular no juega, entra el primero del banquillo que sí juegue (hasta {n}).', {'n': _p.suplentes}),
                    style: t.bodySmall),
              ),
            for (final id in banquillo) Padding(padding: const EdgeInsets.only(bottom: 4), child: fila(id, titular: false)),
          ],
          for (final j in noAlineables)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(trf('{n}: cedido a otro mánager esta jornada', {'n': nombre(j.jugadorId)}), style: t.bodySmall),
            ),
          if (errorRoles != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr(errorRoles), style: t.bodySmall?.copyWith(color: cs.error)),
            ),
          if (bonus.isNotEmpty) ...[
            const SizedBox(height: 12),
            LeyendaBonusRoles(bonus: bonus),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: bloqueada || !_cambiada(resumen) || _guardando || errorRoles != null ? null : () => _guardar(resumen),
              icon: _guardando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Tx('Guardar alineación'),
            ),
          ),
          if (!bloqueada && _guardada.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Tx('Si no guardas ninguna, se repetirá la del partido anterior.', style: t.bodySmall),
            ),
        ]),
      ),
    );
  }
}
