import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import 'supabase.dart';

/// Estado «sin anuncios» del usuario (0046). Lo usan los anuncios del móvil y los banners de la web.
class Publicidad {
  Publicidad._();

  /// true = este usuario no ve anuncios (código canjeado, compra o cuenta máster).
  static final sinAnuncios = ValueNotifier<bool>(false);

  /// Pantallas abiertas donde no debe haber anuncios (bienvenida, alta de liga, login, post-partido, tienda…).
  static final pantallasLimpias = ValueNotifier<int>(0);

  static bool get mostrar => !sinAnuncios.value && pantallasLimpias.value == 0;
}

class Ventajas {
  const Ventajas({this.sinAnuncios = false, this.paraSiempre = false, this.hasta});
  final bool sinAnuncios, paraSiempre;
  final DateTime? hasta;

  factory Ventajas.fromMap(Map<String, dynamic> m) => Ventajas(
        sinAnuncios: (m['sin_anuncios'] ?? false) as bool,
        paraSiempre: (m['para_siempre'] ?? false) as bool,
        hasta: m['hasta'] == null ? null : DateTime.parse(m['hasta'] as String).toLocal(),
      );
}

final ventajasProvider = FutureProvider<Ventajas>((ref) async {
  if (ref.watch(uidProvider) == null) {
    Publicidad.sinAnuncios.value = false;
    return const Ventajas();
  }
  try {
    final r = await sb.rpc('mis_ventajas');
    final v = Ventajas.fromMap(Map<String, dynamic>.from(r as Map));
    Publicidad.sinAnuncios.value = v.sinAnuncios;
    return v;
  } catch (_) {
    return const Ventajas();
  }
});

/// Envuelve una pantalla en la que no se enseña publicidad mientras esté abierta.
class SinPublicidad extends StatefulWidget {
  const SinPublicidad({super.key, required this.child});
  final Widget child;

  @override
  State<SinPublicidad> createState() => _SinPublicidadState();
}

class _SinPublicidadState extends State<SinPublicidad> {
  @override
  void initState() {
    super.initState();
    // Fuera del build para no reconstruir el marco mientras se construye
    WidgetsBinding.instance.addPostFrameCallback((_) => Publicidad.pantallasLimpias.value++);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => Publicidad.pantallasLimpias.value--);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
