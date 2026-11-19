import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

final _solicitudesProvider = FutureProvider.autoDispose<List<String>>((ref) => LigasRepo.misSolicitudesPendientes());

/// Pantalla para usuarios que aún no pertenecen a ninguna liga.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nombre = ref.watch(miPerfilProvider).valueOrNull?.nombre.split(' ').first ?? '';
    final solicitudes = ref.watch(_solicitudesProvider).valueOrNull ?? const [];
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fútbol Fantasy'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              refrescarLigas(ref);
              ref.invalidate(_solicitudesProvider);
            },
          ),
          IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout), onPressed: () => sb.auth.signOut()),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('¡Hola, $nombre!', style: t.headlineSmall),
        const SizedBox(height: 4),
        const Text('Para empezar, crea tu liga o únete a la de tus amigos.'),
        if (solicitudes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.hourglass_top),
              title: const Text('Solicitudes pendientes'),
              subtitle: Text('Esperando aprobación en: ${solicitudes.join(', ')}'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _Opcion(
          icono: Icons.add_circle_outline,
          titulo: 'Crear una liga',
          texto: 'Serás el administrador: campo, precio, formato y jugadores.',
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
      ]),
    );
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
          title: Text(titulo),
          subtitle: Text(texto),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
