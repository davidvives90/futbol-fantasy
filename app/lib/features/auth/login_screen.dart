import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../../core/utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _codigo = TextEditingController();
  bool _enviando = false;
  bool _enviado = false;

  @override
  void dispose() {
    _email.dispose();
    _codigo.dispose();
    super.dispose();
  }

  /// Cuentas de prueba (0052): «admin1» … «admin5» en el email entra sin código, si el servidor lo permite.
  static final _cuentaPrueba = RegExp(r'^admin[\s_-]?[1-5]$', caseSensitive: false);

  Future<void> _entrarPrueba(String codigo) async {
    setState(() => _enviando = true);
    await ejecutar(context, () async {
      final r = await sb.functions.invoke('entrar-pruebas', body: {'codigo': codigo});
      final d = r.data as Map;
      if (d['token'] == null) throw tr('Las cuentas de prueba están desactivadas');
      await sb.auth.verifyOTP(email: d['email'] as String, token: d['token'] as String, type: OtpType.email);
    });
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _enlaceMagico() async {
    final email = _email.text.trim();
    if (_cuentaPrueba.hasMatch(email)) {
      await _entrarPrueba(email);
      return;
    }
    if (!email.contains('@')) {
      mostrarError(context, 'Escribe un email válido');
      return;
    }
    setState(() => _enviando = true);
    final ok = await ejecutar(context, () => sb.auth.signInWithOtp(email: email, emailRedirectTo: Env.loginRedirect));
    if (mounted) setState(() {
      _enviando = false;
      _enviado = ok;
    });
  }

  /// Entrar con el código del correo (imprescindible en la web instalada en iPhone: el enlace se abriría en Safari).
  Future<void> _entrarConCodigo() async {
    final codigo = _codigo.text.replaceAll(' ', '');
    if (codigo.length < 6) {
      mostrarError(context, 'Escribe el código del correo');
      return;
    }
    await ejecutar(context,
        () => sb.auth.verifyOTP(email: _email.text.trim(), token: codigo, type: OtpType.email));
  }

  Future<void> _google() async {
    await ejecutar(
      context,
      () => sb.auth.signInWithOAuth(OAuthProvider.google, redirectTo: Env.loginRedirect),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // En ordenador, el formulario no se estira a todo el ancho
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SelectorIdioma(),
              const SizedBox(height: 16),
              Icon(Icons.sports_soccer, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Tx('Fútbol Fantasy', textAlign: TextAlign.center, style: t.headlineMedium),
              Tx('Convocatorias, caja y liga Fantasy con tus amigos',
                  textAlign: TextAlign.center, style: t.bodyMedium),
              const SizedBox(height: 32),
              if (_enviado)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      trf('Te hemos enviado un correo a {e}. Abre el enlace desde este móvil o escribe aquí el código que viene en el correo.',
                          {'e': _email.text.trim()}),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration:  InputDecoration(labelText: tr('Email'), prefixIcon: Icon(Icons.mail_outline)),
                  onSubmitted: (_) => _enlaceMagico(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _enviando ? null : _enlaceMagico,
                  child: Text(tr(_enviando ? 'Enviando…' : 'Entrar con mi email')),
                ),
                const SizedBox(height: 8),
                Tx('Sin contraseñas: te mandamos un enlace o un código al correo. Si es tu primera vez, la cuenta se crea sola.',
                    textAlign: TextAlign.center, style: t.bodySmall),
              ],
              // Google se activa compilando con --dart-define=GOOGLE_LOGIN=true
              // cuando el proveedor esté configurado en Supabase (Authentication → Sign In / Providers → Google).
              if (const bool.fromEnvironment('GOOGLE_LOGIN')) ...[
                const SizedBox(height: 24),
                const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.all(8), child: Text('o')), Expanded(child: Divider())]),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _google,
                  icon: const Icon(Icons.login),
                  label: const Tx('Continuar con Google'),
                ),
              ],
              if (_enviado) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _codigo,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textAlign: TextAlign.center,
                  decoration:  InputDecoration(labelText: tr('Código del correo'), prefixIcon: Icon(Icons.pin_outlined)),
                  onSubmitted: (_) => _entrarConCodigo(),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(onPressed: _entrarConCodigo, child: const Tx('Entrar con el código')),
                TextButton(onPressed: () => setState(() => _enviado = false), child: const Tx('Usar otro email')),
              ],
            ]),
          ),
          ),
        ),
      ),
    );
  }
}
