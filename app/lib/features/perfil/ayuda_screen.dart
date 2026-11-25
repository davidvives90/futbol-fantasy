import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/idioma.dart';
import 'faq_datos.dart';

/// 0056: preguntas frecuentes con buscador, en el idioma de la app.
class AyudaScreen extends ConsumerStatefulWidget {
  const AyudaScreen({super.key});

  @override
  ConsumerState<AyudaScreen> createState() => _AyudaScreenState();
}

class _AyudaScreenState extends ConsumerState<AyudaScreen> {
  final _buscar = TextEditingController();
  String _q = '';

  static String _limpio(String s) {
    const de = 'áàäâéèëêíìïîóòöôúùüûñç';
    const a = 'aaaaeeeeiiiioooouuuunc';
    final b = StringBuffer();
    for (final c in s.toLowerCase().split('')) {
      final i = de.indexOf(c);
      b.write(i < 0 ? c : a[i]);
    }
    return b.toString();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idi = ref.watch(idiomaProvider);
    final i = idiomasFaq.indexOf(idi).clamp(0, idiomasFaq.length - 1);
    final q = _limpio(_q.trim());
    final lista = [
      for (final f in faqs)
        if (q.isEmpty || _limpio(f.p[i]).contains(q) || _limpio(f.r[i]).contains(q)) f,
    ];
    final categorias = <String>[];
    for (final f in lista) {
      if (!categorias.contains(f.categoria)) categorias.add(f.categoria);
    }
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Tx('Preguntas frecuentes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          TextField(
            controller: _buscar,
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Busca tu duda: cláusula, porra, pagar…'),
              border: const OutlineInputBorder(),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                            _buscar.clear();
                            _q = '';
                          })),
            ),
          ),
          const SizedBox(height: 8),
          if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Tx('No hay ninguna pregunta con esas palabras. Prueba con otras o escríbenos desde Perfil › Enviar comentarios.',
                  textAlign: TextAlign.center, style: t.bodyMedium),
            ),
          for (final c in categorias) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(tr(c), style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
            for (final f in lista.where((x) => x.categoria == c))
              Card(
                child: ExpansionTile(
                  initiallyExpanded: q.isNotEmpty && lista.length <= 3,
                  shape: const Border(),
                  title: Text(f.p[i], style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(f.r[i], style: t.bodyMedium)],
                ),
              ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push('/guia'),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Tx('Guía y normas de tu liga'),
          ),
        ],
      ),
    );
  }
}
