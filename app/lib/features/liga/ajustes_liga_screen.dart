import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/exportar.dart';
import '../../core/utils.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

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
        grupo('Módulos'),
        _Interruptor(
          titulo: 'Fantasy',
          activo: mi.liga.fantasyActivo,
          on: 'Mercado, plantillas y alineaciones',
          off: 'Desactivado: la liga usa solo convocatorias, caja y estadísticas',
          campo: 'fantasy_activo',
          ligaId: mi.liga.id,
        ),
        _Interruptor(
          titulo: 'Resultado esperado (xG)',
          activo: mi.liga.prediccionActiva,
          on: 'Con los equipos hechos, la app estima goles y probabilidades',
          off: 'Desactivado',
          campo: 'prediccion_activa',
          ligaId: mi.liga.id,
        ),
        _Interruptor(
          titulo: 'Post-partido avanzado',
          activo: mi.liga.valoracionAvanzada,
          on: 'Además: «Destacó en», autogoles/paradas/penaltis, «No le vi» y valoración por aspectos',
          off: 'Simple: goles y asistencias, nota del 1 al 5 a todos y estrella MVP',
          campo: 'valoracion_avanzada',
          ligaId: mi.liga.id,
        ),
        grupo('Normas y votaciones'),
        opcion(Icons.gavel_outlined, 'Reglamento', 'Modalidad (${mi.liga.nombreModalidad}) y reglas del partido', '/reglamento'),
        opcion(Icons.how_to_vote_outlined, 'Votaciones', 'Pregunta a la liga o somete a votación un cambio de regla', '/votaciones'),
        opcion(Icons.event_busy_outlined, 'Asistencia y bajas', 'Historial de cada jugador y bajas temporales', '/asistencia'),
        ListTile(
          leading: const Icon(Icons.table_view_outlined),
          title: const Text('Exportar a Excel'),
          subtitle: const Text('Caja, saldos, asistencia y clasificación'),
          trailing: const Icon(Icons.download_outlined),
          onTap: () => exportarLigaExcel(context, mi.liga),
        ),
        grupo('Puntuación y Fantasy'),
        opcion(Icons.rule, 'Puntuación y valoraciones', 'Puntos por acción, valoración rápida o detallada', '/liga/reglas'),
        if (mi.liga.fantasyActivo)
          opcion(Icons.storefront_outlined, 'Fantasy', 'Encuesta, mercado, multiplicador de invitados y bonus por rol', '/liga/fantasy'),
      ]),
    );
  }
}


class _Interruptor extends ConsumerWidget {
  const _Interruptor({required this.titulo, required this.activo, required this.on, required this.off, required this.campo, required this.ligaId});
  final String titulo, on, off, campo, ligaId;
  final bool activo;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
        title: Text(titulo),
        subtitle: Text(activo ? on : off),
        value: activo,
        onChanged: (v) async {
          if (await ejecutar(context, () => LigasRepo.actualizarLiga(ligaId, {campo: v}),
              ok: v ? '$titulo activado' : '$titulo desactivado')) {
            refrescarLigas(ref);
          }
        },
      );
}
