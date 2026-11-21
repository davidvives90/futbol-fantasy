import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/idioma.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/repos/partidos_repo.dart';

/// Apuntarse con un toque (0042), lo más simple posible:
///  · Fijos (ya están en la lista como «pendientes»): tres botones grandes Voy · Duda · No voy.
///  · Suplentes: un botón «Apuntarme de suplente»; entran solos por orden cuando un fijo dice que no.
/// Sin diálogos: cada cambio se puede deshacer. Se usa en Inicio y en la convocatoria.
class SelectorAsistencia extends StatelessWidget {
  const SelectorAsistencia({super.key, required this.partido, required this.mi, required this.actual, this.puesto});
  final Partido partido;
  final MiLiga mi;
  final EstadoInscripcion? actual;

  /// Puesto en la lista de suplentes (1 = el siguiente en entrar).
  final int? puesto;

  static String _texto(EstadoInscripcion e) => tr(switch (e) {
        EstadoInscripcion.confirmado => 'Vas ✅',
        EstadoInscripcion.pendiente => 'Estás en la lista: confirma si vas',
        EstadoInscripcion.duda => 'Marcado como «Duda»',
        EstadoInscripcion.baja => 'Hecho: no vas',
        EstadoInscripcion.espera => 'Apuntado de suplente: entras si queda sitio',
      });

  Future<void> _cambiar(BuildContext context, EstadoInscripcion nuevo) async {
    final antes = actual;
    HapticFeedback.selectionClick();
    final ok = await ejecutar(context, () => PartidosRepo.cambiarEstado(partido.id, mi.yo.id, nuevo));
    if (!ok || !context.mounted) return;
    if (antes == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_texto(nuevo == EstadoInscripcion.confirmado && mi.yo.rango != RangoMiembro.fijo
            ? EstadoInscripcion.espera
            : nuevo))));
      return;
    }
    avisoDeshacer(
      context,
      antes.ocupaPlaza && nuevo == EstadoInscripcion.baja
          ? tr('Hecho: no vas. Tu plaza pasa al primer suplente.')
          : _texto(nuevo),
      () => PartidosRepo.cambiarEstado(partido.id, mi.yo.id, antes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final colores = AppColores.of(context);
    final dentro = actual != null && actual!.ocupaPlaza;
    final fijo = mi.yo.rango == RangoMiembro.fijo;

    // Suplente que aún no está dentro: un único botón
    if (!dentro && !(fijo && actual == null)) {
      if (actual == EstadoInscripcion.espera) {
        return Row(children: [
          Icon(Icons.hourglass_top, color: colores.aviso),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              puesto == null ? tr('Eres suplente: entras si queda sitio') : trf('Eres el suplente nº {n}', {'n': puesto!}),
              style: t.titleSmall,
            ),
          ),
          TextButton(onPressed: () => _cambiar(context, EstadoInscripcion.baja), child: const Tx('Quitarme')),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (actual == EstadoInscripcion.baja)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(tr('Has dicho que no vas'), style: t.bodySmall, textAlign: TextAlign.center),
          ),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: () => _cambiar(context, EstadoInscripcion.confirmado),
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(tr(fijo ? 'Voy' : 'Apuntarme de suplente'), style: const TextStyle(fontSize: 17)),
          ),
        ),
      ]);
    }

    Widget boton(EstadoInscripcion e, String texto, IconData icono, Color color) {
      final sel = actual == e;
      final estilo = sel
          ? FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: EdgeInsets.zero)
          : OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.5)),
              padding: EdgeInsets.zero);
      final hijo = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icono, size: 26),
        const SizedBox(height: 2),
        Text(tr(texto), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ]);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 68,
            child: sel
                ? FilledButton(style: estilo, onPressed: () {}, child: hijo)
                : OutlinedButton(style: estilo, onPressed: () => _cambiar(context, e), child: hijo),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (actual == null || actual == EstadoInscripcion.pendiente)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(tr('Estás en la lista: confirma si vas'),
              textAlign: TextAlign.center, style: t.titleSmall?.copyWith(color: cs.primary)),
        ),
      Row(children: [
        boton(EstadoInscripcion.confirmado, 'Voy', Icons.check_circle_outline, colores.exito),
        boton(EstadoInscripcion.duda, 'Duda', Icons.help_outline, colores.aviso),
        boton(EstadoInscripcion.baja, 'No voy', Icons.cancel_outlined, cs.error),
      ]),
    ]);
  }
}
