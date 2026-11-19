import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../models.dart';

/// Saldos, pagos y facturas.
class CajaRepo {
  static Future<List<Saldo>> saldos(String ligaId) async {
    final rows = await sb.from('v_saldos').select().eq('liga_id', ligaId);
    return [for (final r in rows) Saldo.fromMap(r)];
  }

  static Future<List<Movimiento>> movimientos(String miembroId) async {
    final rows =
        await sb.from('movimientos').select().eq('miembro_id', miembroId).order('fecha', ascending: false).limit(200);
    return [for (final r in rows) Movimiento.fromMap(r)];
  }

  /// Pago (importe > 0) o ajuste (con signo). Solo admins; los cargos los genera `marcar_jugado`.
  static Future<void> registrarMovimiento({
    required String miembroId,
    required String tipo, // 'pago' | 'ajuste'
    required double importe,
    String? concepto,
    String? partidoId,
  }) async {
    await sb.rpc('registrar_pago', params: {
      'p_miembro': miembroId,
      'p_importe': importe,
      'p_partido': partidoId,
      'p_concepto': concepto,
      'p_tipo': tipo,
    });
  }

  static Future<List<Factura>> facturas(String ligaId) async {
    final rows = await sb.from('facturas').select().eq('liga_id', ligaId).order('fecha', ascending: false);
    return [for (final r in rows) Factura.fromMap(r)];
  }

  /// Sube el archivo a Storage (`<liga_id>/<uuid>.<ext>`) y crea la fila.
  static Future<void> subirFactura({
    required String ligaId,
    required Uint8List bytes,
    required String extension,
    required String nombreArchivo,
    double? importe,
    String? notas,
    String? partidoId,
    DateTime? periodoDesde,
    DateTime? periodoHasta,
    required String subidaPor,
  }) async {
    final id = const Uuid().v4();
    final ext = extension.toLowerCase();
    final path = '$ligaId/$id.$ext';
    await sb.storage.from(Env.bucketFacturas).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _mime(ext), upsert: false),
        );
    await sb.from('facturas').insert({
      'id': id,
      'liga_id': ligaId,
      'partido_id': partidoId,
      'archivo_path': path,
      'nombre_archivo': nombreArchivo,
      'importe': importe,
      'notas': notas,
      'subida_por': subidaPor,
      if (periodoDesde != null) 'periodo_desde': fechaSql(periodoDesde),
      if (periodoHasta != null) 'periodo_hasta': fechaSql(periodoHasta),
    });
  }

  /// v0.3, modo factura mensual: cálculo sin escribir nada (para mostrar antes de confirmar).
  static Future<LiquidacionFactura> simularFactura(String facturaId) async {
    final r = await sb.rpc('simular_factura', params: {'p_factura': facturaId});
    return LiquidacionFactura.fromMap(Map<String, dynamic>.from(r as Map));
  }

  /// Genera los cargos a los fijos. Falla si la factura ya está liquidada.
  static Future<LiquidacionFactura> liquidarFactura(String facturaId) async {
    final r = await sb.rpc('liquidar_factura', params: {'p_factura': facturaId});
    return LiquidacionFactura.fromMap(Map<String, dynamic>.from(r as Map));
  }

  /// URL temporal (1 h) para ver una factura del bucket privado.
  static Future<String> urlFactura(String path) =>
      sb.storage.from(Env.bucketFacturas).createSignedUrl(path, 3600);

  static String _mime(String ext) => switch (ext) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        _ => 'application/octet-stream',
      };
}
