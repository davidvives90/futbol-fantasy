import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'espacio_publicitario.dart';
import 'idioma.dart';
import 'ventajas.dart';

/// Marco de la versión web, adaptable. El banner va ABAJO (debajo de las pestañas) para no tapar la cabecera:
///  · móvil (< 600 px): banner inferior 320×50; tableta: 468×60 / 728×90;
///  · ordenador (≥ 1200 px): app centrada (máx. 1100 px) con banner inferior y dos banners laterales fijos.
/// Sin anuncios si el usuario los ha quitado (código o compra) o en pantallas limpias
/// (bienvenida, alta de liga, login, post-partido, tienda). En Android/iOS no hace nada.
/// La forma del árbol no cambia al ocultar anuncios, para no perder el estado de la app.
class MarcoWeb extends StatelessWidget {
  const MarcoWeb({super.key, required this.child, this.onQuitarAnuncios});
  final Widget child;

  /// Abre la tienda (enlace «Quitar anuncios» junto al banner).
  final VoidCallback? onQuitarAnuncios;

  static final _app = GlobalKey(debugLabel: 'app');

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !EspacioPublicitario.activo) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: Publicidad.sinAnuncios,
      builder: (context, sinAnuncios, _) => ValueListenableBuilder<int>(
        valueListenable: Publicidad.pantallasLimpias,
        builder: (context, limpias, _) => _marco(context, !sinAnuncios && limpias == 0),
      ),
    );
  }

  Widget _marco(BuildContext context, bool anuncios) {
    final w = MediaQuery.sizeOf(context).width;
    final cs = Theme.of(context).colorScheme;
    final banner = w >= 760 ? const Size(728, 90) : (w >= 500 ? const Size(468, 60) : const Size(320, 50));
    final abajo = MediaQuery.paddingOf(context).bottom;

    final columna = Column(children: [
      Expanded(
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: anuncios,
          child: KeyedSubtree(key: _app, child: child),
        ),
      ),
      if (anuncios)
        // Material: fuera del Navigator no hay estilo de texto (saldría subrayado en amarillo)
        Material(
          color: cs.surfaceContainerLow,
          child: Container(
          width: double.infinity,
          padding: EdgeInsets.only(top: 4, bottom: abajo + 4),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            EspacioPublicitario(hueco: 'superior', ancho: banner.width, alto: banner.height),
            if (onQuitarAnuncios != null)
              InkWell(
                onTap: onQuitarAnuncios,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(tr('Quitar anuncios'),
                      style: TextStyle(fontSize: 11, color: cs.primary, decoration: TextDecoration.underline)),
                ),
              ),
          ]),
        ),
        ),
    ]);
    if (w < 1200) return columna;

    final derecho = w >= 1640 ? 300.0 : 160.0;
    Widget lateral(String hueco, double ancho) => Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: ancho,
            child: anuncios
                ? Align(alignment: Alignment.topCenter, child: EspacioPublicitario(hueco: hueco, ancho: ancho, alto: 600))
                : null,
          ),
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
