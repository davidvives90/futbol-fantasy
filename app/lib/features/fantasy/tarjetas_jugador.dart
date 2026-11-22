import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/avatar.dart';
import '../../core/idioma.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../liga/chip_rango.dart';
import 'widgets_fantasy.dart';

/// Lo que ha hecho un jugador en el Fantasy de la liga (0044, `resumen_jugadores_fantasy`).
class ResumenFantasy {
  ResumenFantasy.fromMap(Map<String, dynamic> m)
      : partidos = toInt(m['partidos']),
        media = toDouble(m['media']) ?? 0,
        maximo = toDouble(m['maximo']) ?? 0,
        goles = toInt(m['goles']),
        asistencias = toInt(m['asistencias']),
        mvps = toInt(m['mvps']),
        nota = toDouble(m['nota']),
        ultimos = [
          for (final u in (m['ultimos'] as List? ?? const []))
            (
              fecha: DateTime.parse((u as Map)['fecha'] as String).toLocal(),
              total: toDouble(u['total']) ?? 0,
              mvp: (u['mvp'] ?? false) as bool,
              nota: toDouble(u['nota']),
            ),
        ];

  final int partidos, goles, asistencias, mvps;
  final double media, maximo;

  /// Nota media de los compañeros en estrellas (1–5).
  final double? nota;

  /// Últimos 5 partidos, del más reciente al más antiguo.
  final List<({DateTime fecha, double total, bool mvp, double? nota})> ultimos;
}

final resumenFantasyProvider = FutureProvider.autoDispose.family<Map<String, ResumenFantasy>, String>((ref, ligaId) async {
  final r = await sb.rpc('resumen_jugadores_fantasy', params: {'p_liga': ligaId});
  final m = Map<String, dynamic>.from((r as Map?) ?? const {});
  return {for (final e in m.entries) e.key: ResumenFantasy.fromMap(Map<String, dynamic>.from(e.value as Map))};
});

/// Color de una puntuación: verde si es buena, ámbar si normal, rojo si floja (respecto a la media de la liga ≈ 8).
Color colorPuntos(BuildContext context, double p) {
  final c = AppColores.of(context);
  if (p >= 12) return c.exito;
  if (p >= 6) return c.aviso;
  return Theme.of(context).colorScheme.error;
}

/// Número con la coma del idioma (7,2) y sin decimales si es entero.
String _num(double v) => NumberFormat('#0.#', idiomaActual).format(v);

/// Las 5 últimas puntuaciones en mini barras (la más reciente a la derecha).
class MiniUltimos extends StatelessWidget {
  const MiniUltimos(this.ultimos, {super.key, this.alto = 26, this.conNumeros = true});
  final List<({DateTime fecha, double total, bool mvp, double? nota})> ultimos;
  final double alto;
  final bool conNumeros;

  @override
  Widget build(BuildContext context) {
    final lista = ultimos.reversed.toList();
    final tope = math.max(15.0, lista.fold<double>(0, (a, u) => math.max(a, u.total)));
    final cs = Theme.of(context).colorScheme;
    // La altura ya dice cuánto puntuó (no solo el color); el lector de pantalla lee los números
    return Semantics(
      label: trf('Últimos partidos: {p}', {'p': [for (final u in lista) _num(u.total)].join(', ')}),
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < 5; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (conNumeros)
              Text(i < lista.length ? _num(lista[i].total) : '–',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            Container(
              width: 14,
              height: i < lista.length ? math.max(3, alto * (lista[i].total.clamp(0, tope) / tope)) : 3,
              decoration: BoxDecoration(
                color: i < lista.length ? colorPuntos(context, lista[i].total) : cs.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ]),
        ),
    ]));
  }
}

/// Tarjeta de jugador para las listas (mercado, plantilla): foto, nombre, rango y posición, valor,
/// media por partido y sus 5 últimas puntuaciones.
class TarjetaJugadorLista extends StatelessWidget {
  const TarjetaJugadorLista({
    super.key,
    required this.miembro,
    required this.precio,
    this.variacion,
    this.resumen,
    this.mio = false,
    this.extra,
    this.insignia,
    this.onTap,
  });
  final Miembro? miembro;
  final double? precio, variacion;
  final ResumenFantasy? resumen;
  final bool mio;
  final String? extra;
  final Widget? insignia;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = resumen;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              AvatarMiembro(miembro, radio: 26),
              if (mio)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: CircleAvatar(radius: 9, backgroundColor: cs.primary, child: Icon(Icons.check, size: 12, color: cs.onPrimary)),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(miembro?.nombre ?? '…', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (miembro != null) ChipRango(miembro!.rango),
                  Text(etiquetaPosicion(miembro?.posicion), style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                  if (insignia != null) insignia!,
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  // Media por partido
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (r == null ? cs.outline : colorPuntos(context, r.media)).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      r == null || r.partidos == 0 ? tr('Sin partidos') : trf('{m} pts/partido', {'m': _num(r.media)}),
                      style: t.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800, color: r == null ? cs.onSurfaceVariant : colorPuntos(context, r.media)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (r != null && r.ultimos.isNotEmpty) MiniUltimos(r.ultimos, alto: 18, conNumeros: false),
                ]),
                if (extra != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(extra!, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(millones(precio), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              VariacionTexto(variacion),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Carta del jugador (cabecera de su ficha): foto, nombre, media en grande, rango, posición, valor y números clave.
class CartaJugador extends StatelessWidget {
  const CartaJugador({super.key, required this.miembro, this.precio, this.variacion, this.resumen, this.valoracion});
  final Miembro? miembro;
  final double? precio, variacion;
  final ResumenFantasy? resumen;

  /// Valoración 0–100 del mercado.
  final double? valoracion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = resumen;
    final media = r?.media ?? 0;
    const blanco = Colors.white;
    Widget dato(String valor, String etiqueta) => Expanded(
          child: Column(children: [
            Text(valor, style: const TextStyle(color: blanco, fontSize: 20, fontWeight: FontWeight.w800)),
            Text(tr(etiqueta), style: TextStyle(color: blanco.withValues(alpha: 0.8), fontSize: 11)),
          ]),
        );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(cs.primary, Colors.black, 0.35)!, cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.5)!],
        ),
        boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Media por partido, como el «rating» de una carta
          Column(children: [
            Text(r == null || r.partidos == 0 ? '–' : _num(media),
                style: const TextStyle(color: blanco, fontSize: 44, fontWeight: FontWeight.w900, height: 1)),
            Text(tr('pts/partido'), style: TextStyle(color: blanco.withValues(alpha: 0.85), fontSize: 11)),
            const SizedBox(height: 8),
            if (miembro != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: blanco.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
                child: Text(miembro!.rango.etiqueta.toUpperCase(),
                    style: const TextStyle(color: blanco, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: blanco),
            child: AvatarMiembro(miembro, radio: 46),
          ),
        ]),
        const SizedBox(height: 12),
        Text(miembro?.nombre ?? '…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: blanco, fontSize: 24, fontWeight: FontWeight.w800)),
        Text(etiquetaPosicion(miembro?.posicion).toUpperCase(),
            style: TextStyle(color: blanco.withValues(alpha: 0.85), fontSize: 12, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        // Valor de mercado (no se enseña en Perfil, donde no hay precio)
        if (precio != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.sell_outlined, color: blanco, size: 18),
            const SizedBox(width: 6),
            Text(millones(precio), style: const TextStyle(color: blanco, fontSize: 20, fontWeight: FontWeight.w800)),
            if (variacion != null && variacion != 0) ...[
              const SizedBox(width: 8),
              Icon(variacion! > 0 ? Icons.trending_up : Icons.trending_down,
                  color: variacion! > 0 ? const Color(0xFF9CF2B5) : const Color(0xFFFFB4A9), size: 18),
              Text('${variacion! > 0 ? '+' : ''}${millones(variacion)}',
                  style: TextStyle(
                      color: variacion! > 0 ? const Color(0xFF9CF2B5) : const Color(0xFFFFB4A9), fontWeight: FontWeight.w700)),
            ],
            if (valoracion != null) ...[
              const SizedBox(width: 10),
              Text('· ${valoracion!.round()}/100', style: TextStyle(color: blanco.withValues(alpha: 0.85))),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        Divider(color: blanco.withValues(alpha: 0.25), height: 1),
        const SizedBox(height: 10),
        Row(children: [
          dato('${r?.partidos ?? 0}', 'Partidos'),
          dato('${r?.goles ?? 0}', 'Goles'),
          dato('${r?.asistencias ?? 0}', 'Asist.'),
          dato('${r?.mvps ?? 0}', 'MVP'),
          dato(r?.nota == null ? '–' : _num(r!.nota!), 'Estrellas'),
        ]),
      ]),
    );
  }
}

/// Últimas 5 puntuaciones con fecha, grandes y legibles (la más reciente a la derecha).
class UltimasPuntuaciones extends StatelessWidget {
  const UltimasPuntuaciones(this.resumen, {super.key});
  final ResumenFantasy? resumen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lista = (resumen?.ultimos ?? const []).reversed.toList();
    if (lista.isEmpty) {
      return Padding(padding: const EdgeInsets.all(8), child: Text(tr('Aún no ha jugado ningún partido puntuado.')));
    }
    final tope = math.max(15.0, lista.fold<double>(0, (a, u) => math.max(a, u.total)));
    final media = resumen!.media;
    // La media va como leyenda encima: dentro del gráfico pisaba la cifra de alguna barra.
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 16, height: 2, color: cs.primary.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(trf('media {m}', {'m': _num(media)}), style: t.labelSmall?.copyWith(color: cs.primary)),
      ]),
      const SizedBox(height: 4),
      SizedBox(
      height: 150,
      child: Stack(children: [
        // Línea de su media
        Positioned.fill(
          child: LayoutBuilder(builder: (context, c) {
            final y = 22 + (c.maxHeight - 52) * (1 - (media.clamp(0, tope) / tope));
            return Stack(children: [
              Positioned(
                left: 0,
                right: 0,
                top: y,
                child: Container(height: 1, color: cs.primary.withValues(alpha: 0.5)),
              ),
            ]);
          }),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final u in lista)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_num(u.total), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    if (u.mvp) const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF9A825)),
                  ]),
                  const SizedBox(height: 2),
                  Container(
                    height: math.max(4, 98 * (u.total.clamp(0, tope) / tope)),
                    decoration: BoxDecoration(
                      color: colorPuntos(context, u.total),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(DateFormat('d MMM', idiomaActual).format(u.fecha), style: t.labelSmall),
                ]),
              ),
            ),
        ]),
      ]),
      ),
    ]);
  }
}
