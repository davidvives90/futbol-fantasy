import '../../core/supabase.dart';
import '../../core/utils.dart';

/// Un pronóstico del boleto: mercado '1x2' | 'goleador' | 'no_goleador' | 'mvp' y la selección ('1', 'X', '2' o el id del jugador).
class Pronostico {
  const Pronostico(this.mercado, this.seleccion, this.cuota, {this.acierto});
  final String mercado, seleccion;
  final double cuota;
  final bool? acierto;

  factory Pronostico.fromMap(Map<String, dynamic> m) => Pronostico(
        m['mercado'] as String,
        m['seleccion'] as String,
        toDouble(m['cuota']) ?? 1,
        acierto: m['acierto'] as bool?,
      );

  String get clave => '$mercado/$seleccion';
  Map<String, dynamic> toMap() => {'mercado': mercado, 'seleccion': seleccion};
}

class Boleto {
  Boleto({
    required this.id,
    required this.miembroId,
    required this.tipo,
    required this.importe,
    required this.seguro,
    required this.estado,
    required this.selecciones,
    this.cuotaTotal,
    this.retorno,
  });
  final String id, miembroId, tipo, estado;
  final double importe;
  final double? cuotaTotal, retorno;
  final bool seguro;
  final List<Pronostico> selecciones;

  factory Boleto.fromMap(Map<String, dynamic> m) => Boleto(
        id: m['id'] as String,
        miembroId: m['miembro_id'] as String,
        tipo: m['tipo'] as String,
        importe: toDouble(m['importe']) ?? 0,
        seguro: (m['seguro'] ?? false) as bool,
        estado: m['estado'] as String,
        cuotaTotal: toDouble(m['cuota_total']),
        retorno: toDouble(m['retorno']),
        selecciones: [
          for (final x in (m['selecciones'] as List? ?? const [])) Pronostico.fromMap(Map<String, dynamic>.from(x as Map)),
        ],
      );
}

class EstadoPorra {
  EstadoPorra({
    required this.abierta,
    required this.modo,
    required this.tope,
    required this.apostado,
    required this.cuotas,
    required this.mias,
    required this.todas,
    this.saldo,
    this.maxGanancia,
  });
  final bool abierta;
  final String modo;
  final double tope, apostado;
  /// 0057: lo máximo que se puede ganar con un boleto (10 M o 100 pts).
  final double? maxGanancia;
  final double? saldo;
  final List<Pronostico> cuotas;
  final List<Boleto> mias, todas;

  bool get conDinero => modo == 'dinero';
  double get disponible => tope - apostado;

  factory EstadoPorra.fromMap(Map<String, dynamic> m) => EstadoPorra(
        abierta: (m['abierta'] ?? false) as bool,
        modo: (m['modo'] ?? 'puntos') as String,
        tope: toDouble(m['tope']) ?? 100,
        apostado: toDouble(m['apostado']) ?? 0,
        saldo: toDouble(m['saldo']),
        maxGanancia: toDouble(m['max_ganancia']),
        cuotas: [for (final x in (m['cuotas'] as List? ?? const [])) Pronostico.fromMap(Map<String, dynamic>.from(x as Map))],
        mias: [for (final x in (m['mias'] as List? ?? const [])) Boleto.fromMap(Map<String, dynamic>.from(x as Map))],
        todas: [for (final x in (m['todas'] as List? ?? const [])) Boleto.fromMap(Map<String, dynamic>.from(x as Map))],
      );
}

/// Retorno de un boleto si aciertan los pronósticos marcados (mismo cálculo que el servidor, 0055).
double retornoBoleto(String tipo, double importe, bool seguro, List<(double, bool)> sel, {double? maxGanancia}) {
  var bruto = 0.0;
  if (tipo == 'multiple') {
    final n = sel.length;
    final pares = n * (n - 1) / 2;
    for (var i = 0; i < n - 1; i++) {
      for (var j = i + 1; j < n; j++) {
        if (sel[i].$2 && sel[j].$2) bruto += importe / pares * sel[i].$1 * sel[j].$1;
      }
    }
  } else {
    final ok = sel.every((s) => s.$2);
    bruto = ok ? sel.fold<double>(importe, (a, s) => a * s.$1) : 0;
  }
  if (seguro) bruto = bruto >= importe ? importe + (bruto - importe) * 0.70 : (bruto > importe * 0.5 ? bruto : importe * 0.5);
  if (maxGanancia != null && bruto > importe + maxGanancia) bruto = importe + maxGanancia;
  return (bruto * 100).round() / 100;
}

class PorraRepo {
  static Future<EstadoPorra> estado(String partidoId) async =>
      EstadoPorra.fromMap(Map<String, dynamic>.from(await sb.rpc('porra_partido', params: {'p_partido': partidoId}) as Map));

  static Future<void> apostar(String partidoId, String tipo, List<Pronostico> sel, double importe, bool seguro) =>
      sb.rpc('apostar', params: {
        'p_partido': partidoId,
        'p_tipo': tipo,
        'p_selecciones': [for (final s in sel) s.toMap()],
        'p_importe': importe,
        'p_seguro': seguro,
      });

  static Future<void> cancelar(String apuestaId) => sb.rpc('cancelar_apuesta', params: {'p_apuesta': apuestaId});

  static Future<List<Map<String, dynamic>>> ranking(String ligaId) async {
    final r = await sb.rpc('ranking_porra', params: {'p_liga': ligaId});
    return [for (final x in (r as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
  }
}
