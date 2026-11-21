import 'package:flutter/material.dart';

import '../../core/info.dart';
import '../../data/models.dart';

/// Chip compacto con el rango del jugador (Fijo / Reserva / Invitado). Al tocarlo, explica qué significa.
class ChipRango extends StatelessWidget {
  const ChipRango(this.rango, {super.key, this.corto = false});
  final RangoMiembro rango;

  /// Solo la inicial (F / R / I), para listas densas.
  final bool corto;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (fondo, texto) = switch (rango) {
      RangoMiembro.fijo => (cs.primaryContainer, cs.onPrimaryContainer),
      RangoMiembro.reserva => (cs.secondaryContainer, cs.onSecondaryContainer),
      RangoMiembro.invitado => (cs.tertiaryContainer, cs.onTertiaryContainer),
    };
    // Tocar el chip explica qué es fijo, reserva o invitado (palabras de la app)
    return GestureDetector(
      onTap: () => mostrarAyuda(context, Ayuda.rangos),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(6)),
        child: Text(
          corto ? rango.letra : rango.etiqueta,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: texto, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
