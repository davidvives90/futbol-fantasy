export '../../core/avatar.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/avatar.dart';
import '../../core/idioma.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';

/// Insignia "Invitado ×1,5" (rango Invitado en la liga, v0.3).
class InsigniaNoHabitual extends StatelessWidget {
  const InsigniaNoHabitual({super.key, required this.bonus, this.corta = false});
  final double bonus;
  final bool corta;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Con el multiplicador desactivado (×1) solo se indica que es invitado
    final x = bonus > 1 ? '×${bonus.toStringAsFixed(1).replaceAll('.', ',')}' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      // Premium: dorado (tertiaryContainer + texto onTertiary)
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.5)),
      ),
      child: Text(corta ? (x.isEmpty ? 'Inv.' : x) : 'Invitado $x'.trim(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onTertiary)),
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
        ? AppColores.of(context).exito
        : v < 0
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.outline;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(v > 0 ? Icons.arrow_drop_up : (v < 0 ? Icons.arrow_drop_down : Icons.remove), size: 18, color: color),
      Text(variacionM(v), style: AppTheme.tabular(TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
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
      EstadoInscripcion.confirmado => (Icons.check_circle, AppColores.of(context).exito, 'Confirmado'),
      EstadoInscripcion.pendiente => (Icons.schedule, AppColores.of(context).aviso, 'Sin confirmar'),
      EstadoInscripcion.duda => (Icons.help, AppColores.of(context).aviso, 'En duda'),
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

    // Verde si ha subido desde el inicio, rojo si ha bajado; con relleno degradado bajo la línea
    final color = valores.last > valores.first
        ? const Color(0xFF2E7D32)
        : (valores.last < valores.first ? const Color(0xFFC62828) : linea);
    final path = Path()..moveTo(x(0), y(valores.first));
    for (var i = 1; i < valores.length; i++) {
      path.lineTo(x(i), y(valores[i]));
    }
    final area = Path.from(path)
      ..lineTo(x(valores.length - 1), arriba + h)
      ..lineTo(x(0), arriba + h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(izq, arriba, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    for (var i = 0; i < valores.length; i++) {
      canvas.drawCircle(Offset(x(i), y(valores[i])), i == valores.length - 1 ? 5 : 2.5, Paint()..color = color);
    }
    final tp = TextPainter(
      text: TextSpan(text: millones(valores.last), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(math.min(x(valores.length - 1) - tp.width / 2, size.width - tp.width), math.max(0, y(valores.last) - tp.height - 6)));
  }

  @override
  bool shouldRepaint(covariant _LineaPainter old) => old.valores != valores || old.linea != linea;
}

/// Insignia del rol en la alineación (POR/DEF/MED/DEL).
class InsigniaRol extends StatelessWidget {
  const InsigniaRol(this.rol, {super.key});
  final RolAlineacion rol;

  @override
  Widget build(BuildContext context) {
    // Roles con la paleta de equipos (sobria) y el portero en dorado
    final colores = AppColores.of(context);
    final color = switch (rol) {
      RolAlineacion.POR => Theme.of(context).colorScheme.tertiary,
      RolAlineacion.DEF => colores.equipo1,
      RolAlineacion.MED => Theme.of(context).colorScheme.primary,
      RolAlineacion.DEL => colores.equipo2,
    };
    return Container(
      width: 34,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(rol.name,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: rol == RolAlineacion.POR ? Theme.of(context).colorScheme.onTertiary : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// Desglose de los puntos de un mánager en una jornada: por jugador, rol, puntos, bonus de rol,
/// multiplicador de no habitual y si era una ficha cedida.
class DesgloseManager extends StatelessWidget {
  const DesgloseManager({super.key, required this.lineas, required this.nombres});
  final List<LineaDesglose> lineas;
  final Map<String, String> nombres;

  static String fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final orden = [...lineas]
      ..sort((a, b) {
        final s = (a.suplente ?? 0).compareTo(b.suplente ?? 0);
        return s != 0 ? s : (a.rol?.index ?? 9).compareTo(b.rol?.index ?? 9);
      });
    return Column(children: [
      for (final l in orden)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            if (l.rol != null) InsigniaRol(l.rol!) else const SizedBox(width: 34),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombres[l.jugadorId] ?? '…', overflow: TextOverflow.ellipsis),
                Text(
                  [
                    if (l.suplente != null && l.entraPor == null) tr('Suplente (no hizo falta)'),
                    if (l.entraPor != null) trf('Entra por {n}', {'n': nombres[l.entraPor] ?? '…'}),
                    if (!l.jugo) tr('No jugó'),
                    if (l.jugo) '${fmt(l.puntos)} pts',
                    if (l.jugo && l.bonusRol != 0) '${l.bonusRol > 0 ? '+' : ''}${fmt(l.bonusRol)} rol',
                    if (l.multiplicador != 1) '×${fmt(l.multiplicador)} invitado',
                    if (l.rareza != 1) '×${fmt(l.rareza)} copia',
                    if (l.capitan) tr('×2 capitán'),
                    if (l.ariete) tr('+3 ariete'),
                    if (l.doble) tr('×2 jornada especial'),
                    if (l.cedido) 'cedido',
                  ].join(' · '),
                  style: t.bodySmall,
                ),
              ]),
            ),
            Text(l.cuenta ? fmt(l.total) : '—', style: t.titleSmall),
          ]),
        ),
    ]);
  }
}
