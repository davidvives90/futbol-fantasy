import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

/// Alta del perfil tras el primer login ([inicial]) o edición posterior.
class PerfilFormScreen extends ConsumerStatefulWidget {
  const PerfilFormScreen({super.key, this.inicial = false});
  final bool inicial;

  @override
  ConsumerState<PerfilFormScreen> createState() => _PerfilFormScreenState();
}

class _PerfilFormScreenState extends ConsumerState<PerfilFormScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _apodo = TextEditingController();
  final _telefono = TextEditingController();
  String? _posicion;
  bool _cargado = false;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _apodo.dispose();
    _telefono.dispose();
    super.dispose();
  }

  void _rellenar(Perfil? p) {
    if (_cargado) return;
    _cargado = true;
    if (p == null) {
      final meta = sb.auth.currentUser?.userMetadata;
      _nombre.text = (meta?['full_name'] ?? meta?['name'] ?? '') as String;
      return;
    }
    _nombre.text = p.nombre;
    _apodo.text = p.apodo ?? '';
    _telefono.text = p.telefono ?? '';
    _posicion = p.posicion;
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final actual = ref.read(miPerfilProvider).valueOrNull;
    final ok = await ejecutar(
      context,
      () => LigasRepo.guardarPerfil(Perfil(
        id: uidActual!,
        nombre: _nombre.text.trim(),
        apodo: _apodo.text.trim().isEmpty ? null : _apodo.text.trim(),
        telefono: _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
        posicion: _posicion,
        avatarUrl: actual?.avatarUrl ?? sb.auth.currentUser?.userMetadata?['avatar_url'] as String?,
      )),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      refrescarLigas(ref);
      if (!widget.inicial && context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    _rellenar(ref.watch(miPerfilProvider).valueOrNull);
    return Scaffold(
      appBar: AppBar(title: Text(widget.inicial ? 'Tu perfil de jugador' : 'Editar perfil')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.inicial)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('Así te verán tus compañeros en las convocatorias y en la clasificación.'),
            ),
          TextFormField(
            controller: _nombre,
            decoration: const InputDecoration(labelText: 'Nombre y apellido'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v == null || v.trim().length < 2) ? 'Obligatorio' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _apodo,
            decoration: const InputDecoration(labelText: 'Apodo (opcional)', helperText: 'Se muestra en lugar del nombre'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _posicion,
            decoration: const InputDecoration(labelText: 'Posición habitual'),
            items: [for (final p in posiciones) DropdownMenuItem(value: p, child: Text(etiquetaPosicion(p)))],
            onChanged: (v) => setState(() => _posicion = v),
            validator: (v) => v == null ? 'Elige una posición' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telefono,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
          if (widget.inicial) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: () => sb.auth.signOut(), child: const Text('Cerrar sesión')),
          ],
        ]),
      ),
    );
  }
}
