import 'package:flutter/material.dart';
import 'idioma.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'idioma.dart';
import 'theme.dart';
import 'errores.dart';

final _euro = NumberFormat.currency(locale: 'es_ES', symbol: '€');
// Formatos de fecha en el idioma elegido (se crean al usarlos para seguir los cambios de idioma)
DateFormat get _fecha => DateFormat("EEE d MMM · HH:mm", idiomaActual);
DateFormat get _fechaCorta => DateFormat('d/M/yy', idiomaActual);

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

/// ¿Es un fallo de conexión (sin internet, servidor inaccesible, tiempo agotado)?
bool esErrorConexion(Object e) {
  final t = e.toString().toLowerCase();
  return t.contains('socketexception') ||
      t.contains('failed host lookup') ||
      t.contains('clientexception') ||
      t.contains('xmlhttprequest') ||
      t.contains('failed to fetch') ||
      t.contains('network') ||
      t.contains('timeoutexception') ||
      t.contains('connection');
}

/// Mensaje legible y con qué hacer, a partir de una excepción de Supabase o genérica.
/// Los mensajes de las funciones del servidor ya están pensados para el usuario y se dejan tal cual.
String mensajeError(Object e) {
  if (esErrorConexion(e)) return 'Sin conexión. Revisa tu internet y vuelve a intentarlo.';
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || m.contains('jwt')) return 'Tu sesión ha caducado. Cierra sesión y vuelve a entrar.';
    if (m.contains('invalid') && m.contains('otp')) return 'El código no es correcto o ha caducado. Pide uno nuevo.';
    return e.message;
  }
  if (e is PostgrestException) {
    final m = e.message.toLowerCase();
    if (e.code == 'PGRST301' || m.contains('jwt')) return 'Tu sesión ha caducado. Cierra sesión y vuelve a entrar.';
    if (m.contains('row-level security') || m.contains('permission denied')) {
      return 'No tienes permiso para hacer esto. Si crees que es un error, habla con el admin de la liga.';
    }
    if (e.code == '23505') return 'Eso ya existe. Revisa si ya estaba hecho.';
    if (e.code == '23514' || e.code == '22P02') return 'Algún dato no es válido. Revísalo y vuelve a intentarlo.';
    return e.message;
  }
  if (e is StorageException) return 'No se ha podido subir o leer el archivo. Vuelve a intentarlo.';
  if (e is String) return e;
  return 'Algo ha fallado. Vuelve a intentarlo en unos segundos.';
}

void mostrarError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
    SnackBar(
      content: Text(tr(e is String ? e : mensajeError(e))),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

/// Un aviso cada vez: el nuevo sustituye al anterior (si no, se encolan y siguen saliendo minutos después).
void mostrarOk(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(tr(texto)), duration: const Duration(milliseconds: 2500)));
}

/// Ejecuta una acción mostrando el error si falla. Devuelve true si fue bien.
Future<bool> ejecutar(BuildContext context, Future<void> Function() accion, {String? ok}) async {
  try {
    await accion();
    if (ok != null && context.mounted) mostrarOk(context, ok);
    return true;
  } catch (e, s) {
    Errores.registrar(e, s); // solo se guardan los inesperados (no los mensajes de validación)
    if (context.mounted) mostrarError(context, e);
    return false;
  }
}

/// Tipo de acción que confirma el diálogo: decide el color del botón final.
enum TipoConfirmacion { normal, peligro, premium }

Future<bool> confirmar(BuildContext context, String titulo, String texto,
    {String accion = 'Aceptar', TipoConfirmacion tipo = TipoConfirmacion.normal}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(titulo)),
      content: Text(tr(texto)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Tx('Cancelar')),
        FilledButton(
          style: switch (tipo) {
            TipoConfirmacion.peligro => AppButtons.peligroRelleno(c),
            TipoConfirmacion.premium => AppButtons.premium(c),
            TipoConfirmacion.normal => null,
          },
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr(accion)),
        ),
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
            Icon(esErrorConexion(error) ? Icons.cloud_off_outlined : Icons.error_outline, size: 44),
            const SizedBox(height: 8),
            Text(tr(mensajeError(error)), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Tx('Reintentar')),
            ],
          ]),
        ),
      );
}

/// Carga: «esqueleto» con la forma de una lista (filas con avatar y dos líneas) que late suavemente.
/// Se percibe más rápido que un spinner y evita saltos cuando llegan los datos.
class Cargando extends StatefulWidget {
  const Cargando({super.key, this.filas = 6});
  final int filas;

  @override
  State<Cargando> createState() => _CargandoState();
}

class _CargandoState extends State<Cargando> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget barra(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        );
    return LayoutBuilder(builder: (context, caja) {
      // Ajusta el nº de filas al hueco disponible (nunca desborda)
      final caben = caja.maxHeight.isFinite ? ((caja.maxHeight - 32) / 60).floor().clamp(0, widget.filas).toInt() : widget.filas;
      if (caben == 0) {
        return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
      }
      return _esqueleto(caben, barra, color);
    });
  }

  Widget _esqueleto(int filas, Widget Function(double, double) barra, Color color) {
    return Semantics(
      label: 'Cargando',
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < filas; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      barra(i.isEven ? 160 : 120, 12),
                      const SizedBox(height: 8),
                      barra(i.isEven ? 90 : 140, 10),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Estado vacío: icono en un círculo suave, título opcional, texto y, si procede, una acción principal.
class Vacio extends StatelessWidget {
  const Vacio(this.texto, {super.key, this.icono = Icons.inbox_outlined, this.titulo, this.accion, this.onAccion});
  final String texto;
  final IconData icono;
  final String? titulo;
  final String? accion;
  final VoidCallback? onAccion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.6), shape: BoxShape.circle),
            child: Icon(icono, size: 42, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 16),
          if (titulo != null) ...[
            Text(tr(titulo!), textAlign: TextAlign.center, style: t.titleMedium),
            const SizedBox(height: 6),
          ],
          Text(tr(texto), textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          if (accion != null && onAccion != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAccion, child: Text(tr(accion!))),
          ],
        ]),
      ),
    );
  }
}

/// Aviso con «Deshacer» para acciones reversibles (en lugar de pedir confirmación antes).
void avisoDeshacer(BuildContext context, String texto, VoidCallback deshacer) {
  final m = ScaffoldMessenger.of(context);
  m.clearSnackBars();
  m.showSnackBar(SnackBar(
    content: Text(texto),
    duration: const Duration(seconds: 5),
    action: SnackBarAction(label: 'Deshacer', onPressed: deshacer),
  ));
}

/// Fecha en formato SQL `date` (AAAA-MM-DD), sin hora ni zona.
String fechaSql(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
