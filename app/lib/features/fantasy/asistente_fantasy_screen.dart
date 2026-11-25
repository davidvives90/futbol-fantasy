import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/idioma.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';
import '../../data/repos/ligas_repo.dart';

/// Asistente de configuración del Fantasy (Fase 2, 0054): economía, copias, inicio, alineaciones y temporada.
/// Todo se guarda de una vez al final. El valor base reescala todo el dinero de la liga.
class AsistenteFantasyScreen extends ConsumerStatefulWidget {
  const AsistenteFantasyScreen({super.key});

  @override
  ConsumerState<AsistenteFantasyScreen> createState() => _AsistenteFantasyScreenState();
}

class _AsistenteFantasyScreenState extends ConsumerState<AsistenteFantasyScreen> {
  int _paso = 0;
  bool _cargado = false, _guardando = false;

  // Economía
  final _base = TextEditingController();
  final _presupuesto = TextEditingController();
  final _ingreso = TextEditingController();
  final _prima = TextEditingController();
  bool _presupuestoAuto = true, _primaActiva = false;
  // Copias y cláusulas
  String _modoCopias = 'clasico';
  bool _inflacion = false;
  double _clausulaPct = 1.5;
  // Inicio
  String _modoInicio = 'reparto';
  String _subastaTipo = 'abierta';
  int _subastaLote = 1, _subastaHoras = 24;
  TimeOfDay _subastaHora = const TimeOfDay(hour: 10, minute: 0);
  bool _autoFichaje = true;
  // Alineaciones
  String _modoAlineacion = 'tactico';
  int _suplentes = 1;
  bool _capitan = true, _ariete = true;
  // Temporada
  String _herencia = 'ninguna';

  static String _n(num v) => (v % 1 == 0 ? v.toInt().toString() : v.toString()).replaceAll('.', ',');
  static double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _rellenar(Liga l) {
    if (_cargado) return;
    _cargado = true;
    final p = l.fantasy;
    _base.text = _n(p.valorBase);
    _presupuestoAuto = p.presupuestoFijo == null;
    _presupuesto.text = _n(p.presupuestoFijo ?? _auto(l, p.valorBase));
    _ingreso.text = _n(p.ingresoPorPunto);
    _primaActiva = p.primaInversa > 0;
    _prima.text = _n(p.primaInversa > 0 ? p.primaInversa : p.valorBase / 10);
    _modoCopias = p.modoCopias;
    _inflacion = p.inflacionEscasez;
    _clausulaPct = p.clausulaPct;
    _modoInicio = p.modoInicio;
    _subastaTipo = p.subastaTipo;
    _subastaLote = p.subastaLote;
    _subastaHoras = p.subastaHoras;
    final hm = p.subastaHora.split(':');
    _subastaHora = TimeOfDay(hour: int.tryParse(hm.first) ?? 10, minute: int.tryParse(hm.last) ?? 0);
    _autoFichaje = p.autoFichaje;
    _modoAlineacion = p.modoAlineacion;
    _suplentes = p.suplentes;
    _capitan = p.capitanActivo;
    _ariete = p.arieteActivo;
    _herencia = p.herenciaTemporada;
  }

  static double _auto(Liga l, double base) => l.jugadoresPorEquipo * base + (base / 5 * 100).round() / 100;

  @override
  void dispose() {
    for (final c in [_base, _presupuesto, _ingreso, _prima]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar(MiLiga mi) async {
    final l = mi.liga;
    final base = _num(_base);
    if (base == null || base < 1 || base > 500) {
      mostrarError(context, tr('El valor base va de 1 a 500 M'));
      setState(() => _paso = 0);
      return;
    }
    final presupuesto = _num(_presupuesto);
    if (!_presupuestoAuto && (presupuesto == null || presupuesto <= 0)) {
      mostrarError(context, tr('Pon un presupuesto mayor que 0'));
      setState(() => _paso = 0);
      return;
    }
    setState(() => _guardando = true);
    final ok = await ejecutar(context, () async {
      // Primero la escala: multiplica todo el dinero de la liga (también el presupuesto fijo guardado)
      if ((base - l.fantasy.valorBase).abs() > 0.001) await FantasyRepo.cambiarEscala(l.id, base);
      await LigasRepo.actualizarLiga(l.id, {
        'presupuesto_fijo': _presupuestoAuto ? null : presupuesto,
        'ingreso_por_punto': _num(_ingreso) ?? l.fantasy.ingresoPorPunto,
        'prima_inversa': _primaActiva ? (_num(_prima) ?? 0) : 0,
        'modo_copias': _modoCopias,
        'inflacion_escasez': _inflacion,
        'clausula_pct': _clausulaPct,
        'modo_inicio': _modoInicio,
        'subasta_tipo': _subastaTipo,
        'subasta_lote': _subastaLote,
        'subasta_horas': _subastaHoras,
        'subasta_hora': '${_subastaHora.hour.toString().padLeft(2, '0')}:${_subastaHora.minute.toString().padLeft(2, '0')}',
        'auto_fichaje': _autoFichaje,
        'modo_alineacion': _modoAlineacion,
        'suplentes': _suplentes,
        'capitan_activo': _capitan,
        'ariete_activo': _ariete,
        'herencia_temporada': _herencia,
      });
    }, ok: tr('Fantasy configurado'));
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      refrescarLigas(ref);
      Navigator.of(context).maybePop();
    }
  }

  Widget _radio<T>(T valor, T grupo, String titulo, String texto, ValueChanged<T> on) => RadioListTile<T>(
        contentPadding: EdgeInsets.zero,
        value: valor,
        groupValue: grupo,
        title: Tx(titulo),
        subtitle: Tx(texto),
        onChanged: (v) => setState(() => on(v as T)),
      );

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    _rellenar(mi.liga);
    final l = mi.liga;
    final t = Theme.of(context).textTheme;
    final base = _num(_base) ?? l.fantasy.valorBase;
    final miembros = ref.watch(miembrosPorIdProvider(l.id)).values.where((m) => m.estado == EstadoMiembro.activo).length;
    final yaEmpezado = l.fantasy.presupuestoInicial != null;

    final pasos = <Step>[
      Step(
        title: const Tx('Economía'),
        subtitle: Text('${_n(base)} M · ${_presupuestoAuto ? millones(_auto(l, base)) : millones(_num(_presupuesto))}'),
        isActive: _paso >= 0,
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _base,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: tr('Valor de un jugador medio (M)'),
              helperText: tr('50 M por defecto. Si lo cambias, todo el dinero de la liga se multiplica en proporción.'),
              helperMaxLines: 3,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Presupuesto automático'),
            subtitle: Text(trf('{n} jugadores × {b} M + margen = {p}',
                {'n': l.jugadoresPorEquipo, 'b': _n(base), 'p': millones(_auto(l, base))})),
            value: _presupuestoAuto,
            onChanged: (v) => setState(() => _presupuestoAuto = v),
          ),
          if (!_presupuestoAuto)
            TextField(
              controller: _presupuesto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(labelText: tr('Presupuesto inicial (M)')),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _ingreso,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: tr('Prima por punto (M)'),
              helperText: tr('Lo que gana el mánager por cada punto de la jornada. 0,5 = 500.000 € por punto.'),
              helperMaxLines: 2,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Prima inversa'),
            subtitle: const Tx('Ayuda a los últimos: el último de la jornada cobra el extra entero; el primero, nada.'),
            value: _primaActiva,
            onChanged: (v) => setState(() => _primaActiva = v),
          ),
          if (_primaActiva)
            TextField(
              controller: _prima,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(labelText: tr('Extra para el último (M)')),
            ),
        ]),
      ),
      Step(
        title: const Tx('Copias y cláusulas'),
        subtitle: Text(trf('{c} copias por jugador ahora', {'c': l.fantasy.copiasPorJugador})),
        isActive: _paso >= 1,
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Tx('Las copias se calculan solas: siempre hay suficientes para que cada mánager tenga la alineación '
              'completa y un reserva. Un mánager no puede tener dos copias del mismo jugador.', style: t.bodySmall),
          const SizedBox(height: 8),
          _radio('clasico', _modoCopias, 'Copias iguales', 'Todas las copias valen y puntúan lo mismo.', (v) => _modoCopias = v),
          _radio('rareza', _modoCopias, 'Ediciones (rareza)',
              'Copia #1 Única: ×1,25 pts y ×1,5 precio. #2-#3 Titular: ×1,10 y ×1,2. El resto, Base.', (v) => _modoCopias = v),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Inflación por escasez'),
            subtitle: const Tx('Cada copia que se ficha encarece un 10 % la siguiente libre.'),
            value: _inflacion,
            onChanged: (v) => setState(() => _inflacion = v),
          ),
          const SizedBox(height: 8),
          Text(trf('Cláusula al fichar: {p} % de lo pagado', {'p': (_clausulaPct * 100).round()}), style: t.titleSmall),
          Slider(
            value: _clausulaPct,
            min: 1,
            max: 3,
            divisions: 8,
            label: '${(_clausulaPct * 100).round()} %',
            onChanged: (v) => setState(() => _clausulaPct = v),
          ),
          Tx('El dueño puede subirla (blindaje) pagando una parte de la subida, en la ficha del jugador.', style: t.bodySmall),
        ]),
      ),
      Step(
        title: const Tx('Inicio de la liga'),
        subtitle: Tx(modosInicioFantasy.firstWhere((m) => m.$1 == _modoInicio).$2),
        isActive: _paso >= 2,
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (yaEmpezado)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Tx('El Fantasy ya ha empezado: el modo de inicio vale para los mánagers nuevos y para cuando '
                  'reinicies o cierres la temporada. La subasta y el draft empiezan cuando los actives.',
                  style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
            ),
          for (final (v, titulo, texto) in modosInicioFantasy) _radio(v, _modoInicio, titulo, texto, (x) => _modoInicio = x),
          if (_modoInicio == 'subasta') ...[
            const Divider(),
            Tx('Subasta diaria', style: t.titleSmall),
            _radio('abierta', _subastaTipo, 'Abierta', 'Todos ven la mejor puja. Si pujas al final, se alarga 2 min.',
                (v) => _subastaTipo = v),
            _radio('ciega', _subastaTipo, 'Ciega', 'Nadie ve las pujas hasta que cierra.', (v) => _subastaTipo = v),
            Row(children: [
              Expanded(child: Tx('Jugadores al día', style: t.bodyMedium)),
              IconButton(
                  onPressed: _subastaLote > 1 ? () => setState(() => _subastaLote--) : null,
                  icon: const Icon(Icons.remove_circle_outline)),
              Text('$_subastaLote', style: t.titleMedium),
              IconButton(
                  onPressed: _subastaLote < 10 ? () => setState(() => _subastaLote++) : null,
                  icon: const Icon(Icons.add_circle_outline)),
            ]),
            Row(children: [
              Expanded(child: Tx('Duración (horas)', style: t.bodyMedium)),
              DropdownButton<int>(
                value: _subastaHoras,
                items: [for (final h in const [2, 6, 12, 24, 48]) DropdownMenuItem(value: h, child: Text('$h h'))],
                onChanged: (v) => setState(() => _subastaHoras = v ?? 24),
              ),
            ]),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Tx('Hora de salida'),
              trailing: Text(_subastaHora.format(context)),
              onTap: () async {
                final h = await showTimePicker(context: context, initialTime: _subastaHora);
                if (h != null) setState(() => _subastaHora = h);
              },
            ),
          ],
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Permitir ficharse a uno mismo'),
            value: _autoFichaje,
            onChanged: (v) => setState(() => _autoFichaje = v),
          ),
          Text(trf('Con {n} jugadores en la liga.', {'n': miembros}), style: t.bodySmall),
        ]),
      ),
      Step(
        title: const Tx('Alineaciones'),
        subtitle: Tx(_modoAlineacion == 'tactico' ? 'Táctica por posiciones' : 'Libre'),
        isActive: _paso >= 3,
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _radio('tactico', _modoAlineacion, 'Táctica por posiciones',
              'Un portero y, con 4 o más, al menos un defensa y un delantero.', (v) => _modoAlineacion = v),
          _radio('libre', _modoAlineacion, 'Libre', 'Cualquier jugador en cualquier puesto, sin portero obligatorio.',
              (v) => _modoAlineacion = v),
          Tx('Se puede alinear con menos jugadores si no tienes más: los huecos puntúan 0.', style: t.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Tx('Suplentes que entran solos', style: t.bodyMedium)),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('0')),
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
              ],
              selected: {_suplentes},
              onSelectionChanged: (s) => setState(() => _suplentes = s.first),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Capitán (puntos ×2)'),
            value: _capitan,
            onChanged: (v) => setState(() => _capitan = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Ariete (+3 si marca)'),
            value: _ariete,
            onChanged: (v) => setState(() => _ariete = v),
          ),
        ]),
      ),
      Step(
        title: const Tx('Al cerrar la temporada'),
        subtitle: Tx(herenciasTemporada.firstWhere((h) => h.$1 == _herencia).$2),
        isActive: _paso >= 4,
        content: Column(children: [
          for (final (v, titulo, texto) in herenciasTemporada) _radio(v, _herencia, titulo, texto, (x) => _herencia = x),
          Tx('Se puede cambiar en el momento de cerrar la temporada.', style: t.bodySmall),
        ]),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Tx('Asistente Fantasy')),
      body: Stepper(
        currentStep: _paso,
        onStepTapped: (i) => setState(() => _paso = i),
        onStepContinue: () => _paso < pasos.length - 1 ? setState(() => _paso++) : _guardar(mi),
        onStepCancel: _paso > 0 ? () => setState(() => _paso--) : null,
        controlsBuilder: (c, d) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            FilledButton(
              onPressed: _guardando ? null : d.onStepContinue,
              child: Text(_paso == pasos.length - 1 ? tr('Guardar') : tr('Siguiente')),
            ),
            const SizedBox(width: 8),
            if (_paso > 0) TextButton(onPressed: d.onStepCancel, child: const Tx('Atrás')),
          ]),
        ),
        steps: pasos,
      ),
    );
  }
}
