import 'package:flutter/material.dart';
import '../../core/idioma.dart';
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
import '../../core/equipaciones.dart';
import '../shell/sincronizacion.dart';

class _DatosResultado {
  _DatosResultado(this.encuentros, this.puntos, this.acta, this.equipoJornada);
  final List<Encuentro> encuentros;
  final List<PuntosFantasy> puntos;
  final Map<String, Map<String, dynamic>> acta;
  final List<Map<String, dynamic>> equipoJornada;
}

final _resultadoProvider = FutureProvider.autoDispose.family<_DatosResultado, String>((ref, partidoId) async {
  ref.watch(latidoProvider('partido:$partidoId')); // 0062: en vivo
  final r = await Future.wait([
    PartidosRepo.encuentros(partidoId),
    PostPartidoRepo.puntos(partidoId),
    PostPartidoRepo.acta(partidoId),
    PostPartidoRepo.equipoJornada(partidoId).catchError((_) => <Map<String, dynamic>>[]),
  ]);
  return _DatosResultado(
    r[0] as List<Encuentro>,
    r[1] as List<PuntosFantasy>,
    r[2] as Map<String, Map<String, dynamic>>,
    r[3] as List<Map<String, dynamic>>,
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
        'podio' => 'Podio (2.º / 3.º)',
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
        final podio = d.puntos.where((p) => p.puesto != null).toList()..sort((a, b) => a.puesto!.compareTo(b.puesto!));
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final e in d.encuentros)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  EtiquetaEquipo(e.equipoLocal),
                  Text('${e.golesLocal} - ${e.golesVisitante}', style: AppTheme.numero(context)),
                  EtiquetaEquipo(e.equipoVisitante),
                ]),
              ),
            ),
          if (podio.isNotEmpty)
            _TarjetaPodio(podio: podio, miembros: miembros, acta: d.acta, porVotos: mi.liga.votaPodio),
          if (d.equipoJornada.isNotEmpty)
            _TarjetaEquipoJornada(filas: d.equipoJornada, miembros: miembros),
          _PuntosManagerSeccion(partido: partido, mi: mi, puntos: d.puntos),
          const SizedBox(height: 8),
          Tx('Puntos Fantasy', style: Theme.of(context).textTheme.titleMedium),
          for (final (i, p) in d.puntos.indexed)
            ExpansionTile(
              leading: AvatarMiembro(miembros[p.miembroId], anillo: p.esMvp ? Theme.of(context).colorScheme.tertiary : null),
              title: Text('${i + 1}. ${miembros[p.miembroId]?.nombre ?? '…'}${_medalla(p.puesto)}'),
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
                for (final e in p.desglose.entries.where((e) =>
                    (e.value is num) && e.value != 0 && !const {'votos_mvp', 'votos_podio', 'votos_primero'}.contains(e.key)))
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
            Expanded(child: Tx('Tus puntos de mánager', style: t.titleMedium)),
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


String _medalla(int? puesto) => switch (puesto) { 1 => '  🥇', 2 => '  🥈', 3 => '  🥉', _ => '' };

/// Resumen del partido: MVP destacado con sus puntos Fantasy y el resto del podio (0053).
class _TarjetaPodio extends StatelessWidget {
  const _TarjetaPodio({required this.podio, required this.miembros, required this.acta, required this.porVotos});
  final List<PuntosFantasy> podio;
  final Map<String, Miembro> miembros;
  final Map<String, Map<String, dynamic>> acta;
  final bool porVotos;

  String _pts(num v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  String _detalle(PuntosFantasy p) {
    final a = acta[p.miembroId] ?? const {};
    return [
      if (((a['goles'] ?? 0) as num) > 0) '⚽ ${a['goles']}',
      if (((a['asistencias'] ?? 0) as num) > 0) '🅰️ ${a['asistencias']}',
      if (porVotos && p.desglose['votos_podio'] != null) trf('{n} pts de votación', {'n': p.desglose['votos_podio']}),
      if (!porVotos && p.notaMedia != null) trf('nota {n}', {'n': p.notaMedia!.toStringAsFixed(1)}),
    ].join('  ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final mvps = podio.where((p) => p.puesto == 1).toList();
    final resto = podio.where((p) => p.puesto != 1).toList();
    return Card(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final m in mvps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                AvatarMiembro(miembros[m.miembroId], radio: 28, anillo: cs.tertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(mvps.length > 1 ? tr('🏆 MVP compartido') : tr('🏆 MVP del partido'),
                        style: t.labelLarge?.copyWith(color: cs.onTertiaryContainer)),
                    Text(miembros[m.miembroId]?.nombre ?? '…', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    if (_detalle(m).isNotEmpty) Text(_detalle(m), style: t.bodySmall),
                  ]),
                ),
                Column(children: [
                  Text(_pts(m.total), style: AppTheme.numero(context, size: 30)),
                  Tx('pts Fantasy', style: t.labelSmall),
                ]),
              ]),
            ),
          if (resto.isNotEmpty) const Divider(),
          for (final p in resto)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(_medalla(p.puesto).trim(), style: const TextStyle(fontSize: 24)),
              title: Text(miembros[p.miembroId]?.nombre ?? '…', style: t.titleSmall),
              subtitle: _detalle(p).isEmpty ? null : Text(_detalle(p)),
              trailing: Text(_pts(p.total), style: AppTheme.numero(context, size: 20)),
            ),
        ]),
      ),
    );
  }
}

/// Equipo de la jornada: los mejores por puntos Fantasy, colocados por posición si la liga las usa.
class _TarjetaEquipoJornada extends StatelessWidget {
  const _TarjetaEquipoJornada({required this.filas, required this.miembros});
  final List<Map<String, dynamic>> filas;
  final Map<String, Miembro> miembros;

  static const _orden = ['delantero', 'medio', 'defensa', 'portero'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final conPosiciones = filas.any((f) => f['hueco'] != null);
    final total = filas.fold<num>(0, (s, f) => s + ((f['total'] ?? 0) as num));
    Widget jugador(Map<String, dynamic> f) {
      final m = miembros[f['miembro_id']];
      return SizedBox(
        width: 76,
        child: Column(children: [
          AvatarMiembro(m, radio: 20, anillo: f['es_mvp'] == true ? cs.tertiary : null),
          const SizedBox(height: 2),
          Text(m?.nombre ?? '…', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall, textAlign: TextAlign.center),
          Text('${f['total']}', style: AppTheme.tabular(t.labelMedium)),
        ]),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.stars_outlined, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Tx('Equipo de la jornada', style: t.titleMedium)),
            Text(trf('{n} pts', {'n': total.toStringAsFixed(total % 1 == 0 ? 0 : 1)}), style: t.labelLarge),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              if (conPosiciones) ...[
                for (final pos in _orden.where((pos) => filas.any((f) => f['hueco'] == pos)))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
                      for (final f in filas.where((f) => f['hueco'] == pos)) jugador(f),
                    ]),
                  ),
              ] else
                Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 8, children: [for (final f in filas) jugador(f)]),
            ]),
          ),
        ]),
      ),
    );
  }
}
