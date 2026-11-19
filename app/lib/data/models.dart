// Los valores de los enums coinciden con los de Postgres (snake_case).
// ignore_for_file: constant_identifier_names

import '../core/utils.dart';

// ---------------------------------------------------------------------------
// Enumeraciones (se guardan como texto en Postgres)
// ---------------------------------------------------------------------------

enum EstadoInscripcion { confirmado, duda, baja, espera }

enum EstadoPartido { abierto, completo, equipos_hechos, jugado, post_partido, en_revision, cerrado, cancelado }

enum RolLiga { admin, jugador }

enum EstadoMiembro { pendiente_registro, solicitud, activo, expulsado, abandonado, rechazado }

T _enum<T extends Enum>(List<T> valores, dynamic texto, T defecto) =>
    valores.where((v) => v.name == texto).firstOrNull ?? defecto;

extension EstadoPartidoX on EstadoPartido {
  String get etiqueta => switch (this) {
        EstadoPartido.abierto => 'Convocatoria abierta',
        EstadoPartido.completo => 'Completo',
        EstadoPartido.equipos_hechos => 'Equipos hechos',
        EstadoPartido.jugado => 'Jugado',
        EstadoPartido.post_partido => 'Post-partido',
        EstadoPartido.en_revision => 'En revisión',
        EstadoPartido.cerrado => 'Cerrado',
        EstadoPartido.cancelado => 'Cancelado',
      };

  bool get antesDeJugar =>
      this == EstadoPartido.abierto || this == EstadoPartido.completo || this == EstadoPartido.equipos_hechos;
}

const posiciones = ['portero', 'defensa', 'medio', 'delantero'];

/// Posición preferida del jugador: solo informativa (desde 0.2 los puntos no dependen de ella).
String etiquetaPosicion(String? p) => switch (p) {
      'portero' => 'Portero',
      'defensa' => 'Defensa',
      'medio' => 'Centrocampista',
      'delantero' => 'Delantero',
      _ => 'Sin posición',
    };

// ---------------------------------------------------------------------------
// Entidades
// ---------------------------------------------------------------------------

class Perfil {
  Perfil({required this.id, required this.nombre, this.apodo, this.avatarUrl, this.posicion, this.telefono});
  final String id;
  final String nombre;
  final String? apodo, avatarUrl, posicion, telefono;

  factory Perfil.fromMap(Map<String, dynamic> m) => Perfil(
        id: m['id'] as String,
        nombre: (m['nombre'] ?? '') as String,
        apodo: m['apodo'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        posicion: m['posicion'] as String?,
        telefono: m['telefono'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'apodo': apodo,
        'avatar_url': avatarUrl,
        'posicion': posicion,
        'telefono': telefono,
      };
}

class Liga {
  Liga({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.ciudad,
    this.campoNombre,
    this.campoMapsUrl,
    this.precioEstimado,
    required this.jugadoresPorEquipo,
    required this.numEquipos,
    required this.plazas,
    required this.publica,
    required this.requiereAprobacion,
    required this.puntuarPorPosicion,
    required this.codigoInvitacion,
    this.fantasy = const ParamsFantasy(),
  });

  final String id, nombre, codigoInvitacion;

  /// Parámetros del mercado Fantasy (columnas de `ligas`, ver docs/mercado_fantasy.md §2).
  final ParamsFantasy fantasy;
  final String? descripcion, ciudad, campoNombre, campoMapsUrl;
  final double? precioEstimado;
  final int jugadoresPorEquipo, numEquipos, plazas;
  final bool publica, requiereAprobacion, puntuarPorPosicion;

  String get formato => 'Fútbol $jugadoresPorEquipo · $numEquipos equipos';

  factory Liga.fromMap(Map<String, dynamic> m) {
    final jpe = toInt(m['jugadores_por_equipo'], 5);
    final ne = toInt(m['num_equipos'], 2);
    return Liga(
      id: m['id'] as String,
      nombre: m['nombre'] as String,
      descripcion: m['descripcion'] as String?,
      ciudad: m['ciudad'] as String?,
      campoNombre: m['campo_nombre'] as String?,
      campoMapsUrl: m['campo_maps_url'] as String?,
      precioEstimado: toDouble(m['precio_estimado']),
      jugadoresPorEquipo: jpe,
      numEquipos: ne,
      plazas: toInt(m['plazas'], jpe * ne),
      publica: m['visibilidad'] == 'publica',
      requiereAprobacion: (m['requiere_aprobacion'] ?? true) as bool,
      puntuarPorPosicion: (m['puntuar_por_posicion'] ?? false) as bool,
      codigoInvitacion: (m['codigo_invitacion'] ?? '') as String,
      fantasy: ParamsFantasy.fromMap(m),
    );
  }
}

/// Parámetros del mercado Fantasy de una liga. Los valores por defecto son los de la especificación.
class ParamsFantasy {
  const ParamsFantasy({
    this.precioMin = 1,
    this.precioMax = 12,
    this.maxPlantilla = 6,
    this.bonusNoHabitual = 1.5,
    this.horasCierreAlineacion = 2,
    this.ingresoPorPunto = 0.10,
    this.comisionVenta = 0.05,
    this.kEncuesta = 5,
    this.maxVariacion = 0.15,
    this.bonusRoles = true,
    this.copiasPorJugador = 2,
    this.costeSubidaClausula = 0.10,
    this.proteccionJornadas = 1,
    this.cesionPctMin = 0.05,
    this.cesionPctMax = 0.30,
    this.horasCaducidadOferta = 48,
    this.partidosMinRendimiento = 3,
  });

  final double precioMin, precioMax, bonusNoHabitual, horasCierreAlineacion, ingresoPorPunto, comisionVenta;
  final double kEncuesta, maxVariacion;
  final int maxPlantilla;

  // ---- Ampliación 0.2 (migraciones 0010–0014) ----
  /// Si el rol en la alineación (POR/DEF/MED/DEL) da bonus; si no, es solo estético.
  final bool bonusRoles;

  /// Fichas de cada jugador (las calcula el backend; solo lectura).
  final int copiasPorJugador;

  /// Fracción de la subida de cláusula que se paga al subirla (0,10 = 10 %).
  final double costeSubidaClausula;
  final int proteccionJornadas;

  /// % de cesión permitido, como fracción 0–1.
  final double cesionPctMin, cesionPctMax;
  final int horasCaducidadOferta, partidosMinRendimiento;

  /// Coste de subir una cláusula de [actual] a [nueva] (bajarla es gratis).
  double costeSubida(double actual, double nueva) => nueva > actual ? (nueva - actual) * costeSubidaClausula : 0;

  /// Momento en que se cierra la alineación (y el mercado) para un partido.
  DateTime cierre(DateTime fechaHoraPartido) =>
      fechaHoraPartido.subtract(Duration(minutes: (horasCierreAlineacion * 60).round()));

  /// Lo que se recibe al vender a [precio].
  double precioVenta(double precio) => precio * (1 - comisionVenta);

  factory ParamsFantasy.fromMap(Map<String, dynamic> m) => ParamsFantasy(
        precioMin: toDouble(m['precio_min']) ?? 1,
        precioMax: toDouble(m['precio_max']) ?? 12,
        maxPlantilla: toInt(m['max_plantilla'], 6),
        bonusNoHabitual: toDouble(m['bonus_no_habitual']) ?? 1.5,
        horasCierreAlineacion: toDouble(m['horas_cierre_alineacion']) ?? 2,
        ingresoPorPunto: toDouble(m['ingreso_por_punto']) ?? 0.10,
        comisionVenta: toDouble(m['comision_venta']) ?? 0.05,
        kEncuesta: toDouble(m['k_encuesta']) ?? 5,
        maxVariacion: toDouble(m['max_variacion']) ?? 0.15,
        bonusRoles: (m['bonus_roles'] ?? true) as bool,
        copiasPorJugador: toInt(m['copias_por_jugador'], 2),
        costeSubidaClausula: toDouble(m['coste_subida_clausula']) ?? 0.10,
        proteccionJornadas: toInt(m['proteccion_jornadas'], 1),
        cesionPctMin: toDouble(m['cesion_pct_min']) ?? 0.05,
        cesionPctMax: toDouble(m['cesion_pct_max']) ?? 0.30,
        horasCaducidadOferta: toInt(m['horas_caducidad_oferta'], 48),
        partidosMinRendimiento: toInt(m['partidos_min_rendimiento'], 3),
      );

  Map<String, dynamic> toMap() => {
        'precio_min': precioMin,
        'precio_max': precioMax,
        'max_plantilla': maxPlantilla,
        'bonus_no_habitual': bonusNoHabitual,
        'horas_cierre_alineacion': horasCierreAlineacion,
        'ingreso_por_punto': ingresoPorPunto,
        'comision_venta': comisionVenta,
        'bonus_roles': bonusRoles,
        'coste_subida_clausula': costeSubidaClausula,
        'proteccion_jornadas': proteccionJornadas,
        'cesion_pct_min': cesionPctMin,
        'cesion_pct_max': cesionPctMax,
        'horas_caducidad_oferta': horasCaducidadOferta,
        'partidos_min_rendimiento': partidosMinRendimiento,
      };
}

class Miembro {
  Miembro({
    required this.id,
    required this.ligaId,
    this.perfilId,
    this.nombreProvisional,
    this.posicionLiga,
    required this.rol,
    required this.estado,
    this.perfil,
  });

  final String id, ligaId;
  final String? perfilId, nombreProvisional;

  /// Posición propia en esta liga (si es nula se usa la del perfil), como `posicion_de()` en SQL.
  final String? posicionLiga;
  final RolLiga rol;
  final EstadoMiembro estado;
  final Perfil? perfil;

  bool get esAdmin => rol == RolLiga.admin;
  bool get registrado => perfilId != null;
  String? get posicion => posicionLiga ?? perfil?.posicion;
  bool get esPortero => posicion == 'portero';

  String get nombre {
    final p = perfil;
    if (p != null) return (p.apodo?.isNotEmpty ?? false) ? p.apodo! : p.nombre;
    return nombreProvisional ?? '—';
  }

  String get inicial => nombre.isEmpty ? '?' : String.fromCharCode(nombre.runes.first).toUpperCase();

  /// Select con el perfil embebido (FK miembros.perfil_id → perfiles.id).
  /// Columnas explícitas: `token_invitacion` y `contacto` no son legibles (ver `enlaces_invitacion`).
  static const select = 'id, liga_id, perfil_id, nombre_provisional, posicion, rol, estado, invitado_por, unido_en, '
      'perfil:perfiles(id, nombre, apodo, avatar_url, posicion, telefono)';

  factory Miembro.fromMap(Map<String, dynamic> m) => Miembro(
        id: m['id'] as String,
        ligaId: m['liga_id'] as String,
        perfilId: m['perfil_id'] as String?,
        nombreProvisional: m['nombre_provisional'] as String?,
        posicionLiga: m['posicion'] as String?,
        rol: _enum(RolLiga.values, m['rol'], RolLiga.jugador),
        estado: _enum(EstadoMiembro.values, m['estado'], EstadoMiembro.activo),
        perfil: m['perfil'] == null ? null : Perfil.fromMap(m['perfil'] as Map<String, dynamic>),
      );
}

/// Liga a la que pertenece el usuario + su ficha de miembro en ella.
class MiLiga {
  MiLiga(this.liga, this.yo);
  final Liga liga;
  final Miembro yo;
  bool get soyAdmin => yo.esAdmin;
}

class Partido {
  Partido({
    required this.id,
    required this.ligaId,
    required this.fechaHora,
    required this.horaConfirmada,
    this.campoMapsUrl,
    required this.plazas,
    required this.numEquipos,
    required this.costeTotal,
    required this.estado,
    this.votacionCierra,
  });

  final String id, ligaId;
  final DateTime fechaHora;
  final bool horaConfirmada;
  final String? campoMapsUrl;
  final int plazas, numEquipos;
  final double costeTotal;
  final EstadoPartido estado;
  final DateTime? votacionCierra;

  factory Partido.fromMap(Map<String, dynamic> m) => Partido(
        id: m['id'] as String,
        ligaId: m['liga_id'] as String,
        fechaHora: DateTime.parse(m['fecha_hora'] as String),
        horaConfirmada: (m['hora_confirmada'] ?? false) as bool,
        campoMapsUrl: m['campo_maps_url'] as String?,
        plazas: toInt(m['plazas'], 10),
        numEquipos: toInt(m['num_equipos'], 2),
        costeTotal: toDouble(m['coste_total']) ?? 0,
        estado: _enum(EstadoPartido.values, m['estado'], EstadoPartido.abierto),
        votacionCierra: m['votacion_cierra'] == null ? null : DateTime.parse(m['votacion_cierra'] as String),
      );
}

class Inscripcion {
  Inscripcion({required this.miembroId, required this.estado, required this.inscritoEn, this.equipo});
  final String miembroId;
  final EstadoInscripcion estado;
  final DateTime inscritoEn;
  final int? equipo;

  factory Inscripcion.fromMap(Map<String, dynamic> m) => Inscripcion(
        miembroId: m['miembro_id'] as String,
        estado: _enum(EstadoInscripcion.values, m['estado'], EstadoInscripcion.duda),
        inscritoEn: DateTime.parse(m['inscrito_en'] as String),
        equipo: m['equipo'] == null ? null : toInt(m['equipo']),
      );
}

class Encuentro {
  Encuentro({
    required this.n,
    required this.equipoLocal,
    required this.equipoVisitante,
    required this.golesLocal,
    required this.golesVisitante,
    this.confianza,
    this.enDisputa = false,
  });
  final int n, equipoLocal, equipoVisitante, golesLocal, golesVisitante;
  final double? confianza;
  final bool enDisputa;

  factory Encuentro.fromMap(Map<String, dynamic> m) => Encuentro(
        n: toInt(m['n'], 1),
        equipoLocal: toInt(m['equipo_local'], 1),
        equipoVisitante: toInt(m['equipo_visitante'], 2),
        golesLocal: toInt(m['goles_local']),
        golesVisitante: toInt(m['goles_visitante']),
        confianza: toDouble(m['confianza']),
        enDisputa: (m['en_disputa'] ?? false) as bool,
      );
}

class Aspecto {
  Aspecto({required this.clave, required this.nombre, required this.orden, required this.activo, this.aplicaA = 'todos'});
  final String clave, nombre;
  final int orden;
  final bool activo;

  /// 'todos' | 'porteros' | 'campo' (el backend rechaza valoraciones que no apliquen).
  final String aplicaA;

  bool aplicaAJugador({required bool portero}) =>
      aplicaA == 'todos' || (aplicaA == 'porteros' ? portero : !portero);

  factory Aspecto.fromMap(Map<String, dynamic> m) => Aspecto(
        clave: m['clave'] as String,
        nombre: (m['nombre'] ?? m['clave']) as String,
        orden: toInt(m['orden']),
        activo: (m['activo'] ?? true) as bool,
        aplicaA: (m['aplica_a'] ?? 'todos') as String,
      );
}

class Disputa {
  Disputa({
    required this.id,
    required this.tipo,
    this.sujetoId,
    this.campo,
    this.n,
    required this.valores,
    required this.resuelta,
    this.valorFinal,
  });

  final String id, tipo;
  final String? sujetoId, campo;
  final int? n;

  /// Valor reportado → número de jugadores que lo reportaron.
  final Map<String, int> valores;
  final bool resuelta;
  final num? valorFinal;

  factory Disputa.fromMap(Map<String, dynamic> m) {
    final raw = (m['valores'] as Map?) ?? const {};
    return Disputa(
      id: m['id'].toString(),
      tipo: (m['tipo'] ?? 'jugador') as String,
      sujetoId: m['sujeto_id'] as String?,
      campo: m['campo'] as String?,
      n: m['n'] == null ? null : toInt(m['n']),
      valores: {for (final e in raw.entries) e.key.toString(): toInt(e.value)},
      resuelta: (m['resuelta'] ?? false) as bool,
      valorFinal: m['valor_final'] as num?,
    );
  }
}

class PuntosFantasy {
  PuntosFantasy({
    required this.miembroId,
    required this.total,
    required this.desglose,
    this.notaMedia,
    required this.esMvp,
    this.partidoId,
    this.fecha,
  });
  final String miembroId;
  final String? partidoId;
  final double total;
  final Map<String, dynamic> desglose;
  final double? notaMedia;
  final bool esMvp;
  final DateTime? fecha;

  factory PuntosFantasy.fromMap(Map<String, dynamic> m) => PuntosFantasy(
        miembroId: m['miembro_id'] as String,
        partidoId: m['partido_id'] as String?,
        total: toDouble(m['total']) ?? 0,
        desglose: (m['desglose'] as Map?)?.cast<String, dynamic>() ?? const {},
        notaMedia: toDouble(m['nota_media']),
        esMvp: (m['es_mvp'] ?? false) as bool,
        fecha: (m['partido'] is Map && m['partido']['fecha_hora'] != null)
            ? DateTime.parse(m['partido']['fecha_hora'] as String)
            : null,
      );
}

class Rendimiento {
  Rendimiento({
    required this.miembroId,
    required this.partidos,
    required this.puntosTotal,
    required this.puntosMedia,
    required this.goles,
    required this.golesPartido,
    required this.asistencias,
    this.notaMedia,
    required this.mvps,
    this.pctVictorias,
  });

  final String miembroId;
  final int partidos, goles, asistencias, mvps;
  final double puntosTotal, puntosMedia, golesPartido;
  final double? notaMedia, pctVictorias;

  factory Rendimiento.fromMap(Map<String, dynamic> m) => Rendimiento(
        miembroId: m['miembro_id'] as String,
        partidos: toInt(m['partidos']),
        puntosTotal: toDouble(m['puntos_total']) ?? 0,
        puntosMedia: toDouble(m['puntos_media']) ?? 0,
        goles: toInt(m['goles']),
        golesPartido: toDouble(m['goles_partido']) ?? 0,
        asistencias: toInt(m['asistencias']),
        notaMedia: toDouble(m['nota_media']),
        mvps: toInt(m['mvps']),
        pctVictorias: toDouble(m['pct_victorias']),
      );
}

class Saldo {
  Saldo({required this.miembroId, required this.saldo});
  final String miembroId;
  final double saldo;
  factory Saldo.fromMap(Map<String, dynamic> m) =>
      Saldo(miembroId: m['miembro_id'] as String, saldo: toDouble(m['saldo']) ?? 0);
}

class Movimiento {
  Movimiento({required this.id, required this.miembroId, required this.tipo, required this.importe, this.concepto, required this.fecha});
  final String id, miembroId, tipo;
  final double importe;
  final String? concepto;
  final DateTime fecha;

  factory Movimiento.fromMap(Map<String, dynamic> m) => Movimiento(
        id: m['id'] as String,
        miembroId: m['miembro_id'] as String,
        tipo: m['tipo'] as String,
        importe: toDouble(m['importe']) ?? 0,
        concepto: m['concepto'] as String?,
        fecha: DateTime.parse(m['fecha'] as String),
      );
}

class Factura {
  Factura({required this.id, required this.archivoPath, this.nombreArchivo, this.importe, required this.fecha, this.notas, this.partidoId});
  final String id, archivoPath;
  final String? nombreArchivo, notas, partidoId;
  final double? importe;
  final DateTime fecha;

  factory Factura.fromMap(Map<String, dynamic> m) => Factura(
        id: m['id'] as String,
        archivoPath: m['archivo_path'] as String,
        nombreArchivo: m['nombre_archivo'] as String?,
        importe: toDouble(m['importe']),
        fecha: DateTime.parse(m['fecha'] as String),
        notas: m['notas'] as String?,
        partidoId: m['partido_id'] as String?,
      );
}

class Regla {
  Regla({required this.clave, this.posicion, required this.puntos});
  final String clave;
  final String? posicion;
  final double puntos;

  factory Regla.fromMap(Map<String, dynamic> m) => Regla(
        clave: m['clave'] as String,
        posicion: m['posicion'] as String?,
        puntos: toDouble(m['puntos']) ?? 0,
      );
}

/// Nombres legibles de las reglas de puntuación.
/// Nombres legibles de las reglas (0.2: puntos iguales para todos; la posición solo da bonus de rol
/// en la alineación Fantasy).
const nombresReglas = <String, String>{
  'jugado': 'Partido jugado',
  'victoria': 'Victoria (por encuentro)',
  'empate': 'Empate (por encuentro)',
  'gol': 'Gol',
  'asistencia': 'Asistencia',
  'parada_clave_2': 'Cada 2 paradas clave',
  'penalti_parado': 'Penalti parado',
  'penalti_fallado': 'Penalti fallado',
  'autogol': 'Autogol',
  'valoracion_max': 'Valoración de compañeros (máximo)',
  'mvp': 'MVP del partido',
  'rol_por_porteria_cero': 'Portero: su equipo no encaja',
  'rol_por_menos_goleado': 'Portero: su equipo, el menos goleado',
  'rol_por_encajados_3': 'Portero: cada 3 goles encajados',
  'rol_def_menos_goleado': 'Defensa: su equipo, el menos goleado',
  'rol_med_asistencia': 'Medio: extra por asistencia',
  'rol_del_gol': 'Delantero: extra por gol',
};

/// Claves de 0.1 que ya no se usan desde 0.2 (puntuación por posición fija).
bool reglaObsoleta(String clave) =>
    clave.startsWith('gol_') || clave.startsWith('porteria_cero_') || clave == 'goles_encajados_3';

String nombreRegla(String clave) => nombresReglas[clave] ?? clave;

/// Nombres por defecto de los aspectos de valoración.
const nombresAspectos = <String, String>{
  'ataque': 'Ataque',
  'defensa': 'Defensa',
  'pase_vision': 'Pase y visión',
  'esfuerzo': 'Esfuerzo',
  'juego_limpio': 'Juego limpio',
  'porteria': 'Portería',
};
