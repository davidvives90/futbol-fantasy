import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/guias.dart';
import '../../core/ventajas.dart';

const claveBienvenida = 'bienvenida_vista';

/// Enseña la bienvenida si este móvil aún no la ha visto (una sola vez).
void mostrarBienvenidaSiToca(BuildContext context, SharedPreferences prefs, {bool fantasy = true}) {
  if (prefs.getBool(claveBienvenida) ?? false) return;
  prefs.setBool(claveBienvenida, true);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => SinPublicidad(child: Bienvenida(fantasy: fantasy))));
  });
}

/// Primer uso: 3 tarjetas; cada una con «Saber más» (su guía completa) y compartible como imagen (0060).
class Bienvenida extends StatelessWidget {
  const Bienvenida({super.key, this.fantasy = true});
  final bool fantasy;

  @override
  Widget build(BuildContext context) => VisorGuia(guia: guiaBienvenida(fantasy: fantasy));
}
