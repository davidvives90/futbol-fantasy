import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

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
  final _dorsal = TextEditingController();
  String? _posicion;
  String? _avatarUrl;
  DateTime? _nacimiento;
  bool _subiendo = false;
  bool _cargado = false;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _apodo.dispose();
    _telefono.dispose();
    _dorsal.dispose();
    super.dispose();
  }

  void _rellenar(Perfil? p) {
    if (_cargado) return;
    _cargado = true;
    if (p == null) {
      final meta = sb.auth.currentUser?.userMetadata;
      _nombre.text = (meta?['full_name'] ?? meta?['name'] ?? '') as String;
      _avatarUrl = meta?['avatar_url'] as String?;
      return;
    }
    _nombre.text = p.nombre;
    _apodo.text = p.apodo ?? '';
    _telefono.text = p.telefono ?? '';
    _posicion = p.posicion;
    _dorsal.text = p.dorsal?.toString() ?? '';
    _avatarUrl = p.avatarUrl;
    _nacimiento = p.fechaNacimiento;
  }

  /// Elige foto (galería o cámara), la reduce a 512 px y la sube a Storage (carpeta propia).
  Future<void> _cambiarFoto() async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Tx('Elegir de la galería'),
            onTap: () => Navigator.pop(c, 'galeria'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Tx('Hacer una foto'),
            onTap: () => Navigator.pop(c, 'camara'),
          ),
          if (_avatarUrl != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
              title: const Tx('Quitar foto'),
              onTap: () => Navigator.pop(c, 'quitar'),
            ),
        ]),
      ),
    );
    if (opcion == null) return;
    if (opcion == 'quitar') {
      setState(() => _avatarUrl = null);
      return;
    }
    final foto = await ImagePicker().pickImage(
      source: opcion == 'camara' ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 82,
    );
    if (foto == null || !mounted) return;
    setState(() => _subiendo = true);
    final ok = await ejecutar(context, () async {
      final bytes = await foto.readAsBytes();
      final ruta = '${uidActual!}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await sb.storage.from('avatares').uploadBinary(ruta, bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'));
      _avatarUrl = sb.storage.from('avatares').getPublicUrl(ruta);
    }, ok: 'Foto lista: pulsa Guardar');
    if (mounted) setState(() => _subiendo = false);
    if (!ok) return;
  }

  Future<void> _elegirNacimiento() async {
    final hoy = DateTime.now();
    final f = await showDatePicker(
      context: context,
      initialDate: _nacimiento ?? DateTime(hoy.year - 30, 1, 1),
      firstDate: DateTime(1930),
      lastDate: DateTime(hoy.year - 10, hoy.month, hoy.day),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Fecha de nacimiento',
    );
    if (f != null) setState(() => _nacimiento = f);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final ok = await ejecutar(
      context,
      () => LigasRepo.guardarPerfil(Perfil(
        id: uidActual!,
        nombre: _nombre.text.trim(),
        apodo: _apodo.text.trim().isEmpty ? null : _apodo.text.trim(),
        telefono: _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
        posicion: _posicion,
        avatarUrl: _avatarUrl,
        fechaNacimiento: _nacimiento,
        dorsal: int.tryParse(_dorsal.text.trim()),
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
          if (widget.inicial) ...[
            const SelectorIdioma(),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Tx('Así te verán tus compañeros en las convocatorias y en la clasificación.'),
            ),
          ],
          Center(
            child: Stack(children: [
              CircleAvatar(
                radius: 52,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundImage: _avatarUrl == null ? null : NetworkImage(_avatarUrl!),
                child: _subiendo
                    ? const CircularProgressIndicator()
                    : Icon(Icons.person, size: 52, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: IconButton.filled(
                  tooltip: tr('Cambiar foto'),
                  onPressed: _subiendo ? null : _cambiarFoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('Con foto, tus compañeros te reconocen al momento',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nombre,
            decoration:  InputDecoration(labelText: tr('Nombre y apellido')),
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v == null || v.trim().length < 2) ? 'Obligatorio' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _apodo,
            decoration:  InputDecoration(labelText: tr('Apodo (opcional)'), helperText: tr('Se muestra en lugar del nombre')),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _posicion,
            decoration:  InputDecoration(
              labelText: tr('Posición preferida'),
              helperText: tr('Solo informativa: no cambia tus puntos (todos rotáis, también en la portería)'),
            ),
            items: [for (final p in posiciones) DropdownMenuItem(value: p, child: Text(etiquetaPosicion(p)))],
            onChanged: (v) => setState(() => _posicion = v),
            validator: (v) => v == null ? 'Elige una posición' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _dorsal,
            keyboardType: TextInputType.number,
            maxLength: 2,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: tr('Dorsal (opcional)'),
              helperText: tr('Del 1 al 99. Sale en tu carta y en las alineaciones'),
              prefixIcon: const Icon(Icons.tag),
              counterText: '',
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return (v ?? '').trim().isEmpty || (n != null && n >= 1 && n <= 99) ? null : tr('Del 1 al 99');
            },
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _elegirNacimiento,
            child: InputDecorator(
              decoration:  InputDecoration(
                labelText: tr('Fecha de nacimiento'),
                helperText: tr('Tus compañeros solo verán tu edad'),
                suffixIcon: Icon(Icons.cake_outlined),
              ),
              isEmpty: _nacimiento == null,
              child: _nacimiento == null
                  ? null
                  : Text('${_nacimiento!.day}/${_nacimiento!.month}/${_nacimiento!.year} · '
                      '${Perfil(id: '', nombre: '', fechaNacimiento: _nacimiento).edad} años'),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telefono,
            keyboardType: TextInputType.phone,
            decoration:  InputDecoration(labelText: tr('Teléfono (opcional)')),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _guardando ? null : _guardar, child: const Tx('Guardar')),
          if (widget.inicial) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: () => sb.auth.signOut(), child: const Tx('Cerrar sesión')),
          ],
        ]),
      ),
    );
  }
}
