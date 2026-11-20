import 'package:flutter/material.dart';

import '../data/models.dart';
import 'theme.dart';

/// Equipaciones de la liga activa, disponibles en todo el árbol (se pone en MaterialApp.builder).
class EquipacionesScope extends InheritedWidget {
  const EquipacionesScope({super.key, required this.equipaciones, required super.child});
  final List<Equipacion> equipaciones;

  static List<Equipacion> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EquipacionesScope>()?.equipaciones ?? Equipacion.porDefecto;

  @override
  bool updateShouldNotify(EquipacionesScope old) => old.equipaciones != equipaciones;
}

/// Colores que se pueden elegir para una equipación.
const paletaEquipaciones = <(String, String?)>[
  ('Blanco', '#F4F4F2'),
  ('Negro', '#1E1E1E'),
  ('Gris', '#8A8F8C'),
  ('Rojo', '#C62828'),
  ('Granate', '#7A1F2B'),
  ('Naranja', '#EF7D1A'),
  ('Amarillo', '#F2C230'),
  ('Verde', '#2E7D32'),
  ('Celeste', '#5BA7DE'),
  ('Azul', '#1F4FA0'),
  ('Morado', '#6A3FA0'),
  ('Rosa', '#E06292'),
  ('Petos', '#E8C21A'),
  ('Color', null),
];

Color? _hex(String? h) {
  if (h == null || h.length != 7 || !h.startsWith('#')) return null;
  final v = int.tryParse(h.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

Equipacion equipacionDe(BuildContext context, int n) {
  final l = EquipacionesScope.of(context);
  return (n >= 1 && n <= l.length) ? l[n - 1] : Equipacion('Equipo ${String.fromCharCode(64 + n)}');
}

/// Nombre del equipo según su equipación: «Blanco», «Color», «Petos»…
String nombreEquipo(BuildContext context, int n) => equipacionDe(context, n).nombre;

/// Color real de la equipación (relleno de puntos, anillos, barras). «Color» sin especificar → color de la app.
Color colorEquipo(BuildContext context, int n) => _hex(equipacionDe(context, n).colorHex) ?? AppColores.of(context).equipo(n);

/// Variante legible para TEXTO sobre el fondo actual (el blanco sobre marfil o el negro en oscuro no se leerían).
Color colorTextoEquipo(BuildContext context, int n) {
  final c = colorEquipo(context, n);
  final fondo = Theme.of(context).colorScheme.surface;
  final diferencia = (c.computeLuminance() - fondo.computeLuminance()).abs();
  return diferencia < 0.25 ? Theme.of(context).colorScheme.onSurface : c;
}

/// Punto de color de la equipación, con borde para que el blanco (o el negro en oscuro) se vea.
class PuntoEquipo extends StatelessWidget {
  const PuntoEquipo(this.equipo, {super.key, this.tamano = 12});
  final int equipo;
  final double tamano;

  @override
  Widget build(BuildContext context) => Container(
        width: tamano,
        height: tamano,
        decoration: BoxDecoration(
          color: colorEquipo(context, equipo),
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
        ),
      );
}

/// Chip «● Blanco» para cabeceras de equipo.
class EtiquetaEquipo extends StatelessWidget {
  const EtiquetaEquipo(this.equipo, {super.key, this.estilo});
  final int equipo;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        PuntoEquipo(equipo),
        const SizedBox(width: 6),
        Text(nombreEquipo(context, equipo),
            style: (estilo ?? const TextStyle(fontWeight: FontWeight.w700)).copyWith(color: colorTextoEquipo(context, equipo))),
      ]);
}
