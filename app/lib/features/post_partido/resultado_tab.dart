import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../../data/models_fantasy.dart';
import '../../data/repos/fantasy_repo.dart';
import '../../data/repos/post_partido_repo.dart';
import '../fantasy/widgets_fantasy.dart';
import '../../core/avatar.dart';

class _DatosResultado {
  _DatosResultado(this.encuentros, this.puntos, this.acta);
  final List<Encuentro> encuentros;
  final List<PuntosFantasy> puntos;
  final Map<String, Map<String, dynamic>> acta;
}

final _resultadoProvider = FutureProvider.autoDispose.family<_DatosResultado, String>((ref, partidoId) async {
  final r = await Future.wait([
    PartidosRepo.encuentros(partidoId),
    PostPartidoRepo.puntos(partidoId),
    PostPartidoRepo.acta(partidoId),
  ]);
  return _DatosResultado(
    r[0] as List<Encuentro>,
    r[1] as List<PuntosFantasy>,
    r[2] as Map<String, Map<String, dynamic>>,
  );
});

/// Marcador, MVP y puntos Fantasy con su desglose.
class ResultadoTab extends ConsumerWidget {
  const ResultadoTab({super.key, required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  static String _etiqueta(String clave) => switch (clave) {
        'jugado' => 'Jugado',
        'resultado' => 'Resultado',
        'goles' => 'Goles',
        'asistencias' => 'Asistencias',
        'porteria_cero' => 'Portería a cero',
        'goles_encajados' => 'Goles encajados',
        'paradas' => 'Paradas',
        'penaltis_parados' => 'Penaltis parados',
        'penaltis_fallados' => 'Penaltis fallados',
        'autogoles' => 'Autogoles',
        'valoracion' || 'nota' => 'Valoración',
        'mvp' => 'MVP',
        _ => clave,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(_resultadoProvider(partido.id));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));

    return datos.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(_resultadoProvider(partido.id))),
      data: (d) {
        final mvps = d.puntos.where((p) => p.esMvp).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final e in d.encuentros)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  Text('Equipo ${e.equipoLocal}',
                      style: TextStyle(color: AppColores.of(context).equipo(e.equipoLocal), fontWeight: FontWeight.w600)),
                  Text('${e.golesLocal} - ${e.golesVisitante}', style: AppTheme.numero(context)),
                  Text('Equipo ${e.equipoVisitante}',
                      style: TextStyle(color: AppColores.of(context).equipo(e.equipoVisitante), fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          for (final m in mvps)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                leading: Icon(Icons.star, color: Theme.of(context).colorScheme.tertiary, size: 36),
                title: Text('${mvps.length > 1 ? 'MVP compartido' : 'MVP'}: ${miembros[m.miembroId]?.nombre ?? '…'}'),
                subtitle: Text('Valoración media ${m.notaMedia?.toStringAsFixed(1) ?? '—'}'),
              ),
            ),
          _PuntosManagerSeccion(partido: partido, mi: mi, puntos: d.puntos),
          const SizedBox(height: 8),
          Text('Puntos Fantasy', style: Theme.of(context).textTheme.titleMedium),
          for (final (i, p) in d.puntos.indexed)
            ExpansionTile(
              leading: AvatarMiembro(miembros[p.miembroId], anillo: p.esMvp ? Theme.of(context).colorScheme.tertiary : null),
              title: Text('${i + 1}. ${miembros[p.miembroId]?.nombre ?? '…'}'),
              subtitle: Text([
                if ((d.acta[p.miembroId]?['goles'] ?? 0) as num > 0) '⚽ ${d.acta[p.miembroId]!['goles']}',
                if ((d.acta[p.miembroId]?['asistencias'] ?? 0) as num > 0) '🅰️ ${d.acta[p.miembroId]!['asistencias']}',
                if (p.notaMedia != null) 'nota ${p.notaMedia!.toStringAsFixed(1)}',
                if (((p.desglose['votos_mvp'] ?? 0) as num) > 0) '⭐ ${p.desglose['votos_mvp']}',
                if (_destacados(p).isNotEmpty) _destacados(p),
              ].join('  ')),
              trailing: Text(p.total.toStringAsFixed(p.total % 1 == 0 ? 0 : 1),
                  style: AppTheme.numero(context, size: 22)),
              children: [
                for (final e in p.desglose.entries.where((e) => (e.value is num) && e.value != 0 && e.key != 'votos_mvp'))
                  ListTile(
                    dense: true,
                    title: Text(_etiqueta(e.key)),
                    trailing: Text('${(e.value as num) > 0 ? '+' : ''}${e.value}',
                        style: AppTheme.tabular(Theme.of(context).textTheme.bodyMedium)),
                  ),
              ],
            ),
        ]);
      },
    );
  }
}

class _DatosManager {
  _DatosManager(this.alineados, this.puntos);
  final List<Alineado> alineados;
  final PuntosManager? puntos;
}

final _managerProvider =
    FutureProvider.autoDispose.family<_DatosManager, ({String partidoId, String managerId})>((ref, k) async {
  final r = await Future.wait([
    FantasyRepo.alineacion(k.partidoId, k.managerId),
    FantasyRepo.puntosManager(k.partidoId, k.managerId),
  ]);
  return _DatosManager(r[0] as List<Alineado>, r[1] as PuntosManager?);
});

/// "Tus puntos de mánager": puntos de cada alineado (×1,5 si era invitado) e ingreso de la jornada.
class _PuntosManagerSeccion extends ConsumerWidget {
  const _PuntosManagerSeccion({required this.partido, required this.mi, required this.puntos});
  final Partido partido;
  final MiLiga mi;
  final List<PuntosFantasy> puntos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(_managerProvider((partidoId: partido.id, managerId: mi.yo.id))).valueOrNull;
    if (datos == null || datos.alineados.isEmpty) return const SizedBox.shrink();
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final porJugador = {for (final p in puntos) p.miembroId: p.total};
    final t = Theme.of(context).textTheme;
    String fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

    // Liquidado: el desglose del backend (rol, bonus de rol, ×1,5, cedidos). Si no, cálculo provisional
    // con los puntos ya publicados (el bonus de rol se calcula al liquidar).
    final lineas = (datos.puntos?.desglose.isNotEmpty ?? false)
        ? datos.puntos!.desglose
        : [
            for (final a in datos.alineados)
              LineaDesglose(
                jugadorId: a.jugadorId,
                rol: a.rol,
                puntos: porJugador[a.jugadorId] ?? 0,
                bonusRol: a.bonusRol ?? 0,
                multiplicador: a.multiplicador,
                jugo: porJugador.containsKey(a.jugadorId),
                total: porJugador.containsKey(a.jugadorId)
                    ? ((porJugador[a.jugadorId] ?? 0) + (a.bonusRol ?? 0)) * a.multiplicador
                    : 0,
              ),
          ];
    final total = datos.puntos?.puntos ?? lineas.fold<double>(0, (s, l) => s + l.total);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.shield_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text('Tus puntos de mánager', style: t.titleMedium)),
            Text(fmt(total), style: t.headlineSmall),
          ]),
          const SizedBox(height: 4),
          DesgloseManager(lineas: lineas, nombres: {for (final e in miembros.entries) e.key: e.value.nombre}),
          if (datos.puntos?.ingreso != null)
            Text('Ingreso para el mercado: ${millones(datos.puntos!.ingreso)}', style: t.bodySmall)
          else if (datos.puntos == null)
            Text('Provisional: se liquida al cerrar el partido.', style: t.bodySmall),
        ]),
      ),
    );
  }
}

const _nombreDestacado = {
  'ataque': 'ataque',
  'defensa': 'defensa',
  'pase_vision': 'pase',
  'esfuerzo': 'esfuerzo',
  'juego_limpio': 'juego limpio',
  'porteria': 'portería',
};

/// «Destacó en defensa ×3, pase ×1» (v0.3b), a partir de desglose.destacados.
String _destacados(PuntosFantasy p) {
  final d = p.desglose['destacados'];
  if (d is! Map || d.isEmpty) return '';
  final e = d.entries.toList()..sort((a, b) => (b.value as num).compareTo(a.value as num));
  return 'Destacó en ${e.map((x) => '${_nombreDestacado[x.key] ?? x.key} ×${x.value}').join(', ')}';
}
