import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/stats_repo.dart';
import '../../core/avatar.dart';
import '../../data/repos/reglamento_repo.dart';
import '../liga/asistencia_screen.dart';
import 'logros_screen.dart';

final historialProvider = FutureProvider.autoDispose.family<List<PuntosFantasy>, String>(
  (ref, miembroId) => StatsRepo.historial(miembroId),
);


final premiosMiembroProvider = FutureProvider.autoDispose.family<List<Premio>, String>(
  (ref, miembroId) => StatsRepo.premiosDe(miembroId),
);

final statsJugadorProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, miembroId) => StatsRepo.jugador(miembroId),
);

/// 0060: estadísticas del jugador en todas las ligas que compartes con él (y el total).
final rendimientoPerfilProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, miembroId) async {
  final r = await sb.rpc('rendimiento_perfil', params: {'p_miembro': miembroId});
  return r == null ? null : Map<String, dynamic>.from(r as Map);
});

/// 0060: balance contra y con cada compañero.
final caraACaraProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, miembroId) async {
  final r = await sb.rpc('cara_a_cara', params: {'p_miembro': miembroId});
  return [for (final x in (r as List)) Map<String, dynamic>.from(x as Map)];
});

/// Liga elegida en la ficha (null = todas). Por ficha abierta.
final fichaLigaProvider = StateProvider.autoDispose.family<String?, String>((ref, miembroId) => null);

/// Ficha de un jugador: totales y puntos por partido.
class FichaScreen extends ConsumerWidget {
  const FichaScreen({super.key, required this.miembroId, this.conAppBar = true});
  final String miembroId;
  final bool conAppBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final miembro = ref.watch(miembrosPorIdProvider(mi.liga.id))[miembroId];
    // 0060: todas mis ligas o una en concreto (como en Inicio)
    final perfil = ref.watch(rendimientoPerfilProvider(miembroId)).valueOrNull;
    final ligasJugador = [for (final x in (perfil?['ligas'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final ligaSel = ref.watch(fichaLigaProvider(miembroId));
    final filaSel = ligaSel == null ? null : ligasJugador.where((x) => x['liga_id'] == ligaSel).firstOrNull;
    // Miembro de la liga elegida (el mismo jugador puede tener otra ficha en otra liga)
    final ver = (filaSel?['miembro_id'] as String?) ?? miembroId;
    final ligaVer = (filaSel?['liga_id'] as String?) ?? mi.liga.id;
    final rend = perfil == null
        ? (ref.watch(rendimientoProvider(mi.liga.id)).valueOrNull ?? const <Rendimiento>[])
            .where((r) => r.miembroId == miembroId)
            .firstOrNull
        : () {
            final m = filaSel ?? (perfil['total'] as Map?);
            if (m == null || ((m['partidos'] as num?) ?? 0) == 0) return null;
            return Rendimiento.fromMap({...Map<String, dynamic>.from(m), 'miembro_id': ver});
          }();
    final historial = ref.watch(historialProvider(ver));

    final cuerpo = ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        AvatarMiembro(miembro, radio: 36, dorsal: true),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(miembro?.nombre ?? '…', style: Theme.of(context).textTheme.headlineSmall),
            Text([etiquetaPosicion(miembro?.posicion), if (textoEdad(miembro) != null) textoEdad(miembro)!].join(' · ')),
          ]),
        ),
      ]),
      if (ligasJugador.length > 1) ...[
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ChoiceChip(
              label: const Tx('Todas sus ligas'),
              selected: ligaSel == null,
              onSelected: (_) => ref.read(fichaLigaProvider(miembroId).notifier).state = null,
            ),
            for (final l in ligasJugador)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text('${l['nombre']}'),
                  selected: ligaSel == l['liga_id'],
                  onSelected: (_) => ref.read(fichaLigaProvider(miembroId).notifier).state = l['liga_id'] as String,
                ),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      if (rend == null)
        const Tx('Aún no ha jugado ningún partido cerrado.')
      else
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.4,
          children: [
            _Dato('Puntos', rend.puntosTotal.toStringAsFixed(0)),
            _Dato('Partidos', '${rend.partidos}'),
            _Dato('Media', rend.puntosMedia.toStringAsFixed(1)),
            _Dato('Goles', '${rend.goles}'),
            _Dato('Asistencias', '${rend.asistencias}'),
            _Dato('MVPs', '${rend.mvps}'),
            _Dato('Nota media', rend.notaMedia?.toStringAsFixed(1) ?? '—'),
            _Dato('Goles/partido', rend.golesPartido.toStringAsFixed(2)),
            _Dato('% victorias', rend.pctVictorias == null ? '—' : '${rend.pctVictorias!.toStringAsFixed(0)} %'),
          ],
        ),
      // Logros (0056: 150, con pantalla propia)
      ...() {
        // 0061: con «Todas sus ligas», agrupados (cada logro una vez, con las ligas donde lo tiene)
        final todasLigas = ligaSel == null && ligasJugador.length > 1;
        final l = ref.watch(todasLigas ? logrosPerfilProvider(miembroId) : logrosProvider(ver)).valueOrNull;
        final rutaLogros = todasLigas ? '/logros/$miembroId?todas=1' : '/logros/$ver';
        if (l == null) return const <Widget>[];
        final recientes = l.recientes.take(6).toList();
        return <Widget>[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(trf('Logros ({x}/{y})', {'x': l.conseguidos, 'y': l.total}),
                style: Theme.of(context).textTheme.titleMedium)),
            TextButton(onPressed: () => context.push(rutaLogros), child: const Tx('Ver todos')),
          ]),
          const SizedBox(height: 6),
          if (recientes.isEmpty)
            Tx('Aún sin logros. ¡El primer gol ya cuenta!', style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in recientes)
                Tooltip(
                  message: [trf('Conseguido el {x}', {'x': fechaCorta(x.conseguidoEn!)}), if (todasLigas) ...x.enLigas].join(' · '),
                  child: ActionChip(
                    avatar: Text(x.emoji),
                    label: Text('${x.nombre} ${x.medalla}'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context.push(rutaLogros),
                  ),
                ),
            ]),
        ];
      }(),
      // Palmarés del jugador
      ...() {
        final premios = ref.watch(premiosMiembroProvider(ver)).valueOrNull ?? const <Premio>[];
        if (premios.isEmpty) return const <Widget>[];
        return <Widget>[
          const SizedBox(height: 16),
          Tx('Palmarés', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in premios)
              Chip(
                avatar: Text(p.info.icono),
                label: Text('${tr(p.info.titulo)}${p.temporada == null ? '' : ' · ${p.temporada}'}'),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ];
      }(),
      // Bajas (lesiones, viajes…)
      ...() {
        final bajas = ref.watch(ausenciasMiembroProvider(ver)).valueOrNull ?? const <Ausencia>[];
        if (bajas.isEmpty) return const <Widget>[];
        return <Widget>[
          const SizedBox(height: 16),
          Tx('Bajas', style: Theme.of(context).textTheme.titleMedium),
          for (final a in bajas.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.actual ? Icons.healing : Icons.history,
                  color: a.actual ? Colors.amber.shade700 : null),
              title: Text(textoBaja(a)),
              subtitle: a.nota == null ? null : Text(a.nota!),
            ),
        ];
      }(),
      ...ref.watch(statsJugadorProvider(ver)).maybeWhen(
            data: (e) => [const SizedBox(height: 16), _Extra(e, miembros: ref.watch(miembrosPorIdProvider(ligaVer)))],
            orElse: () => const <Widget>[],
          ),
      // 0060: rivalidades
      ...ref.watch(caraACaraProvider(ver)).maybeWhen(
            data: (l) => l.isEmpty ? const <Widget>[] : [const SizedBox(height: 16), _CaraACara(l, nombre: miembro?.nombre)],
            orElse: () => const <Widget>[],
          ),
      ...historial.maybeWhen(
            data: (lista) => lista.length < 2
                ? const <Widget>[]
                : <Widget>[
                    const SizedBox(height: 16),
                    Tx('Evolución', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    GraficaEvolucion(partidos: lista.reversed.toList()),
                  ],
            orElse: () => const <Widget>[],
          ),
      const SizedBox(height: 16),
      Tx('Puntos por partido', style: Theme.of(context).textTheme.titleMedium),
      ...historial.when(
        loading: () => [const Padding(padding: EdgeInsets.all(24), child: Cargando())],
        error: (e, _) => [ErrorVista(e)],
        data: (lista) {
          if (lista.isEmpty) return [const Padding(padding: EdgeInsets.all(16), child: Tx('Sin partidos todavía.'))];
          final maximo = lista.map((p) => p.total.abs()).fold<double>(1, (a, b) => b > a ? b : a);
          return [
            for (final p in lista)
              ListTile(
                dense: true,
                leading: p.esMvp
                    ? Icon(Icons.star, color: Theme.of(context).colorScheme.tertiary)
                    : const Icon(Icons.sports_soccer),
                title: Text(p.fecha == null ? 'Partido' : fechaCorta(p.fecha!)),
                subtitle: LinearProgressIndicator(value: (p.total.abs() / maximo).clamp(0.0, 1.0).toDouble()),
                trailing: Text(p.total.toStringAsFixed(p.total % 1 == 0 ? 0 : 1),
                    style: AppTheme.tabular(Theme.of(context).textTheme.titleMedium)),
              ),
          ];
        },
      ),
    ]);

    if (!conAppBar) return cuerpo;
    return Scaffold(appBar: AppBar(title: Text(miembro?.nombre ?? 'Jugador')), body: cuerpo);
  }
}

/// Balance contra cada compañero («contra Pepe has ganado 7 de 10») y partidos juntos.
class _CaraACara extends StatefulWidget {
  const _CaraACara(this.filas, {this.nombre});
  final List<Map<String, dynamic>> filas;
  final String? nombre;

  @override
  State<_CaraACara> createState() => _CaraACaraState();
}

class _CaraACaraState extends State<_CaraACara> {
  bool _todos = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final contra = widget.filas.where((x) => ((x['contra'] as num?) ?? 0) > 0).toList()
      ..sort((a, b) => (b['contra'] as num).compareTo(a['contra'] as num));
    final lista = _todos ? contra : contra.take(5).toList();
    if (contra.isEmpty) return const SizedBox.shrink();
    Widget cifra(Object n, String l, Color c) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text('$n$l', style: t.labelLarge?.copyWith(color: c, fontWeight: FontWeight.w700)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Tx('Cara a cara', style: t.titleMedium),
      Text(trf('Balance de {n} contra cada uno (V-E-D) y partidos en el mismo equipo', {'n': widget.nombre ?? tr('jugador')}),
          style: t.bodySmall),
      const SizedBox(height: 6),
      for (final x in lista)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: switch (((x['v'] as num) - (x['d'] as num)).sign) {
              1 => Colors.green.shade600,
              -1 => cs.error,
              _ => cs.outline,
            },
            child: Text('${x['contra']}', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          title: Text('${x['nombre']}'),
          subtitle: Text(trf('Juntos: {n} partidos ({v} ganados)', {'n': x['juntos'], 'v': x['juntos_v']})),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            cifra(x['v'], 'V', Colors.green.shade700),
            cifra(x['e'], 'E', cs.outline),
            cifra(x['d'], 'D', cs.error),
          ]),
        ),
      if (contra.length > 5)
        TextButton(
          onPressed: () => setState(() => _todos = !_todos),
          child: Tx(_todos ? 'Ver menos' : 'Ver todos'),
        ),
    ]);
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);
  final String etiqueta, valor;

  @override
  Widget build(BuildContext context) => Card(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(valor, style: Theme.of(context).textTheme.titleLarge),
          Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

/// Forma, rachas, porcentaje de asistencia, compañeros y destacados.
class _Extra extends StatelessWidget {
  const _Extra(this.e, {required this.miembros});
  final Map<String, dynamic> e;
  final Map<String, Miembro> miembros;

  String _nombre(dynamic m) => miembros[(m as Map)['miembro_id']]?.nombre ?? 'Alguien';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final forma = (e['forma'] as String?) ?? '';
    final destacados = Map<String, dynamic>.from((e['destacados'] as Map?) ?? const {});
    Color colorForma(String c) => switch (c) { 'V' => Colors.green.shade600, 'D' => cs.error, _ => cs.outline };
    final filas = <Widget>[
      if (e['mejor_companero'] != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.handshake_outlined),
          title: Text('Mejor pareja: ${_nombre(e['mejor_companero'])}'),
          subtitle: Text('${e['mejor_companero']['pct_victorias']} % de victorias juntos '
              '(${e['mejor_companero']['partidos']} partidos)'),
        ),
      if (e['mas_juega_con'] != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.groups_outlined),
          title: Text('Más partidos con: ${_nombre(e['mas_juega_con'])}'),
          subtitle: Text('${e['mas_juega_con']['partidos']} partidos en el mismo equipo'),
        ),
      if (e['bestia_negra'] != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.sentiment_dissatisfied_outlined),
          title: Text('Bestia negra: ${_nombre(e['bestia_negra'])}'),
          subtitle: Text('Pierde el ${e['bestia_negra']['pct_derrotas']} % cuando le tiene enfrente'),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Tx('Forma y rachas', style: t.titleMedium),
      const SizedBox(height: 8),
      Row(children: [
        for (final c in forma.split(''))
          Container(
            margin: const EdgeInsets.only(right: 6),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colorForma(c), borderRadius: BorderRadius.circular(8)),
            child: Text(c, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        if (forma.isEmpty) const Tx('Sin partidos todavía'),
        const Spacer(),
        if (e['asistencia_pct'] != null) Text('Asistencia ${e['asistencia_pct']} %', style: t.bodySmall),
      ]),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.4,
        children: [
          _Dato('Invicto ahora', '${e['racha_invicto_actual'] ?? 0}'),
          _Dato('Mejor racha invicto', '${e['racha_invicto_max'] ?? 0}'),
          _Dato('Victorias seguidas', '${e['racha_victorias_max'] ?? 0}'),
          _Dato('Porterías a cero', '${e['porterias_cero'] ?? 0}'),
          _Dato('Encajados/partido', '${e['goles_encajados_partido'] ?? '—'}'),
          _Dato('Votos MVP', '${e['votos_mvp'] ?? 0}'),
        ],
      ),
      if (destacados.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Destacó en', style: t.titleSmall),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in destacados.entries)
            Chip(label: Text('${nombresAspectos[d.key] ?? d.key} ×${d.value}'), visualDensity: VisualDensity.compact),
        ]),
      ],
      if (filas.isNotEmpty) ...[const SizedBox(height: 8), ...filas],
    ]);
  }
}

/// Gráfica sin dependencias: barras = puntos de cada partido (oro si fue MVP); línea = nota media (escala 0–10).
class GraficaEvolucion extends StatelessWidget {
  const GraficaEvolucion({super.key, required this.partidos});

  /// Del más antiguo al más reciente.
  final List<PuntosFantasy> partidos;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ultimos = partidos.length > 20 ? partidos.sublist(partidos.length - 20) : partidos;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 160,
        width: double.infinity,
        child: CustomPaint(
          painter: _PintorEvolucion(
            puntos: [for (final p in ultimos) p.total],
            notas: [for (final p in ultimos) p.notaMedia],
            mvp: [for (final p in ultimos) p.esMvp],
            barra: cs.primary,
            barraMvp: cs.tertiary,
            linea: cs.secondary,
            eje: cs.outlineVariant,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 14, children: [
        _Leyenda(color: cs.primary, texto: 'Puntos'),
        _Leyenda(color: cs.tertiary, texto: 'MVP'),
        _Leyenda(color: cs.secondary, texto: 'Nota (0–10)', linea: true),
        Text('Últimos ${ultimos.length} partidos', style: Theme.of(context).textTheme.bodySmall),
      ]),
    ]);
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.color, required this.texto, this.linea = false});
  final Color color;
  final String texto;
  final bool linea;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: linea ? 3 : 10, color: color),
        const SizedBox(width: 4),
        Text(texto, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _PintorEvolucion extends CustomPainter {
  _PintorEvolucion({required this.puntos, required this.notas, required this.mvp, required this.barra,
      required this.barraMvp, required this.linea, required this.eje});
  final List<double> puntos;
  final List<double?> notas;
  final List<bool> mvp;
  final Color barra, barraMvp, linea, eje;

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.isEmpty) return;
    final maxP = puntos.fold<double>(1, (a, b) => b > a ? b : a);
    final minP = puntos.fold<double>(0, (a, b) => b < a ? b : a);
    final rango = maxP - minP;
    final cero = size.height * (maxP / (rango == 0 ? 1 : rango));
    final ancho = size.width / puntos.length;
    canvas.drawLine(Offset(0, cero), Offset(size.width, cero), Paint()..color = eje..strokeWidth = 1);
    for (var i = 0; i < puntos.length; i++) {
      final alto = puntos[i] / (rango == 0 ? 1 : rango) * size.height;
      final r = Rect.fromLTWH(i * ancho + ancho * 0.2, puntos[i] >= 0 ? cero - alto : cero, ancho * 0.6, alto.abs());
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), Paint()..color = mvp[i] ? barraMvp : barra.withValues(alpha: 0.8));
    }
    final camino = Path();
    var empezado = false;
    for (var i = 0; i < notas.length; i++) {
      final n = notas[i];
      if (n == null) continue;
      final p = Offset(i * ancho + ancho / 2, size.height - (n.clamp(0, 10) / 10) * size.height);
      if (empezado) {
        camino.lineTo(p.dx, p.dy);
      } else {
        camino.moveTo(p.dx, p.dy);
        empezado = true;
      }
      canvas.drawCircle(p, 3, Paint()..color = linea);
    }
    canvas.drawPath(camino, Paint()..color = linea..strokeWidth = 2..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _PintorEvolucion old) => old.puntos != puntos || old.notas != notas;
}
