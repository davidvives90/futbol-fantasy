// Anuncios a pantalla completa (AdMob) solo en Android/iOS; en la web los anuncios van en los
// espacios fijos del marco (ver marco_web.dart), así que aquí no hacen nada.
export 'anuncios_movil.dart' if (dart.library.js_interop) 'anuncios_web.dart';
