import 'package:flutter/material.dart';

import '../../core/idioma.dart';

const claveBienvenida = 'bienvenida_vista';

/// Primer uso: 3 pantallas cortas (apuntarse, votar y Fantasy). Solo se enseña una vez por móvil.
class Bienvenida extends StatefulWidget {
  const Bienvenida({super.key, required this.fantasy});
  final bool fantasy;

  @override
  State<Bienvenida> createState() => _BienvenidaState();
}

class _BienvenidaState extends State<Bienvenida> {
  final _pc = PageController();
  int _i = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paginas = <(IconData, String, String)>[
      (Icons.check_circle_outline, 'Apúntate con un toque',
          'Cuando haya partido, pulsa «Voy» en Inicio o directamente en la notificación. Si no puedes, «No voy» y tu plaza pasa al siguiente.'),
      (Icons.star_outline, 'Vota después del partido',
          'Pon el resultado, quién marcó y unas estrellas a tus compañeros. Es un minuto y de ahí salen los puntos.'),
      if (widget.fantasy)
        (Icons.shield_outlined, 'Juega al Fantasy',
            'Empiezas con dinero y unos jugadores. Ficha a quien creas que va a brillar: sus puntos en el partido son los tuyos.'),
    ];
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ultima = _i == paginas.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Tx('Saltar')),
          ),
          Expanded(
            child: PageView(
              controller: _pc,
              onPageChanged: (i) => setState(() => _i = i),
              children: [
                for (final (icono, titulo, texto) in paginas)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icono, size: 96, color: cs.primary),
                      const SizedBox(height: 24),
                      Text(tr(titulo), style: t.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(tr(texto), style: t.bodyLarge, textAlign: TextAlign.center),
                    ]),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < paginas.length; k++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(shape: BoxShape.circle, color: k == _i ? cs.primary : cs.outlineVariant),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => ultima
                    ? Navigator.pop(context)
                    : _pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(tr(ultima ? 'Empezar' : 'Siguiente')),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
