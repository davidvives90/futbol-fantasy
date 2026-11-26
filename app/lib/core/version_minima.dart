import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'idioma.dart';
import 'supabase.dart';
import 'utils.dart';

/// Número de compilación de esta app (lo pone el CI con --dart-define=APP_BUILD). 0 = desarrollo: sin control.
const appBuild = int.fromEnvironment('APP_BUILD');

/// 0059: versión mínima de la app Android. Cuando un cambio del servidor no funciona con versiones viejas,
/// se sube `config_app.version_minima_android` y la app pide actualizar antes de seguir.
final configAppProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final r = await sb.rpc('config_app_publica');
    return Map<String, dynamic>.from(r as Map);
  } catch (_) {
    return const {}; // sin conexión: no se bloquea
  }
});

class PuertaVersion extends ConsumerWidget {
  const PuertaVersion({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb || appBuild == 0) return child; // la web siempre es la última
    final c = ref.watch(configAppProvider).valueOrNull ?? const {};
    final minima = (c['version_minima_android'] as num?)?.toInt() ?? 0;
    if (appBuild >= minima) return child;
    final url = c['url_descarga'] as String?;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/icono/icono.png', width: 96, height: 96),
              ),
              const SizedBox(height: 20),
              Tx('Hay una versión nueva', style: t.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Tx('Esta versión de la app ya no funciona con el servidor. Descarga la última para seguir jugando: tus datos no se pierden.',
                  textAlign: TextAlign.center, style: t.bodyMedium),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: url == null ? null : () => abrirUrl(context, url),
                icon: const Icon(Icons.system_update),
                label: const Tx('Descargar la nueva versión'),
              ),
              TextButton(onPressed: () => ref.invalidate(configAppProvider), child: const Tx('Ya la he actualizado')),
            ]),
          ),
        ),
      ),
    );
  }
}
