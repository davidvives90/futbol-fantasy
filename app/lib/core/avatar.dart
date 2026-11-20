import 'package:flutter/material.dart';

import '../data/models.dart';

/// Avatar único de la app: foto del jugador o, si no tiene, su inicial sobre un color estable
/// (siempre el mismo para la misma persona, para reconocerla de un vistazo).
/// [anillo] dibuja un borde (color de equipo, selección, MVP…).
class AvatarMiembro extends StatelessWidget {
  const AvatarMiembro(this.miembro, {super.key, this.radio = 20, this.anillo});
  final Miembro? miembro;
  final double radio;
  final Color? anillo;

  static const _tonos = [
    (Color(0xFFDCEBE4), Color(0xFF0A3A2D)),
    (Color(0xFFE3E8F4), Color(0xFF1F3A66)),
    (Color(0xFFF4EAD3), Color(0xFF5A4012)),
    (Color(0xFFF3E1E1), Color(0xFF6B2323)),
    (Color(0xFFE9E3F3), Color(0xFF433068)),
    (Color(0xFFE0EEF0), Color(0xFF1C4C55)),
  ];

  @override
  Widget build(BuildContext context) {
    final url = miembro?.perfil?.avatarUrl;
    final hayFoto = url != null && url.isNotEmpty;
    final nombre = miembro?.nombre ?? '?';
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final (fondo, texto) = _tonos[nombre.codeUnits.fold<int>(0, (a, b) => a + b) % _tonos.length];
    final avatar = CircleAvatar(
      radius: radio,
      backgroundColor: oscuro ? texto : fondo,
      foregroundImage: hayFoto ? NetworkImage(url) : null,
      onForegroundImageError: hayFoto ? (_, __) {} : null,
      child: Text(
        miembro?.inicial ?? '?',
        style: TextStyle(
          fontSize: radio * 0.85,
          fontWeight: FontWeight.w700,
          color: oscuro ? fondo : texto,
        ),
      ),
    );
    if (anillo == null) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: anillo!, width: 2)),
      child: avatar,
    );
  }
}

/// «28 años» o null.
String? textoEdad(Miembro? m) {
  final e = m?.perfil?.edad;
  return e == null ? null : '$e años';
}

/// Fila de avatares solapados («quién va»): hasta [max] y luego «+N».
class PilaAvatares extends StatelessWidget {
  const PilaAvatares(this.miembros, {super.key, this.max = 7, this.radio = 14});
  final List<Miembro?> miembros;
  final int max;
  final double radio;

  @override
  Widget build(BuildContext context) {
    if (miembros.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final visibles = miembros.take(max).toList();
    final resto = miembros.length - visibles.length;
    final paso = radio * 1.45;
    final n = visibles.length + (resto > 0 ? 1 : 0);
    return SizedBox(
      height: radio * 2 + 4,
      width: paso * (n - 1) + radio * 2 + 4,
      child: Stack(children: [
        for (var i = 0; i < visibles.length; i++)
          Positioned(
            left: i * paso,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
              child: AvatarMiembro(visibles[i], radio: radio),
            ),
          ),
        if (resto > 0)
          Positioned(
            left: visibles.length * paso,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
              child: CircleAvatar(
                radius: radio,
                backgroundColor: cs.surfaceContainerHighest,
                child: Text('+$resto', style: TextStyle(fontSize: radio * 0.75, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      ]),
    );
  }
}
