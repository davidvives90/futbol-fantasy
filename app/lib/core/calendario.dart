import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'idioma.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import 'supabase.dart';
import 'utils.dart';

String _utc(DateTime d) {
  final u = d.toUtc();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${dos(u.month)}${dos(u.day)}T${dos(u.hour)}${dos(u.minute)}${dos(u.second)}Z';
}

String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll(';', '\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');

String _titulo(Liga l) => '⚽ ${l.nombre}';
String? _lugar(Partido p, Liga l) => l.campoNombre ?? p.campoMapsUrl ?? l.campoMapsUrl;
String _detalle(Partido p, Liga l) => [
      if (!p.horaConfirmada) 'Hora pendiente de confirmar.',
      if ((p.campoMapsUrl ?? l.campoMapsUrl) != null) 'Mapa: ${p.campoMapsUrl ?? l.campoMapsUrl}',
      'Convocatoria: ${Env.webApp}#/partidos/${p.id}',
    ].join('\n');

/// Calendario .ics (RFC 5545) con uno o varios partidos, con aviso 2 h antes.
String icsDePartidos(List<Partido> partidos, Liga l) {
  final b = StringBuffer()
    ..writeln('BEGIN:VCALENDAR')
    ..writeln('VERSION:2.0')
    ..writeln('PRODID:-//Futbol Fantasy//ES')
    ..writeln('CALSCALE:GREGORIAN')
    ..writeln('METHOD:PUBLISH');
  for (final p in partidos) {
    final fin = p.fechaHora.add(Duration(minutes: l.duracionPartidoMin));
    final lugar = _lugar(p, l);
    b
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:${p.id}@futbolfantasy')
      ..writeln('DTSTAMP:${_utc(DateTime.now())}')
      ..writeln('DTSTART:${_utc(p.fechaHora)}')
      ..writeln('DTEND:${_utc(fin)}')
      ..writeln('SUMMARY:${_esc(_titulo(l))}')
      ..writeln('DESCRIPTION:${_esc(_detalle(p, l))}');
    if (lugar != null) b.writeln('LOCATION:${_esc(lugar)}');
    b
      ..writeln('BEGIN:VALARM')
      ..writeln('TRIGGER:-PT2H')
      ..writeln('ACTION:DISPLAY')
      ..writeln('DESCRIPTION:${_esc(_titulo(l))}')
      ..writeln('END:VALARM')
      ..writeln('END:VEVENT');
  }
  b.writeln('END:VCALENDAR');
  return b.toString().replaceAll('\n', '\r\n');
}

Uri enlaceGoogleCalendar(Partido p, Liga l) {
  final fin = p.fechaHora.add(Duration(minutes: l.duracionPartidoMin));
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': _titulo(l),
    'dates': '${_utc(p.fechaHora)}/${_utc(fin)}',
    'details': _detalle(p, l),
    if (_lugar(p, l) != null) 'location': _lugar(p, l)!,
  });
}

Future<void> _compartirIcs(BuildContext context, String ics, String nombre) async {
  final datos = Uint8List.fromList(utf8.encode(ics));
  await Share.shareXFiles([XFile.fromData(datos, mimeType: 'text/calendar', name: nombre)], fileNameOverrides: [nombre]);
}

/// Añadir un partido al calendario del móvil: Google Calendar o archivo .ics (Samsung, Outlook, Apple…).
Future<void> anadirAlCalendario(BuildContext context, Partido p, Liga l) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text('Partido del ${fechaHora(p.fechaHora)}'),
          subtitle: Text('Con aviso 2 horas antes${p.horaConfirmada ? '' : ' · la hora aún no está confirmada'}'),
        ),
        ListTile(
          leading: const Icon(Icons.event),
          title: const Tx('Google Calendar'),
          onTap: () {
            Navigator.pop(ctx);
            launchUrl(enlaceGoogleCalendar(p, l), mode: LaunchMode.externalApplication);
          },
        ),
        ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Tx('Otro calendario (archivo .ics)'),
          subtitle: const Tx('Samsung, Outlook, Apple…'),
          onTap: () {
            Navigator.pop(ctx);
            _compartirIcs(context, icsDePartidos([p], l), 'partido.ics');
          },
        ),
      ]),
    ),
  );
}

/// Todos los próximos partidos (no cancelados) en un solo archivo .ics.
Future<void> exportarProximos(BuildContext context, List<Partido> todos, Liga l) async {
  final proximos = todos
      .where((p) => p.fechaHora.isAfter(DateTime.now()) && p.estado != EstadoPartido.cancelado)
      .toList()
    ..sort((a, b) => a.fechaHora.compareTo(b.fechaHora));
  if (proximos.isEmpty) {
    mostrarError(context, 'No hay partidos programados');
    return;
  }
  await _compartirIcs(context, icsDePartidos(proximos, l), 'partidos.ics');
  if (context.mounted) mostrarOk(context, '${proximos.length} partidos listos para tu calendario');
}

/// Calendario suscrito: el móvil lo consulta solo cada pocas horas y recoge partidos nuevos, cambios de hora y cancelaciones.
Future<void> suscribirCalendario(BuildContext context, Liga l, List<Partido> todos) async {
  String url;
  try {
    final token = await sb.rpc('mi_calendario', params: {'p_liga': l.id}) as String;
    url = '${Env.supabaseUrl}/functions/v1/calendario?t=$token';
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
    return;
  }
  if (!context.mounted) return;
  final webcal = url.replaceFirst(RegExp('^https?://'), 'webcal://');
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Tx('Partidos en tu calendario'),
            subtitle: Tx('Suscríbete una vez y se actualiza solo: partidos nuevos, cambios de hora y cancelaciones.'),
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Tx('Google Calendar'),
            subtitle: const Tx('Android y web'),
            onTap: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('https://calendar.google.com/calendar/r?cid=${Uri.encodeComponent(webcal)}'),
                  mode: LaunchMode.externalApplication);
            },
          ),
          ListTile(
            leading: const Icon(Icons.phone_iphone),
            title: const Tx('iPhone, Mac u Outlook'),
            onTap: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(webcal), mode: LaunchMode.externalApplication);
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Tx('Copiar enlace'),
            subtitle: const Tx('Para otros calendarios: «Añadir calendario desde URL». Es personal, no lo compartas.'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              mostrarOk(context, 'Enlace copiado');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Tx('Solo descargar los próximos (.ics)'),
            subtitle: const Tx('No se actualiza si cambia algo'),
            onTap: () {
              Navigator.pop(ctx);
              exportarProximos(context, todos, l);
            },
          ),
        ]),
      ),
    ),
  );
}
