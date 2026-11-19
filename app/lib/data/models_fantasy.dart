// Modelos del mercado Fantasy (docs/mercado_fantasy.md §8).
// Los nombres de columna son el contrato con la migración 0008_mercado_fantasy.sql.

import 'package:intl/intl.dart';

import '../core/utils.dart';

final _m = NumberFormat('#,##0.00', 'es');

/// Moneda virtual del Fantasy: "3,75 M".
String millones(num? v) => v == null ? '—' : '${_m.format(v)} M';

/// Variación con signo: "+0,40 M" / "−0,25 M".
String variacionM(num? v) {
  if (v == null || v == 0) return '=';
  final s = _m.format(v.abs());
  return v > 0 ? '+$s M' : '−$s M';
}

/// Atributos de la encuesta inicial, en el orden en que se preguntan.
enum Atributo { calidad, velocidad, resistencia, defensa, regate, portero }

extension AtributoX on Atributo {
  String get etiqueta => switch (this) {
        Atributo.calidad => 'Calidad',
        Atributo.velocidad => 'Velocidad',
        Atributo.resistencia => 'Resistencia',
        Atributo.defensa => 'Defensa',
        Atributo.regate => 'Regate',
        Atributo.portero => 'Portería',
      };

  String get pregunta => switch (this) {
        Atributo.calidad => 'Ordena a los jugadores por calidad general',
        Atributo.velocidad => 'Ordena a los jugadores por velocidad',
        Atributo.resistencia => 'Ordena a los jugadores por resistencia física',
        Atributo.defensa => 'Ordena a los jugadores por cómo defienden',
        Atributo.regate => 'Ordena a los jugadores por regate',
        Atributo.portero => 'Ordena a los jugadores por cómo juegan de portero',
      };
}

String? _s(dynamic v) => v as String?;

/// Fila de `v_mercado`.
class JugadorMercado {
  JugadorMercado({
    required this.miembroId,
    required this.precio,
    this.variacion,
    this.rating,
    this.pctFichado,
    this.noHabitual = false,
  });

  final String miembroId;
  final double precio;

  /// Variación de precio en la última jornada (M).
  final double? variacion;
  final double? rating;

  /// % de plantillas de la liga que lo tienen (0–100).
  final double? pctFichado;
  final bool noHabitual;

  factory JugadorMercado.fromMap(Map<String, dynamic> m) => JugadorMercado(
        miembroId: (m['miembro_id'] ?? m['jugador_id']) as String,
        precio: toDouble(m['precio']) ?? 0,
        variacion: toDouble(m['variacion']),
        rating: toDouble(m['rating']),
        pctFichado: toDouble(m['pct_plantillas'] ?? m['pct_fichado']),
        noHabitual: (m['no_habitual'] ?? false) as bool,
      );
}

/// Fila de `valoracion_jugador` (resultado de la encuesta, 0–100).
class ValoracionJugador {
  ValoracionJugador({required this.miembroId, required this.atributos, this.general, this.numEvaluadores = 0});
  final String miembroId;
  final Map<Atributo, double?> atributos;
  final double? general;
  final int numEvaluadores;

  factory ValoracionJugador.fromMap(Map<String, dynamic> m) => ValoracionJugador(
        miembroId: m['miembro_id'] as String,
        atributos: {for (final a in Atributo.values) a: toDouble(m[a.name])},
        general: toDouble(m['general']),
        numEvaluadores: toInt(m['num_evaluadores']),
      );
}

/// Punto de `historial_precios`.
class PuntoPrecio {
  PuntoPrecio({required this.fecha, required this.precio, this.rating});
  final DateTime fecha;
  final double precio;
  final double? rating;

  factory PuntoPrecio.fromMap(Map<String, dynamic> m) => PuntoPrecio(
        fecha: DateTime.parse(m['creado_en'] as String),
        precio: toDouble(m['precio']) ?? 0,
        rating: toDouble(m['rating']),
      );
}

/// Fila de `fantasy_managers`.
class Manager {
  Manager({required this.miembroId, required this.saldo, required this.puntosTotales});
  final String miembroId;
  final double saldo, puntosTotales;

  factory Manager.fromMap(Map<String, dynamic> m) => Manager(
        miembroId: m['miembro_id'] as String,
        saldo: toDouble(m['saldo']) ?? 0,
        puntosTotales: toDouble(m['puntos_totales']) ?? 0,
      );
}

/// Fila de `v_mi_plantilla`: un jugador de mi plantilla con su precio actual.
class JugadorPlantilla {
  JugadorPlantilla({
    required this.jugadorId,
    required this.precioCompra,
    required this.precio,
    this.variacion,
    this.noHabitual = false,
    this.compradoEn,
  });
  final String jugadorId;
  final double precioCompra, precio;
  final double? variacion;
  final bool noHabitual;
  final DateTime? compradoEn;

  double get plusvalia => precio - precioCompra;

  factory JugadorPlantilla.fromMap(Map<String, dynamic> m) => JugadorPlantilla(
        jugadorId: m['jugador_id'] as String,
        precioCompra: toDouble(m['precio_compra']) ?? 0,
        // Si la vista no trae el precio actual, se usa el de compra.
        precio: toDouble(m['precio_actual'] ?? m['precio']) ?? toDouble(m['precio_compra']) ?? 0,
        variacion: toDouble(m['variacion']),
        noHabitual: (m['no_habitual'] ?? false) as bool,
        compradoEn: m['comprado_en'] == null ? null : DateTime.parse(m['comprado_en'] as String),
      );
}

/// Fila de `alineaciones`.
class Alineado {
  Alineado({required this.managerId, required this.jugadorId, this.noHabitual = false, this.multiplicador = 1});
  final String managerId, jugadorId;
  final bool noHabitual;
  final double multiplicador;

  factory Alineado.fromMap(Map<String, dynamic> m) => Alineado(
        managerId: m['manager_id'] as String,
        jugadorId: m['jugador_id'] as String,
        noHabitual: (m['no_habitual'] ?? false) as bool,
        multiplicador: toDouble(m['multiplicador']) ?? 1,
      );
}

/// Fila de `puntos_manager`.
class PuntosManager {
  PuntosManager({required this.partidoId, required this.managerId, required this.puntos, this.ingreso});
  final String partidoId, managerId;
  final double puntos;
  final double? ingreso;

  factory PuntosManager.fromMap(Map<String, dynamic> m) => PuntosManager(
        partidoId: m['partido_id'] as String,
        managerId: m['manager_id'] as String,
        puntos: toDouble(m['puntos']) ?? 0,
        ingreso: toDouble(m['ingreso']),
      );
}

/// Fila de `v_clasificacion_managers`.
class ClasManager {
  ClasManager({
    required this.managerId,
    required this.puntos,
    this.posicion,
    this.valorPlantilla,
    this.saldo,
    this.puntosUltima,
  });
  final String managerId;
  final double puntos;
  final int? posicion;
  final double? valorPlantilla, saldo, puntosUltima;

  factory ClasManager.fromMap(Map<String, dynamic> m) => ClasManager(
        managerId: (m['manager_id'] ?? m['miembro_id']) as String,
        puntos: toDouble(m['puntos_totales'] ?? m['puntos']) ?? 0,
        posicion: m['posicion'] == null ? null : toInt(m['posicion']),
        valorPlantilla: toDouble(m['valor_plantilla']),
        saldo: toDouble(m['saldo']),
        puntosUltima: toDouble(m['puntos_ultima_jornada']),
      );
}

/// Fila de `encuestas_valoracion`.
class Encuesta {
  Encuesta({required this.id, required this.ligaId, this.sujetoId, required this.abierta, this.creadaEn});
  final String id, ligaId;

  /// null = encuesta general; un miembro = mini-encuesta para colocar a un jugador nuevo.
  final String? sujetoId;
  final bool abierta;
  final DateTime? creadaEn;

  bool get esMini => sujetoId != null;

  factory Encuesta.fromMap(Map<String, dynamic> m) => Encuesta(
        id: m['id'] as String,
        ligaId: m['liga_id'] as String,
        sujetoId: _s(m['sujeto_id']),
        abierta: m['estado'] == 'abierta',
        creadaEn: m['creada_en'] == null ? null : DateTime.parse(m['creada_en'] as String),
      );
}
