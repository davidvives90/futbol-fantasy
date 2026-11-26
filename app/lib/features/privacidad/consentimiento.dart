import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/anuncios.dart';
import '../../core/errores.dart';
import '../../core/idioma.dart';
import '../../core/supabase.dart';
import '../../core/utils.dart';

/// Estado del consentimiento RGPD del usuario (0053): política vigente, última aceptación y si está al día.
class Consentimiento {
  Consentimiento(this.version, this.url, this.alDia, this.aceptadoEn, this.errores);
  final String version, url;
  final bool alDia, errores;
  final DateTime? aceptadoEn;

  factory Consentimiento.fromMap(Map<String, dynamic> m) {
    final p = (m['politica'] as Map?) ?? const {};
    final u = m['ultimo'] as Map?;
    final f = (u?['consent_flags'] as Map?) ?? const {};
    return Consentimiento(
      p['version'] as String? ?? '',
      p['url'] as String? ?? '',
      m['al_dia'] == true,
      u?['accepted_at'] == null ? null : DateTime.parse(u!['accepted_at'] as String).toLocal(),
      f['errores'] == true,
    );
  }
}

final consentimientoProvider = FutureProvider.autoDispose.family<Consentimiento?, String?>((ref, uid) async {
  if (uid == null) return null;
  final r = await sb.rpc('mi_consentimiento');
  final c = Consentimiento.fromMap(Map<String, dynamic>.from(r as Map));
  Errores.activo = c.alDia && c.errores; // solo con el permiso opcional aceptado
  return c;
});

String get _plataforma => kIsWeb ? 'web' : defaultTargetPlatform.name;

/// Envuelve la app: con sesión iniciada y sin aceptar la política vigente, solo se ve la pantalla de aceptación.
/// Vuelve a salir cada vez que se publica una versión nueva de la política.
class PuertaConsentimiento extends ConsumerStatefulWidget {
  const PuertaConsentimiento({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PuertaConsentimiento> createState() => _PuertaConsentimientoState();
}

class _PuertaConsentimientoState extends ConsumerState<PuertaConsentimiento> {
  String? _uid = sb.auth.currentUser?.id;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = sb.auth.onAuthStateChange.listen((e) {
      final u = e.session?.user.id;
      if (u != _uid && mounted) setState(() => _uid = u);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) return widget.child;
    final c = ref.watch(consentimientoProvider(_uid));
    // Si no se puede comprobar (sin conexión), no se bloquea la app: se volverá a pedir en el siguiente arranque.
    final pendiente = c.valueOrNull != null && !c.valueOrNull!.alDia;
    if (!pendiente) return widget.child;
    return PantallaConsentimiento(
      consentimiento: c.value!,
      onAceptado: () => ref.invalidate(consentimientoProvider(_uid)),
    );
  }
}

class PantallaConsentimiento extends StatefulWidget {
  const PantallaConsentimiento({super.key, required this.consentimiento, required this.onAceptado});
  final Consentimiento consentimiento;
  final VoidCallback onAceptado;

  @override
  State<PantallaConsentimiento> createState() => _PantallaConsentimientoState();
}

class _PantallaConsentimientoState extends State<PantallaConsentimiento> {
  bool _acepto = false;
  bool _errores = true;
  bool _enviando = false;

  Future<void> _aceptar() async {
    setState(() => _enviando = true);
    try {
      await sb.rpc('registrar_consentimiento', params: {
        'p_version': widget.consentimiento.version,
        'p_errores': _errores,
        'p_anuncios': false,
        'p_plataforma': _plataforma,
      });
      Errores.activo = _errores;
      widget.onAceptado();
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(mensajeError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final nueva = widget.consentimiento.aceptadoEn != null;
    Widget punto(IconData i, String titulo, String texto) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(i, color: cs.primary),
          title: Tx(titulo, style: t.titleSmall),
          subtitle: Tx(texto),
        );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              Icon(Icons.privacy_tip_outlined, size: 48, color: cs.primary),
              const SizedBox(height: 12),
              Tx(nueva ? 'Hemos actualizado la política de privacidad' : 'Antes de empezar',
                  style: t.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Tx('Resumen en lenguaje claro. El texto completo está en el enlace de abajo.',
                  style: t.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              punto(Icons.person_outline, 'Qué guardamos',
                  'Tu email, nombre, apodo, foto y posición, y los datos deportivos de tus ligas: asistencia, goles, '
                      'votaciones, pagos y el juego Fantasy.'),
              punto(Icons.groups_outlined, 'Quién lo ve',
                  'Los miembros de tus ligas ven tu perfil y tus datos deportivos de esa liga. No vendemos tus datos.'),
              punto(Icons.campaign_outlined, 'Anuncios',
                  'La versión gratuita muestra anuncios de Google. En Europa, Google te pregunta aparte si quieres '
                      'anuncios personalizados; puedes cambiarlo cuando quieras.'),
              punto(Icons.delete_outline, 'Tus derechos',
                  'Puedes consultar, corregir o eliminar tu cuenta y tus datos desde Perfil → Privacidad y datos.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Tx('Leer la política completa'),
                onPressed: () => launchUrl(Uri.parse(widget.consentimiento.url), mode: LaunchMode.externalApplication),
              ),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _errores,
                onChanged: (v) => setState(() => _errores = v),
                title: const Tx('Enviar informes de errores (opcional)'),
                subtitle: const Tx('Si algo falla, se envía qué pantalla y qué error, para arreglarlo.'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _acepto,
                onChanged: (v) => setState(() => _acepto = v ?? false),
                title: const Tx('He leído y acepto los términos de uso y la política de privacidad'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _acepto && !_enviando ? _aceptar : null,
                child: _enviando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Tx('Aceptar y continuar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _enviando ? null : () => sb.auth.signOut(),
                child: const Tx('No acepto (cerrar sesión)'),
              ),
              Tx(trf('Versión de la política: {v}', {'v': widget.consentimiento.version}),
                  style: t.bodySmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Perfil → Privacidad y datos: lo aceptado, permisos opcionales, anuncios y eliminar la cuenta.
class PrivacidadScreen extends ConsumerWidget {
  const PrivacidadScreen({super.key, required this.onEliminarCuenta});
  final Future<void> Function(BuildContext, WidgetRef) onEliminarCuenta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = sb.auth.currentUser?.id;
    final c = ref.watch(consentimientoProvider(uid));
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Tx('Privacidad y datos')),
      body: c.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(consentimientoProvider(uid))),
        data: (d) => ListView(children: [
          if (d != null)
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(trf('Política aceptada · versión {v}', {'v': d.version})),
              subtitle: d.aceptadoEn == null ? null : Text(fechaHora(d.aceptadoEn!)),
            ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Tx('Leer la política de privacidad'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse(d?.url.isNotEmpty == true ? d!.url : urlPoliticaPrivacidad),
                mode: LaunchMode.externalApplication),
          ),
          if (d != null)
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: const Tx('Enviar informes de errores'),
              subtitle: const Tx('Opcional. Puedes retirarlo cuando quieras.'),
              value: d.errores,
              onChanged: (v) => ejecutar(context, () async {
                await sb.rpc('registrar_consentimiento', params: {
                  'p_version': d.version,
                  'p_errores': v,
                  'p_anuncios': false,
                  'p_plataforma': _plataforma,
                });
                Errores.activo = v;
                ref.invalidate(consentimientoProvider(uid));
              }),
            ),
          FutureBuilder<bool>(
            future: Anuncios.hayOpcionesPrivacidad(),
            builder: (_, s) => s.data == true
                ? ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: const Tx('Anuncios personalizados'),
                    subtitle: const Tx('Cambia tu consentimiento de anuncios personalizados'),
                    onTap: Anuncios.abrirOpcionesPrivacidad,
                  )
                : const SizedBox.shrink(),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Tx('Condiciones del servicio'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse(urlCondiciones), mode: LaunchMode.externalApplication),
          ),
          // 0059: portabilidad (RGPD): todos tus datos en un archivo JSON
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Tx('Descargar mis datos'),
            subtitle: const Tx('Tu perfil, ligas, partidos, logros, pagos y Fantasy en un archivo'),
            onTap: () => ejecutar(context, () async {
              final datos = await sb.rpc('exportar_mis_datos');
              final texto = const JsonEncoder.withIndent('  ').convert(datos);
              await Share.shareXFiles(
                [XFile.fromData(Uint8List.fromList(utf8.encode(texto)), mimeType: 'application/json', name: 'mis_datos_pachanga.json')],
                fileNameOverrides: ['mis_datos_pachanga.json'],
                subject: tr('Mis datos de Pachanga Fantasy'),
              );
            }),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.person_remove_outlined, color: cs.error),
            title: Tx('Eliminar mi cuenta y mis datos', style: TextStyle(color: cs.error)),
            subtitle: const Tx('Borra tu perfil, foto, acceso y consentimientos. No se puede deshacer.'),
            onTap: () => onEliminarCuenta(context, ref),
          ),
        ]),
      ),
    );
  }
}

const urlPoliticaPrivacidad = 'https://www.pachangafantasy.com/privacidad';
const urlCondiciones = 'https://www.pachangafantasy.com/condiciones';
