import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';
import 'fantasy_providers.dart';
import 'widgets_fantasy.dart';

/// Alineación del próximo partido dibujada sobre un campo: 1 portero y el resto defensa/medio/delantero.
/// Los roles solo existen en el Fantasy (en el partido real todos rotan); si la liga tiene `bonus_roles`,
/// cada rol suma un pequeño bonus al mánager que lo alinea.
class AlineacionCampo extends ConsumerStatefulWidget {
  const AlineacionCampo({super.key, required this.mi, required this.partido, required this.plantilla});
  final MiLiga mi;
  final Partido partido;
  final List<JugadorPlantilla> plantilla;

  @override
  ConsumerState<AlineacionCampo> createState() => _AlineacionCampoState();
}

class _AlineacionCampoState extends ConsumerState<AlineacionCampo> {
  /// Jugador → rol, en orden de inserción. null = aún no cargada.
  Map<String, RolAlineacion>? _sel;
  Map<String, RolAlineacion> _guardada = {};
  // 0054: capitán (×2), ariete (+3 si marca) y suplentes que entran solos si un titular no juega
  String? _capitan, _ariete, _capitanG, _arieteG;
  List<String> _suplentes = [], _suplentesG = [];
  bool _guardando = false;
  Timer? _timer;

  int get _tam => widget.partido.plazas ~/ widget.partido.numEquipos;
  DateTime get _cierre => widget.mi.liga.fantasy.cierre(widget.partido.fechaHora);
  bool get _bloqueada => !DateTime.now().isBefore(_cierre);

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant AlineacionCampo old) {
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
        _suplentes = [..._suplentesG];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sel = {});
      mostrarError(context, e);
    }
  }

  int get _porteros => _sel?.values.where((r) => r == RolAlineacion.POR).length ?? 0;

  bool get _tactica => widget.mi.liga.fantasy.tactica;

  String? get _errorRoles {
    final s = _sel;
    if (s == null || s.isEmpty) return null;
    if (!_tactica) return null;
    if (s.length >= 4 &&
        (!s.values.contains(RolAlineacion.DEF) || !s.values.contains(RolAlineacion.DEL)) &&
        _porteros == 1) {
      return 'Con 4 o más jugadores, la alineación táctica lleva al menos un defensa y un delantero.';
    }
    if (_porteros == 0) return 'Elige un portero (toca un jugador del campo y márcalo como POR).';
    if (_porteros > 1) return 'Solo puede haber un portero.';
    return null;
  }

  bool get _cambiada {
    final s = _sel;
    if (s == null) return false;
    if (s.length != _guardada.length) return true;
    if (_capitan != _capitanG || _ariete != _arieteG) return true;
    if (_suplentes.join(',') != _suplentesG.join(',')) return true;
    return s.entries.any((e) => _guardada[e.key] != e.value);
  }

  Future<void> _guardar() async {
    final s = _sel!;
    setState(() => _guardando = true);
    final ok = await ejecutar(
      context,
      () => FantasyRepo.guardarAlineacion(widget.partido.id, s.keys.toList(), s.values.toList(),
          capitan: s.containsKey(_capitan) ? _capitan : null,
          ariete: s.containsKey(_ariete) ? _ariete : null,
          suplentes: _suplentes),
      ok: 'Alineación guardada',
    );
    if (!mounted) return;
    setState(() {
      _guardando = false;
      if (ok) {
        _guardada = {...s};
        _capitanG = _capitan;
        _arieteG = _ariete;
        _suplentesG = [..._suplentes];
      }
    });
  }

  void _anadir(String jugadorId) {
    final s = _sel!;
    if (s.length >= _tam) {
      // Titulares completos: va al banquillo si queda sitio
      if (_suplentes.length < widget.mi.liga.fantasy.suplentes) {
        setState(() => _suplentes.add(jugadorId));
        return;
      }
      mostrarError(context, trf('Máximo {n} titulares y {s} suplentes', {'n': _tam, 's': widget.mi.liga.fantasy.suplentes}));
      return;
    }
    // El primero que entra va de portero (en la táctica); los demás de medio (se cambia tocándolos en el campo).
    setState(() => s[jugadorId] = _tactica && _porteros == 0 ? RolAlineacion.POR : RolAlineacion.MED);
  }

  Future<void> _editar(String jugadorId, String nombre) async {
    final s = _sel!;
    final r = await showModalBottomSheet<Object>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(nombre, style: Theme.of(c).textTheme.titleMedium)),
          for (final rol in RolAlineacion.values)
            ListTile(
              leading: Icon(s[jugadorId] == rol ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text('${rol.etiqueta} (${rol.name})'),
              onTap: () => Navigator.pop(c, rol),
            ),
          if (widget.mi.liga.fantasy.capitanActivo)
            ListTile(
              leading: Icon(_capitan == jugadorId ? Icons.check_circle : Icons.copyright_outlined),
              title: const Tx('Capitán (puntos ×2)'),
              onTap: () => Navigator.pop(c, 'capitan'),
            ),
          if (widget.mi.liga.fantasy.arieteActivo)
            ListTile(
              leading: Icon(_ariete == jugadorId ? Icons.check_circle : Icons.sports_soccer),
              title: const Tx('Ariete (+3 si marca)'),
              onTap: () => Navigator.pop(c, 'ariete'),
            ),
          if (widget.mi.liga.fantasy.suplentes > 0)
            ListTile(
              leading: const Icon(Icons.event_seat_outlined),
              title: const Tx('Al banquillo (suplente)'),
              onTap: () => Navigator.pop(c, 'banquillo'),
            ),
          ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: const Tx('Quitar de la alineación'),
            onTap: () => Navigator.pop(c, 'quitar'),
          ),
        ]),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      if (r == 'quitar') {
        s.remove(jugadorId);
        if (_capitan == jugadorId) _capitan = null;
        if (_ariete == jugadorId) _ariete = null;
      } else if (r == 'capitan') {
        _capitan = _capitan == jugadorId ? null : jugadorId;
      } else if (r == 'ariete') {
        _ariete = _ariete == jugadorId ? null : jugadorId;
      } else if (r == 'banquillo') {
        if (_suplentes.length >= widget.mi.liga.fantasy.suplentes) {
          mostrarError(context, tr('El banquillo está lleno: quita antes a un suplente'));
          return;
        }
        s.remove(jugadorId);
        if (_capitan == jugadorId) _capitan = null;
        if (_ariete == jugadorId) _ariete = null;
        _suplentes.add(jugadorId);
      } else if (r is RolAlineacion) {
        // Si se elige un nuevo portero, el anterior pasa a defensa.
        if (r == RolAlineacion.POR) {
          for (final k in s.keys.toList()) {
            if (k != jugadorId && s[k] == RolAlineacion.POR) s[k] = RolAlineacion.DEF;
          }
        }
        s[jugadorId] = r;
      }
    });
  }

  String _cuentaAtras() {
    final d = _cierre.difference(DateTime.now());
    if (d.isNegative) return 'Cerrada desde ${fechaHora(_cierre)}';
    if (d.inDays > 0) return 'Cierra en ${d.inDays} d ${d.inHours % 24} h';
    if (d.inHours > 0) return 'Cierra en ${d.inHours} h ${d.inMinutes % 60} min';
    return 'Cierra en ${d.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final params = widget.mi.liga.fantasy;
    final miembros = ref.watch(miembrosPorIdProvider(widget.mi.liga.id));
    final conv = ref.watch(convocatoriaProvider(widget.partido.id)).valueOrNull ?? const <Inscripcion>[];
    final estado = {for (final i in conv) i.miembroId: i.estado};
    final bonus = params.bonusRoles
        ? ref.watch(reglasRolProvider(widget.mi.liga.id)).valueOrNull ?? const <String, double>{}
        : const <String, double>{};
    final porId = {for (final j in widget.plantilla) j.jugadorId: j};
    final s = _sel;
    final bloqueada = _bloqueada;
    final errorRoles = _errorRoles;

    String nombre(String id) => miembros[id]?.nombre ?? '…';

    Widget fichaEnCampo(String id) {
      final j = porId[id];
      return GestureDetector(
        onTap: bloqueada ? null : () => _editar(id, nombre(id)),
        child: SizedBox(
          width: 72,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              AvatarMiembro(miembros[id], radio: 20, dorsal: true),
              Positioned(right: -4, bottom: -4, child: IconoConvocatoria(estado[id])),
              if (_capitan == id || _ariete == id)
                Positioned(
                  left: -6,
                  top: -6,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: _capitan == id ? Colors.amber : Colors.deepOrange,
                    child: Text(_capitan == id ? 'C' : 'A',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black)),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: Text(
                [nombre(id), if (j?.noHabitual ?? false) '×${params.bonusNoHabitual.toStringAsFixed(1).replaceAll('.', ',')}']
                    .join(' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ]),
        ),
      );
    }

    Widget linea(RolAlineacion rol) {
      final ids = s?.entries.where((e) => e.value == rol).map((e) => e.key).toList() ?? const <String>[];
      return Expanded(
        child: Center(
          child: ids.isEmpty
              ? Text(rol.etiqueta.toUpperCase(),
                  style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1))
              : Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
                  for (final id in ids) fichaEnCampo(id),
                ]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(bloqueada ? Icons.lock : Icons.lock_open, size: 20, color: bloqueada ? cs.error : cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Alineación · ${fechaHora(widget.partido.fechaHora)}', style: t.titleMedium)),
          ]),
          const SizedBox(height: 4),
          Text(
              [
                _cuentaAtras(),
                _tactica ? trf('hasta {n} jugadores, uno de portero', {'n': _tam}) : trf('hasta {n} jugadores', {'n': _tam}),
                if (params.suplentes > 0) trf('{s} suplentes', {'s': params.suplentes}),
              ].join(' · '),
              style: t.bodySmall),
          const SizedBox(height: 12),
          if (s == null)
            const LinearProgressIndicator()
          else ...[
            AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: _CampoPainter(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      linea(RolAlineacion.DEL),
                      linea(RolAlineacion.MED),
                      linea(RolAlineacion.DEF),
                      linea(RolAlineacion.POR),
                    ]),
                  ),
                ),
              ),
            ),
            if (params.suplentes > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.event_seat_outlined, size: 18),
                const SizedBox(width: 6),
                Tx('Banquillo', style: t.labelLarge),
                const SizedBox(width: 8),
                Expanded(
                  child: _suplentes.isEmpty
                      ? Tx('Entran solos si un titular no juega', style: t.bodySmall)
                      : Wrap(spacing: 6, children: [
                          for (final (i, id) in _suplentes.indexed)
                            InputChip(
                              avatar: CircleAvatar(child: Text('${i + 1}')),
                              label: Text(nombre(id)),
                              onDeleted: bloqueada ? null : () => setState(() => _suplentes.remove(id)),
                            ),
                        ]),
                ),
              ]),
            ],
            if (params.capitanActivo || params.arieteActivo)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    [
                      if (params.capitanActivo)
                        _capitan != null && s.containsKey(_capitan) ? 'C: ${nombre(_capitan!)} ×2' : tr('Sin capitán'),
                      if (params.arieteActivo)
                        _ariete != null && s.containsKey(_ariete) ? 'A: ${nombre(_ariete!)} +3' : tr('Sin ariete'),
                    ].join(' · '),
                    style: t.bodySmall),
              ),
            if (errorRoles != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(errorRoles, style: t.bodySmall?.copyWith(color: cs.error)),
              ),
            const SizedBox(height: 12),
            Text(bloqueada ? 'Plantilla' : 'Toca para alinear · toca en el campo para el rol, capitán o ariete',
                style: t.labelLarge),
            const SizedBox(height: 6),
            if (widget.plantilla.isEmpty)
              const Tx('Ficha jugadores para poder alinearlos.')
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final j in widget.plantilla.where((j) => !s.containsKey(j.jugadorId) && !_suplentes.contains(j.jugadorId)))
                  ActionChip(
                    avatar: IconoConvocatoria(estado[j.jugadorId]),
                    label: Text([
                      nombre(j.jugadorId),
                      if (j.cedidaAMi) '(cedido)',
                      if (j.cedidaAOtro) '(cedido a otro)',
                    ].join(' ')),
                    onPressed: bloqueada || !j.alineable ? null : () => _anadir(j.jugadorId),
                  ),
              ]),
            for (final id in s.keys)
              if (estado[id] != EstadoInscripcion.confirmado && estado[id] != EstadoInscripcion.pendiente)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '⚠ ${nombre(id)} '
                    '${switch (estado[id]) {
                      EstadoInscripcion.duda => 'está en duda',
                      EstadoInscripcion.baja => 'se ha dado de baja',
                      EstadoInscripcion.espera => 'es suplente',
                      _ => 'no está apuntado',
                    }}: si no juega, puntúa 0.',
                    style: t.bodySmall?.copyWith(color: cs.error),
                  ),
                ),
            if (bonus.isNotEmpty) ...[
              const SizedBox(height: 12),
              LeyendaBonusRoles(bonus: bonus),
            ] else if (!params.bonusRoles) ...[
              const SizedBox(height: 8),
              Text('En esta liga el rol es solo estético: no da puntos extra.', style: t.bodySmall),
            ],
          ],
          const SizedBox(height: 8),
          Row(children: [
            Text('${s?.length ?? 0}/$_tam', style: t.titleSmall),
            const Spacer(),
            FilledButton.icon(
              onPressed: bloqueada || !_cambiada || _guardando || errorRoles != null ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Tx('Guardar alineación'),
            ),
          ]),
          if (!bloqueada && _guardada.isEmpty)
            Text('Si no guardas ninguna, se repetirá la del partido anterior.', style: t.bodySmall),
        ]),
      ),
    );
  }
}

/// Leyenda de los bonus de rol (claves `rol_*` de reglas_puntuacion).
class LeyendaBonusRoles extends StatelessWidget {
  const LeyendaBonusRoles({super.key, required this.bonus});
  final Map<String, double> bonus;

  static const _textos = <String, String>{
    'rol_por_porteria_cero': 'POR · su equipo no encaja',
    'rol_por_menos_goleado': 'POR · su equipo es el menos goleado',
    'rol_por_encajados_3': 'POR · por cada 3 goles encajados',
    'rol_def_menos_goleado': 'DEF · su equipo es el menos goleado',
    'rol_med_asistencia': 'MED · por cada asistencia',
    'rol_del_gol': 'DEL · por cada gol',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String fmt(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(v % 1 == 0 ? 0 : 1).replaceAll('.', ',')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Bonus por rol (solo para ti)', style: t.labelLarge),
        const SizedBox(height: 4),
        for (final e in _textos.entries)
          if (bonus[e.key] != null && bonus[e.key] != 0)
            Text('${e.value}: ${fmt(bonus[e.key]!)}', style: t.bodySmall),
      ]),
    );
  }
}

/// Césped con las líneas básicas de un campo (vista vertical, portería propia abajo).
class _CampoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cesped = Paint()..color = const Color(0xFF2E7D32);
    final franja = Paint()..color = const Color(0xFF388E3C);
    canvas.drawRect(Offset.zero & size, cesped);
    for (var i = 0; i < 8; i += 2) {
      canvas.drawRect(Rect.fromLTWH(0, h * i / 8, w, h / 8), franja);
    }
    final linea = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const m = 8.0;
    canvas.drawRect(Rect.fromLTWH(m, m, w - 2 * m, h - 2 * m), linea);
    canvas.drawLine(Offset(m, h / 2), Offset(w - m, h / 2), linea);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.15, linea);
    final areaW = w * 0.5, areaH = h * 0.12;
    canvas.drawRect(Rect.fromLTWH((w - areaW) / 2, m, areaW, areaH), linea);
    canvas.drawRect(Rect.fromLTWH((w - areaW) / 2, h - m - areaH, areaW, areaH), linea);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
