import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/repos/partidos_repo.dart';

/// Voy / Duda / No voy con un toque y «Deshacer» (sin diálogos de confirmación).
/// Se usa en el inicio y en la convocatoria, para que funcione igual en los dos sitios.
class SelectorAsistencia extends StatelessWidget {
  const SelectorAsistencia({super.key, required this.partido, required this.mi, required this.actual});
  final Partido partido;
  final MiLiga mi;
  final EstadoInscripcion? actual;

  static String _texto(EstadoInscripcion e) => switch (e) {
        EstadoInscripcion.confirmado => 'Te has apuntado',
        EstadoInscripcion.duda => 'Marcado como «Duda»',
        EstadoInscripcion.baja => 'Te has dado de baja',
        EstadoInscripcion.espera => 'Estás en lista de espera',
      };

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<EstadoInscripcion>(
      // Voy = verde éxito · Duda = ámbar · No voy = gris neutro (no es destructivo)
      style: AppButtons.segmentoEstado(context, actual?.name),
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: EstadoInscripcion.confirmado, label: Tx('Voy'), icon: Icon(Icons.check)),
        ButtonSegment(value: EstadoInscripcion.duda, label: Tx('Duda'), icon: Icon(Icons.help_outline)),
        ButtonSegment(value: EstadoInscripcion.baja, label: Tx('No voy'), icon: Icon(Icons.close)),
      ],
      selected: {
        if (actual != null) actual == EstadoInscripcion.espera ? EstadoInscripcion.confirmado : actual!,
      },
      onSelectionChanged: (s) async {
        if (s.isEmpty) return;
        final nuevo = s.first;
        final antes = actual;
        HapticFeedback.selectionClick();
        final ok = await ejecutar(context, () => PartidosRepo.cambiarEstado(partido.id, mi.yo.id, nuevo));
        if (!ok || !context.mounted) return;
        if (antes == null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(_texto(nuevo))));
          return;
        }
        avisoDeshacer(
          context,
          antes == EstadoInscripcion.confirmado && nuevo == EstadoInscripcion.baja
              ? 'Te has dado de baja. Si deshaces y ya entró otro, irás a la lista de espera.'
              : _texto(nuevo),
          () => PartidosRepo.cambiarEstado(partido.id, mi.yo.id, antes),
        );
      },
    );
  }
}
