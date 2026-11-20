import 'package:shared_preferences/shared_preferences.dart';

/// Versión web: sin intersticiales (la publicidad web va en banners fijos, ver MarcoWeb).
class Anuncios {
  Anuncios._();
  static final instancia = Anuncios._();

  Future<void> iniciar(SharedPreferences prefs) async {}
  void pausaNatural() {}
  static Future<bool> hayOpcionesPrivacidad() async => false;
  static void abrirOpcionesPrivacidad() {}
}
