import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';

final temporadasProvider = FutureProvider.autoDispose.family<List<Temporada>, String>(
  (ref, ligaId) => PartidosRepo.temporadas(ligaId),
);

final _fmtDia = DateFormat("EEE d MMM yyyy", 'es');
final _fmtMes = DateFormat("MMM yyyy", 'es');

/// Programar los partidos de una temporada (v0.3): p. ej. todos los lunes a las 21:00 de septiembre a junio.
class TemporadaScreen extends ConsumerStatefulWidget {
  const TemporadaScreen({super.key});

  @override
  ConsumerState<TemporadaScreen> createState() => _TemporadaScreenState();
}

class _TemporadaScreenState extends ConsumerState<TemporadaScreen> {
  final _nombre = TextEditingController();
  final _coste = TextEditingController(text: '0');
  late DateTime _desde;
  late DateTime _hasta;
  final _dias = <int>{1}; // 1 = lunes
  TimeOfDay _hora = const TimeOfDay(hour: 21, minute: 0);
  bool _horaFija = true;
  final _excluir = <DateTime>{};
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _desde = DateTime(hoy.year, hoy.month, hoy.day);
    // Por defecto, hasta el 30 de junio siguiente (temporada de septiembre a junio).
    _hasta = DateTime(hoy.month > 6 ? hoy.year + 1 : hoy.year, 6, 30);
  }

  @override
  void dispose() {
    _nombre.dispose();
    _coste.dispose();
    super.dispose();
  }

  static DateTime _soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Mismo cálculo que hace el backend: cada día entre desde y hasta cuyo día de la semana esté marcado,
  /// salvo las fechas excluidas y las anteriores a hoy.
  List<DateTime> _fechas() {
    final r = <DateTime>[];
    final hoy = _soloDia(DateTime.now());
    for (var d = _soloDia(_desde); !d.isAfter(_hasta); d = DateTime(d.year, d.month, d.day + 1)) {
      if (!_dias.contains(d.weekday)) continue;
      if (d.isBefore(hoy)) continue;
      if (_excluir.contains(d)) continue;
      r.add(d);
    }
    return r;
  }

  String get _horaTexto => '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}';

  Future<void> _elegirFecha({required bool desde}) async {
    final r = await showDatePicker(
      context: context,
      initialDate: desde ? _desde : _hasta,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (r == null) return;
    setState(() {
      if (desde) {
        _desde = r;
        if (_hasta.isBefore(_desde)) _hasta = _desde;
      } else {
        _hasta = r;
      }
    });
  }

  Future<void> _anadirExcluida() async {
    // La fecha inicial del selector tiene que ser un día de partido (si no, el selector falla).
    final candidatas = _fechas();
    if (candidatas.isEmpty) {
      mostrarError(context, 'No hay partidos en esas fechas');
      return;
    }
    final r = await showDatePicker(
      context: context,
      helpText: 'Fecha sin partido (festivo, vacaciones…)',
      initialDate: candidatas.first,
      firstDate: candidatas.first,
      lastDate: _hasta,
      selectableDayPredicate: (d) => _dias.contains(d.weekday),
    );
    if (r != null) setState(() => _excluir.add(_soloDia(r)));
  }

  Future<void> _programar(String ligaId, List<DateTime> fechas) async {
    final coste = double.tryParse(_coste.text.trim().replaceAll(',', '.')) ?? 0;
    if (!await confirmar(
      context,
      'Programar ${fechas.length} partidos',
      'Se crearán ${fechas.length} partidos los ${_dias.map((d) => nombresDias[d - 1]).join(', ')} a las $_horaTexto'
          '${_horaFija ? '' : ' (hora por confirmar cada semana)'}. '
          'Los fijos quedarán apuntados en todos.',
      accion: 'Programar',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _guardando = true);
    var creados = 0;
    final ok = await ejecutar(context, () async {
      creados = await PartidosRepo.programarTemporada(
        ligaId,
        desde: _desde,
        hasta: _hasta,
        diasSemana: _dias.toList()..sort(),
        hora: _horaTexto,
        horaFija: _horaFija,
        coste: coste,
        excluir: _excluir.toList()..sort(),
        nombre: _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
      );
    });
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      mostrarOk(context, 'Creados $creados partidos');
      ref.invalidate(partidosProvider(ligaId));
      ref.invalidate(temporadasProvider(ligaId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final fechas = _fechas();
    final t = Theme.of(context).textTheme;
    final temporadas = ref.watch(temporadasProvider(mi.liga.id));

    return Scaffold(
      appBar: AppBar(title: const Tx('Programar temporada')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _nombre,
          decoration: const InputDecoration(labelText: 'Nombre (opcional)', hintText: 'Temporada 2026-27'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('Desde ${fechaCorta(_desde)}'),
              onPressed: () => _elegirFecha(desde: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('Hasta ${fechaCorta(_hasta)}'),
              onPressed: () => _elegirFecha(desde: false),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Días de la semana', style: t.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(
              label: Text(nombresDiasCortos[d - 1]),
              selected: _dias.contains(d),
              onSelected: (v) => setState(() => v ? _dias.add(d) : _dias.remove(d)),
            ),
        ]),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text('Hora: $_horaTexto'),
          trailing: const Icon(Icons.edit),
          onTap: () async {
            final r = await showTimePicker(context: context, initialTime: _hora);
            if (r != null) setState(() => _hora = r);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _horaFija,
          onChanged: (v) => setState(() => _horaFija = v),
          title: Text(_horaFija ? 'Hora fija' : 'Hora variable'),
          subtitle: Text(_horaFija
              ? 'Todos los partidos a la misma hora, ya confirmada.'
              : 'Se crean con hora tentativa y el admin la confirma cada semana.'),
        ),
        TextField(
          controller: _coste,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Coste por partido',
            suffixText: '€',
            helperText: mi.liga.facturaMensual ? 'Con factura mensual puedes dejarlo en 0.' : null,
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Fechas sin partido (${_excluir.length})', style: t.titleSmall)),
          TextButton.icon(onPressed: _anadirExcluida, icon: const Icon(Icons.add), label: const Tx('Añadir')),
        ]),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in (_excluir.toList()..sort()))
            InputChip(label: Text(fechaCorta(d)), onDeleted: () => setState(() => _excluir.remove(d))),
        ]),
        const Divider(height: 32),
        Text('Vista previa: ${fechas.length} partidos', style: t.titleMedium),
        if (fechas.length > 120)
          Text('Máximo 120 partidos por temporada: acorta las fechas.',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 4),
        for (final d in fechas.take(6)) Text('• ${_fmtDia.format(d)} · $_horaTexto${_horaFija ? '' : ' (por confirmar)'}'),
        if (fechas.length > 6) Text('… y ${fechas.length - 6} más hasta ${_fmtDia.format(fechas.last)}'),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.event_repeat),
          label: Text(_guardando ? 'Programando…' : 'Programar ${fechas.length} partidos'),
          onPressed: _guardando || fechas.isEmpty || fechas.length > 120 || _dias.isEmpty
              ? null
              : () => _programar(mi.liga.id, fechas),
        ),
        const Divider(height: 40),
        Text('Temporadas programadas', style: t.titleMedium),
        temporadas.when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Cargando()),
          error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(temporadasProvider(mi.liga.id))),
          data: (lista) => lista.isEmpty
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aún no hay ninguna.'))
              : Column(children: [
                  for (final tp in lista)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.date_range),
                      title: Text(tp.nombre ?? '${_fmtMes.format(tp.desde)} – ${_fmtMes.format(tp.hasta)}'),
                      subtitle: Text(
                        '${tp.diasSemana.map((d) => nombresDias[d >= 1 && d <= 7 ? d - 1 : 0]).join(', ')} · '
                        '${tp.hora.length >= 5 ? tp.hora.substring(0, 5) : tp.hora}'
                        '${tp.horaFija ? '' : ' (variable)'}',
                      ),
                      trailing: TextButton(
                        style: AppButtons.peligroTexto(context),
                        child: const Text('Cancelar futuros'),
                        onPressed: () async {
                          if (!await confirmar(
                            context,
                            'Cancelar partidos futuros',
                            'Se cancelarán los partidos de esta temporada que aún no se han jugado. '
                                'Los ya jugados no se tocan.',
                            accion: 'Cancelar partidos',
                            tipo: TipoConfirmacion.peligro,
                          )) {
                            return;
                          }
                          if (!context.mounted) return;
                          final ok = await ejecutar(context, () => PartidosRepo.cancelarTemporada(tp.id),
                              ok: 'Partidos cancelados');
                          if (ok) {
                            ref.invalidate(partidosProvider(mi.liga.id));
                            ref.invalidate(temporadasProvider(mi.liga.id));
                          }
                        },
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}
