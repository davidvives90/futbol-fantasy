import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/idioma.dart';
import '../../core/supabase.dart';
import '../../core/utils.dart';

/// Crear o cambiar la contraseña de la cuenta (también tras «¿Has olvidado la contraseña?»).
/// Sirve para quien entraba con código o con Google: a partir de ahí puede entrar también con email y contraseña.
class ContrasenaScreen extends StatefulWidget {
  const ContrasenaScreen({super.key, this.recuperar = false});
  final bool recuperar;

  @override
  State<ContrasenaScreen> createState() => _ContrasenaScreenState();
}

class _ContrasenaScreenState extends State<ContrasenaScreen> {
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  bool _ver = false;
  bool _guardando = false;

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_c1.text.length < 8) {
      mostrarError(context, 'La contraseña debe tener al menos 8 caracteres');
      return;
    }
    if (_c1.text != _c2.text) {
      mostrarError(context, 'Las dos contraseñas no coinciden');
      return;
    }
    setState(() => _guardando = true);
    final ok = await ejecutar(context, () => sb.auth.updateUser(UserAttributes(password: _c1.text)));
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      mostrarOk(context, 'Contraseña guardada. Ya puedes entrar con tu email y esta contraseña.');
      if (context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = sb.auth.currentUser;
    final proveedores = <String>{
      ...?u?.identities?.map((i) => i.provider),
      if (u?.appMetadata['provider'] != null) u!.appMetadata['provider'] as String,
    };
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Tx(widget.recuperar ? 'Nueva contraseña' : 'Contraseña')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (u?.email != null) Text(u!.email!, style: t.titleMedium),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [
          if (proveedores.contains('google')) Chip(avatar: const Icon(Icons.check, size: 16), label: const Tx('Google vinculado')),
          if (proveedores.contains('email')) Chip(avatar: const Icon(Icons.check, size: 16), label: const Tx('Email')),
        ]),
        const SizedBox(height: 12),
        Tx(
            widget.recuperar
                ? 'Escribe tu contraseña nueva.'
                : 'Con una contraseña puedes entrar con tu email sin esperar el código. Si entras con Google y el correo es el mismo, es la misma cuenta.',
            style: t.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _c1,
          obscureText: !_ver,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: tr('Contraseña nueva (mínimo 8 caracteres)'),
            suffixIcon: IconButton(
              icon: Icon(_ver ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _ver = !_ver),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _c2,
          obscureText: !_ver,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _guardar(),
          decoration: InputDecoration(labelText: tr('Repite la contraseña')),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Tx(_guardando ? 'Guardando…' : 'Guardar contraseña'),
        ),
      ]),
    );
  }
}
