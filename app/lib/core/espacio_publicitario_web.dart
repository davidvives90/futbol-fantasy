import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Hueco de anuncio en la web.
///  · Con --dart-define=ADSENSE_CLIENT=ca-pub-… y los ADSENSE_SLOT_* : anuncio real de Google AdSense.
///  · Sin ellos: un recuadro discreto «Publicidad» para ver dónde irán (WEB_ANUNCIOS_DEMO=false lo oculta).
class EspacioPublicitario extends StatelessWidget {
  const EspacioPublicitario({super.key, required this.hueco, required this.ancho, required this.alto});

  /// 'superior' | 'lateral_izq' | 'lateral_der'
  final String hueco;
  final double ancho, alto;

  static const _cliente = String.fromEnvironment('ADSENSE_CLIENT');
  static const _slotSuperior = String.fromEnvironment('ADSENSE_SLOT_SUPERIOR');
  static const _slotLateral = String.fromEnvironment('ADSENSE_SLOT_LATERAL');
  static const _demo = bool.fromEnvironment('WEB_ANUNCIOS_DEMO', defaultValue: true);

  static bool get _real => _cliente.isNotEmpty;
  static bool get activo => _real || _demo;

  static final _registrados = <String>{};
  static bool _scriptCargado = false;

  String get _slot => hueco == 'superior' ? _slotSuperior : _slotLateral;

  static void _cargarScript() {
    if (_scriptCargado) return;
    _scriptCargado = true;
    final s = web.document.createElement('script') as web.HTMLScriptElement;
    s.async = true;
    s.crossOrigin = 'anonymous';
    s.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=$_cliente';
    web.document.head?.append(s);
  }

  String _registrar() {
    final tipo = 'ff-anuncio-$hueco-${ancho.toInt()}x${alto.toInt()}';
    if (_registrados.add(tipo)) {
      ui_web.platformViewRegistry.registerViewFactory(tipo, (int _) {
        final caja = web.document.createElement('div') as web.HTMLDivElement;
        caja.style
          ..width = '100%'
          ..height = '100%'
          ..textAlign = 'center';
        final ins = web.document.createElement('ins') as web.HTMLElement;
        ins.className = 'adsbygoogle';
        ins.style
          ..display = 'inline-block'
          ..width = '${ancho.toInt()}px'
          ..height = '${alto.toInt()}px';
        ins.setAttribute('data-ad-client', _cliente);
        if (_slot.isNotEmpty) ins.setAttribute('data-ad-slot', _slot);
        caja.append(ins);
        final empuje = web.document.createElement('script') as web.HTMLScriptElement;
        empuje.text = '(adsbygoogle = window.adsbygoogle || []).push({});';
        caja.append(empuje);
        return caja;
      });
    }
    return tipo;
  }

  @override
  Widget build(BuildContext context) {
    if (!activo) return const SizedBox.shrink();
    if (_real) {
      _cargarScript();
      return SizedBox(width: ancho, height: alto, child: HtmlElementView(viewType: _registrar()));
    }
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: ancho,
      height: alto,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('Publicidad · ${ancho.toInt()}×${alto.toInt()}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
    );
  }
}
