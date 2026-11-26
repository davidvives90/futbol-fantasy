import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/compartir.dart';
import '../../core/idioma.dart';
import '../../core/supabase.dart';
import '../../core/utils.dart';

/// 0060: equipo ideal de la última jornada o del último mes (los que más puntos sacaron).
final equipoIdealProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, ({String liga, String modo})>(
  (ref, k) async => Map<String, dynamic>.from(
      await sb.rpc('equipo_ideal', params: {'p_liga': k.liga, 'p_modo': k.modo}) as Map),
);

class EquipoIdeal extends ConsumerStatefulWidget {
  const EquipoIdeal({super.key, required this.ligaId, required this.ligaNombre});
  final String ligaId, ligaNombre;

  @override
  ConsumerState<EquipoIdeal> createState() => _EquipoIdealState();
}

class _EquipoIdealState extends ConsumerState<EquipoIdeal> {
  String _modo = 'jornada';

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(equipoIdealProvider((liga: widget.ligaId, modo: _modo)));
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(equipoIdealProvider((liga: widget.ligaId, modo: _modo)).future),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'jornada', label: Tx('Última jornada')),
            ButtonSegment(value: 'mes', label: Tx('Último mes')),
          ],
          selected: {_modo},
          onSelectionChanged: (v) => setState(() => _modo = v.first),
        ),
        const SizedBox(height: 16),
        ...datos.when(
          loading: () => const [Cargando(filas: 4)],
          error: (e, _) => [ErrorVista(e)],
          data: (d) {
            final jugadores = [for (final x in (d['jugadores'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
            if (jugadores.isEmpty) {
              return [
                const Vacio('Cuando se cierre un partido saldrán aquí los que más puntos sacaron.',
                    titulo: 'Aún no hay equipo ideal', icono: Icons.star_outline),
              ];
            }
            final subtitulo = _modo == 'jornada'
                ? (d['fecha'] == null ? '' : fechaCorta(DateTime.parse(d['fecha'] as String).toLocal()))
                : trf('Media de puntos · mínimo {n} partidos', {'n': d['minimo']});
            final tarjeta = TarjetaEquipoIdeal(
              liga: widget.ligaNombre,
              titulo: tr(_modo == 'jornada' ? 'Equipo ideal de la jornada' : 'Equipo ideal del mes'),
              subtitulo: subtitulo,
              jugadores: jugadores,
            );
            return [
              Center(child: FittedBox(child: tarjeta)),
              const SizedBox(height: 12),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => compartirImagen(context, tarjeta, nombre: 'equipo-ideal.png'),
                  icon: const Icon(Icons.share),
                  label: const Tx('Compartir en WhatsApp'),
                ),
              ),
              const SizedBox(height: 8),
              Tx('Se calcula con los puntos de cada partido: goles, victorias, valoraciones y MVP.',
                  textAlign: TextAlign.center, style: t.bodySmall),
            ];
          },
        ),
      ]),
    );
  }
}

/// Tarjeta para compartir: el once (o el cinco) ideal con sus puntos.
class TarjetaEquipoIdeal extends StatelessWidget {
  const TarjetaEquipoIdeal(
      {super.key, required this.liga, required this.titulo, required this.subtitulo, required this.jugadores});
  final String liga, titulo, subtitulo;
  final List<Map<String, dynamic>> jugadores;

  static const _rojo = Color(0xFFC8102E), _rojoOscuro = Color(0xFF7A0A1C), _oro = Color(0xFFF2A229), _crema = Color(0xFFF4F1E8);

  @override
  Widget build(BuildContext context) {
    const blanco = TextStyle(color: _crema, fontFamilyFallback: ['Roboto']);
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_rojo, _rojoOscuro]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(liga, style: blanco.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('⭐ $titulo', textAlign: TextAlign.center,
            style: const TextStyle(color: _oro, fontSize: 20, fontWeight: FontWeight.w800)),
        if (subtitulo.isNotEmpty) Text(subtitulo, style: blanco.copyWith(fontSize: 12, color: _crema.withValues(alpha: 0.75))),
        const SizedBox(height: 14),
        for (final (i, j) in jugadores.indexed)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: i == 0 ? 0.22 : 0.1), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              SizedBox(width: 26, child: Text('${i + 1}', style: blanco.copyWith(fontWeight: FontWeight.w800, fontSize: 16))),
              Expanded(
                child: Text('${j['nombre']}${j['es_mvp'] == true ? '  ⭐' : ''}',
                    overflow: TextOverflow.ellipsis, style: blanco.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (((j['goles'] as num?) ?? 0) > 0)
                Padding(padding: const EdgeInsets.only(right: 10), child: Text('⚽ ${j['goles']}', style: blanco.copyWith(fontSize: 13))),
              Text('${j['puntos']} pts', style: const TextStyle(color: _oro, fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
          ),
        const SizedBox(height: 14),
        Text('Pachanga Fantasy', style: TextStyle(color: _oro.withValues(alpha: 0.9), fontSize: 11, letterSpacing: 2)),
      ]),
    );
  }
}
