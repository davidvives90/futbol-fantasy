import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/idioma.dart';
import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Logotipo de la liga en un círculo; si no tiene, la inicial sobre su color.
class LogoLiga extends StatelessWidget {
  LogoLiga(Liga liga, {super.key, this.tamano = 28})
      : nombre = liga.nombre,
        color = liga.colorPropio,
        logoUrl = liga.logoUrl;
  const LogoLiga.datos({super.key, required this.nombre, this.color, this.logoUrl, this.tamano = 28});
  final String nombre;
  final Color? color;
  final String? logoUrl;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final fondo = color ?? Theme.of(context).colorScheme.primary;
    final inicial = nombre.trim().isEmpty ? '?' : nombre.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: tamano / 2,
      backgroundColor: fondo,
      foregroundImage: logoUrl == null ? null : NetworkImage(logoUrl!),
      child: Text(inicial,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: tamano * 0.45)),
    );
  }
}

/// 0061: color propio y logotipo de la liga (solo admin). El color tiñe la app cuando esta liga está activa.
class MarcaLigaScreen extends ConsumerStatefulWidget {
  const MarcaLigaScreen({super.key});

  @override
  ConsumerState<MarcaLigaScreen> createState() => _MarcaLigaScreenState();
}

class _MarcaLigaScreenState extends ConsumerState<MarcaLigaScreen> {
  static const _paleta = <String>[
    '#C8102E', '#E65100', '#F2A229', '#2E7D32', '#00838F', '#1565C0', '#283593', '#6A1B9A',
    '#AD1457', '#5D4037', '#455A64', '#212121', '#7CB342', '#0097A7', '#3949AB', '#D81B60',
  ];
  String? _color, _logo;
  bool _iniciado = false, _subiendo = false, _guardando = false;

  Color _de(String hex) => Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

  Future<void> _elegirLogo(Liga l) async {
    final foto = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 88);
    if (foto == null || !mounted) return;
    setState(() => _subiendo = true);
    await ejecutar(context, () async {
      final bytes = await foto.readAsBytes();
      final ext = foto.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final ruta = '${l.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await sb.storage.from('logos').uploadBinary(ruta, bytes,
          fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg', upsert: true));
      _logo = sb.storage.from('logos').getPublicUrl(ruta);
    });
    if (mounted) setState(() => _subiendo = false);
  }

  Future<void> _guardar(Liga l) async {
    setState(() => _guardando = true);
    final ok = await ejecutar(
      context,
      () => sb.rpc('personalizar_liga', params: {'p_liga': l.id, 'p_color': _color, 'p_logo_url': _logo}),
      ok: tr('Guardado'),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      ref.invalidate(misLigasProvider);
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    if (!_iniciado) {
      _color = mi.liga.color;
      _logo = mi.liga.logoUrl;
      _iniciado = true;
    }
    final t = Theme.of(context).textTheme;
    final colorVista = _color == null ? Theme.of(context).colorScheme.primary : _de(_color!);
    return Scaffold(
      appBar: AppBar(title: const Tx('Color y logotipo')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Vista previa
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: [colorVista, Color.lerp(colorVista, Colors.black, 0.35)!]),
          ),
          child: Row(children: [
            LogoLiga.datos(nombre: mi.liga.nombre, color: colorVista, logoUrl: _logo, tamano: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Text(mi.liga.nombre,
                  style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        Tx('Logotipo', style: t.titleMedium),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.tonalIcon(
            onPressed: _subiendo ? null : () => _elegirLogo(mi.liga),
            icon: _subiendo
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.image_outlined),
            label: Tx(_logo == null ? 'Subir logotipo' : 'Cambiar logotipo'),
          ),
          if (_logo != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: () => setState(() => _logo = null), child: const Tx('Quitar')),
          ],
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Tx('Mejor cuadrado y con fondo, de al menos 256 × 256 píxeles.', style: t.bodySmall),
        ),
        const SizedBox(height: 24),
        Tx('Color de la liga', style: t.titleMedium),
        Tx('La app se tiñe de este color cuando esta liga está activa.', style: t.bodySmall),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _Muestra(
            color: null,
            elegido: _color == null,
            onTap: () => setState(() => _color = null),
          ),
          for (final hex in _paleta)
            _Muestra(color: _de(hex), elegido: _color?.toUpperCase() == hex, onTap: () => setState(() => _color = hex)),
        ]),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _guardando ? null : () => _guardar(mi.liga),
          child: const Tx('Guardar'),
        ),
      ]),
    );
  }
}

class _Muestra extends StatelessWidget {
  const _Muestra({required this.color, required this.elegido, required this.onTap});
  final Color? color;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: color == null ? tr('Colores de Pachanga Fantasy') : '',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color ?? cs.surfaceContainerHighest,
            border: Border.all(color: elegido ? cs.onSurface : cs.outlineVariant, width: elegido ? 3 : 1),
          ),
          child: color == null
              ? Icon(Icons.format_color_reset, size: 20, color: cs.onSurfaceVariant)
              : (elegido ? const Icon(Icons.check, color: Colors.white) : null),
        ),
      ),
    );
  }
}
