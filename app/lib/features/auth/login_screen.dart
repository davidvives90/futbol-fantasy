import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/idioma.dart';
import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../privacidad/consentimiento.dart' show urlPoliticaPrivacidad, urlCondiciones;

/// Inicio de sesión: Google, correo y contraseña, o código/enlace al correo (sin contraseña).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _clave = TextEditingController();
  bool _enviando = false;
  bool _verClave = false;
  late final TapGestureRecognizer _tapCondiciones = TapGestureRecognizer()
    ..onTap = () => abrirUrl(context, urlCondiciones);
  late final TapGestureRecognizer _tapPrivacidad = TapGestureRecognizer()
    ..onTap = () => abrirUrl(context, urlPoliticaPrivacidad);

  @override
  void dispose() {
    _email.dispose();
    _clave.dispose();
    _tapCondiciones.dispose();
    _tapPrivacidad.dispose();
    super.dispose();
  }

  /// Cuentas de prueba (0052): «admin1» … «admin5» en el email entra sin código, si el servidor lo permite.
  static final _cuentaPrueba = RegExp(r'^admin[\s_-]?[1-5]$', caseSensitive: false);

  String get _mail => _email.text.trim();

  bool _emailValido() {
    if (_mail.contains('@') && _mail.contains('.')) return true;
    mostrarError(context, 'Escribe un email válido');
    return false;
  }

  Future<void> _ocupado(Future<void> Function() f) async {
    setState(() => _enviando = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _entrarPrueba(String codigo) => _ocupado(() async {
        await ejecutar(context, () async {
          final r = await sb.functions.invoke('entrar-pruebas', body: {'codigo': codigo});
          final d = r.data as Map;
          if (d['token'] == null) throw tr('Las cuentas de prueba están desactivadas');
          await sb.auth.verifyOTP(email: d['email'] as String, token: d['token'] as String, type: OtpType.email);
        });
      });

  // ───── Con contraseña
  Future<void> _entrarConClave() async {
    if (_cuentaPrueba.hasMatch(_mail)) return _entrarPrueba(_mail);
    if (!_emailValido()) return;
    if (_clave.text.isEmpty) {
      mostrarError(context, 'Escribe tu contraseña');
      return;
    }
    await _ocupado(() async {
      try {
        await sb.auth.signInWithPassword(email: _mail, password: _clave.text);
      } on AuthException catch (e) {
        if (!mounted) return;
        final m = e.message.toLowerCase();
        if (m.contains('invalid login') || m.contains('invalid credentials')) {
          mostrarError(context,
              'Email o contraseña incorrectos. Si siempre entrabas con código o con Google, entra así y crea tu contraseña en Perfil › Cuenta.');
        } else if (m.contains('not confirmed')) {
          mostrarError(context, 'Confirma tu email con el enlace que te enviamos al crear la cuenta.');
        } else {
          mostrarError(context, e.message);
        }
      } catch (e) {
        if (mounted) mostrarError(context, mensajeError(e));
      }
    });
  }

  Future<void> _crearCuenta() async {
    if (!_emailValido()) return;
    if (_clave.text.length < 8) {
      mostrarError(context, 'La contraseña debe tener al menos 8 caracteres');
      return;
    }
    await _ocupado(() async {
      final ok = await ejecutar(context,
          () => sb.auth.signUp(email: _mail, password: _clave.text, emailRedirectTo: Env.loginRedirect));
      if (ok && mounted && sb.auth.currentSession == null) {
        await showDialog<void>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Tx('Revisa tu correo'),
            content: Text(trf(
                'Te hemos enviado un enlace a {e} para confirmar la cuenta. Si ya tenías cuenta con ese correo, entra con el código y crea tu contraseña en Perfil › Cuenta.',
                {'e': _mail})),
            actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Tx('Entendido'))],
          ),
        );
      }
    });
  }

  Future<void> _olvide() async {
    if (!_emailValido()) return;
    await _ocupado(() async {
      final ok = await ejecutar(context, () => sb.auth.resetPasswordForEmail(_mail, redirectTo: Env.loginRedirect));
      if (ok && mounted) {
        mostrarOk(context, trf('Te hemos enviado un enlace a {e} para crear una contraseña nueva.', {'e': _mail}));
      }
    });
  }

  Future<void> _google() => _ocupado(() async {
        await ejecutar(context, () => sb.auth.signInWithOAuth(OAuthProvider.google, redirectTo: Env.loginRedirect));
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // En ordenador, el formulario no se estira a todo el ancho
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Align(alignment: Alignment.centerRight, child: SelectorIdioma()),
                  const SizedBox(height: 16),
                  // Logo (ya lleva el nombre de la app)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset('assets/icono/icono.png', width: 120, height: 120, semanticLabel: 'Pachanga Fantasy'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Tx('Convocatorias, caja y liga Fantasy con tus amigos', textAlign: TextAlign.center, style: t.bodyMedium),
                  const SizedBox(height: 24),
                  // Google primero: es lo más rápido
                  if (const bool.fromEnvironment('GOOGLE_LOGIN')) ...[
                    OutlinedButton.icon(
                      onPressed: _enviando ? null : _google,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1F1F1F),
                        side: const BorderSide(color: Color(0xFF747775)),
                      ),
                      icon: const _LogoGoogle(),
                      label: const Tx('Continuar con Google'),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(padding: const EdgeInsets.all(8), child: Tx('o con tu email', style: t.bodySmall)),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email, AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: tr('Email'), prefixIcon: const Icon(Icons.mail_outline)),
                  ),
                  const SizedBox(height: 12),
                  ...[
                    TextField(
                      controller: _clave,
                      obscureText: !_verClave,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _entrarConClave(),
                      decoration: InputDecoration(
                        labelText: tr('Contraseña'),
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                          tooltip: tr(_verClave ? 'Ocultar' : 'Mostrar'),
                          icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _verClave = !_verClave),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: _enviando ? null : _olvide, child: const Tx('¿Has olvidado la contraseña?')),
                    ),
                    FilledButton(
                      onPressed: _enviando ? null : _entrarConClave,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: Text(tr(_enviando ? 'Entrando…' : 'Entrar')),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _enviando ? null : _crearCuenta, child: const Tx('¿Primera vez? Crear cuenta con esta contraseña')),
                    // 0062: ya no se entra con código. Quien entraba así crea su contraseña con «¿Has olvidado…?»
                    Tx('¿Antes entrabas con un código del correo? Pulsa «¿Has olvidado la contraseña?» y crea una.',
                        textAlign: TextAlign.center, style: t.bodySmall),
                  ],
                  const SizedBox(height: 28),
                  // Condiciones y privacidad, visibles antes de entrar
                  Text.rich(
                    TextSpan(style: t.bodySmall, children: [
                      TextSpan(text: '${tr('Al continuar aceptas las')} '),
                      TextSpan(
                        text: tr('Condiciones del servicio'),
                        style: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
                        recognizer: _tapCondiciones,
                      ),
                      TextSpan(text: ' ${tr('y la')} '),
                      TextSpan(
                        text: tr('Política de privacidad'),
                        style: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
                        recognizer: _tapPrivacidad,
                      ),
                      const TextSpan(text: '.'),
                    ]),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «G» de Google en sus cuatro colores (sin depender de imágenes externas).
class _LogoGoogle extends StatelessWidget {
  const _LogoGoogle();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 20, height: 20, child: CustomPaint(painter: _PintorG()));
}

class _PintorG extends CustomPainter {
  const _PintorG();

  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    final w = s.width * 0.2;
    final arco = r.deflate(w / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    const pi = 3.141592653589793;
    // Rojo arriba, amarillo a la izquierda abajo, verde abajo, azul a la derecha
    p.color = const Color(0xFFEA4335);
    c.drawArc(arco, -pi * 0.78, pi * 0.55, false, p);
    p.color = const Color(0xFFFBBC05);
    c.drawArc(arco, pi * 0.72, pi * 0.52, false, p);
    p.color = const Color(0xFF34A853);
    c.drawArc(arco, pi * 0.22, pi * 0.52, false, p);
    p.color = const Color(0xFF4285F4);
    c.drawArc(arco, -pi * 0.22, pi * 0.44, false, p);
    final barra = Paint()..color = const Color(0xFF4285F4);
    c.drawRect(Rect.fromLTWH(s.width * 0.5, s.height * 0.5 - w / 2, s.width * 0.5 - w / 4, w), barra);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
