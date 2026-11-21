import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ventajas.dart';

/// Anuncios no intrusivos por tiempo de uso (docs: diseño Pistas y Monetización):
///  · nunca los 2 primeros días tras instalar (primera impresión limpia);
///  · el primero cuando llevas 5 minutos de uso en el día, luego cada 10 minutos y como mucho 3 al día;
///  · nunca a quien los ha quitado (código o compra) ni en pantallas limpias (bienvenida, alta, post-partido…);
///  · nunca a mitad de algo: solo en una pausa natural (cambiar de pestaña, tras enviar el post-partido);
///  · consentimiento europeo (RGPD) con el formulario de Google (UMP) antes de pedir anuncios.
/// Con los IDs de prueba de Google mientras no haya cuenta de AdMob (--dart-define=ADMOB_INTERSTICIAL=…).
class Anuncios with WidgetsBindingObserver {
  Anuncios._();
  static final instancia = Anuncios._();

  static const _activos = bool.fromEnvironment('ADS_ACTIVOS', defaultValue: true);
  static const _unidad = String.fromEnvironment('ADMOB_INTERSTICIAL',
      defaultValue: 'ca-app-pub-3940256099942544/1033173712'); // prueba de Google
  static const _primero = 5 * 60;
  static const _cada = 10 * 60;
  static const _maxDia = 3;
  static const _diasGracia = 2;

  SharedPreferences? _prefs;
  Timer? _reloj;
  InterstitialAd? _anuncio;
  bool _listo = false;
  bool _mostrando = false;
  int _segundos = 0;
  int _proximo = _primero;
  int _vistosHoy = 0;
  DateTime? _instalada;

  Future<void> iniciar(SharedPreferences prefs) async {
    if (!_activos) return;
    _prefs = prefs;
    final i = prefs.getString('ads_instalada');
    _instalada = i == null ? null : DateTime.tryParse(i);
    if (_instalada == null) {
      _instalada = DateTime.now();
      prefs.setString('ads_instalada', _instalada!.toIso8601String());
    }
    _cargarContador();
    WidgetsBinding.instance.addObserver(this);
    _arrancarReloj();
    try {
      final params = ConsentRequestParameters();
      ConsentInformation.instance.requestConsentInfoUpdate(params, () {
        ConsentForm.loadAndShowConsentFormIfRequired((_) => _arrancarAnuncios());
      }, (_) => _arrancarAnuncios());
    } catch (_) {
      _arrancarAnuncios();
    }
  }

  Future<void> _arrancarAnuncios() async {
    try {
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      _listo = true;
      _cargar();
    } catch (_) {}
  }

  void _cargar() {
    if (!_listo || _anuncio != null) return;
    InterstitialAd.load(
      adUnitId: _unidad,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (a) => _anuncio = a,
        onAdFailedToLoad: (_) => Future.delayed(const Duration(minutes: 1), _cargar),
      ),
    );
  }

  String get _hoy {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  void _cargarContador() {
    final p = _prefs!;
    if (p.getString('ads_dia') == _hoy) {
      _segundos = p.getInt('ads_segundos') ?? 0;
      _proximo = p.getInt('ads_proximo') ?? _primero;
      _vistosHoy = p.getInt('ads_vistos') ?? 0;
    } else {
      _segundos = 0;
      _proximo = _primero;
      _vistosHoy = 0;
    }
  }

  void _guardar() {
    final p = _prefs;
    if (p == null) return;
    p.setString('ads_dia', _hoy);
    p.setInt('ads_segundos', _segundos);
    p.setInt('ads_proximo', _proximo);
    p.setInt('ads_vistos', _vistosHoy);
  }

  void _arrancarReloj() {
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_prefs?.getString('ads_dia') != _hoy) _cargarContador();
      _segundos += 10;
      if (_segundos % 60 == 0) _guardar();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _arrancarReloj();
    } else {
      _reloj?.cancel();
      _guardar();
    }
  }

  /// Llamar en una pausa natural. Muestra el anuncio solo si ya toca por tiempo de uso.
  void pausaNatural() {
    if (!_activos || _mostrando || _segundos < _proximo || !Publicidad.mostrar) return;
    if (_vistosHoy >= _maxDia) return;
    final ins = _instalada;
    if (ins != null && DateTime.now().difference(ins).inDays < _diasGracia) return;
    final a = _anuncio;
    if (a == null) {
      _cargar();
      return;
    }
    _anuncio = null;
    _mostrando = true;
    a.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _mostrando = false;
        _cargar();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _mostrando = false;
        _cargar();
      },
    );
    _proximo = _segundos + _cada;
    _vistosHoy++;
    _guardar();
    a.show();
  }

  /// Para el formulario de privacidad desde Perfil (obligatorio poder cambiar el consentimiento).
  static Future<bool> hayOpcionesPrivacidad() async {
    try {
      return await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  static void abrirOpcionesPrivacidad() {
    ConsentForm.showPrivacyOptionsForm((_) {});
  }
}
