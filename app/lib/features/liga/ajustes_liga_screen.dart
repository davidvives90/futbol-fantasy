import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../data/providers.dart';

/// Ajustes de la liga (solo admin): todo lo que se configura, agrupado, fuera de la vista de jugadores.
class AjustesLigaScreen extends ConsumerWidget {
  const AjustesLigaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    if (!mi.soyAdmin) {
      return Scaffold(appBar: AppBar(), body: const Vacio('Solo los administradores pueden cambiar los ajustes.'));
    }
    Widget grupo(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
          child: Text(t.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 1, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        );
    Widget opcion(IconData i, String titulo, String sub, String ruta) => ListTile(
          leading: Icon(i),
          title: Text(titulo),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(ruta),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes de la liga')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        grupo('Liga'),
        opcion(Icons.edit_outlined, 'Datos de la liga', 'Nombre, campo, plazas, equipos y precio', '/liga/editar'),
        opcion(Icons.checkroom, 'Equipaciones', 'Qué lleva cada equipo (p. ej. blanco y color)', '/liga/equipaciones'),
        opcion(Icons.menu_book_outlined, 'Normas y guía', 'Lo acordado en la liga y cómo funciona todo', '/guia'),
        grupo('Partidos'),
        opcion(Icons.event_repeat, 'Programar temporada', 'Partidos recurrentes entre dos fechas', '/temporada'),
        opcion(Icons.how_to_reg_outlined, 'Convocatoria y cobro', 'Lista de espera, factura mensual y precio de reservas',
            '/liga/convocatoria'),
        grupo('Puntuación y Fantasy'),
        opcion(Icons.rule, 'Puntuación y valoraciones', 'Puntos por acción, valoración rápida o detallada', '/liga/reglas'),
        opcion(Icons.storefront_outlined, 'Fantasy', 'Encuesta, mercado, multiplicador de invitados y bonus por rol', '/liga/fantasy'),
      ]),
    );
  }
}
