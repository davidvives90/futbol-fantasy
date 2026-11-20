import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import 'supabase.dart';
import 'utils.dart';

/// Exporta la liga a un Excel con 4 hojas: Saldos, Caja (movimientos), Asistencia y Clasificación.
Future<void> exportarLigaExcel(BuildContext context, Liga liga) async {
  try {
    final d = Map<String, dynamic>.from(await sb.rpc('exportar_liga', params: {'p_liga': liga.id}) as Map);
    final excel = Excel.createExcel();
    excel.rename(excel.getDefaultSheet() ?? 'Sheet1', 'Saldos');

    CellValue texto(Object? v) => TextCellValue(v == null ? '' : '$v');
    CellValue numero(Object? v) => DoubleCellValue(v == null ? 0 : (v as num).toDouble());
    String fecha(Object? v) => v == null ? '' : fechaHora(DateTime.parse(v as String));

    final saldos = excel['Saldos'];
    saldos.appendRow([texto('Jugador'), texto('Cargado (€)'), texto('Pagado (€)'), texto('Saldo (€)')]);
    for (final s in (d['saldos'] as List? ?? const [])) {
      final m = s as Map;
      saldos.appendRow([texto(m['jugador']), numero(m['cargado']), numero(m['pagado']), numero(m['saldo'])]);
    }

    final caja = excel['Caja'];
    caja.appendRow([texto('Fecha'), texto('Jugador'), texto('Tipo'), texto('Importe (€)'), texto('Concepto'), texto('Partido')]);
    for (final x in (d['movimientos'] as List? ?? const [])) {
      final m = x as Map;
      caja.appendRow([texto(fecha(m['fecha'])), texto(m['jugador']), texto(m['tipo']), numero(m['importe']),
          texto(m['concepto']), texto(fecha(m['partido']))]);
    }

    final asis = excel['Asistencia'];
    final h = Map<String, dynamic>.from((d['asistencia'] as Map?) ?? const {});
    final nombres = Map<String, dynamic>.from((d['nombres'] as Map?) ?? const {});
    final partidos = [for (final p in (h['partidos'] as List? ?? const [])) (p as Map)['fecha']];
    asis.appendRow([texto('Jugador'), texto('% asistencia'), texto('Jugados'), for (final p in partidos) texto(fechaCorta(DateTime.parse(p as String)))]);
    const leyenda = {'J': 'Jugó', 'D': 'No', 'N': '—', 'B': 'Baja'};
    for (final x in (h['miembros'] as List? ?? const [])) {
      final m = x as Map;
      asis.appendRow([
        texto(nombres[m['miembro_id']]),
        m['pct'] == null ? texto('') : numero(m['pct']),
        numero(m['jugados']),
        for (final e in (m['estados'] as List)) texto(e == null ? '' : leyenda[e] ?? e),
      ]);
    }

    final clas = excel['Clasificación'];
    clas.appendRow([texto('Jugador'), texto('Partidos'), texto('Puntos'), texto('Media'), texto('Goles'), texto('Asistencias'),
        texto('MVPs'), texto('Nota media'), texto('Victorias'), texto('Empates'), texto('Derrotas'), texto('% victorias')]);
    for (final x in (d['clasificacion'] as List? ?? const [])) {
      final m = x as Map;
      clas.appendRow([texto(m['jugador']), numero(m['partidos']), numero(m['puntos_total']), numero(m['puntos_media']),
          numero(m['goles']), numero(m['asistencias']), numero(m['mvps']), m['nota_media'] == null ? texto('') : numero(m['nota_media']),
          numero(m['victorias']), numero(m['empates']), numero(m['derrotas']),
          m['pct_victorias'] == null ? texto('') : numero(m['pct_victorias'])]);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('No se pudo generar el Excel');
    final hoy = DateTime.now();
    final nombre = '${liga.nombre.replaceAll(RegExp(r'[^\w\- ]'), '')}_${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}.xlsx';
    await Share.shareXFiles([
      XFile.fromData(Uint8List.fromList(bytes),
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', name: nombre),
    ], fileNameOverrides: [nombre]);
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
  }
}
