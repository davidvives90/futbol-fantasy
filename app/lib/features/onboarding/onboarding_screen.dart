import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';
import '../../core/liga_activa.dart';
import 'bienvenida.dart';
import '../../core/ventajas.dart';

final _solicitudesProvider = FutureProvider.autoDispose<List<String>>((ref) => LigasRepo.misSolicitudesPendientes());

/// Pantalla para usuarios que aún no pertenecen a ninguna liga.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Igual que en el resto de la app: el apodo si lo hay, si no el nombre
    final perfil = ref.watch(miPerfilProvider).valueOrNull;
    final nombre = (perfil?.apodo?.isNotEmpty ?? false) ? perfil!.apodo! : (perfil?.nombre.split(' ').first ?? '');
    final solicitudes = ref.watch(_solicitudesProvider).valueOrNull ?? const [];
    final t = Theme.of(context).textTheme;
    mostrarBienvenidaSiToca(context, ref.read(prefsProvider));

    return SinPublicidad(child: Scaffold(
      appBar: AppBar(
        title: const Tx('Fútbol Fantasy'),
      ),
      // Sin iconos sueltos arriba: se actualiza deslizando hacia abajo y «Cerrar sesión» va al final, con texto
      body: RefreshIndicator(
        onRefresh: () async {
          refrescarLigas(ref);
          ref.invalidate(_solicitudesProvider);
        },
        child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('¡Hola, $nombre!', style: t.headlineSmall),
        const SizedBox(height: 4),
        const Tx('Para empezar, crea tu liga o únete a la de tus amigos.'),
        if (solicitudes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.hourglass_top),
              title: const Tx('Solicitudes pendientes'),
              subtitle: Text(trf('Esperando aprobación en: {l}', {'l': solicitudes.toSet().join(', ')})),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _Opcion(
          icono: Icons.add_circle_outline,
          titulo: 'Crear una liga',
          texto: 'Elige modo básico, medio o avanzado. Serás el administrador.',
          onTap: () => context.push('/crear-liga'),
        ),
        _Opcion(
          icono: Icons.vpn_key_outlined,
          titulo: 'Tengo un código o enlace',
          texto: 'Pega el código de 6 letras o el enlace que te enviaron.',
          onTap: () => context.push('/unirse'),
        ),
        _Opcion(
          icono: Icons.search,
          titulo: 'Buscar ligas públicas',
          texto: 'Busca por nombre o ciudad y solicita entrar.',
          onTap: () => context.push('/buscar-ligas'),
        ),
        const SizedBox(height: 32),
        Center(
          child: TextButton.icon(
            onPressed: () async {
              if (await confirmar(context, 'Cerrar sesión', '¿Seguro que quieres salir?')) await sb.auth.signOut();
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Tx('Cerrar sesión'),
          ),
        ),
      ]),
      ),
    ));
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({required this.icono, required this.titulo, required this.texto, required this.onTap});
  final IconData icono;
  final String titulo, texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(icono, size: 32),
          title: Text(tr(titulo)),
          subtitle: Text(tr(texto)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
