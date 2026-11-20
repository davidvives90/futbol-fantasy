import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/liga_activa.dart';
import '../../core/utils.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

/// Unirse con el código general de la liga o con el enlace personal.
class UnirseScreen extends ConsumerStatefulWidget {
  const UnirseScreen({super.key, this.codigoInicial});
  final String? codigoInicial;

  @override
  ConsumerState<UnirseScreen> createState() => _UnirseScreenState();
}

class _UnirseScreenState extends ConsumerState<UnirseScreen> {
  late final _codigo = TextEditingController(text: widget.codigoInicial ?? '');
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    // Si viene de un enlace, se une sin pedir nada más.
    if ((widget.codigoInicial ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unirse());
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  /// Acepta el código suelto o un enlace completo pegado.
  String _extraer(String texto) {
    final t = texto.trim();
    final uri = Uri.tryParse(t);
    if (uri != null && uri.pathSegments.isNotEmpty && (uri.scheme == 'https' || uri.host == 'invite')) {
      return uri.pathSegments.last;
    }
    return t;
  }

  Future<void> _unirse() async {
    final codigo = _extraer(_codigo.text);
    if (codigo.length < 4) {
      mostrarError(context, 'Código demasiado corto');
      return;
    }
    setState(() => _enviando = true);
    try {
      final ligaId = await LigasRepo.unirse(codigo);
      await ref.read(ligaActivaIdProvider.notifier).elegir(ligaId);
      refrescarLigas(ref);
      if (mounted) {
        mostrarOk(context, '¡Ya estás dentro!');
        context.go('/partidos');
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Tx('Unirse a una liga')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Pega el código de la liga (6 letras) o el enlace de invitación que te enviaron por WhatsApp.'),
        const SizedBox(height: 16),
        TextField(
          controller: _codigo,
          textCapitalization: TextCapitalization.characters,
          decoration:  InputDecoration(labelText: tr('Código o enlace'), prefixIcon: Icon(Icons.vpn_key_outlined)),
          onSubmitted: (_) => _unirse(),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _enviando ? null : _unirse, child: Text(_enviando ? 'Uniéndote…' : 'Unirme')),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => context.push('/buscar-ligas'),
          icon: const Icon(Icons.search),
          label: const Tx('No tengo código: buscar ligas públicas'),
        ),
      ]),
    );
  }
}
