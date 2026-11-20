import 'package:flutter/material.dart';
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
Future<void> compartirTexto(BuildContext context, String texto, {String asunto = 'Fútbol Fantasy'}) async {
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
    await compartirTexto(context, textoPartido(r, liga, p.id));
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
  }
}
