import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import 'supabase.dart';
import 'utils.dart';

final _diaHora = DateFormat("EEEE d 'de' MMMM · HH:mm", 'es');

/// Texto para WhatsApp de un partido, según en qué punto esté:
/// convocatoria (quién va y cuántos faltan) → equipos hechos → resultado con goleadores y MVP.
String textoPartido(Map<String, dynamic> r, Liga liga, String partidoId) {
  final b = StringBuffer();
  final fecha = DateTime.parse(r['fecha'] as String).toLocal();
  String equipo(dynamic n) {
    final i = int.parse('$n') - 1;
    return i >= 0 && i < liga.equipaciones.length ? liga.equipaciones[i].nombre : 'Equipo $n';
  }

  final encuentros = [for (final e in (r['encuentros'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
  final jugados = encuentros.where((e) => e['goles_local'] != null && e['goles_visitante'] != null).toList();
  final equipos = Map<String, dynamic>.from((r['equipos'] as Map?) ?? const {});
  final confirmados = [for (final n in (r['confirmados'] as List? ?? const [])) '$n'];
  final espera = [for (final n in (r['espera'] as List? ?? const [])) '$n'];
  final plazas = (r['plazas'] as num?)?.toInt() ?? 0;
  final cap = _diaHora.format(fecha);

  b.writeln('⚽ *${r['liga']}*');
  b.writeln('🗓️ ${cap[0].toUpperCase()}${cap.substring(1)}');
  if (r['campo'] != null) b.writeln('📍 ${r['campo']}');
  b.writeln();

  if (jugados.isNotEmpty) {
    for (final e in jugados) {
      b.writeln('🏁 *${equipo(e['local'])} ${e['goles_local']} – ${e['goles_visitante']} ${equipo(e['visitante'])}*');
    }
    final goleadores = [for (final g in (r['goleadores'] as List? ?? const [])) Map<String, dynamic>.from(g as Map)];
    if (goleadores.isNotEmpty) {
      b.writeln();
      b.writeln('⚽ ${goleadores.map((g) => '${g['nombre']}${(g['goles'] as num) > 1 ? ' (${g['goles']})' : ''}').join(', ')}');
    }
    final mvp = [for (final m in (r['mvp'] as List? ?? const [])) '$m'];
    if (mvp.isNotEmpty) b.writeln('⭐ MVP: ${mvp.join(' y ')}');
  } else if (equipos.isNotEmpty) {
    final claves = equipos.keys.toList()..sort();
    for (final k in claves) {
      b.writeln('*${equipo(k)}*: ${(equipos[k] as List).join(', ')}');
    }
  } else if (r['abre_en'] != null) {
    b.writeln('🔒 La convocatoria se abre el ${fechaHora(DateTime.parse(r['abre_en'] as String))}');
  } else {
    b.writeln('✅ *${confirmados.length}/$plazas confirmados*');
    for (var i = 0; i < confirmados.length; i++) {
      b.writeln('${i + 1}. ${confirmados[i]}');
    }
    if (espera.isNotEmpty) b.writeln('⏳ En espera: ${espera.join(', ')}');
    final faltan = plazas - confirmados.length;
    if (faltan > 0) {
      b.writeln();
      b.writeln(faltan == 1 ? '🙋 *¡Falta 1!*' : '🙋 *¡Faltan $faltan!*');
    }
  }
  b.writeln();
  b.write('👉 ${Env.webApp}#/partidos/$partidoId');
  return b.toString();
}

/// Elegir dónde compartir: WhatsApp directamente o el menú del sistema.
Future<void> compartirTexto(BuildContext context, String texto, {String asunto = 'Fútbol Fantasy', Widget? tarjeta}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(child: Text(texto)),
        ),
        ListTile(
          leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
          title: const Text('Enviar por WhatsApp'),
          onTap: () async {
            Navigator.pop(ctx);
            final ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}'),
                mode: LaunchMode.externalApplication);
            if (!ok) await Share.share(texto, subject: asunto);
          },
        ),
        if (tarjeta != null)
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Como imagen'),
            subtitle: const Text('Para el grupo o Instagram'),
            onTap: () {
              Navigator.pop(ctx);
              compartirImagen(context, tarjeta);
            },
          ),
        ListTile(
          leading: const Icon(Icons.share),
          title: const Text('Otras apps'),
          onTap: () {
            Navigator.pop(ctx);
            Share.share(texto, subject: asunto);
          },
        ),
      ]),
    ),
  );
}

Future<void> compartirPartido(BuildContext context, Partido p, Liga liga) async {
  try {
    final r = Map<String, dynamic>.from(await sb.rpc('resumen_compartir', params: {'p_partido': p.id}) as Map);
    if (!context.mounted) return;
    await compartirTexto(context, textoPartido(r, liga, p.id), tarjeta: TarjetaPartido(r: r, liga: liga));
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
  }
}

/// Vista previa de una tarjeta y botón para compartirla como PNG.
Future<void> compartirImagen(BuildContext context, Widget tarjeta, {String nombre = 'futbol-fantasy.png'}) async {
  final clave = GlobalKey();
  await showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(12), child: RepaintBoundary(key: clave, child: tarjeta)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: FilledButton.icon(
              onPressed: () async {
                try {
                  final b = clave.currentContext!.findRenderObject() as RenderRepaintBoundary;
                  final img = await b.toImage(pixelRatio: 3);
                  final png = await img.toByteData(format: ui.ImageByteFormat.png);
                  await Share.shareXFiles(
                    [XFile.fromData(png!.buffer.asUint8List(), mimeType: 'image/png', name: nombre)],
                    fileNameOverrides: [nombre],
                  );
                } catch (e) {
                  if (c.mounted) mostrarError(c, e);
                }
              },
              icon: const Icon(Icons.share),
              label: const Text('Compartir imagen'),
            ),
          ),
        ]),
      ),
    ),
  );
}

/// Tarjeta visual del partido: resultado (marcador, goleadores, MVP), equipos o convocatoria.
class TarjetaPartido extends StatelessWidget {
  const TarjetaPartido({super.key, required this.r, required this.liga});
  final Map<String, dynamic> r;
  final Liga liga;

  static const _verde = Color(0xFF0E4B3A);
  static const _verdeOscuro = Color(0xFF082E24);
  static const _oro = Color(0xFFE3B341);
  static const _crema = Color(0xFFF4F1E8);

  Equipacion _eq(dynamic n) {
    final i = int.parse('$n') - 1;
    return i >= 0 && i < liga.equipaciones.length ? liga.equipaciones[i] : Equipacion('Equipo $n');
  }

  Color _color(Equipacion e) {
    final h = e.colorHex;
    if (h == null || h.length != 7) return _oro;
    return Color(int.parse('FF${h.substring(1)}', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final fecha = DateTime.parse(r['fecha'] as String).toLocal();
    final encuentros = [for (final e in (r['encuentros'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    final jugados = encuentros.where((e) => e['goles_local'] != null && e['goles_visitante'] != null).toList();
    final equipos = Map<String, dynamic>.from((r['equipos'] as Map?) ?? const {});
    final confirmados = [for (final n in (r['confirmados'] as List? ?? const [])) '$n'];
    final plazas = (r['plazas'] as num?)?.toInt() ?? 0;
    const blanco = TextStyle(color: _crema, fontFamilyFallback: ['Roboto']);

    Widget contenido;
    if (jugados.isNotEmpty) {
      final goleadores = [for (final g in (r['goleadores'] as List? ?? const [])) Map<String, dynamic>.from(g as Map)];
      final mvp = [for (final m in (r['mvp'] as List? ?? const [])) '$m'];
      contenido = Column(children: [
        for (final e in jugados)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(child: _Equipo(_eq(e['local']).nombre, _color(_eq(e['local'])), alinear: TextAlign.right)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('${e['goles_local']} – ${e['goles_visitante']}',
                    style: blanco.copyWith(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
              Expanded(child: _Equipo(_eq(e['visitante']).nombre, _color(_eq(e['visitante'])))),
            ]),
          ),
        if (goleadores.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('⚽ ${goleadores.map((g) => '${g['nombre']}${(g['goles'] as num) > 1 ? ' ×${g['goles']}' : ''}').join('  ·  ')}',
              textAlign: TextAlign.center, style: blanco.copyWith(fontSize: 14)),
        ],
        if (mvp.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: _oro, borderRadius: BorderRadius.circular(24)),
            child: Text('⭐ MVP · ${mvp.join(' y ')}',
                style: const TextStyle(color: _verdeOscuro, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ]);
    } else if (equipos.isNotEmpty) {
      final claves = equipos.keys.toList()..sort();
      contenido = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final k in claves)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(children: [
                _Equipo(_eq(k).nombre, _color(_eq(k)), alinear: TextAlign.center),
                const SizedBox(height: 6),
                for (final n in (equipos[k] as List))
                  Text('$n', textAlign: TextAlign.center, style: blanco.copyWith(fontSize: 14, height: 1.5)),
              ]),
            ),
          ),
      ]);
    } else {
      final faltan = plazas - confirmados.length;
      contenido = Column(children: [
        Text('${confirmados.length}/$plazas', style: blanco.copyWith(fontSize: 44, fontWeight: FontWeight.w800)),
        Text('confirmados', style: blanco.copyWith(fontSize: 14)),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final n in confirmados)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(n, style: blanco.copyWith(fontSize: 13)),
              ),
          ],
        ),
        if (faltan > 0) ...[
          const SizedBox(height: 14),
          Text(faltan == 1 ? '¡Falta 1!' : '¡Faltan $faltan!',
              style: const TextStyle(color: _oro, fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ]);
    }

    final cap = DateFormat("EEEE d MMM · HH:mm", 'es').format(fecha);
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_verde, _verdeOscuro]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('⚽', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${r['liga']}', overflow: TextOverflow.ellipsis,
                style: blanco.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('${cap[0].toUpperCase()}${cap.substring(1)}${r['campo'] == null ? '' : ' · ${r['campo']}'}',
              style: blanco.copyWith(fontSize: 12, color: _crema.withValues(alpha: 0.75))),
        ),
        const SizedBox(height: 18),
        contenido,
        const SizedBox(height: 18),
        Text('Fútbol Fantasy', style: TextStyle(color: _oro.withValues(alpha: 0.9), fontSize: 11, letterSpacing: 2)),
      ]),
    );
  }
}

class _Equipo extends StatelessWidget {
  const _Equipo(this.nombre, this.color, {this.alinear = TextAlign.left});
  final String nombre;
  final Color color;
  final TextAlign alinear;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: switch (alinear) {
          TextAlign.right => MainAxisAlignment.end,
          TextAlign.center => MainAxisAlignment.center,
          _ => MainAxisAlignment.start,
        },
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle,
              border: Border.all(color: Colors.white54))),
          const SizedBox(width: 6),
          Flexible(
            child: Text(nombre.toUpperCase(), overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFF4F1E8), fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1)),
          ),
        ],
      );
}
