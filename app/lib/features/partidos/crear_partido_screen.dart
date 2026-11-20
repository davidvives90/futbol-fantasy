import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';

class CrearPartidoScreen extends ConsumerStatefulWidget {
  const CrearPartidoScreen({super.key});

  @override
  ConsumerState<CrearPartidoScreen> createState() => _CrearPartidoScreenState();
}

class _CrearPartidoScreenState extends ConsumerState<CrearPartidoScreen> {
  final _form = GlobalKey<FormState>();
  late DateTime _fecha;
  TimeOfDay _hora = const TimeOfDay(hour: 21, minute: 0);
  bool _horaConfirmada = true;
  late int _plazas;
  late int _numEquipos;
  final _coste = TextEditingController();
  final _maps = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final liga = ref.read(ligaActualProvider)!.liga;
    final hoy = DateTime.now();
    _fecha = DateTime(hoy.year, hoy.month, hoy.day).add(const Duration(days: 7));
    _plazas = liga.plazas;
    _numEquipos = liga.numEquipos;
    if (liga.precioEstimado != null) _coste.text = (liga.precioEstimado! * liga.plazas).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _coste.dispose();
    _maps.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _fecha = d);
  }

  Future<void> _elegirHora() async {
    final h = await showTimePicker(context: context, initialTime: _hora);
    if (h != null) setState(() => _hora = h);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final mi = ref.read(ligaActualProvider)!;
    final fechaHora = DateTime(_fecha.year, _fecha.month, _fecha.day, _hora.hour, _hora.minute);
    setState(() => _guardando = true);
    try {
      final id = await PartidosRepo.crear(
        mi.liga.id,
        fechaHora: fechaHora,
        horaConfirmada: _horaConfirmada,
        plazas: _plazas,
        numEquipos: _numEquipos,
        coste: double.tryParse(_coste.text.replaceAll(',', '.')) ?? 0,
        campoMapsUrl: _maps.text.trim().isEmpty ? null : _maps.text.trim(),
      );
      ref.invalidate(partidosProvider(mi.liga.id));
      if (mounted) context.pushReplacement('/partidos/$id');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liga = ref.watch(ligaActualProvider)!.liga;
    return Scaffold(
      appBar: AppBar(title: const Tx('Nuevo partido')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _elegirFecha,
                icon: const Icon(Icons.calendar_today),
                label: Text(fechaCorta(_fecha)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _elegirHora,
                icon: const Icon(Icons.schedule),
                label: Text(_hora.format(context)),
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Hora confirmada'),
            subtitle: const Tx('Desactívalo si aún falta cerrar la reserva'),
            value: _horaConfirmada,
            onChanged: (v) => setState(() => _horaConfirmada = v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Tx('Plazas')),
            IconButton(onPressed: _plazas > 6 ? () => setState(() => _plazas--) : null, icon: const Icon(Icons.remove)),
            Text('$_plazas', style: Theme.of(context).textTheme.titleLarge),
            IconButton(onPressed: _plazas < 44 ? () => setState(() => _plazas++) : null, icon: const Icon(Icons.add)),
          ]),
          Row(children: [
            const Expanded(child: Tx('Equipos')),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
              ],
              selected: {_numEquipos},
              onSelectionChanged: (s) => setState(() => _numEquipos = s.first),
            ),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            controller: _coste,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:  InputDecoration(labelText: tr('Coste total del campo'), suffixText: '€'),
            validator: (v) {
              final d = double.tryParse((v ?? '').replaceAll(',', '.'));
              return (d == null || d < 0) ? 'Importe no válido' : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _maps,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: tr('Otro campo (enlace de Maps, opcional)'),
              helperText: 'Vacío = ${liga.campoNombre ?? 'el campo de la liga'}',
            ),
            validator: (v) => (v == null || v.trim().isEmpty || esEnlaceMaps(v)) ? null : 'No parece un enlace de Google Maps',
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _guardando ? null : _guardar, child: const Tx('Crear convocatoria')),
        ]),
      ),
    );
  }
}
