import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/exportar.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

/// Ajustes de la liga (solo admin): todo lo que se configura, agrupado, fuera de la vista de jugadores.
class AjustesLigaScreen extends ConsumerStatefulWidget {
  const AjustesLigaScreen({super.key});

  @override
  ConsumerState<AjustesLigaScreen> createState() => _AjustesLigaScreenState();
}

class _AjustesLigaScreenState extends ConsumerState<AjustesLigaScreen> {
  bool _verTodo = false;

  Future<void> _cambiarNivel(Liga l, String nivel) async {
    if (nivel == l.nivel) return;
    final nombre = tr(nivelesLiga.firstWhere((n) => n.$1 == nivel).$3);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(trf('¿Pasar a modo {n}?', {'n': nombre})),
        content: Text(tr(nivelesLiga.firstWhere((n) => n.$1 == nivel).$4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Tx('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Tx('Cambiar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await ejecutar(context, () => LigasRepo.actualizarLiga(l.id, ajustesNivel(nivel)),
        ok: trf('Modo {n} activado', {'n': nombre}))) {
      refrescarLigas(ref);
    }
  }

  /// «El árbitro (Juan)», «Los capitanes»…
  String _textoActa(MiLiga mi) {
    final l = mi.liga;
    final porId = ref.watch(miembrosPorIdProvider(l.id)); // también carga la lista para elegir árbitro
    final nombre = tr(modosActa.firstWhere((m) => m.$1 == l.quienRellena, orElse: () => modosActa.first).$2);
    if (l.quienRellena != 'arbitro') return nombre;
    final arbitro = l.arbitroId == null ? null : porId[l.arbitroId];
    return '$nombre · ${arbitro?.nombre ?? tr('el administrador')}';
  }

  /// 0050: jugadores, árbitro o capitanes. Con árbitro, se elige quién (o el administrador).
  Future<void> _elegirActa(MiLiga mi) async {
    final l = mi.liga;
    final modo = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Tx('Quién rellena el acta', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 4),
              Tx('El acta es el resultado, los goles y las asistencias. Las notas y el MVP los ponen siempre todos los que jugaron.',
                  style: Theme.of(c).textTheme.bodySmall),
            ]),
          ),
          for (final (v, titulo, sub) in modosActa)
            ListTile(
              leading: Icon(l.quienRellena == v ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: l.quienRellena == v ? Theme.of(c).colorScheme.primary : null),
              title: Text(tr(titulo)),
              subtitle: Text(tr(sub)),
              onTap: () => Navigator.pop(c, v),
            ),
        ]),
      ),
    );
    if (modo == null || !mounted) return;
    String? arbitro = l.arbitroId;
    if (modo == 'arbitro') {
      final miembros = ref.read(miembrosPorIdProvider(l.id)).values
          .where((m) => m.estado == EstadoMiembro.activo)
          .toList()
        ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      const admin = '__admin__';
      final r = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
            child: ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Tx('¿Quién es el árbitro?', style: Theme.of(c).textTheme.titleLarge),
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Tx('El administrador'),
                subtitle: const Tx('Si no eliges a nadie, rellena el acta el administrador.'),
                selected: arbitro == null,
                onTap: () => Navigator.pop(c, admin),
              ),
              for (final m in miembros)
                ListTile(
                  leading: Icon(arbitro == m.id ? Icons.sports : Icons.person_outline),
                  title: Text(m.nombre),
                  selected: arbitro == m.id,
                  onTap: () => Navigator.pop(c, m.id),
                ),
            ]),
          ),
        ),
      );
      if (r == null || !mounted) return;
      arbitro = r == admin ? null : r;
    }
    if (await ejecutar(context,
        () => LigasRepo.actualizarLiga(l.id, {'quien_rellena': modo, 'arbitro_id': modo == 'arbitro' ? arbitro : null}),
        ok: 'Ajustes guardados')) {
      refrescarLigas(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          title: Text(tr(titulo)),
          subtitle: Text(tr(sub)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(ruta),
        );
    return Scaffold(
      appBar: AppBar(title: const Tx('Ajustes de la liga')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        grupo(tr('Modo de la liga')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final (id, icono, nombre, _) in nivelesLiga)
                ButtonSegment(value: id, icon: Icon(icono), label: Text(tr(nombre))),
            ],
            selected: {mi.liga.nivel},
            onSelectionChanged: (x) => _cambiarNivel(mi.liga, x.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(tr(nivelesLiga.firstWhere((n) => n.$1 == mi.liga.nivel, orElse: () => nivelesLiga.last).$4),
              style: Theme.of(context).textTheme.bodySmall),
        ),
        grupo(tr('Liga')),
        opcion(Icons.edit_outlined, 'Datos de la liga', 'Nombre, campo, plazas, equipos y precio', '/liga/editar'),
        opcion(Icons.checkroom, 'Equipaciones', 'Qué lleva cada equipo (p. ej. blanco y color)', '/liga/equipaciones'),
        opcion(Icons.menu_book_outlined, 'Normas y guía', 'Lo acordado en la liga y cómo funciona todo', '/guia'),
        grupo(tr('Partidos')),
        opcion(Icons.event_repeat, 'Programar temporada', 'Partidos recurrentes entre dos fechas', '/temporada'),
        opcion(Icons.how_to_reg_outlined, 'Convocatoria y cobro',
            '${tr(modosConvocatoria.firstWhere((m) => m.$1 == mi.liga.modoConvocatoria, orElse: () => modosConvocatoria.first).$2)} · ${tr('lista de espera y cobro')}',
            '/liga/convocatoria'),
        ListTile(
          leading: const Icon(Icons.assignment_outlined),
          title: const Tx('Quién rellena el acta'),
          subtitle: Text(_textoActa(mi)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _elegirActa(mi),
        ),
        if (mi.liga.esAvanzada || _verTodo) ...[
        grupo(tr('Módulos')),
        _Interruptor(
          titulo: 'Fantasy',
          activo: mi.liga.fantasyActivo,
          on: 'Mercado, plantillas y alineaciones',
          off: 'Desactivado: la liga usa solo convocatorias, caja y estadísticas',
          campo: 'fantasy_activo',
          ligaId: mi.liga.id,
        ),
        _Interruptor(
          titulo: 'Pronóstico del partido',
          activo: mi.liga.prediccionActiva,
          on: 'Con los equipos hechos, la app estima goles y probabilidades',
          off: 'Desactivado',
          campo: 'prediccion_activa',
          ligaId: mi.liga.id,
        ),
        _Interruptor(
          titulo: 'Post-partido detallado',
          activo: mi.liga.valoracionAvanzada,
          on: 'Además: «Destacó en», autogoles/paradas/penaltis, «No le vi» y valoración por aspectos',
          off: 'Simple: goles y asistencias, nota del 1 al 5 a todos y estrella MVP',
          campo: 'valoracion_avanzada',
          ligaId: mi.liga.id,
        ),
        ],
        grupo(tr('Normas y votaciones')),
        opcion(Icons.gavel_outlined, 'Reglamento', 'Modalidad (${mi.liga.nombreModalidad}) y reglas del partido', '/reglamento'),
        opcion(Icons.how_to_vote_outlined, 'Votaciones', 'Pregunta a la liga o somete a votación un cambio de regla', '/votaciones'),
        opcion(Icons.event_busy_outlined, 'Asistencia y bajas', 'Historial de cada jugador y bajas temporales', '/asistencia'),
        ListTile(
          leading: const Icon(Icons.table_view_outlined),
          title: const Tx('Exportar a Excel'),
          subtitle: const Tx('Caja, saldos, asistencia y clasificación'),
          trailing: const Icon(Icons.download_outlined),
          onTap: () => exportarLigaExcel(context, mi.liga),
        ),
        if (mi.liga.esAvanzada || _verTodo) ...[
        grupo(tr('Puntuación y Fantasy')),
        opcion(Icons.rule, 'Puntuación y valoraciones', 'Puntos por acción, valoración rápida o detallada', '/liga/reglas'),
        if (mi.liga.fantasyActivo)
          opcion(Icons.storefront_outlined, 'Fantasy', 'Bonus, opciones avanzadas y reiniciar', '/liga/fantasy'),
        ],
        if (!mi.liga.esAvanzada && !_verTodo)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _verTodo = true),
              icon: const Icon(Icons.tune),
              label: const Tx('Ver todas las opciones'),
            ),
          ),
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
        title: Text(tr(titulo)),
        subtitle: Text(tr(activo ? on : off)),
        value: activo,
        onChanged: (v) async {
          if (await ejecutar(context, () => LigasRepo.actualizarLiga(ligaId, {campo: v}),
              ok: trf(v ? '{x} activado' : '{x} desactivado', {'x': tr(titulo)}))) {
            refrescarLigas(ref);
          }
        },
      );
}
