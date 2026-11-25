import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/idioma.dart';
import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';

/// Columnas de la plantilla oficial (en este orden).
const columnasHistorial = [
  'nombre_jugador', 'partidos_jugados', 'victorias', 'empates', 'derrotas',
  'goles', 'asistencias', 'mvps', 'valoracion_media',
];

/// Campos numéricos: (columna de la plantilla, clave del servidor, etiqueta corta).
const _numeros = [
  ('partidos_jugados', 'partidos', 'PJ'),
  ('victorias', 'victorias', 'V'),
  ('empates', 'empates', 'E'),
  ('derrotas', 'derrotas', 'D'),
  ('goles', 'goles', 'Goles'),
  ('asistencias', 'asistencias', 'Asist.'),
  ('mvps', 'mvps', 'MVP'),
  ('valoracion_media', 'valoracion_media', 'Nota'),
];

final _historialProvider = FutureProvider.autoDispose.family<Map<String, Map<String, dynamic>>, String>((ref, ligaId) async {
  final rows = await sb.from('historial_importado').select().eq('liga_id', ligaId);
  return {for (final r in rows) r['miembro_id'] as String: Map<String, dynamic>.from(r)};
});

/// Ajustes de la liga → Importar historial (0053): para grupos que ya llevaban estadísticas.
/// Archivo CSV/Excel con previsualización, o tabla editable. Los totales se suman a los de la app
/// (clasificación, equipos nivelados y logros).
class ImportarHistorialScreen extends ConsumerStatefulWidget {
  const ImportarHistorialScreen({super.key});

  @override
  ConsumerState<ImportarHistorialScreen> createState() => _ImportarHistorialScreenState();
}

class _ImportarHistorialScreenState extends ConsumerState<ImportarHistorialScreen> {
  List<Map<String, dynamic>>? _previa; // filas validadas por el servidor
  List<Map<String, dynamic>>? _enviar; // filas tal cual se enviarán
  bool _ocupado = false;

  // ---------------------------------------------------------------- plantilla

  Future<void> _plantilla() async {
    const ejemplo = 'Pepe García;40;22;6;12;31;9;5;7.5';
    final csv = '${columnasHistorial.join(';')}\n$ejemplo\n';
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]); // BOM: Excel lee bien las tildes
    try {
      await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'text/csv', name: 'plantilla_historial.csv')],
          fileNameOverrides: ['plantilla_historial.csv']);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  // ---------------------------------------------------------------- archivo

  static List<List<String>> _leerCsv(String texto) {
    final lineas = const LineSplitter().convert(texto.replaceFirst('﻿', '')).where((l) => l.trim().isNotEmpty).toList();
    if (lineas.isEmpty) return const [];
    final sep = lineas.first.split(';').length >= lineas.first.split(',').length ? ';' : ',';
    List<String> partir(String l) {
      final out = <String>[];
      final b = StringBuffer();
      var comillas = false;
      for (var i = 0; i < l.length; i++) {
        final c = l[i];
        if (c == '"') {
          if (comillas && i + 1 < l.length && l[i + 1] == '"') {
            b.write('"');
            i++;
          } else {
            comillas = !comillas;
          }
        } else if (c == sep && !comillas) {
          out.add(b.toString().trim());
          b.clear();
        } else {
          b.write(c);
        }
      }
      out.add(b.toString().trim());
      return out;
    }

    return [for (final l in lineas) partir(l)];
  }

  static List<List<String>> _leerExcel(Uint8List bytes) {
    final x = Excel.decodeBytes(bytes);
    final hoja = x.tables.values.firstOrNull;
    if (hoja == null) return const [];
    return [
      for (final fila in hoja.rows)
        [for (final c in fila) c?.value == null ? '' : '${c!.value}'.trim()],
    ].where((f) => f.any((c) => c.isNotEmpty)).toList();
  }

  /// Convierte las filas del archivo al formato del servidor. Acepta las columnas en cualquier orden.
  static List<Map<String, dynamic>> _aFilas(List<List<String>> tabla) {
    if (tabla.isEmpty) return const [];
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z_]'), '');
    final cab = [for (final c in tabla.first) norm(c)];
    final conCabecera = cab.contains('nombre_jugador') || cab.contains('nombre');
    final indices = conCabecera
        ? {for (final (i, c) in cab.indexed) (c == 'nombre' ? 'nombre_jugador' : c): i}
        : {for (final (i, c) in columnasHistorial.indexed) c: i};
    final datos = conCabecera ? tabla.skip(1) : tabla;
    num? n(String? v) {
      if (v == null || v.trim().isEmpty) return null;
      return num.tryParse(v.trim().replaceAll(',', '.'));
    }

    String? celda(List<String> f, String col) {
      final i = indices[col];
      return i == null || i >= f.length ? null : f[i];
    }

    return [
      for (final f in datos)
        if ((celda(f, 'nombre_jugador') ?? '').isNotEmpty)
          {
            'nombre': celda(f, 'nombre_jugador'),
            for (final (col, clave, _) in _numeros)
              clave: col == 'valoracion_media' ? n(celda(f, col)) : (n(celda(f, col)) ?? 0).round(),
          },
    ];
  }

  Future<void> _subirArchivo(String ligaId) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'xlsx'],
      withData: true,
    );
    final f = res?.files.single;
    if (f == null || f.bytes == null || !mounted) return;
    try {
      final tabla = f.name.toLowerCase().endsWith('.xlsx')
          ? _leerExcel(f.bytes!)
          : _leerCsv(utf8.decode(f.bytes!, allowMalformed: true));
      final filas = _aFilas(tabla);
      if (filas.isEmpty) throw tr('El archivo no tiene filas con nombre de jugador');
      await _previsualizar(ligaId, filas);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _previsualizar(String ligaId, List<Map<String, dynamic>> filas) async {
    setState(() => _ocupado = true);
    try {
      final r = await sb.rpc('previsualizar_historial', params: {'p_liga': ligaId, 'p_filas': filas});
      setState(() {
        _previa = [for (final x in r as List) Map<String, dynamic>.from(x as Map)];
        _enviar = filas;
      });
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _confirmar(String ligaId) async {
    final filas = _enviar;
    if (filas == null) return;
    setState(() => _ocupado = true);
    Map<String, dynamic>? r;
    final ok = await ejecutar(context, () async {
      r = Map<String, dynamic>.from(await sb.rpc('importar_historial', params: {'p_liga': ligaId, 'p_filas': filas}) as Map);
    });
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (ok && r != null) {
      ref.invalidate(_historialProvider(ligaId));
      ref.invalidate(miembrosProvider(ligaId));
      setState(() {
        _previa = null;
        _enviar = null;
      });
      mostrarOk(context, trf('Importados {n} jugadores ({x} nuevos, con enlace para reclamar su ficha)',
          {'n': r!['guardados'], 'x': r!['nuevos']}));
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final previa = _previa;
    final errores = previa?.where((x) => x['error'] != null).length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Tx('Importar historial')),
      body: _ocupado
          ? const Cargando()
          : previa != null
              ? Column(children: [
                  Expanded(
                    child: ListView(padding: const EdgeInsets.all(16), children: [
                      Tx('Revisa antes de guardar', style: t.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                          trf('{n} filas · {e} con errores · {x} jugadores nuevos', {
                            'n': previa.length,
                            'e': errores,
                            'x': previa.where((x) => x['nuevo'] == true && x['error'] == null).length,
                          }),
                          style: t.bodySmall),
                      const SizedBox(height: 8),
                      for (final x in previa)
                        Card(
                          color: x['error'] != null ? cs.errorContainer : null,
                          child: ListTile(
                            leading: Icon(
                              x['error'] != null
                                  ? Icons.error_outline
                                  : x['nuevo'] == true
                                      ? Icons.person_add_alt_outlined
                                      : Icons.link,
                            ),
                            title: Text('${x['nombre'] ?? '?'}'),
                            subtitle: Text(x['error'] != null
                                ? tr(x['error'] as String)
                                : '${x['nuevo'] == true ? tr('Nuevo: se crea sin cuenta para que lo reclame') : tr('Coincide con un jugador de la liga')}\n'
                                    '${x['partidos']} PJ · ${x['victorias']}V ${x['empates']}E ${x['derrotas']}D · '
                                    '⚽ ${x['goles']} · 🅰️ ${x['asistencias']} · MVP ${x['mvps']}'
                                    '${x['valoracion_media'] == null ? '' : ' · nota ${x['valoracion_media']}'}'),
                            isThreeLine: x['error'] == null,
                          ),
                        ),
                    ]),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        TextButton(onPressed: () => setState(() => _previa = null), child: const Tx('Cancelar')),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: errores > 0 ? null : () => _confirmar(mi.liga.id),
                            icon: const Icon(Icons.check),
                            label: Text(errores > 0 ? tr('Corrige los errores del archivo') : tr('Confirmar importación')),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ])
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Tx('¿Traéis estadísticas de antes?', style: t.titleMedium),
                        const SizedBox(height: 6),
                        const Tx('Importa los totales de cada jugador (partidos, resultados, goles, asistencias, MVPs y '
                            'nota media). Se suman a los de la app: clasificación, equipos nivelados y logros. '
                            'Los nombres que no existan se crean como jugadores sin cuenta, con su enlace para reclamarlos.'),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Tx('1. Descargar la plantilla CSV'),
                    subtitle: Text(columnasHistorial.join(', ')),
                    onTap: _plantilla,
                  ),
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Tx('2. Subir el archivo (CSV o Excel)'),
                    subtitle: const Tx('Verás una previsualización antes de guardar'),
                    onTap: () => _subirArchivo(mi.liga.id),
                  ),
                  const Divider(height: 32),
                  if (mi.liga.fantasyActivo)
                    ListTile(
                      leading: const Icon(Icons.trending_up),
                      title: const Tx('Valor de mercado según el historial'),
                      subtitle: const Tx('Los jugadores con historial empiezan con un valor acorde a sus puntos por partido'),
                      onTap: () => ejecutar(context, () => FantasyRepo.valorarPorHistorial(mi.liga.id),
                          ok: tr('Valores actualizados')),
                    ),
                  ListTile(
                    leading: const Icon(Icons.table_chart_outlined),
                    title: const Tx('O rellenar a mano en una tabla'),
                    subtitle: const Tx('Totales por jugador, como en una hoja de cálculo'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _TablaHistorial())),
                  ),
                ]),
    );
  }
}

/// Carga manual: una fila por jugador de la liga con sus totales importados.
class _TablaHistorial extends ConsumerStatefulWidget {
  const _TablaHistorial();

  @override
  ConsumerState<_TablaHistorial> createState() => _TablaHistorialState();
}

class _TablaHistorialState extends ConsumerState<_TablaHistorial> {
  final _c = <String, Map<String, TextEditingController>>{};
  final _nuevos = <TextEditingController>[];
  bool _guardando = false;

  TextEditingController _ctrl(String fila, String clave, Object? valor) =>
      _c.putIfAbsent(fila, () => {}).putIfAbsent(clave, () => TextEditingController(text: valor == null ? '' : '$valor'));

  @override
  void dispose() {
    for (final m in _c.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    for (final c in _nuevos) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _fila(String id) {
    final m = _c[id] ?? const {};
    num? n(String k) => num.tryParse((m[k]?.text ?? '').trim().replaceAll(',', '.'));
    return {
      for (final (_, clave, _) in _numeros)
        clave: clave == 'valoracion_media' ? n(clave) : (n(clave) ?? 0).round(),
    };
  }

  Future<void> _guardar(String ligaId, List<Miembro> miembros) async {
    final filas = <Map<String, dynamic>>[
      for (final m in miembros)
        if (_c[m.id]?.values.any((c) => c.text.trim().isNotEmpty) ?? false) {'miembro_id': m.id, ..._fila(m.id)},
      for (final (i, c) in _nuevos.indexed)
        if (c.text.trim().isNotEmpty) {'nombre': c.text.trim(), ..._fila('nuevo$i')},
    ];
    if (filas.isEmpty) return;
    setState(() => _guardando = true);
    final ok = await ejecutar(context, () => sb.rpc('importar_historial', params: {'p_liga': ligaId, 'p_filas': filas}),
        ok: tr('Historial guardado'));
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      ref.invalidate(_historialProvider(ligaId));
      ref.invalidate(miembrosProvider(ligaId));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final hist = ref.watch(_historialProvider(mi.liga.id));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id)).values
        .where((m) => m.estado != EstadoMiembro.expulsado && m.estado != EstadoMiembro.rechazado)
        .toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
    final t = Theme.of(context).textTheme;

    Widget celda(String fila, String clave, Object? valor) => SizedBox(
          width: clave == 'valoracion_media' ? 56 : 48,
          child: TextField(
            controller: _ctrl(fila, clave, valor),
            keyboardType: TextInputType.numberWithOptions(decimal: clave == 'valoracion_media'),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(clave == 'valoracion_media' ? r'[0-9.,]' : r'[0-9]'))],
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.all(6)),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Tx('Historial a mano'),
        actions: [
          IconButton(
            tooltip: tr('Añadir jugador que no está en la liga'),
            icon: const Icon(Icons.person_add_alt_outlined),
            onPressed: () => setState(() => _nuevos.add(TextEditingController())),
          ),
        ],
      ),
      body: hist.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(_historialProvider(mi.liga.id))),
        data: (h) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Tx('Deja en blanco a quien no tenga historial. Nota media del 1 al 10.', style: t.bodySmall),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 6,
                  horizontalMargin: 8,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 52,
                  columns: [
                    DataColumn(label: Tx('Jugador', style: t.labelMedium)),
                    for (final (_, _, etiqueta) in _numeros) DataColumn(label: Text(etiqueta, style: t.labelMedium)),
                  ],
                  rows: [
                    for (final m in miembros)
                      DataRow(cells: [
                        DataCell(SizedBox(width: 110, child: Text(m.nombre, overflow: TextOverflow.ellipsis))),
                        for (final (_, clave, _) in _numeros) DataCell(celda(m.id, clave, h[m.id]?[clave])),
                      ]),
                    for (final (i, c) in _nuevos.indexed)
                      DataRow(cells: [
                        DataCell(SizedBox(
                          width: 110,
                          child: TextField(
                            controller: c,
                            decoration: InputDecoration(isDense: true, hintText: tr('Nombre')),
                          ),
                        )),
                        for (final (_, clave, _) in _numeros) DataCell(celda('nuevo$i', clave, null)),
                      ]),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : () => _guardar(mi.liga.id, miembros),
                  icon: const Icon(Icons.save_outlined),
                  label: const Tx('Guardar historial'),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
