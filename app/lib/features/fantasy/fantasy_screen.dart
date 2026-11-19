import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../shell/home_shell.dart';
import '../../core/utils.dart';
import 'clasificacion_managers_tab.dart';
import 'fantasy_providers.dart';
import 'mercado_tab.dart';
import 'mi_equipo_tab.dart';

/// Pestaña inferior "Fantasy": Mi equipo · Mercado · Mánagers.
class FantasyScreen extends ConsumerWidget {
  const FantasyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: const LigaAppBar(
          bottom: TabBar(tabs: [
            Tab(icon: Icon(Icons.shield_outlined), text: 'Mi equipo'),
            Tab(icon: Icon(Icons.storefront_outlined), text: 'Mercado'),
            Tab(icon: Icon(Icons.emoji_events_outlined), text: 'Mánagers'),
          ]),
        ),
        body: Column(children: [
          EncuestaPendienteCard(mi: mi),
          Expanded(
            child: TabBarView(children: [
              MiEquipoTab(mi: mi),
              MercadoTab(mi: mi),
              ClasificacionManagersTab(mi: mi),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Tarjeta destacada si hay una encuesta de valoración abierta que el usuario no ha completado.
/// Se muestra en Fantasy y en Partidos (inicio).
class EncuestaPendienteCard extends ConsumerWidget {
  const EncuestaPendienteCard({super.key, required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes =
        ref.watch(encuestasPendientesProvider((ligaId: mi.liga.id, miembroId: mi.yo.id))).valueOrNull ?? const [];
    if (pendientes.isEmpty) return const SizedBox.shrink();
    final e = pendientes.first;
    final cs = Theme.of(context).colorScheme;
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: cs.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.how_to_vote_outlined, color: cs.onTertiaryContainer),
        title: Text(e.esMini ? 'Coloca a ${miembros[e.sujetoId]?.nombre ?? 'un jugador nuevo'}' : 'Valora a los jugadores de la liga',
            style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
        subtitle: Text(
          e.esMini
              ? 'Mini-encuesta: indica dónde lo pondrías en cada ranking.'
              : 'Ordénalos en 6 rankings. Con esto se fijan los precios iniciales del mercado.',
          style: TextStyle(color: cs.onTertiaryContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: cs.onTertiaryContainer),
        onTap: () => context.push('/fantasy/encuesta/${e.id}'),
      ),
    );
  }
}
