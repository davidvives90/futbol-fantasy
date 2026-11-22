import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

/// Ajustes del admin (v0.3): orden de la lista de espera, modo de cobro y precio de reservas/invitados.
class ConvocatoriaCobroScreen extends ConsumerStatefulWidget {
  const ConvocatoriaCobroScreen({super.key});

  @override
  ConsumerState<ConvocatoriaCobroScreen> createState() => _ConvocatoriaCobroScreenState();
}

class _ConvocatoriaCobroScreenState extends ConsumerState<ConvocatoriaCobroScreen> {
  String _ordenEspera = 'prioridad';
  String _modoCobro = 'por_partido';
  bool _precioFijo = true;
  final _precio = TextEditingController(text: '5');
  bool _cargado = false;
  bool _guardando = false;
  String _modo = 'apertura';
  int _duracion = 60, _horasApertura = 2, _horasReserva = 24, _horasTurno = 24, _horasDecision = 24;
  int? _minimo;
  String _recordatorio = 'mensual';
  String _modoEquipos = 'admin';
  int _capitanes = 1;
  final _bizum = TextEditingController();

  @override
  void dispose() {
    _precio.dispose();
    _bizum.dispose();
    super.dispose();
  }

  Future<void> _guardar(String ligaId) async {
    double? precio;
    if (_precioFijo) {
      precio = double.tryParse(_precio.text.trim().replaceAll(',', '.'));
      if (precio == null || precio < 0) {
        mostrarError(context, 'Escribe un precio válido para reservas e invitados');
        return;
      }
    }
    setState(() => _guardando = true);
    final ok = await ejecutar(
      context,
      () => LigasRepo.actualizarLiga(ligaId, {
        'orden_espera': _ordenEspera,
        'modo_convocatoria': _modo,
        'horas_turno': _horasTurno,
        'horas_decision': _horasDecision,
        if (_modo == 'minimo') 'minimo_jugadores': _minimo,
        'duracion_partido_min': _duracion,
        'horas_apertura_convocatoria': _horasApertura,
        'horas_reserva_fijos': _horasReserva,
        'modo_cobro': _modoCobro,
        'precio_invitado': precio,
        'recordatorio_deudas': _recordatorio,
        'modo_equipos': _modoEquipos,
        'capitanes_por_equipo': _capitanes,
        'bizum_telefono': _bizum.text.trim().isEmpty ? null : _bizum.text.trim(),
      }),
      ok: 'Ajustes guardados',
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) refrescarLigas(ref);
  }

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final l = mi.liga;
    if (!_cargado) {
      _cargado = true;
      _ordenEspera = l.ordenEspera;
      _modoCobro = l.modoCobro;
      _precioFijo = l.precioInvitado != null;
      _modo = l.modoConvocatoria;
      _horasTurno = l.horasTurno;
      _horasDecision = l.horasDecision;
      _minimo = l.minimoJugadores;
      _duracion = l.duracionPartidoMin;
      _horasApertura = l.horasAperturaConvocatoria;
      _horasReserva = l.horasReservaFijos;
      if (l.precioInvitado != null) _precio.text = l.precioInvitado!.toStringAsFixed(2);
      _recordatorio = l.recordatorioDeudas;
      _modoEquipos = l.modoEquipos;
      _capitanes = l.capitanesPorEquipo;
      _bizum.text = l.bizumTelefono ?? '';
    }
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Tx('Convocatoria y cobro')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Tx('Cómo se apunta la gente', style: t.titleMedium),
        const SizedBox(height: 4),
        Tx('Elige el modo que mejor encaje con vuestro grupo. Puedes cambiarlo cuando quieras.', style: t.bodySmall),
        const SizedBox(height: 4),
        for (final (v, titulo, sub) in modosConvocatoria)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_modo == v ? Icons.radio_button_checked : Icons.radio_button_off,
                color: _modo == v ? Theme.of(context).colorScheme.primary : null),
            title: Row(children: [
              Flexible(child: Text(tr(titulo))),
              if (v == l.modoConvocatoria) ...[
                const SizedBox(width: 8),
                Tx('Actual', style: t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ],
            ]),
            subtitle: Text(tr(sub)),
            onTap: () => setState(() {
              _modo = v;
              if (v == 'minimo') _minimo ??= (mi.liga.plazas * 0.8).round().clamp(4, 60);
            }),
          ),
        if (_modo == 'apertura' || _modo == 'turnos' || _modo == 'libre' || _modo == 'minimo') ...[
          _Selector(
            titulo: tr('Duración del partido'),
            valor: _duracion,
            opciones: const [45, 60, 75, 90, 120],
            texto: (v) => v % 60 == 0 ? '${v ~/ 60} h' : '${v ~/ 60} h ${v % 60} min',
            onCambio: (v) => setState(() => _duracion = v),
          ),
          _Selector(
            titulo: tr(_modo == 'apertura' || _modo == 'turnos'
                ? 'Se abre después de acabar el anterior'
                : 'Aviso de «convocatoria abierta» tras el anterior'),
            valor: _horasApertura,
            opciones: const [0, 1, 2, 3, 6, 12, 24],
            texto: (v) => v == 0 ? tr('Al acabar') : '$v h',
            onCambio: (v) => setState(() => _horasApertura = v),
          ),
        ],
        if (_modo == 'turnos')
          _Selector(
            titulo: tr('Tiempo entre turnos'),
            valor: _horasTurno,
            opciones: const [1, 2, 6, 12, 24, 48],
            texto: (v) => '$v h',
            onCambio: (v) => setState(() => _horasTurno = v),
          ),
        if (_modo == 'minimo') ...[
          _Selector(
            titulo: tr('Mínimo de jugadores'),
            valor: _minimo ?? mi.liga.plazas,
            opciones: [for (var n = 4; n <= mi.liga.plazas; n += 2) n],
            texto: (v) => '$v',
            onCambio: (v) => setState(() => _minimo = v),
          ),
          _Selector(
            titulo: tr('Se decide antes del partido'),
            valor: _horasDecision,
            opciones: const [2, 4, 6, 12, 24, 48],
            texto: (v) => '$v h',
            onCambio: (v) => setState(() => _horasDecision = v),
          ),
        ],
        const Divider(height: 32),
        Tx('Quién hace los equipos', style: t.titleMedium),
        for (final (v, titulo, sub) in const [
          ('admin', 'El administrador', 'La app le propone equipos equilibrados y él los confirma.'),
          ('automatico', 'La app, automáticamente', 'Equilibrados por nivel en cuanto la lista está cerrada.'),
          ('capitanes', 'Capitanes', 'Se sortean entre los que van; ellos hacen los equipos y los pasan al grupo.'),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_modoEquipos == v ? Icons.radio_button_checked : Icons.radio_button_off,
                color: _modoEquipos == v ? Theme.of(context).colorScheme.primary : null),
            title: Text(tr(titulo)),
            subtitle: Text(tr(sub)),
            onTap: () => setState(() => _modoEquipos = v),
          ),
        if (_modoEquipos == 'capitanes')
          _Selector(
            titulo: 'Capitanes por equipo',
            valor: _capitanes,
            opciones: const [1, 2],
            texto: (v) => '$v',
            onCambio: (v) => setState(() => _capitanes = v),
          ),
        const Divider(height: 32),
        Text('Cobro', style: t.titleMedium),
        RadioListTile<String>(
          value: 'por_partido',
          groupValue: _modoCobro,
          onChanged: (v) => setState(() => _modoCobro = v!),
          title: const Tx('Por partido'),
          subtitle: const Tx('El coste de cada partido se reparte entre los que juegan ese día.'),
        ),
        RadioListTile<String>(
          value: 'factura_mensual',
          groupValue: _modoCobro,
          onChanged: (v) => setState(() => _modoCobro = v!),
          title: const Tx('Factura mensual'),
          subtitle: const Text('Reservas e invitados pagan su precio al jugar. Al llegar la factura del mes, '
              'se resta lo que pagaron y el resto se reparte entre los fijos según los partidos que jugó cada uno.'),
        ),
        const Divider(height: 32),
        Text('Precio para reservas e invitados', style: t.titleMedium),
        SwitchListTile(
          value: _precioFijo,
          onChanged: (v) => setState(() => _precioFijo = v),
          title: Text(_precioFijo ? 'Precio fijo por partido' : 'Precio variable'),
          subtitle: Text(_precioFijo
              ? 'Pagan siempre lo mismo cada partido que juegan.'
              : 'Pagan la misma cuota por partido que los fijos (se calcula al liquidar la factura).'),
        ),
        if (_precioFijo)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _precio,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:  InputDecoration(labelText: tr('Precio por partido'), suffixText: '€'),
            ),
          ),
        const SizedBox(height: 24),
        Tx('Pagos', style: t.titleMedium),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _bizum,
            keyboardType: TextInputType.phone,
            decoration:  InputDecoration(
              labelText: tr('Teléfono para Bizum (opcional)'),
              helperText: tr('Los jugadores verán «Pagar con Bizum» con este número, el importe y el concepto'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Tx('Recordatorio automático a los que deben'),
          subtitle: const Tx('Aviso con el importe que debe cada uno (entre las 10:00 y las 21:00)'),
          trailing: DropdownButton<String>(
            value: _recordatorio,
            items: const [
              DropdownMenuItem(value: 'nunca', child: Tx('Nunca')),
              DropdownMenuItem(value: 'semanal', child: Tx('Semanal')),
              DropdownMenuItem(value: 'mensual', child: Tx('Mensual')),
              DropdownMenuItem(value: 'trimestral', child: Tx('Trimestral')),
            ],
            onChanged: (v) => setState(() => _recordatorio = v ?? _recordatorio),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _guardando ? null : () => _guardar(l.id),
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ]),
    );
  }
}

class _Selector extends StatelessWidget {
  const _Selector({required this.titulo, required this.valor, required this.opciones, required this.texto, required this.onCambio});
  final String titulo;
  final int valor;
  final List<int> opciones;
  final String Function(int) texto;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) {
    final lista = {...opciones, valor}.toList()..sort();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(titulo),
      trailing: DropdownButton<int>(
        value: valor,
        items: [for (final v in lista) DropdownMenuItem(value: v, child: Text(texto(v)))],
        onChanged: (v) => v == null ? null : onCambio(v),
      ),
    );
  }
}
