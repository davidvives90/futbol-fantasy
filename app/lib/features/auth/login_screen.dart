import 'package:flutter/material.dart';
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
  bool _enviando = false;
  bool _enviado = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _enlaceMagico() async {
    final email = _email.text.trim();
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.sports_soccer, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('Fútbol Fantasy', textAlign: TextAlign.center, style: t.headlineMedium),
              Text('Convocatorias, caja y liga Fantasy con tus amigos',
                  textAlign: TextAlign.center, style: t.bodyMedium),
              const SizedBox(height: 32),
              if (_enviado)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Te hemos enviado un enlace a ${_email.text.trim()}. Ábrelo desde este móvil para entrar.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  onSubmitted: (_) => _enlaceMagico(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _enviando ? null : _enlaceMagico,
                  child: Text(_enviando ? 'Enviando…' : 'Recibir enlace de acceso'),
                ),
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
                  label: const Text('Continuar con Google'),
                ),
              ],
              if (_enviado)
                TextButton(onPressed: () => setState(() => _enviado = false), child: const Text('Usar otro email')),
            ]),
          ),
        ),
      ),
    );
  }
}
