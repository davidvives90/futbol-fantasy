// ignore_for_file: constant_identifier_names
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
    this.fichasTotales = 0,
    this.fichasLibres = 0,
    this.clausulaMinima,
    this.miFichaId,
  });

  final String miembroId;
  final double precio;

  /// Fichas del jugador (0.2): totales y libres en el mercado.
  final int fichasTotales, fichasLibres;

  /// Cláusula más barata que se puede pagar ahora (null si ninguna: protegidas, cedidas o sin dueño).
  final double? clausulaMinima;

  /// Mi ficha de este jugador, si la tengo.
  final String? miFichaId;

  bool get hayLibres => fichasLibres > 0;

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
        fichasTotales: toInt(m['fichas_totales']),
        fichasLibres: toInt(m['fichas_libres']),
        clausulaMinima: toDouble(m['clausula_minima']),
        miFichaId: _s(m['mi_ficha_id']),
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

/// Fila de `v_mi_plantilla`: una ficha mía (o la recibida en cesión esta jornada) con su precio actual.
class JugadorPlantilla {
  JugadorPlantilla({
    required this.jugadorId,
    required this.precio,
    this.fichaId,
    this.precioCompra,
    this.variacion,
    this.noHabitual = false,
    this.compradoEn,
    this.clausula,
    this.protegida = false,
    this.cedidaAMi = false,
    this.cedidaAOtro = false,
    this.cesionPartidoId,
    this.cesionEstado,
  });
  final String jugadorId;
  final String? fichaId;

  /// null en la ficha recibida en cesión (no es mía).
  final double? precioCompra;
  final double precio;
  final double? variacion;
  final bool noHabitual;
  final DateTime? compradoEn;

  /// Cláusula de rescisión (≥ precio de mercado). null en la cedida a mí.
  final double? clausula;

  /// No se puede clausular hasta que se cierre el siguiente partido.
  final bool protegida;

  /// Ficha de otro mánager que tengo cedida esta jornada (plaza extra, solo para alinear).
  final bool cedidaAMi;

  /// Ficha mía cedida a otro esta jornada: no puedo alinearla, venderla ni clausularla.
  final bool cedidaAOtro;
  final String? cesionPartidoId;

  /// 'ofrecida' | 'aceptada' | null.
  final String? cesionEstado;

  bool get propia => !cedidaAMi;
  bool get enCesionOfrecida => cesionEstado == 'ofrecida' && !cedidaAMi;
  bool get alineable => !cedidaAOtro;
  double get plusvalia => precio - (precioCompra ?? precio);

  factory JugadorPlantilla.fromMap(Map<String, dynamic> m) => JugadorPlantilla(
        jugadorId: m['jugador_id'] as String,
        fichaId: _s(m['ficha_id']),
        precioCompra: toDouble(m['precio_compra']),
        // Si la vista no trae el precio actual, se usa el de compra.
        precio: toDouble(m['precio_actual'] ?? m['precio']) ?? toDouble(m['precio_compra']) ?? 0,
        variacion: toDouble(m['variacion']),
        noHabitual: (m['no_habitual'] ?? false) as bool,
        compradoEn: m['comprado_en'] == null ? null : DateTime.parse(m['comprado_en'] as String),
        clausula: toDouble(m['clausula']),
        protegida: (m['protegida'] ?? false) as bool,
        cedidaAMi: (m['cedida_a_mi'] ?? false) as bool,
        cedidaAOtro: (m['cedida_a_otro'] ?? false) as bool,
        cesionPartidoId: _s(m['cesion_partido_id']),
        cesionEstado: _s(m['cesion_estado']),
      );
}

/// Rol en la alineación Fantasy (0.2). Exactamente un POR por alineación.
enum RolAlineacion { POR, DEF, MED, DEL }

extension RolAlineacionX on RolAlineacion {
  String get etiqueta => switch (this) {
        RolAlineacion.POR => 'Portero',
        RolAlineacion.DEF => 'Defensa',
        RolAlineacion.MED => 'Medio',
        RolAlineacion.DEL => 'Delantero',
      };

  static RolAlineacion desde(dynamic texto) =>
      RolAlineacion.values.where((r) => r.name == texto).firstOrNull ?? RolAlineacion.MED;
}

/// Fila de `alineaciones`.
class Alineado {
  Alineado({
    required this.managerId,
    required this.jugadorId,
    this.noHabitual = false,
    this.multiplicador = 1,
    this.rol = RolAlineacion.MED,
    this.bonusRol,
    this.capitan = false,
    this.ariete = false,
    this.suplente,
  });
  final String managerId, jugadorId;
  final bool noHabitual, capitan, ariete;

  /// 1 o 2 si es suplente (0054).
  final int? suplente;
  final double multiplicador;
  final RolAlineacion rol;
  final double? bonusRol;

  factory Alineado.fromMap(Map<String, dynamic> m) => Alineado(
        managerId: m['manager_id'] as String,
        jugadorId: m['jugador_id'] as String,
        noHabitual: (m['no_habitual'] ?? false) as bool,
        multiplicador: toDouble(m['multiplicador']) ?? 1,
        rol: RolAlineacionX.desde(m['rol']),
        bonusRol: toDouble(m['bonus_rol']),
        capitan: (m['capitan'] ?? false) as bool,
        ariete: (m['ariete'] ?? false) as bool,
        suplente: m['suplente'] == null ? null : toInt(m['suplente']),
      );
}

/// Un jugador alineado dentro de `puntos_manager.desglose`.
class LineaDesglose {
  LineaDesglose({
    required this.jugadorId,
    required this.puntos,
    required this.total,
    this.rol,
    this.bonusRol = 0,
    this.multiplicador = 1,
    this.jugo = true,
    this.cedido = false,
    this.capitan = false,
    this.ariete = false,
    this.suplente,
    this.entraPor,
    this.cuenta = true,
    this.rareza = 1,
    this.doble = false,
  });
  final String jugadorId;
  final double puntos, total, bonusRol, multiplicador, rareza;
  final RolAlineacion? rol;
  final bool jugo, cedido, capitan, ariete, cuenta, doble;
  final int? suplente;
  final String? entraPor;

  factory LineaDesglose.fromMap(Map<String, dynamic> m) => LineaDesglose(
        jugadorId: m['jugador_id'] as String,
        puntos: toDouble(m['puntos']) ?? 0,
        total: toDouble(m['total']) ?? 0,
        rol: m['rol'] == null ? null : RolAlineacionX.desde(m['rol']),
        bonusRol: toDouble(m['bonus_rol']) ?? 0,
        multiplicador: toDouble(m['multiplicador']) ?? 1,
        jugo: (m['jugo'] ?? true) as bool,
        cedido: (m['cedido'] ?? false) as bool,
        capitan: (m['capitan'] ?? false) as bool,
        ariete: (m['ariete'] ?? false) as bool,
        suplente: m['suplente'] == null ? null : toInt(m['suplente']),
        entraPor: m['entra_por'] as String?,
        cuenta: (m['cuenta'] ?? true) as bool,
        rareza: toDouble(m['rareza']) ?? 1,
        doble: (m['doble'] ?? false) as bool,
      );
}

/// Fila de `puntos_manager` (o de `v_jornada_managers`).
class PuntosManager {
  PuntosManager({
    required this.partidoId,
    required this.managerId,
    required this.puntos,
    this.ingreso,
    this.desglose = const [],
  });
  final String partidoId, managerId;
  final double puntos;
  final double? ingreso;
  final List<LineaDesglose> desglose;

  factory PuntosManager.fromMap(Map<String, dynamic> m) => PuntosManager(
        partidoId: m['partido_id'] as String,
        managerId: m['manager_id'] as String,
        puntos: toDouble(m['puntos']) ?? 0,
        ingreso: toDouble(m['ingreso']),
        desglose: [
          for (final e in (m['desglose'] as List? ?? const []))
            if (e is Map) LineaDesglose.fromMap(Map<String, dynamic>.from(e)),
        ],
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

// ---------------------------------------------------------------------------
// Ampliación 0.2: fichas, ofertas y cesiones (docs/contrato_app_backend.md)
// ---------------------------------------------------------------------------

/// Fila de `v_fichas_jugador`: cada ficha de un jugador, libre o con dueño.
class FichaJugador {
  FichaJugador({
    required this.fichaId,
    required this.jugadorId,
    required this.numero,
    this.propietarioId,
    this.propietarioNombre,
    this.clausula,
    this.protegida = false,
    this.cedida = false,
    this.esMia = false,
  });
  final String fichaId, jugadorId;
  final int numero;
  final String? propietarioId, propietarioNombre;
  final double? clausula;
  final bool protegida, cedida, esMia;

  bool get libre => propietarioId == null;

  /// Se puede pagar su cláusula ahora mismo (sin contar saldo ni hueco).
  bool get clausulable => !libre && !esMia && !protegida && !cedida;

  factory FichaJugador.fromMap(Map<String, dynamic> m) => FichaJugador(
        fichaId: m['ficha_id'] as String,
        jugadorId: m['jugador_id'] as String,
        numero: toInt(m['numero'], 1),
        propietarioId: _s(m['propietario_id']),
        propietarioNombre: _s(m['propietario_nombre']),
        clausula: toDouble(m['clausula']),
        protegida: (m['protegida'] ?? false) as bool,
        cedida: (m['cedida'] ?? false) as bool,
        esMia: (m['es_mia'] ?? false) as bool,
      );
}

enum EstadoOferta { pendiente, aceptada, rechazada, cancelada, caducada }

/// Fila de `v_mis_ofertas`.
class Oferta {
  Oferta({
    required this.id,
    required this.fichaId,
    required this.jugadorId,
    required this.recibida,
    required this.importe,
    required this.estado,
    this.jugadorNombre,
    this.compradorNombre,
    this.vendedorNombre,
    this.expiraEn,
    this.creadaEn,
    this.precioMercado,
    this.clausulaActual,
  });
  final String id, fichaId, jugadorId;
  final bool recibida;
  final double importe;
  final EstadoOferta estado;
  final String? jugadorNombre, compradorNombre, vendedorNombre;
  final DateTime? expiraEn, creadaEn;
  final double? precioMercado, clausulaActual;

  bool get pendiente => estado == EstadoOferta.pendiente && (expiraEn == null || expiraEn!.isAfter(DateTime.now()));

  factory Oferta.fromMap(Map<String, dynamic> m) => Oferta(
        id: m['oferta_id'] as String,
        fichaId: m['ficha_id'] as String,
        jugadorId: m['jugador_id'] as String,
        recibida: m['direccion'] == 'recibida',
        importe: toDouble(m['importe']) ?? 0,
        estado: EstadoOferta.values.where((e) => e.name == m['estado']).firstOrNull ?? EstadoOferta.pendiente,
        jugadorNombre: _s(m['jugador_nombre']),
        compradorNombre: _s(m['comprador_nombre']),
        vendedorNombre: _s(m['vendedor_nombre']),
        expiraEn: m['expira_en'] == null ? null : DateTime.parse(m['expira_en'] as String),
        creadaEn: m['creada_en'] == null ? null : DateTime.parse(m['creada_en'] as String),
        precioMercado: toDouble(m['precio_mercado']),
        clausulaActual: toDouble(m['clausula_actual']),
      );
}

/// Fila de `v_cesiones_disponibles`.
class CesionDisponible {
  CesionDisponible({
    required this.id,
    required this.fichaId,
    required this.jugadorId,
    required this.propietarioId,
    required this.pct,
    required this.importe,
    this.jugadorNombre,
    this.propietarioNombre,
    this.precioMercado,
    this.noHabitual = false,
    this.partidoId,
    this.fechaHora,
    this.cierre,
    this.esMia = false,
  });
  final String id, fichaId, jugadorId, propietarioId;

  /// Fracción 0–1.
  final double pct, importe;
  final String? jugadorNombre, propietarioNombre, partidoId;
  final double? precioMercado;
  final bool noHabitual, esMia;
  final DateTime? fechaHora, cierre;

  factory CesionDisponible.fromMap(Map<String, dynamic> m) => CesionDisponible(
        id: m['cesion_id'] as String,
        fichaId: m['ficha_id'] as String,
        jugadorId: m['jugador_id'] as String,
        propietarioId: m['propietario_id'] as String,
        pct: toDouble(m['pct']) ?? 0,
        importe: toDouble(m['importe']) ?? 0,
        jugadorNombre: _s(m['jugador_nombre']),
        propietarioNombre: _s(m['propietario_nombre']),
        precioMercado: toDouble(m['precio_mercado']),
        noHabitual: (m['no_habitual'] ?? false) as bool,
        partidoId: _s(m['partido_id']),
        fechaHora: m['fecha_hora'] == null ? null : DateTime.parse(m['fecha_hora'] as String),
        cierre: m['cierre'] == null ? null : DateTime.parse(m['cierre'] as String),
        esMia: (m['es_mia'] ?? false) as bool,
      );
}

/// "15 %" a partir de una fracción 0–1.
String pctTexto(double f) => '${(f * 100).toStringAsFixed(f * 100 % 1 == 0 ? 0 : 1).replaceAll('.', ',')} %';

// ---- Fase 2 (0054) ------------------------------------------------------------

/// Copia libre de un jugador con su precio y su multiplicador de puntos (rareza).
class CopiaLibre {
  CopiaLibre(this.fichaId, this.numero, this.precio, this.puntos);
  final String fichaId;
  final int numero;
  final double precio, puntos;

  factory CopiaLibre.fromMap(Map<String, dynamic> m) =>
      CopiaLibre(m['ficha_id'] as String, toInt(m['numero']), toDouble(m['precio']) ?? 0, toDouble(m['puntos']) ?? 1);

  /// «Única», «Titular» o «Base» en modo rareza.
  String get edicion => numero == 1 ? 'Única' : numero <= 3 ? 'Titular' : 'Base';
}

/// Subasta de una copia (abierta o ciega).
class Subasta {
  Subasta({
    required this.id,
    required this.jugadorId,
    required this.numero,
    required this.tipo,
    required this.precioSalida,
    required this.cierraEn,
    required this.estado,
    required this.numPujas,
    this.mejor,
    this.voyGanando,
    this.miPuja,
    this.ganadorId,
    this.importe,
    this.vendedorId,
    this.fichaId,
  });
  final String id, jugadorId, tipo, estado;
  /// 0059: subasta que lanza un mánager con su propio jugador (null = subasta de la liga).
  final String? vendedorId, fichaId;
  final int numero, numPujas;
  final double precioSalida;
  final double? mejor, miPuja, importe;
  final bool? voyGanando;
  final String? ganadorId;
  final DateTime cierraEn;

  bool get abierta => estado == 'abierta' && cierraEn.isAfter(DateTime.now());
  bool get ciega => tipo == 'ciega';

  /// Mínimo para pujar ahora (en la abierta hay que superar la mejor puja).
  double get minimo {
    if (ciega || mejor == null) return precioSalida;
    final paso = (mejor! * 0.02 * 100).round() / 100;
    return mejor! + (paso < 0.5 ? 0.5 : paso);
  }

  factory Subasta.fromMap(Map<String, dynamic> m) => Subasta(
        id: m['id'] as String,
        jugadorId: m['jugador_id'] as String,
        numero: toInt(m['numero']),
        tipo: m['tipo'] as String,
        precioSalida: toDouble(m['precio_salida']) ?? 0,
        cierraEn: DateTime.parse(m['cierra_en'] as String).toLocal(),
        estado: m['estado'] as String,
        numPujas: toInt(m['num_pujas']),
        mejor: toDouble(m['mejor']),
        voyGanando: m['voy_ganando'] as bool?,
        miPuja: toDouble(m['mi_puja']),
        ganadorId: m['ganador_id'] as String?,
        importe: toDouble(m['importe']),
        vendedorId: m['vendedor_id'] as String?,
        fichaId: m['ficha_id'] as String?,
      );
}

/// Estado del draft por turnos (orden en serpiente).
class EstadoDraft {
  EstadoDraft({
    required this.estado,
    required this.orden,
    required this.rondas,
    required this.pick,
    required this.total,
    required this.ronda,
    this.turno,
    this.picks = const [],
  });
  final String estado;
  final List<String> orden;
  final int rondas, pick, total, ronda;
  final String? turno;
  final List<({String managerId, String? jugadorId, double? importe})> picks;

  bool get enCurso => estado == 'en_curso';

  factory EstadoDraft.fromMap(Map<String, dynamic> m) => EstadoDraft(
        estado: m['estado'] as String,
        orden: [for (final x in (m['orden'] as List? ?? const [])) x as String],
        rondas: toInt(m['rondas']),
        pick: toInt(m['pick']),
        total: toInt(m['total']),
        ronda: toInt(m['ronda']),
        turno: m['turno'] as String?,
        picks: [
          for (final p in (m['picks'] as List? ?? const []))
            (
              managerId: (p as Map)['manager_id'] as String,
              jugadorId: p['jugador_id'] as String?,
              importe: toDouble(p['importe']),
            ),
        ],
      );
}

/// Qué pasa con el Fantasy al cerrar la temporada (0054).
const herenciasTemporada = <(String, String, String)>[
  ('ninguna', 'Seguir igual', 'Plantillas, dinero y precios continúan en la nueva temporada.'),
  ('reinicio', 'Reinicio total', 'Todos empiezan de cero: presupuesto inicial y precios iguales.'),
  ('valor', 'Heredar valor de mercado', 'Se vacían plantillas y dinero, pero cada jugador conserva su valor.'),
  ('bonus', 'Heredar bonus económico', 'Como «heredar valor» y cada mánager recibe el 10 % de su patrimonio final.'),
];

/// Modos de inicio del Fantasy (0054).
const modosInicioFantasy = <(String, String, String)>[
  ('reparto', 'Reparto equilibrado', 'Cada mánager recibe una alineación al azar de valor parecido, pagada de su presupuesto.'),
  ('mercado', 'Mercado libre', 'Todos empiezan sin jugadores y fichan en el mercado con su presupuesto.'),
  ('subasta', 'Subasta diaria', 'Sin jugadores. Cada día salen N copias a subasta: el precio lo ponen las pujas.'),
  ('draft', 'Draft por turnos', 'Sin jugadores. Antes del primer partido se eligen por turnos en serpiente.'),
];

