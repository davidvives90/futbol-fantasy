import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/models_fantasy.dart';

class AvatarMiembro extends StatelessWidget {
  const AvatarMiembro(this.miembro, {super.key, this.radio = 20});
  final Miembro? miembro;
  final double radio;

  @override
  Widget build(BuildContext context) {
    final url = miembro?.perfil?.avatarUrl;
    return CircleAvatar(
      radius: radio,
      backgroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child: url == null || url.isEmpty ? Text(miembro?.inicial ?? '?') : null,
    );
  }
}

/// Insignia "No habitual ×1,5".
class InsigniaNoHabitual extends StatelessWidget {
  const InsigniaNoHabitual({super.key, required this.bonus, this.corta = false});
  final double bonus;
  final bool corta;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final x = '×${bonus.toStringAsFixed(1).replaceAll('.', ',')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(corta ? x : 'No habitual $x',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSecondaryContainer)),
    );
  }
}

/// Variación de precio coloreada.
class VariacionTexto extends StatelessWidget {
  const VariacionTexto(this.variacion, {super.key});
  final double? variacion;

  @override
  Widget build(BuildContext context) {
    final v = variacion ?? 0;
    final color = v > 0
        ? Colors.green.shade700
        : v < 0
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.outline;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(v > 0 ? Icons.arrow_drop_up : (v < 0 ? Icons.arrow_drop_down : Icons.remove), size: 18, color: color),
      Text(variacionM(v), style: TextStyle(fontSize: 12, color: color)),
    ]);
  }
}

/// Estado del jugador en la convocatoria del próximo partido.
class IconoConvocatoria extends StatelessWidget {
  const IconoConvocatoria(this.estado, {super.key});
  final EstadoInscripcion? estado;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icono, color, tip) = switch (estado) {
      EstadoInscripcion.confirmado => (Icons.check_circle, Colors.green.shade700, 'Confirmado'),
      EstadoInscripcion.duda => (Icons.help, Colors.orange.shade700, 'En duda'),
      EstadoInscripcion.baja => (Icons.cancel, cs.error, 'Baja'),
      EstadoInscripcion.espera => (Icons.hourglass_bottom, cs.outline, 'En espera'),
      null => (Icons.radio_button_unchecked, cs.outline, 'Sin apuntar'),
    };
    return Tooltip(message: tip, child: Icon(icono, size: 18, color: color));
  }
}

/// Barra 0–100 de un atributo de la valoración.
class BarraAtributo extends StatelessWidget {
  const BarraAtributo({super.key, required this.etiqueta, required this.valor});
  final String etiqueta;
  final double? valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 96, child: Text(etiqueta)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: ((valor ?? 0) / 100).clamp(0.0, 1.0), minHeight: 10),
            ),
          ),
          SizedBox(width: 40, child: Text(valor == null ? '—' : valor!.round().toString(), textAlign: TextAlign.end)),
        ]),
      );
}

/// Gráfico de línea sencillo del historial de precios (sin dependencias).
class GraficoPrecios extends StatelessWidget {
  const GraficoPrecios({super.key, required this.puntos, this.alto = 160});
  final List<PuntoPrecio> puntos;
  final double alto;

  @override
  Widget build(BuildContext context) {
    if (puntos.length < 2) {
      return SizedBox(
        height: 60,
        child: Center(child: Text(puntos.isEmpty ? 'Sin historial todavía' : 'Precio inicial ${millones(puntos.first.precio)}')),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: alto,
      child: CustomPaint(
        painter: _LineaPainter(
          valores: [for (final p in puntos) p.precio],
          linea: cs.primary,
          rejilla: cs.outlineVariant,
          texto: cs.onSurfaceVariant,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _LineaPainter extends CustomPainter {
  _LineaPainter({required this.valores, required this.linea, required this.rejilla, required this.texto});
  final List<double> valores;
  final Color linea, rejilla, texto;

  @override
  void paint(Canvas canvas, Size size) {
    const izq = 48.0, abajo = 8.0, arriba = 8.0;
    final w = size.width - izq - 8, h = size.height - abajo - arriba;
    var lo = valores.reduce(math.min), hi = valores.reduce(math.max);
    if (hi - lo < 0.5) {
      lo -= 0.25;
      hi += 0.25;
    }
    double y(double v) => arriba + h - (v - lo) / (hi - lo) * h;
    double x(int i) => izq + w * i / (valores.length - 1);

    final pRejilla = Paint()
      ..color = rejilla
      ..strokeWidth = 1;
    for (final v in [lo, (lo + hi) / 2, hi]) {
      canvas.drawLine(Offset(izq, y(v)), Offset(izq + w, y(v)), pRejilla);
      final tp = TextPainter(
        text: TextSpan(text: millones(v), style: TextStyle(fontSize: 10, color: texto)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y(v) - tp.height / 2));
    }

    final path = Path()..moveTo(x(0), y(valores.first));
    for (var i = 1; i < valores.length; i++) {
      path.lineTo(x(i), y(valores[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = linea
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(Offset(x(valores.length - 1), y(valores.last)), 4, Paint()..color = linea);
  }

  @override
  bool shouldRepaint(covariant _LineaPainter old) => old.valores != valores || old.linea != linea;
}
