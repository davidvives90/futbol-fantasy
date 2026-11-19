import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';

/// Diálogos del mercado 0.2: cambiar cláusula, hacer oferta y ofrecer en cesión.

double? _leerImporte(String texto) => double.tryParse(texto.trim().replaceAll(',', '.'));

String _fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// Nueva cláusula para una ficha propia. Subirla cuesta [ParamsFantasy.costeSubidaClausula] de la subida;
/// bajarla es gratis, con mínimo el valor de mercado. Devuelve el importe elegido o null.
Future<double?> dialogoClausula(
  BuildContext context, {
  required String jugador,
  required ParamsFantasy params,
  required double actual,
  required double precioMercado,
  double? saldo,
}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _DialogoClausula(
        jugador: jugador,
        params: params,
        actual: actual,
        precioMercado: precioMercado,
        saldo: saldo,
      ),
    );

class _DialogoClausula extends StatefulWidget {
  const _DialogoClausula({
    required this.jugador,
    required this.params,
    required this.actual,
    required this.precioMercado,
    this.saldo,
  });
  final String jugador;
  final ParamsFantasy params;
  final double actual, precioMercado;
  final double? saldo;

  @override
  State<_DialogoClausula> createState() => _DialogoClausulaState();
}

class _DialogoClausulaState extends State<_DialogoClausula> {
  late final _c = TextEditingController(text: _fmt(widget.actual));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nueva = _leerImporte(_c.text);
    final pct = (widget.params.costeSubidaClausula * 100).round();
    String? error;
    String info = '';
    if (nueva == null) {
      error = 'Importe no válido';
    } else if (nueva < widget.precioMercado) {
      error = 'Mínimo: el valor de mercado (${millones(widget.precioMercado)})';
    } else {
      final coste = widget.params.costeSubida(widget.actual, nueva);
      if (coste > 0) {
        info = 'Subirla te cuesta el $pct % de la subida: ${millones(coste)}.';
        if (widget.saldo != null && coste > widget.saldo!) error = 'Saldo insuficiente (${millones(widget.saldo)})';
      } else if (nueva < widget.actual) {
        info = 'Bajarla es gratis, pero será más fácil que te lo quiten.';
      }
    }
    return AlertDialog(
      title: Text('Cláusula de ${widget.jugador}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Actual: ${millones(widget.actual)} · valor de mercado ${millones(widget.precioMercado)}'),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: 'Nueva cláusula (M)', errorText: error),
          onChanged: (_) => setState(() {}),
        ),
        if (info.isNotEmpty) ...[const SizedBox(height: 8), Text(info)],
        const SizedBox(height: 8),
        Text('Quien pague la cláusula se lleva la ficha sin que puedas negarte.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: AppButtons.premium(context),
          onPressed: error != null || nueva == null || nueva == widget.actual ? null : () => Navigator.pop(context, nueva),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Oferta libre por una ficha concreta. Devuelve el importe o null.
Future<double?> dialogoOferta(
  BuildContext context, {
  required String jugador,
  required String propietario,
  required double precioMercado,
  double? clausula,
  double? saldo,
  required int horasCaducidad,
}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _DialogoOferta(
        jugador: jugador,
        propietario: propietario,
        precioMercado: precioMercado,
        clausula: clausula,
        saldo: saldo,
        horasCaducidad: horasCaducidad,
      ),
    );

class _DialogoOferta extends StatefulWidget {
  const _DialogoOferta({
    required this.jugador,
    required this.propietario,
    required this.precioMercado,
    this.clausula,
    this.saldo,
    required this.horasCaducidad,
  });
  final String jugador, propietario;
  final double precioMercado;
  final double? clausula, saldo;
  final int horasCaducidad;

  @override
  State<_DialogoOferta> createState() => _DialogoOfertaState();
}

class _DialogoOfertaState extends State<_DialogoOferta> {
  late final _c = TextEditingController(text: _fmt(widget.precioMercado));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _leerImporte(_c.text);
    String? error;
    if (v == null || v <= 0) {
      error = 'Importe no válido';
    } else if (widget.saldo != null && v > widget.saldo!) {
      error = 'Más que tu saldo (${millones(widget.saldo)}): si la acepta, fallará';
    }
    return AlertDialog(
      title: Text('Oferta por ${widget.jugador}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ficha de ${widget.propietario}. Valor ${millones(widget.precioMercado)}'
            '${widget.clausula != null ? ' · cláusula ${millones(widget.clausula)}' : ''}.'),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: 'Tu oferta (M)', errorText: error),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          'El dueño la acepta o la rechaza. Caduca en ${widget.horasCaducidad} h o al cerrarse el mercado. '
          'El dinero no se reserva: se comprueba tu saldo al aceptarla.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: AppButtons.premium(context),
          onPressed: v == null || v <= 0 ? null : () => Navigator.pop(context, v),
          child: const Text('Enviar oferta'),
        ),
      ],
    );
  }
}

/// % de cesión (fracción 0–1) entre el mínimo y el máximo de la liga. Devuelve el % o null.
Future<double?> dialogoCesion(
  BuildContext context, {
  required String jugador,
  required ParamsFantasy params,
  required double precioMercado,
}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _DialogoCesion(jugador: jugador, params: params, precioMercado: precioMercado),
    );

class _DialogoCesion extends StatefulWidget {
  const _DialogoCesion({required this.jugador, required this.params, required this.precioMercado});
  final String jugador;
  final ParamsFantasy params;
  final double precioMercado;

  @override
  State<_DialogoCesion> createState() => _DialogoCesionState();
}

class _DialogoCesionState extends State<_DialogoCesion> {
  late double _pct = ((widget.params.cesionPctMin + widget.params.cesionPctMax) / 2 * 100).roundToDouble() / 100;

  @override
  Widget build(BuildContext context) {
    final min = widget.params.cesionPctMin, max = widget.params.cesionPctMax;
    final divisiones = ((max - min) * 100).round();
    return AlertDialog(
      title: Text('Ceder a ${widget.jugador}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Para el próximo partido. Quien la acepte te paga ese % de su valor '
            '(${millones(widget.precioMercado)}) y solo él podrá alinearlo esa jornada; después vuelve a ti.'),
        const SizedBox(height: 16),
        Row(children: [
          Text(pctTexto(_pct), style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          Text('Cobras ${millones(_pct * widget.precioMercado)}'),
        ]),
        Slider(
          value: _pct.clamp(min, max),
          min: min,
          max: max,
          divisions: divisiones > 0 ? divisiones : null,
          label: pctTexto(_pct),
          onChanged: (v) => setState(() => _pct = v),
        ),
        Text('Entre ${pctTexto(min)} y ${pctTexto(max)}. Solo puedes ceder una ficha por jornada; '
            'mientras está ofrecida o cedida no puedes venderla ni alinearla si la aceptan.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: AppButtons.premium(context),
          onPressed: () => Navigator.pop(context, (_pct * 1000).round() / 1000),
          child: const Text('Ofrecer en cesión'),
        ),
      ],
    );
  }
}
