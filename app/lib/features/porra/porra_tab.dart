import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/avatar.dart';
import '../../core/equipaciones.dart';
import '../../core/idioma.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/porra_repo.dart';
import '../../core/guias.dart';

final porraProvider = FutureProvider.autoDispose.family<EstadoPorra, String>((ref, p) => PorraRepo.estado(p));
final rankingPorraProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, l) => PorraRepo.ranking(l));

String _cuota(double c) => c.toStringAsFixed(2).replaceAll('.', ',');

/// Porra del partido (Fase 3, 0055): quiniela 1-X-2, goleador y MVP; sencilla, combinada o múltiple; seguro.
class PorraTab extends ConsumerStatefulWidget {
  const PorraTab({super.key, required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  @override
  ConsumerState<PorraTab> createState() => _PorraTabState();
}

class _PorraTabState extends ConsumerState<PorraTab> {
  final _boleto = <String, Pronostico>{};
  final _importe = TextEditingController(text: '10');
  bool _seguro = false;
  bool _enviando = false;
  String? _tipoElegido;

  @override
  void dispose() {
    _importe.dispose();
    super.dispose();
  }

  String _unidad(EstadoPorra e) => e.conDinero ? 'M' : 'pts';
  String _fmt(EstadoPorra e, double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2).replaceAll('.', ',')} ${_unidad(e)}';

  void _alternar(Pronostico p) {
    setState(() {
      if (_boleto.containsKey(p.clave)) {
        _boleto.remove(p.clave);
      } else {
        // Un solo 1-X-2 y un solo MVP por boleto: el nuevo sustituye al anterior
        if (p.mercado == '1x2' || p.mercado == 'mvp') _boleto.removeWhere((_, x) => x.mercado == p.mercado);
        // «Marca» y «no marca» del mismo jugador se excluyen
        if (p.mercado == 'goleador' || p.mercado == 'no_goleador') {
          _boleto.removeWhere((_, x) =>
              x.seleccion == p.seleccion && x.mercado == (p.mercado == 'goleador' ? 'no_goleador' : 'goleador'));
        }
        _boleto[p.clave] = p;
      }
      _tipoElegido = null;
    });
  }

  List<String> get _tiposPosibles => switch (_boleto.length) {
        0 => const [],
        1 => const ['sencilla'],
        2 => const ['combinada'],
        3 || 4 => const ['combinada', 'multiple'],
        _ => const ['combinada'],
      };

  String get _tipo => _tipoElegido != null && _tiposPosibles.contains(_tipoElegido) ? _tipoElegido! : _tiposPosibles.first;

  String _nombreSel(Pronostico p, Map<String, Miembro> miembros) => switch (p.mercado) {
        '1x2' => switch (p.seleccion) {
            '1' => trf('Gana {e}', {'e': nombreEquipo(context, 1)}),
            '2' => trf('Gana {e}', {'e': nombreEquipo(context, 2)}),
            _ => tr('Empate'),
          },
        'goleador' => trf('Marca {n}', {'n': miembros[p.seleccion]?.nombre ?? '…'}),
        'no_goleador' => trf('{n} no marca', {'n': miembros[p.seleccion]?.nombre ?? '…'}),
        _ => trf('MVP: {n}', {'n': miembros[p.seleccion]?.nombre ?? '…'}),
      };

  Future<void> _apostar(EstadoPorra e) async {
    final importe = double.tryParse(_importe.text.trim().replaceAll(',', '.'));
    if (importe == null || importe <= 0) {
      mostrarError(context, tr('Pon un importe mayor que 0'));
      return;
    }
    setState(() => _enviando = true);
    final ok = await ejecutar(
      context,
      () => PorraRepo.apostar(widget.partido.id, _tipo, _boleto.values.toList(), importe, _seguro),
      ok: tr('¡Boleto hecho!'),
    );
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) {
        _boleto.clear();
        _seguro = false;
      }
    });
    if (ok) ref.invalidate(porraProvider(widget.partido.id));
  }

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(porraProvider(widget.partido.id));
    final miembros = ref.watch(miembrosPorIdProvider(widget.mi.liga.id));
    return datos.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(porraProvider(widget.partido.id))),
      data: (e) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(porraProvider(widget.partido.id)),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
          const AvisoGuia('porra'),
          _cabecera(e),
          if (e.bote != null) _Bote(e: e, partidoId: widget.partido.id, onCambio: () => ref.invalidate(porraProvider(widget.partido.id))),
          if (e.abierta) ..._mercados(e, miembros),
          if (e.abierta && _boleto.isNotEmpty) _tarjetaBoleto(e, miembros),
          if (e.mias.isNotEmpty) ...[
            const SizedBox(height: 16),
            Tx('Mis boletos', style: Theme.of(context).textTheme.titleMedium),
            for (final b in e.mias) _TarjetaBoletoHecho(b: b, e: e, nombre: (p) => _nombreSel(p, miembros), fmt: (v) => _fmt(e, v),
                cancelable: e.abierta && b.estado == 'pendiente', onCancelar: () async {
              final ok = await ejecutar(context, () => PorraRepo.cancelar(b.id), ok: tr('Boleto quitado'));
              if (ok) ref.invalidate(porraProvider(widget.partido.id));
            }),
          ],
          if (e.todas.isNotEmpty) ...[
            const SizedBox(height: 16),
            Tx('Boletos de la liga', style: Theme.of(context).textTheme.titleMedium),
            const _AvisoPublico(),
            for (final b in e.todas)
              _TarjetaBoletoHecho(b: b, e: e, nombre: (p) => _nombreSel(p, miembros), fmt: (v) => _fmt(e, v),
                  autor: miembros[b.miembroId]?.nombre),
          ],
          const SizedBox(height: 16),
          _RankingPorra(mi: widget.mi, unidad: _unidad(e)),
        ]),
      ),
    );
  }

  Widget _cabecera(EstadoPorra e) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: e.abierta ? cs.primaryContainer : cs.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(e.abierta ? Icons.casino_outlined : Icons.lock_clock),
        title: Tx(e.abierta ? 'Porra abierta hasta el pitido inicial' : 'Porra cerrada', style: t.titleSmall),
        subtitle: Text(e.abierta
            ? [
                e.conDinero ? tr('Con dinero Fantasy') : tr('Solo puntos: ranking de Mejor pronosticador'),
                trf('te quedan {x} de {t}', {'x': _fmt(e, e.disponible), 't': _fmt(e, e.tope)}),
                if (e.maxGanancia != null) trf('ganancia máxima {x} por boleto', {'x': _fmt(e, e.maxGanancia!)}),
                if (e.conDinero && e.saldo != null) trf('saldo {s}', {'s': _fmt(e, e.saldo!)}),
              ].join(' · ')
            : switch (e.motivo) {
                'menores' => tr('No disponible: en esta liga hay jugadores menores de 18 años.'),
                'desactivada' => tr('La porra no está disponible ahora mismo.'),
                _ => tr('Se abre al hacer los equipos y se liquida al cerrar el acta.'),
              }),
      ),
    );
  }

  List<Widget> _mercados(EstadoPorra e, Map<String, Miembro> miembros) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final q = e.cuotas.where((c) => c.mercado == '1x2').toList()
      ..sort((a, b) => const ['1', 'X', '2'].indexOf(a.seleccion).compareTo(const ['1', 'X', '2'].indexOf(b.seleccion)));
    Widget chipJugador(Pronostico p) {
      final sel = _boleto.containsKey(p.clave);
      return FilterChip(
        selected: sel,
        avatar: AvatarMiembro(miembros[p.seleccion], radio: 12),
        label: Text('${miembros[p.seleccion]?.nombre ?? '…'}  ${_cuota(p.cuota)}'),
        onSelected: (_) => _alternar(p),
      );
    }

    return [
      const SizedBox(height: 8),
      Tx('Quiniela 1-X-2', style: t.titleMedium),
      const SizedBox(height: 6),
      Row(children: [
        for (final p in q)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _boleto.containsKey(p.clave)
                  ? FilledButton(onPressed: () => _alternar(p), child: _BotonSigno(p: p, equipo: _equipoDe(p)))
                  : OutlinedButton(onPressed: () => _alternar(p), child: _BotonSigno(p: p, equipo: _equipoDe(p))),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Tx('Goleador (marca al menos un gol)', style: t.titleSmall),
        subtitle: Tx('Fácil de acertar: paga muy poco', style: t.bodySmall),
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in e.cuotas.where((c) => c.mercado == 'goleador')) chipJugador(p),
          ]),
        ],
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Tx('No marca (ningún gol)', style: t.titleSmall),
        subtitle: Tx('Fácil de acertar: paga muy poco', style: t.bodySmall),
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in e.cuotas.where((c) => c.mercado == 'no_goleador')) chipJugador(p),
          ]),
        ],
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Tx('MVP del partido', style: t.titleSmall),
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in e.cuotas.where((c) => c.mercado == 'mvp')) chipJugador(p),
          ]),
        ],
      ),
      if (_boleto.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('Toca un pronóstico para empezar tu boleto.'), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
    ];
  }

  int? _equipoDe(Pronostico p) => p.seleccion == '1' ? 1 : p.seleccion == '2' ? 2 : null;

  Widget _tarjetaBoleto(EstadoPorra e, Map<String, Miembro> miembros) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final importe = double.tryParse(_importe.text.trim().replaceAll(',', '.')) ?? 0;
    final sel = _boleto.values.toList();
    final todos = [for (final s in sel) (s.cuota, true)];
    final ninguno = [for (final s in sel) (s.cuota, false)];
    final gana = retornoBoleto(_tipo, importe, _seguro, todos, maxGanancia: e.maxGanancia);
    final pierde = retornoBoleto(_tipo, importe, _seguro, ninguno, maxGanancia: e.maxGanancia);
    final sinSeguro = retornoBoleto(_tipo, importe, false, todos, maxGanancia: e.maxGanancia);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined),
            const SizedBox(width: 8),
            Expanded(child: Tx('Tu boleto', style: t.titleMedium)),
            TextButton(onPressed: () => setState(_boleto.clear), child: const Tx('Vaciar')),
          ]),
          for (final s in sel)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(_nombreSel(s, miembros)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_cuota(s.cuota), style: AppTheme.tabular(t.titleSmall)),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _alternar(s)),
              ]),
            ),
          if (_tiposPosibles.length > 1)
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final x in _tiposPosibles)
                  ButtonSegment(value: x, label: Tx(x == 'combinada' ? 'Combinada' : 'Múltiple')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipoElegido = s.first),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Tx(
              switch (_tipo) {
                'sencilla' => 'Sencilla: un pronóstico.',
                'combinada' => 'Combinada: se multiplican las cuotas; hay que acertarlo todo.',
                _ => 'Múltiple: todas las parejas posibles; si fallas uno, cobras las parejas acertadas.',
              },
              style: t.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _importe,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: tr('Importe'),
              suffixText: _unidad(e),
              helperText: trf('Máximo {x} en este partido', {'x': _fmt(e, e.disponible)}),
            ),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Text('🛡️', style: TextStyle(fontSize: 22)),
            title: const Tx('Activar seguro'),
            subtitle: const Tx('Si pierdes, recuperas el 50 %. Si ganas, el beneficio se queda en el 70 %.'),
            value: _seguro,
            onChanged: (v) => setState(() => _seguro = v),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Text(
              _seguro
                  ? trf('Con seguro: ganas {g} · si fallas recuperas {p}  (sin seguro ganarías {s})',
                      {'g': _fmt(e, gana), 'p': _fmt(e, pierde), 's': _fmt(e, sinSeguro)})
                  : trf('Si aciertas cobras {g} · si fallas pierdes {i}', {'g': _fmt(e, gana), 'i': _fmt(e, importe)}),
              style: t.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _enviando || importe <= 0 || importe > e.disponible + 0.001 ? null : () => _apostar(e),
              icon: const Icon(Icons.check),
              label: Tx(e.conDinero ? 'Confirmar boleto (se descuenta del saldo)' : 'Confirmar boleto'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BotonSigno extends StatelessWidget {
  const _BotonSigno({required this.p, required this.equipo});
  final Pronostico p;
  final int? equipo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(p.seleccion, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if (equipo != null) PuntoEquipo(equipo!) else const SizedBox(height: 10),
          Text(_cuota(p.cuota)),
        ]),
      );
}

class _TarjetaBoletoHecho extends StatelessWidget {
  const _TarjetaBoletoHecho({
    required this.b,
    required this.e,
    required this.nombre,
    required this.fmt,
    this.autor,
    this.cancelable = false,
    this.onCancelar,
  });
  final Boleto b;
  final EstadoPorra e;
  final String Function(Pronostico) nombre;
  final String Function(double) fmt;
  final String? autor;
  final bool cancelable;
  final VoidCallback? onCancelar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final (icono, color, texto) = switch (b.estado) {
      'ganada' => (Icons.emoji_events, AppColores.of(context).exito, trf('Ganado: cobras {x}', {'x': fmt(b.retorno ?? 0)})),
      'parcial' => (Icons.shield_outlined, cs.tertiary, trf('Recuperas {x}', {'x': fmt(b.retorno ?? 0)})),
      'perdida' => (Icons.close, cs.error, tr('Perdido')),
      'anulada' => (Icons.undo, cs.outline, tr('Anulado: partido cancelado')),
      _ => (Icons.hourglass_bottom, cs.primary, tr('Pendiente')),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icono, color: color, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  [
                    if (autor != null) autor!,
                    tr(switch (b.tipo) { 'sencilla' => 'Sencilla', 'combinada' => 'Combinada', _ => 'Múltiple' }),
                    fmt(b.importe),
                    if (b.cuotaTotal != null) '@ ${_cuota(b.cuotaTotal!)}',
                    if (b.seguro) '🛡️',
                  ].join(' · '),
                  style: t.titleSmall),
            ),
            if (cancelable) IconButton(icon: const Icon(Icons.delete_outline), tooltip: tr('Quitar'), onPressed: onCancelar),
          ]),
          for (final s in b.selecciones)
            Text(
                '${s.acierto == null ? '·' : s.acierto! ? '✅' : '❌'} ${nombre(s)} (${_cuota(s.cuota)})',
                style: t.bodySmall),
          const SizedBox(height: 4),
          Text(texto, style: t.bodyMedium?.copyWith(color: color)),
        ]),
      ),
    );
  }
}

class _RankingPorra extends ConsumerWidget {
  const _RankingPorra({required this.mi, required this.unidad});
  final MiLiga mi;
  final String unidad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(rankingPorraProvider(mi.liga.id)).valueOrNull ?? const [];
    if (r.isEmpty) return const SizedBox.shrink();
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Tx('🎯 Resumen de aciertos', style: t.titleMedium),
          Tx('Boletos y bote de cada jugador. Todo es público en la liga.', style: t.bodySmall),
          for (final (i, x) in r.take(10).indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text('${i + 1}.', style: t.titleSmall),
              title: Text(miembros[x['miembro_id']]?.nombre ?? (x['nombre'] as String?) ?? '…'),
              subtitle: Text([
                if (((x['boletos'] as num?) ?? 0) > 0) trf('{a} de {b} boletos ganados', {'a': x['aciertos'], 'b': x['boletos']}),
                if (((x['quinielas'] as num?) ?? 0) > 0)
                  trf('bote: {p} plenos y {s} 1X2 en {q}', {'p': x['plenos'], 's': x['signos'], 'q': x['quinielas']}),
              ].join(' · ')),
              trailing: Text(
                  '${((x['beneficio_total'] ?? x['beneficio']) as num) >= 0 ? '+' : ''}${((x['beneficio_total'] ?? x['beneficio']) as num).toStringAsFixed(1).replaceAll('.', ',')} $unidad',
                  style: AppTheme.tabular(t.titleSmall)),
            ),
        ]),
      ),
    );
  }
}


/// 0061: las apuestas son públicas.
class _AvisoPublico extends StatelessWidget {
  const _AvisoPublico();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 6),
        child: Row(children: [
          Icon(Icons.visibility_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Tx('Las apuestas y el bote son públicos: todos los de la liga ven lo que juega cada uno.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ]),
      );
}

/// 0061: bote del partido, como la quiniela. Entrada fija, pronóstico del resultado; pleno 70 %, 1X2 30 %, si no, se acumula.
class _Bote extends StatelessWidget {
  const _Bote({required this.e, required this.partidoId, required this.onCambio});
  final EstadoPorra e;
  final String partidoId;
  final VoidCallback onCambio;

  String _m(num v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1).replaceAll('.', ',')} M';

  Future<void> _jugar(BuildContext context, Map<String, dynamic>? mia) async {
    var g1 = (mia?['goles1'] as num?)?.toInt() ?? 1, g2 = (mia?['goles2'] as num?)?.toInt() ?? 1;
    final entrada = (e.bote!['entrada'] as num?) ?? 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) {
        Widget marcador(String equipo, int v, void Function(int) cambia) => Column(children: [
              Text(equipo, style: Theme.of(c).textTheme.titleSmall, textAlign: TextAlign.center),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: v > 0 ? () => setD(() => cambia(v - 1)) : null, icon: const Icon(Icons.remove_circle_outline)),
                SizedBox(width: 36, child: Text('$v', textAlign: TextAlign.center, style: Theme.of(c).textTheme.headlineMedium)),
                IconButton(onPressed: v < 30 ? () => setD(() => cambia(v + 1)) : null, icon: const Icon(Icons.add_circle_outline)),
              ]),
            ]);
        return AlertDialog(
          title: const Tx('¿Cómo acabará?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              Expanded(child: marcador(nombreEquipo(context, 1), g1, (x) => g1 = x)),
              Expanded(child: marcador(nombreEquipo(context, 2), g2, (x) => g2 = x)),
            ]),
            const SizedBox(height: 8),
            Text(mia == null
                ? trf('Entrada: {x}. Puedes cambiar el resultado hasta que empiece el partido sin volver a pagar.', {'x': _m(entrada)})
                : tr('Puedes cambiar el resultado hasta que empiece el partido sin volver a pagar.'),
                style: Theme.of(c).textTheme.bodySmall),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Tx('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Tx(mia == null ? 'Jugar' : 'Guardar')),
          ],
        );
      }),
    );
    if (ok != true || !context.mounted) return;
    final hecho = await ejecutar(context, () => PorraRepo.jugarQuiniela(partidoId, g1, g2),
        ok: mia == null ? tr('¡Estás en el bote!') : tr('Resultado cambiado'));
    if (hecho) onCambio();
  }

  @override
  Widget build(BuildContext context) {
    final b = e.bote!;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final mia = b['mia'] == null ? null : Map<String, dynamic>.from(b['mia'] as Map);
    final res = b['resultado'] == null ? null : Map<String, dynamic>.from(b['resultado'] as Map);
    final lista = [for (final x in (b['quinielas'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    const oro = Color(0xFFF2A229);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFC8102E), Color(0xFF7A0A1C)])),
          child: Row(children: [
            const Text('💰', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Tx(res == null ? 'Bote del partido' : 'Bote repartido', style: t.labelLarge?.copyWith(color: Colors.white70)),
                Text(_m(b['total'] as num), style: t.headlineMedium?.copyWith(color: oro, fontWeight: FontWeight.w900)),
              ]),
            ),
            if (e.abierta)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: oro, foregroundColor: Colors.black),
                onPressed: () => _jugar(context, mia),
                child: Text(mia == null
                    ? trf('Jugar · {x}', {'x': _m((b['entrada'] as num?) ?? 1)})
                    : '${tr('Mi resultado')} ${mia['goles1']}-${mia['goles2']}'),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
              res != null
                  ? trf('Acabó {a}-{b}: {p} plenos y {s} aciertos del 1X2. Pasan al siguiente bote {x}.',
                      {'a': res['goles1'], 'b': res['goles2'], 'p': res['plenos'], 's': res['signos'], 'x': _m(res['arrastre'] as num)})
                  : tr('Pronostica el resultado. El resultado exacto se lleva el 70 % y quien acierte el ganador o el empate se reparte el 30 %. Lo que nadie acierta se acumula para el próximo partido.'),
              style: t.bodySmall),
        ),
        if (res == null && b['acumulado'] != null && (b['entradas'] as num) > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(trf('Fondo de la liga {f} + entradas {e}', {'f': _m(b['acumulado'] as num), 'e': _m(b['entradas'] as num)}),
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        if (lista.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: _AvisoPublico()),
          for (final q in lista)
            ListTile(
              dense: true,
              leading: Text(switch (q['acierto']) { 'pleno' => '🎯', 'signo' => '✅', 'nada' => '❌', 'anulada' => '↩️', _ => '⏳' },
                  style: const TextStyle(fontSize: 18)),
              title: Text('${q['nombre']}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${q['goles1']}-${q['goles2']}', style: AppTheme.tabular(t.titleSmall)),
                if (((q['premio'] as num?) ?? 0) > 0 && q['acierto'] != 'anulada')
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text('+${_m(q['premio'] as num)}', style: t.labelLarge?.copyWith(color: Colors.green.shade700)),
                  ),
              ]),
            ),
        ],
        const SizedBox(height: 6),
      ]),
    );
  }
}
