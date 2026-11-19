import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

final _euro = NumberFormat.currency(locale: 'es_ES', symbol: '€');
final _fecha = DateFormat("EEE d MMM · HH:mm", 'es');
final _fechaCorta = DateFormat('d/M/yy', 'es');

String euros(num? v) => v == null ? '—' : _euro.format(v);
String fechaHora(DateTime d) => _fecha.format(d.toLocal());
String fechaCorta(DateTime d) => _fechaCorta.format(d.toLocal());

double? toDouble(dynamic v) => v == null ? null : (v as num).toDouble();
int toInt(dynamic v, [int defecto = 0]) => v == null ? defecto : (v as num).toInt();

/// Valida un enlace de Google Maps (formatos habituales al compartir desde la app de Maps).
bool esEnlaceMaps(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.scheme != 'https') return false;
  final h = u.host.toLowerCase();
  return h == 'maps.app.goo.gl' ||
      h == 'goo.gl' && u.path.startsWith('/maps') ||
      h.startsWith('maps.google.') ||
      (h.contains('google.') && u.path.startsWith('/maps'));
}

Future<void> abrirUrl(BuildContext context, String? url) async {
  if (url == null || url.isEmpty) return;
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) mostrarError(context, 'No se pudo abrir el enlace');
}

/// Mensaje legible a partir de una excepción de Supabase o genérica.
String mensajeError(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  if (e is StorageException) return e.message;
  return e.toString();
}

void mostrarError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(e is String ? e : mensajeError(e)),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

void mostrarOk(BuildContext context, String texto) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
}

/// Ejecuta una acción mostrando el error si falla. Devuelve true si fue bien.
Future<bool> ejecutar(BuildContext context, Future<void> Function() accion, {String? ok}) async {
  try {
    await accion();
    if (ok != null && context.mounted) mostrarOk(context, ok);
    return true;
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
    return false;
  }
}

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String accion = 'Aceptar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(accion)),
      ],
    ),
  );
  return r ?? false;
}

/// Contenido estándar para AsyncValue con error.
class ErrorVista extends StatelessWidget {
  const ErrorVista(this.error, {super.key, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 8),
            Text(mensajeError(error), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ]),
        ),
      );
}

class Cargando extends StatelessWidget {
  const Cargando({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class Vacio extends StatelessWidget {
  const Vacio(this.texto, {super.key, this.icono = Icons.inbox_outlined});
  final String texto;
  final IconData icono;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
          ]),
        ),
      );
}
