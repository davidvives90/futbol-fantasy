import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/idioma.dart';

const claveBienvenida = 'bienvenida_vista';

/// Enseña la bienvenida si este móvil aún no la ha visto (una sola vez).
void mostrarBienvenidaSiToca(BuildContext context, SharedPreferences prefs, {bool fantasy = true}) {
  if (prefs.getBool(claveBienvenida) ?? false) return;
  prefs.setBool(claveBienvenida, true);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => Bienvenida(fantasy: fantasy)));
  });
}

/// Primer uso: 3 tarjetas (apuntarse, jugar y puntuar, Fantasy o todo de un vistazo). También desde Perfil › Cómo funciona.
class Bienvenida extends StatefulWidget {
  const Bienvenida({super.key, this.fantasy = true});
  final bool fantasy;

  @override
  State<Bienvenida> createState() => _BienvenidaState();
}

class _BienvenidaState extends State<Bienvenida> {
  final _pc = PageController(viewportFraction: 0.88);
  int _i = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tarjetas = <(IconData, Color, String, String)>[
      (Icons.touch_app_rounded, const Color(0xFF2E7D32), 'Apúntate con un toque',
          'Cuando haya partido, pulsa «Voy». Si eres fijo ya estás en la lista; si no puedes, «No voy» y entra el primer suplente.'),
      (Icons.sports_soccer_rounded, const Color(0xFF1565C0), 'Juega y puntúa',
          'Al acabar, apunta el resultado y quién marcó, y da estrellas a tus compañeros. Así salen los puntos y la clasificación.'),
      widget.fantasy
          ? (Icons.shield_rounded, const Color(0xFF6A1B9A), 'Ficha y gana',
              'En el Fantasy tienes dinero para fichar a jugadores de tu liga. Elige a quien creas que va a brillar: sus puntos son los tuyos.')
          : (Icons.calendar_month_rounded, const Color(0xFF6A1B9A), 'Todo de un vistazo',
              'En Inicio ves los partidos de todas tus ligas y lo que tienes pendiente: responder, votar o pagar.'),
    ];
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ultima = _i == tarjetas.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
            child: Row(children: [
              Expanded(child: Tx('Así funciona', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => Navigator.pop(context), child: const Tx('Saltar')),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pc,
              onPageChanged: (i) => setState(() => _i = i),
              children: [
                for (var k = 0; k < tarjetas.length; k++)
                  _Tarjeta(
                    numero: k + 1,
                    total: tarjetas.length,
                    icono: tarjetas[k].$1,
                    color: tarjetas[k].$2,
                    titulo: tr(tarjetas[k].$3),
                    texto: tr(tarjetas[k].$4),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < tarjetas.length; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: k == _i ? 22 : 8,
                height: 8,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4), color: k == _i ? cs.primary : cs.outlineVariant),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => ultima
                    ? Navigator.pop(context)
                    : _pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(tr(ultima ? 'Empezar' : 'Siguiente'), style: const TextStyle(fontSize: 17)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.numero,
    required this.total,
    required this.icono,
    required this.color,
    required this.titulo,
    required this.texto,
  });
  final int numero, total;
  final IconData icono;
  final Color color;
  final String titulo, texto;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // Cabecera de color con el icono grande
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, Color.lerp(color, Colors.black, 0.35)!],
                ),
              ),
              child: Stack(children: [
                Positioned(
                  right: -30,
                  bottom: -30,
                  child: Icon(icono, size: 200, color: Colors.white.withValues(alpha: 0.08)),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                    child: Icon(icono, size: 72, color: Colors.white),
                  ),
                ),
                Positioned(
                  left: 18,
                  top: 16,
                  child: Text('$numero/$total',
                      style: t.labelLarge?.copyWith(color: Colors.white70, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(texto, style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
