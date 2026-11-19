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

  @override
  void dispose() {
    _precio.dispose();
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
        'modo_cobro': _modoCobro,
        'precio_invitado': precio,
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
      if (l.precioInvitado != null) _precio.text = l.precioInvitado!.toStringAsFixed(2);
    }
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Convocatoria y cobro')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Lista de espera', style: t.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Los fijos entran solos en cada partido. Cuando un fijo marca "No voy", entra automáticamente '
          'el primero de la lista de espera.',
        ),
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
        FilledButton(
          onPressed: _guardando ? null : () => _guardar(l.id),
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ]),
    );
  }
}
