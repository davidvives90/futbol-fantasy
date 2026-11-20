import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
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
  bool _apertura = true;
  int _duracion = 60, _horasApertura = 2, _horasReserva = 24;
  String _recordatorio = 'mensual';
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
        'modo_convocatoria': _apertura ? 'apertura' : 'clasica',
        'duracion_partido_min': _duracion,
        'horas_apertura_convocatoria': _horasApertura,
        'horas_reserva_fijos': _horasReserva,
        'modo_cobro': _modoCobro,
        'precio_invitado': precio,
        'recordatorio_deudas': _recordatorio,
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
      _apertura = l.conApertura;
      _duracion = l.duracionPartidoMin;
      _horasApertura = l.horasAperturaConvocatoria;
      _horasReserva = l.horasReservaFijos;
      if (l.precioInvitado != null) _precio.text = l.precioInvitado!.toStringAsFixed(2);
      _recordatorio = l.recordatorioDeudas;
      _bizum.text = l.bizumTelefono ?? '';
    }
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Convocatoria y cobro')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Apertura de la convocatoria', style: t.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _apertura,
          onChanged: (v) => setState(() => _apertura = v),
          title: const Text('Convocatoria vacía hasta que se abre'),
          subtitle: Text(_apertura
              ? 'Se abre después del partido anterior y todos, también los fijos, pulsan «Voy».'
              : 'Clásica: los fijos entran solos en cada partido nada más crearlo.'),
        ),
        if (_apertura) ...[
          _Selector(
            titulo: 'Duración del partido',
            valor: _duracion,
            opciones: const [45, 60, 75, 90, 120],
            texto: (v) => v % 60 == 0 ? '${v ~/ 60} h' : '${v ~/ 60} h ${v % 60} min',
            onCambio: (v) => setState(() => _duracion = v),
          ),
          _Selector(
            titulo: 'Se abre después de acabar el anterior',
            valor: _horasApertura,
            opciones: const [0, 1, 2, 3, 6, 12, 24],
            texto: (v) => v == 0 ? 'Al acabar' : '$v h',
            onCambio: (v) => setState(() => _horasApertura = v),
          ),
          _Selector(
            titulo: 'Plaza guardada a los fijos hasta',
            valor: _horasReserva,
            opciones: const [0, 12, 24, 48, 72],
            texto: (v) => v == 0 ? 'Sin reserva' : '$v h antes',
            onCambio: (v) => setState(() => _horasReserva = v),
          ),
        ],
        const Divider(height: 32),
        Text('Lista de espera', style: t.titleMedium),
        const SizedBox(height: 4),
        Text(_apertura
            ? 'Cuando no queda plaza (sin contar las guardadas a fijos), los que pulsan «Voy» esperan aquí. '
                'Si alguien se da de baja o se acaba la reserva de los fijos, entra el primero.'
            : 'Los fijos entran solos en cada partido. Cuando un fijo marca "No voy", entra automáticamente '
                'el primero de la lista de espera.'),
        RadioListTile<String>(
          value: 'prioridad',
          groupValue: _ordenEspera,
          onChanged: (v) => setState(() => _ordenEspera = v!),
          title: const Text('Por prioridad'),
          subtitle: const Text('Primero los fijos que vuelven, luego reservas y después invitados; '
              'dentro de cada grupo, por orden de apuntarse.'),
        ),
        RadioListTile<String>(
          value: 'anotacion',
          groupValue: _ordenEspera,
          onChanged: (v) => setState(() => _ordenEspera = v!),
          title: const Text('Por orden de apuntarse'),
          subtitle: const Text('El primero que se apunta a la espera, el primero que entra.'),
        ),
        const Divider(height: 32),
        Text('Cobro', style: t.titleMedium),
        RadioListTile<String>(
          value: 'por_partido',
          groupValue: _modoCobro,
          onChanged: (v) => setState(() => _modoCobro = v!),
          title: const Text('Por partido'),
          subtitle: const Text('El coste de cada partido se reparte entre los que juegan ese día.'),
        ),
        RadioListTile<String>(
          value: 'factura_mensual',
          groupValue: _modoCobro,
          onChanged: (v) => setState(() => _modoCobro = v!),
          title: const Text('Factura mensual'),
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
              decoration: const InputDecoration(labelText: 'Precio por partido', suffixText: '€'),
            ),
          ),
        const SizedBox(height: 24),
        Text('Pagos', style: t.titleMedium),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _bizum,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Teléfono para Bizum (opcional)',
              helperText: 'Los jugadores verán «Pagar con Bizum» con este número, el importe y el concepto',
            ),
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Recordatorio automático a los que deben'),
          subtitle: const Text('Aviso con el importe que debe cada uno (entre las 10:00 y las 21:00)'),
          trailing: DropdownButton<String>(
            value: _recordatorio,
            items: const [
              DropdownMenuItem(value: 'nunca', child: Text('Nunca')),
              DropdownMenuItem(value: 'semanal', child: Text('Semanal')),
              DropdownMenuItem(value: 'mensual', child: Text('Mensual')),
              DropdownMenuItem(value: 'trimestral', child: Text('Trimestral')),
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
