import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/equipaciones.dart';
import '../../core/info.dart';
import '../../core/utils.dart';
import '../equipos/prediccion_card.dart' show ayudaXg;
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

/// Guía: las normas acordadas en la liga (texto del admin), cómo está configurada y cómo funciona todo.
class GuiaScreen extends ConsumerWidget {
  const GuiaScreen({super.key});

  Future<void> _editarNormas(BuildContext context, WidgetRef ref, String ligaId, String? actuales) async {
    final c = TextEditingController(text: actuales ?? '');
    final texto = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Normas de la liga'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: c,
            autofocus: true,
            minLines: 8,
            maxLines: 16,
            maxLength: 6000,
            decoration: const InputDecoration(
              hintText: 'Ej.:\n• Llegar 10 min antes.\n• Darse de baja antes del domingo a las 20:00.\n'
                  '• Pagar antes del siguiente partido.\n• Equipación: blanco y color.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    if (texto == null || !context.mounted) return;
    if (await ejecutar(context, () => LigasRepo.actualizarLiga(ligaId, {'normas': texto.isEmpty ? null : texto}),
        ok: 'Normas guardadas')) {
      refrescarLigas(ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final l = mi.liga;
    final f = l.fantasy;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Widget seccion(String texto) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(texto.toUpperCase(), style: t.labelMedium?.copyWith(letterSpacing: 1, color: cs.onSurfaceVariant)),
        );
    Widget dato(IconData i, String titulo, String valor) => ListTile(
          dense: true,
          leading: Icon(i, size: 20),
          title: Text(titulo),
          trailing: Text(valor, style: t.labelLarge),
        );
    Widget tema((String, String) a, IconData i) => ExpansionTile(
          leading: Icon(i),
          title: Text(a.$1),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(a.$2, style: t.bodyMedium)],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Guía y normas')),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        // ───── Normas acordadas
        seccion('Normas de ${l.nombre}'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                (l.normas ?? '').isEmpty
                    ? (mi.soyAdmin
                        ? 'Aún no habéis escrito normas. Apunta aquí lo acordado: puntualidad, plazo para darse de baja, pagos…'
                        : 'El administrador aún no ha escrito las normas de la liga.')
                    : l.normas!,
                style: t.bodyLarge?.copyWith(height: 1.5),
              ),
              if (mi.soyAdmin)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _editarNormas(context, ref, l.id, l.normas),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text((l.normas ?? '').isEmpty ? 'Escribir normas' : 'Editar'),
                  ),
                ),
            ]),
          ),
        ),

        // ───── Cómo está configurada esta liga
        seccion('Cómo está configurada'),
        dato(Icons.sports_soccer, 'Formato', '${l.jugadoresPorEquipo} contra ${l.jugadoresPorEquipo} · ${l.numEquipos} equipos'),
        dato(Icons.groups, 'Plazas por partido', '${l.plazas}${l.plazasFijas != null ? ' (${l.plazasFijas} fijos)' : ''}'),
        ListTile(
          dense: true,
          leading: const Icon(Icons.checkroom, size: 20),
          title: const Text('Equipaciones'),
          trailing: Wrap(spacing: 10, children: [for (var i = 1; i <= l.numEquipos.clamp(2, 4); i++) EtiquetaEquipo(i)]),
        ),
        dato(Icons.payments_outlined, 'Cobro', l.facturaMensual ? 'Factura mensual' : 'Por partido'),
        if (l.precioEstimado != null) dato(Icons.euro, 'Precio aproximado', '${euros(l.precioEstimado)}/jugador'),
        if (l.precioInvitado != null) dato(Icons.person_add_alt, 'Reservas e invitados', '${euros(l.precioInvitado)}/partido'),
        dato(Icons.lock_clock, 'Convocatoria',
            l.conApertura ? 'Se abre ${l.horasAperturaConvocatoria} h tras el partido anterior' : 'Fijos dentro desde el principio'),
        if (l.conApertura && l.horasReservaFijos > 0)
          dato(Icons.event_seat, 'Plaza guardada a fijos', 'Hasta ${l.horasReservaFijos} h antes'),
        dato(Icons.format_list_numbered, 'Lista de espera', l.esperaPorPrioridad ? 'Por prioridad' : 'Por orden de apuntarse'),
        dato(Icons.how_to_vote_outlined, 'Valoración', l.valoracionDetallada ? 'Detallada (por aspectos)' : 'Rápida (1 a 5)'),
        dato(Icons.shield_outlined, 'Fantasy', l.fantasyActivo ? 'Plantillas de hasta ${f.maxPlantilla} jugadores' : 'Desactivado'),
        if (l.fantasyActivo) dato(Icons.verified_user_outlined, 'Protección tras fichar', '${f.proteccionDias} días'),
        dato(Icons.lock_clock, 'Cierre de alineación', '${f.horasCierreAlineacion.toStringAsFixed(0)} h antes'),
        dato(Icons.star_half, 'Multiplicador de invitados',
            f.bonusNoHabitual > 1 ? '×${f.bonusNoHabitual.toStringAsFixed(1).replaceAll('.', ',')}' : 'Desactivado'),
        dato(Icons.sports_handball, 'Bonus por rol', f.bonusRoles ? 'Activado' : 'Desactivado'),

        // ───── Una semana normal
        seccion('Una semana normal'),
        for (final (n, texto) in [
          ('1', l.conApertura
              ? 'Se abre la convocatoria tras el partido anterior. Todos pulsan «Voy»; los fijos tienen la plaza guardada.'
              : 'Se abre la convocatoria. Los fijos ya están dentro; el resto pulsa «Voy» y espera plaza.'),
          ('2', 'El admin hace equipos equilibrados con las estadísticas de cada uno.'),
          if (l.fantasyActivo) ('3', 'Antes del cierre, cada mánager prepara su alineación del Fantasy.'),
          ('4', 'Se juega. El admin pulsa «Partido jugado» y se abre el post-partido.'),
          ('5', 'Cada jugador envía el resultado, quién marcó y sus notas (1 minuto).'),
          ('6', 'La app cruza los partes; si algo no cuadra, el admin lo resuelve.'),
          ('7', 'Se publican los puntos, el MVP, la clasificación y los nuevos precios del mercado.'),
        ])
          ListTile(
            leading: CircleAvatar(radius: 14, child: Text(n, style: const TextStyle(fontSize: 13))),
            title: Text(texto),
          ),

        // ───── Explicaciones
        seccion('Partidos'),
        if (l.conApertura) tema(Ayuda.apertura, Icons.lock_clock),
        tema(Ayuda.rangos, Icons.badge_outlined),
        tema(Ayuda.listaEspera, Icons.hourglass_top),
        if (l.facturaMensual) tema(Ayuda.facturaMensual, Icons.receipt_long_outlined),
        seccion('Post-partido y puntos'),
        tema(Ayuda.puntos, Icons.calculate_outlined),
        tema(Ayuda.notas, Icons.how_to_vote_outlined),
        tema(Ayuda.mvp, Icons.star_outline),
        tema(Ayuda.destacados, Icons.local_fire_department_outlined),
        tema(Ayuda.noMeFije, Icons.visibility_off_outlined),
        tema(Ayuda.disputas, Icons.report_outlined),
        if (l.prediccionActiva) tema(ayudaXg, Icons.insights),
        if (l.fantasyActivo) ...[
        seccion('Fantasy'),
        tema(Ayuda.repartoInicial, Icons.casino_outlined),
        tema(Ayuda.valorMercado, Icons.trending_up),
        tema(Ayuda.fichas, Icons.style_outlined),
        tema(Ayuda.clausula, Icons.gavel_outlined),
        tema(Ayuda.cesion, Icons.swap_horiz),
        tema(Ayuda.alineacion, Icons.sports),
        tema(Ayuda.rolesBonus, Icons.sports_handball),
        tema(Ayuda.multiplicadorInvitado, Icons.star_half),
        ],
      ]),
    );
  }
}
