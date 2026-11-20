import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'espacio_publicitario.dart';

/// Marco de la versión web, adaptable:
///  · móvil (< 600 px): banner superior 320×50 y la app a pantalla completa;
///  · tableta (600–1199 px): banner superior 468×60 / 728×90 y la app a todo el ancho (con menú lateral desde 720 px);
///  · ordenador (≥ 1200 px): app centrada (máx. 1100 px) con banner superior y dos banners laterales fijos
///    (160×600 a la izquierda; 300×600 a la derecha si hay sitio, si no 160×600).
/// En Android/iOS no hace nada.
class MarcoWeb extends StatelessWidget {
  const MarcoWeb({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !EspacioPublicitario.activo) return child;
    final w = MediaQuery.sizeOf(context).width;
    final cs = Theme.of(context).colorScheme;
    final banner = w >= 760 ? const Size(728, 90) : (w >= 500 ? const Size(468, 60) : const Size(320, 50));

    // El banner ocupa la zona de la barra de estado (iPhone en pantalla completa); la app ya no la necesita.
    final arriba = MediaQuery.paddingOf(context).top;
    final columna = Column(children: [
      Container(
        width: double.infinity,
        color: cs.surfaceContainerLow,
        padding: EdgeInsets.only(top: arriba + 4, bottom: 4),
        alignment: Alignment.center,
        child: EspacioPublicitario(hueco: 'superior', ancho: banner.width, alto: banner.height),
      ),
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
    ]);
    if (w < 1200) return columna;

    final derecho = w >= 1640 ? 300.0 : 160.0;
    Widget lateral(String hueco, double ancho) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Align(alignment: Alignment.topCenter, child: EspacioPublicitario(hueco: hueco, ancho: ancho, alto: 600)),
        );
    return ColoredBox(
      color: cs.surfaceContainerLow,
      child: Row(children: [
        lateral('lateral_izq', 160),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Material(elevation: 1, color: cs.surface, child: columna),
            ),
          ),
        ),
        lateral('lateral_der', derecho),
      ]),
    );
  }
}
