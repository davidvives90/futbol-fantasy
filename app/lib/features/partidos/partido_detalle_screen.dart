import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../equipos/equipos_tab.dart';
import '../post_partido/post_partido_tab.dart';
import '../post_partido/resultado_tab.dart';
import '../post_partido/revision_tab.dart';
import 'convocatoria_tab.dart';

/// Detalle de un partido. Las pestañas visibles dependen del estado y del rol.
class PartidoDetalleScreen extends ConsumerWidget {
  const PartidoDetalleScreen({super.key, required this.partidoId});
  final String partidoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    final partido = ref.watch(partidoProvider(partidoId));

    return partido.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Cargando()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorVista(e)),
      data: (p) {
        if (p == null || mi == null) {
          return Scaffold(appBar: AppBar(), body: const Vacio('Partido no encontrado'));
        }
        final admin = mi.soyAdmin;
        final e = p.estado;
        final postPartido = e == EstadoPartido.jugado || e == EstadoPartido.post_partido || e == EstadoPartido.en_revision;

        final tabs = <(String, Widget)>[
          ('Convocatoria', ConvocatoriaTab(partido: p, mi: mi)),
          if (e != EstadoPartido.cancelado) ('Equipos', EquiposTab(partido: p, mi: mi)),
          if (postPartido) ('Post-partido', PostPartidoTab(partido: p, mi: mi)),
          if (admin && (e == EstadoPartido.post_partido || e == EstadoPartido.en_revision))
            ('Revisión', RevisionTab(partido: p, mi: mi)),
          if (e == EstadoPartido.cerrado) ('Resultado', ResultadoTab(partido: p, mi: mi)),
        ];

        // Al cambiar de estado cambia el nº de pestañas: la key fuerza un controlador nuevo
        // y abre por defecto la última (la más relevante).
        return DefaultTabController(
          key: ValueKey('${p.id}-${tabs.length}'),
          length: tabs.length,
          initialIndex: tabs.length - 1,
          child: Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fechaHora(p.fechaHora)),
                Text(p.estado.etiqueta, style: Theme.of(context).textTheme.bodySmall),
              ]),
              actions: [
                IconButton(
                  tooltip: 'Abrir en Maps',
                  icon: const Icon(Icons.map_outlined),
                  onPressed: () => abrirUrl(context, p.campoMapsUrl ?? mi.liga.campoMapsUrl),
                ),
                if (admin) _MenuAdmin(partido: p),
              ],
              bottom: TabBar(isScrollable: tabs.length > 3, tabs: [for (final t in tabs) Tab(text: t.$1)]),
            ),
            body: TabBarView(children: [for (final t in tabs) t.$2]),
          ),
        );
      },
    );
  }
}

class _MenuAdmin extends ConsumerWidget {
  const _MenuAdmin({required this.partido});
  final Partido partido;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = partido.estado;
    return PopupMenuButton<String>(
      onSelected: (accion) async {
        switch (accion) {
          case 'hora':
            await ejecutar(context, () => PartidosRepo.cambiarHora(partido.id, partido.fechaHora),
                ok: 'Hora confirmada');
          case 'cambiar_hora':
            final local = partido.fechaHora.toLocal();
            final dia = await showDatePicker(
              context: context,
              initialDate: local,
              firstDate: DateTime(local.year - 1),
              lastDate: DateTime(local.year + 2),
            );
            if (dia == null || !context.mounted) return;
            final hora = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(local));
            if (hora == null || !context.mounted) return;
            final nueva = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute);
            await ejecutar(context, () => PartidosRepo.cambiarHora(partido.id, nueva),
                ok: 'Hora cambiada y confirmada');
          case 'jugado':
            // marcar_jugado: genera los cargos (facturas del partido o coste total) y abre la
            // ventana post-partido (ligas.horas_post_partido, 48 h por defecto).
            if (await confirmar(context, 'Partido jugado',
                'Se cargará a cada confirmado su parte del coste y se abrirá el plazo para enviar partes y valoraciones.')) {
              if (context.mounted) {
                await ejecutar(context, () => PartidosRepo.marcarJugado(partido.id),
                    ok: 'Post-partido abierto: ya pueden enviar resultado y valoraciones');
              }
            }
          case 'cerrar':
            if (context.mounted) {
              await ejecutar(context, () => PartidosRepo.cerrarPostPartido(partido.id),
                  ok: 'Partes cruzados: revisa el acta y las disputas');
            }
          case 'cancelar':
            if (await confirmar(context, 'Cancelar partido', '¿Seguro? Se avisará a los inscritos.', accion: 'Cancelar partido', tipo: TipoConfirmacion.peligro)) {
              if (context.mounted) {
                await ejecutar(context, () => PartidosRepo.actualizar(partido.id, {'estado': EstadoPartido.cancelado.name}));
              }
            }
        }
        final ligaId = partido.ligaId;
        ref.invalidate(partidosProvider(ligaId));
      },
      itemBuilder: (_) => [
        if (!partido.horaConfirmada && e.antesDeJugar) const PopupMenuItem(value: 'hora', child: Text('Confirmar hora')),
        if (e.antesDeJugar) const PopupMenuItem(value: 'cambiar_hora', child: Text('Cambiar fecha u hora')),
        if (e == EstadoPartido.equipos_hechos)
          const PopupMenuItem(value: 'jugado', child: Text('Partido jugado: cobrar y abrir post-partido')),
        if (e == EstadoPartido.post_partido)
          const PopupMenuItem(value: 'cerrar', child: Text('Cerrar plazo y cruzar partes')),
        if (e.antesDeJugar) const PopupMenuItem(value: 'cancelar', child: Text('Cancelar partido')),
      ],
    );
  }
}
