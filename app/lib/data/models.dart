import 'package:flutter/material.dart';
// Los valores de los enums coinciden con los de Postgres (snake_case).
// ignore_for_file: constant_identifier_names

import '../core/idioma.dart';
import '../core/utils.dart';

// ---------------------------------------------------------------------------
// Enumeraciones (se guardan como texto en Postgres)
// ---------------------------------------------------------------------------

/// 0042: «pendiente» = fijo apuntado solo que aún no ha confirmado (ocupa plaza). «espera» = suplente.
enum EstadoInscripcion { confirmado, pendiente, duda, baja, espera }

extension EstadoInscripcionX on EstadoInscripcion {
  /// Ocupa plaza en la convocatoria (confirmado, fijo pendiente o en duda).
  bool get ocupaPlaza =>
      this == EstadoInscripcion.confirmado || this == EstadoInscripcion.pendiente || this == EstadoInscripcion.duda;
}

enum EstadoPartido { abierto, completo, equipos_hechos, jugado, post_partido, en_revision, cerrado, cancelado }

enum RolLiga { admin, jugador }

enum EstadoMiembro { pendiente_registro, solicitud, activo, expulsado, abandonado, rechazado }

/// Rango del jugador en la liga (v0.3). Los fijos entran solos en cada partido;
/// reservas e invitados se apuntan a la lista de espera. En el Fantasy, el invitado puntúa ×1,5.
enum RangoMiembro { fijo, reserva, invitado }

extension RangoMiembroX on RangoMiembro {
  String get etiqueta => tr(switch (this) {
        RangoMiembro.fijo => 'Fijo',
        RangoMiembro.reserva => 'Reserva',
        RangoMiembro.invitado => 'Invitado',
      });

  /// Inicial para mostrar junto al nombre (F / R / I).
  String get letra => switch (this) {
        RangoMiembro.fijo => 'F',
        RangoMiembro.reserva => 'R',
        RangoMiembro.invitado => 'I',
      };

  /// Prioridad en la lista de espera con `orden_espera = prioridad` (menor = antes).
  int get prioridad => index;
}

RangoMiembro? rangoDe(dynamic texto) => RangoMiembro.values.where((r) => r.name == texto).firstOrNull;

T _enum<T extends Enum>(List<T> valores, dynamic texto, T defecto) =>
    valores.where((v) => v.name == texto).firstOrNull ?? defecto;

extension EstadoPartidoX on EstadoPartido {
  String get etiqueta => tr(switch (this) {
        EstadoPartido.abierto => 'Convocatoria abierta',
        EstadoPartido.completo => 'Completo',
        EstadoPartido.equipos_hechos => 'Equipos hechos',
        EstadoPartido.jugado => 'Jugado',
        EstadoPartido.post_partido => 'Post-partido',
        EstadoPartido.en_revision => 'En revisión',
        EstadoPartido.cerrado => 'Cerrado',
        EstadoPartido.cancelado => 'Cancelado',
      });

  bool get antesDeJugar =>
      this == EstadoPartido.abierto || this == EstadoPartido.completo || this == EstadoPartido.equipos_hechos;
}

const posiciones = ['portero', 'defensa', 'medio', 'delantero'];

/// Posición preferida del jugador: solo informativa (desde 0.2 los puntos no dependen de ella).
String etiquetaPosicion(String? p) => tr(switch (p) {
      'portero' => 'Portero',
      'defensa' => 'Defensa',
      'medio' => 'Centrocampista',
      'delantero' => 'Delantero',
      _ => 'Sin posición',
    });

// ---------------------------------------------------------------------------
// Entidades
// ---------------------------------------------------------------------------

class Perfil {
  Perfil({
    required this.id,
    required this.nombre,
    this.apodo,
    this.avatarUrl,
    this.posicion,
    this.telefono,
    this.fechaNacimiento,
    this.dorsal,
  });
  final String id;
  final String nombre;
  final String? apodo, avatarUrl, posicion, telefono;
  final DateTime? fechaNacimiento;

  /// 0053: número de camiseta (1-99).
  final int? dorsal;

  /// Edad en años cumplidos (null si no la ha indicado).
  int? get edad {
    final f = fechaNacimiento;
    if (f == null) return null;
    final hoy = DateTime.now();
    var e = hoy.year - f.year;
    if (hoy.month < f.month || (hoy.month == f.month && hoy.day < f.day)) e--;
    return e;
  }

  factory Perfil.fromMap(Map<String, dynamic> m) => Perfil(
        id: m['id'] as String,
        nombre: (m['nombre'] ?? '') as String,
        apodo: m['apodo'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        posicion: m['posicion'] as String?,
        telefono: m['telefono'] as String?,
        fechaNacimiento: m['fecha_nacimiento'] == null ? null : DateTime.parse(m['fecha_nacimiento'] as String),
        dorsal: m['dorsal'] == null ? null : toInt(m['dorsal']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'apodo': apodo,
        'avatar_url': avatarUrl,
        'posicion': posicion,
        'telefono': telefono,
        'dorsal': dorsal,
        'fecha_nacimiento': fechaNacimiento == null
            ? null
            : '${fechaNacimiento!.year.toString().padLeft(4, '0')}-${fechaNacimiento!.month.toString().padLeft(2, '0')}-${fechaNacimiento!.day.toString().padLeft(2, '0')}',
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
    this.ordenEspera = 'prioridad',
    this.modoCobro = 'por_partido',
    this.precioInvitado,
    this.plazasFijas,
    this.modoValoracion = 'rapida',
    this.puntosPodio = const [5, 3, 1],
    this.equipaciones = Equipacion.porDefecto,
    this.normas,
    this.modoConvocatoria = 'apertura',
    this.duracionPartidoMin = 60,
    this.horasAperturaConvocatoria = 2,
    this.horasReservaFijos = 24,
    this.fantasyActivo = true,
    this.prediccionActiva = true,
    this.valoracionAvanzada = false,
    this.modalidad = 'f7',
    this.recordatorioDeudas = 'mensual',
    this.bizumTelefono,
    this.modoEquipos = 'admin',
    this.capitanesPorEquipo = 1,
    this.nivel = 'avanzado',
    this.comprasDinero = true,
    this.horasTurno = 24,
    this.minimoJugadores,
    this.horasDecision = 24,
    this.quienRellena = 'jugadores',
    this.arbitroId,
  });

  /// 0050: modo «turnos» (horas entre fijos → reservas → invitados) y modo «mínimo».
  final int horasTurno, horasDecision;
  final int? minimoJugadores;

  /// 0050: quién rellena el acta del post-partido: 'jugadores' | 'arbitro' | 'capitanes'.
  final String quienRellena;
  final String? arbitroId;

  /// En estos modos los fijos aparecen en la lista (pendientes) nada más crearse el partido.
  bool get fijosApuntadosSolos => modoConvocatoria == 'apertura' || modoConvocatoria == 'clasica';

  /// En la lista de espera, los fijos entran antes (salvo en «orden de llegada» y «mínimo»).
  bool get fijosPrimero => modoConvocatoria != 'libre' && modoConvocatoria != 'minimo';

  /// 0046: se puede conseguir dinero Fantasy con códigos o compras (lo decide el admin).
  final bool comprasDinero;

  /// 0045: 'basico' | 'medio' | 'avanzado'. Decide qué opciones se enseñan en Ajustes.
  final String nivel;
  bool get esAvanzada => nivel == 'avanzado';

  /// 0042: quién hace los equipos: 'admin' | 'automatico' | 'capitanes' (1 o 2 por equipo).
  final String modoEquipos;
  final int capitanesPorEquipo;
  bool get conCapitanes => modoEquipos == 'capitanes';

  /// 0036: 'nunca' | 'semanal' | 'mensual' | 'trimestral'.
  final String recordatorioDeudas;

  /// 0036: teléfono al que se hace Bizum (lo pone el admin).
  final String? bizumTelefono;

  /// 0032: post-partido avanzado (destacados, más datos, valoración por aspectos, «no le vi»). Por defecto, simple.
  final bool valoracionAvanzada;

  /// 0032: 'f3' | 'sala' | 'f7' | 'f8' | 'f11' (decide qué reglas tiene el reglamento).
  final String modalidad;
  String get nombreModalidad => tr(nombresModalidad[modalidad] ?? modalidad);

  /// 0026: 'apertura' (vacía hasta X h después del partido anterior; todos pulsan «Voy») | 'clasica'.
  final String modoConvocatoria;
  final int duracionPartidoMin, horasAperturaConvocatoria, horasReservaFijos;
  bool get conApertura => modoConvocatoria == 'apertura' || modoConvocatoria == 'turnos';

  /// 0026: la liga puede usar solo convocatorias. 0028: resultado esperado (xG).
  final bool fantasyActivo, prediccionActiva;

  /// Fin del partido anterior + X horas (null si no hay partido anterior). Igual que `_base_convocatoria` (0050).
  DateTime? _baseConvocatoria(Partido p, List<Partido> todos) {
    final anteriores = todos
        .where((a) => a.id != p.id && a.fechaHora.isBefore(p.fechaHora) && a.estado != EstadoPartido.cancelado)
        .map((a) => a.fechaHora)
        .toList();
    if (anteriores.isEmpty) return null;
    anteriores.sort();
    return anteriores.last.add(Duration(minutes: duracionPartidoMin, hours: horasAperturaConvocatoria));
  }

  /// Cuándo se abre la convocatoria de [p] para el primer grupo (null = ya abierta).
  DateTime? abreConvocatoria(Partido p, List<Partido> todos) {
    if (!conApertura) return null;
    final abre = _baseConvocatoria(p, todos);
    return abre != null && abre.isAfter(DateTime.now()) ? abre : null;
  }

  /// Cuándo puede apuntarse alguien de [rango] (null = ya puede). Igual que `convocatoria_abre_para` (0050).
  DateTime? abreConvocatoriaPara(Partido p, List<Partido> todos, RangoMiembro rango) {
    final base = _baseConvocatoria(p, todos);
    if (base == null) return null;
    final DateTime? abre = switch (modoConvocatoria) {
      'apertura' => rango == RangoMiembro.fijo ? null : base,
      'turnos' => base.add(Duration(hours: horasTurno * switch (rango) {
            RangoMiembro.fijo => 0,
            RangoMiembro.reserva => 1,
            RangoMiembro.invitado => 2,
          })),
      _ => null,
    };
    return abre != null && abre.isAfter(DateTime.now()) ? abre : null;
  }

  /// Hasta cuándo tienen los fijos su plaza guardada.
  DateTime finReservaFijos(Partido p) => p.fechaHora.subtract(Duration(hours: horasReservaFijos));

  /// Equipación de cada equipo (1, 2, 3, 4), elegida por el admin. Ver core/equipaciones.dart.
  final List<Equipacion> equipaciones;

  /// Normas acordadas en la liga (texto libre del admin, se muestra en la Guía).
  final String? normas;

  /// v0.3b: 'rapida' (una nota general por compañero) | 'detallada' (nota por aspecto).
  final String modoValoracion;

  /// 0053: puntos de votación del podio (1.º, 2.º, 3.º) en modo 'podio'.
  final List<int> puntosPodio;
  bool get votaPodio => modoValoracion == 'podio';
  bool get valoracionDetallada => valoracionAvanzada && modoValoracion == 'detallada';

  // ---- v0.3: convocatoria con fijos y cobro ----
  /// 'prioridad' (fijos que vuelven, reservas, invitados) | 'anotacion' (por orden de apuntarse).
  final String ordenEspera;

  /// 'por_partido' | 'factura_mensual'.
  final String modoCobro;

  /// Precio fijo por partido para reservas e invitados; null = variable (misma cuota que los fijos).
  final double? precioInvitado;
  final int? plazasFijas;

  bool get facturaMensual => modoCobro == 'factura_mensual';
  bool get esperaPorPrioridad => ordenEspera != 'anotacion';

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
      ordenEspera: (m['orden_espera'] ?? 'prioridad') as String,
      modoCobro: (m['modo_cobro'] ?? 'por_partido') as String,
      precioInvitado: toDouble(m['precio_invitado']),
      plazasFijas: m['plazas_fijas'] == null ? null : toInt(m['plazas_fijas']),
      modoValoracion: (m['modo_valoracion'] ?? 'rapida') as String,
      puntosPodio: m['puntos_podio'] is List && (m['puntos_podio'] as List).length == 3
          ? [for (final x in m['puntos_podio'] as List) toInt(x)]
          : const [5, 3, 1],
      equipaciones: m['equipaciones'] is List
          ? [for (final e in m['equipaciones'] as List) Equipacion.fromMap((e as Map).cast<String, dynamic>())]
          : Equipacion.porDefecto,
      normas: m['normas'] as String?,
      modoConvocatoria: (m['modo_convocatoria'] ?? 'clasica') as String,
      duracionPartidoMin: toInt(m['duracion_partido_min'], 60),
      horasAperturaConvocatoria: toInt(m['horas_apertura_convocatoria'], 2),
      horasReservaFijos: toInt(m['horas_reserva_fijos'], 24),
      fantasyActivo: (m['fantasy_activo'] ?? true) as bool,
      prediccionActiva: (m['prediccion_activa'] ?? true) as bool,
      valoracionAvanzada: (m['valoracion_avanzada'] ?? false) as bool,
      modalidad: (m['modalidad'] ?? 'f7') as String,
      recordatorioDeudas: (m['recordatorio_deudas'] ?? 'mensual') as String,
      bizumTelefono: m['bizum_telefono'] as String?,
      modoEquipos: (m['modo_equipos'] ?? 'admin') as String,
      capitanesPorEquipo: toInt(m['capitanes_por_equipo'], 1),
      nivel: (m['nivel'] ?? 'avanzado') as String,
      comprasDinero: (m['compras_dinero'] ?? true) as bool,
      horasTurno: toInt(m['horas_turno'], 24),
      minimoJugadores: m['minimo_jugadores'] == null ? null : toInt(m['minimo_jugadores']),
      horasDecision: toInt(m['horas_decision'], 24),
      quienRellena: (m['quien_rellena'] ?? 'jugadores') as String,
      arbitroId: m['arbitro_id'] as String?,
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
    this.proteccionDias = 7,
    this.cesionPctMin = 0.05,
    this.cesionPctMax = 0.30,
    this.horasCaducidadOferta = 48,
    this.partidosMinRendimiento = 3,
    this.cesionesActivas = false,
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

  /// Días que un fichaje no se puede clausular (0027).
  final int proteccionDias;

  /// % de cesión permitido, como fracción 0–1.
  final double cesionPctMin, cesionPctMax;
  final int horasCaducidadOferta, partidosMinRendimiento;

  /// Cesiones de jugadores entre mánagers (0039): opcional, desactivadas por defecto.
  final bool cesionesActivas;

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
        proteccionDias: toInt(m['proteccion_dias'], 7),
        cesionPctMin: toDouble(m['cesion_pct_min']) ?? 0.05,
        cesionPctMax: toDouble(m['cesion_pct_max']) ?? 0.30,
        horasCaducidadOferta: toInt(m['horas_caducidad_oferta'], 48),
        partidosMinRendimiento: toInt(m['partidos_min_rendimiento'], 3),
        cesionesActivas: (m['cesiones_activas'] ?? false) as bool,
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
        'cesiones_activas': cesionesActivas,
        'coste_subida_clausula': costeSubidaClausula,
        'proteccion_jornadas': proteccionJornadas,
        'proteccion_dias': proteccionDias,
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
    this.rango = RangoMiembro.reserva,
  });

  /// Rango en la liga (v0.3): fijo, reserva o invitado.
  final RangoMiembro rango;

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
  static const select = 'id, liga_id, perfil_id, nombre_provisional, posicion, rol, estado, rango, invitado_por, unido_en, '
      'perfil:perfiles!miembros_perfil_id_fkey(id, nombre, apodo, avatar_url, posicion, telefono, fecha_nacimiento, dorsal)';

  factory Miembro.fromMap(Map<String, dynamic> m) => Miembro(
        id: m['id'] as String,
        ligaId: m['liga_id'] as String,
        perfilId: m['perfil_id'] as String?,
        nombreProvisional: m['nombre_provisional'] as String?,
        posicionLiga: m['posicion'] as String?,
        rol: _enum(RolLiga.values, m['rol'], RolLiga.jugador),
        estado: _enum(EstadoMiembro.values, m['estado'], EstadoMiembro.activo),
        perfil: m['perfil'] == null ? null : Perfil.fromMap(m['perfil'] as Map<String, dynamic>),
        rango: rangoDe(m['rango']) ?? RangoMiembro.reserva,
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
    this.temporadaId,
    this.arbitroId,
  });

  final String id, ligaId;
  final String? temporadaId;
  /// 0050: árbitro de este partido (si no, el de la liga).
  final String? arbitroId;
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
        temporadaId: m['temporada_id'] as String?,
        arbitroId: m['arbitro_id'] as String?,
      );
}

class Inscripcion {
  Inscripcion({required this.miembroId, required this.estado, required this.inscritoEn, this.equipo, this.rango,
      this.capitan = false});
  final String miembroId;

  /// 0042: capitán de su equipo en este partido (forma los equipos).
  final bool capitan;
  final EstadoInscripcion estado;
  final DateTime inscritoEn;
  final int? equipo;

  /// Rango del miembro en el momento de inscribirse/jugar (`convocatorias.rango`, v0.3).
  /// Nulo en partidos anteriores: usar el rango actual del miembro.
  final RangoMiembro? rango;

  factory Inscripcion.fromMap(Map<String, dynamic> m) => Inscripcion(
        miembroId: m['miembro_id'] as String,
        estado: _enum(EstadoInscripcion.values, m['estado'], EstadoInscripcion.duda),
        inscritoEn: DateTime.parse(m['inscrito_en'] as String),
        equipo: m['equipo'] == null ? null : toInt(m['equipo']),
        rango: rangoDe(m['rango']),
        capitan: (m['capitan'] ?? false) as bool,
      );
}

/// Orden real de la lista de espera según la regla de la liga (v0.3, igual que `promover_espera`):
/// - prioridad: fijos que vuelven, luego reservas, luego invitados; dentro de cada grupo por `inscrito_en`.
/// - anotacion: solo por `inscrito_en`.
List<Inscripcion> ordenarEspera(
  List<Inscripcion> espera,
  Map<String, Miembro> miembros, {
  required bool porPrioridad,
}) {
  // 0042 (como `rellenar_plazas`): primero un fijo que esperaba; luego, por orden de apuntarse.
  RangoMiembro rango(Inscripcion i) => i.rango ?? miembros[i.miembroId]?.rango ?? RangoMiembro.reserva;
  final lista = [...espera];
  lista.sort((a, b) {
    // 0050: en «orden de llegada» y «mínimo» no hay prioridad para los fijos
    final fa = porPrioridad && rango(a) == RangoMiembro.fijo ? 0 : 1,
        fb = porPrioridad && rango(b) == RangoMiembro.fijo ? 0 : 1;
    if (fa != fb) return fa.compareTo(fb);
    return a.inscritoEn.compareTo(b.inscritoEn);
  });
  return lista;
}

/// Temporada: partidos recurrentes entre dos fechas (v0.3, tabla `temporadas`).
class Temporada {
  Temporada({
    required this.id,
    this.nombre,
    required this.desde,
    required this.hasta,
    required this.diasSemana,
    required this.hora,
    required this.horaFija,
    this.costePartido = 0,
  });
  final String id;
  final String? nombre;
  final DateTime desde, hasta;

  /// 1 = lunes … 7 = domingo.
  final List<int> diasSemana;

  /// 'HH:MM[:SS]'.
  final String hora;
  final bool horaFija;
  final double costePartido;

  factory Temporada.fromMap(Map<String, dynamic> m) => Temporada(
        id: m['id'] as String,
        nombre: m['nombre'] as String?,
        desde: DateTime.parse(m['desde'] as String),
        hasta: DateTime.parse(m['hasta'] as String),
        diasSemana: [for (final d in (m['dias_semana'] as List? ?? const [])) toInt(d)],
        hora: (m['hora'] ?? '') as String,
        horaFija: (m['hora_fija'] ?? true) as bool,
        costePartido: toDouble(m['coste_partido']) ?? 0,
      );
}

const nombresDiasCortos = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const nombresDias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados', 'domingos'];

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
    this.valorPropuesto,
  });

  /// 0047: lo que propone la app (lo más probable ponderando los partes).
  final int? valorPropuesto;

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
      valorPropuesto: m['valor_propuesto'] == null ? null : toInt(m['valor_propuesto']),
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
    this.puesto,
  });
  final String miembroId;
  final String? partidoId;
  final double total;
  final Map<String, dynamic> desglose;
  final double? notaMedia;
  final bool esMvp;
  final DateTime? fecha;

  /// 0053: 1 (MVP), 2 o 3 si quedó en el podio del partido.
  final int? puesto;

  factory PuntosFantasy.fromMap(Map<String, dynamic> m) => PuntosFantasy(
        miembroId: m['miembro_id'] as String,
        partidoId: m['partido_id'] as String?,
        total: toDouble(m['total']) ?? 0,
        desglose: (m['desglose'] as Map?)?.cast<String, dynamic>() ?? const {},
        notaMedia: toDouble(m['nota_media']),
        esMvp: (m['es_mvp'] ?? false) as bool,
        puesto: m['puesto'] == null ? null : toInt(m['puesto']),
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
  Factura({
    required this.id,
    required this.archivoPath,
    this.nombreArchivo,
    this.importe,
    required this.fecha,
    this.notas,
    this.partidoId,
    this.periodoDesde,
    this.periodoHasta,
    this.liquidada = false,
  });
  final String id, archivoPath;
  final String? nombreArchivo, notas, partidoId;
  final double? importe;
  final DateTime fecha;

  /// Periodo que cubre una factura mensual (v0.3). Nulo = factura de un partido o sin periodo.
  final DateTime? periodoDesde, periodoHasta;
  final bool liquidada;

  bool get esMensual => periodoDesde != null && periodoHasta != null;

  factory Factura.fromMap(Map<String, dynamic> m) => Factura(
        id: m['id'] as String,
        archivoPath: m['archivo_path'] as String,
        nombreArchivo: m['nombre_archivo'] as String?,
        importe: toDouble(m['importe']),
        fecha: DateTime.parse(m['fecha'] as String),
        notas: m['notas'] as String?,
        partidoId: m['partido_id'] as String?,
        periodoDesde: m['periodo_desde'] == null ? null : DateTime.parse(m['periodo_desde'] as String),
        periodoHasta: m['periodo_hasta'] == null ? null : DateTime.parse(m['periodo_hasta'] as String),
        liquidada: (m['liquidada'] ?? false) as bool,
      );
}

/// Desglose de `simular_factura` / `liquidar_factura` (v0.3).
class LiquidacionFactura {
  LiquidacionFactura({
    required this.importe,
    required this.pagadoInvitados,
    required this.resto,
    required this.partidos,
    required this.cuota,
    required this.cargos,
  });
  final double importe, pagadoInvitados, resto, cuota;

  /// Nº total de asistencias que se reparten la factura (fijos; + no fijos si el precio es variable).
  final int partidos;

  /// Filas {miembro_id, partidos, importe}.
  final List<({String miembroId, int partidos, double importe})> cargos;

  factory LiquidacionFactura.fromMap(Map<String, dynamic> m) => LiquidacionFactura(
        importe: toDouble(m['importe']) ?? 0,
        pagadoInvitados: toDouble(m['pagado_invitados']) ?? 0,
        resto: toDouble(m['resto']) ?? 0,
        partidos: toInt(m['partidos']),
        cuota: toDouble(m['cuota']) ?? 0,
        cargos: [
          for (final c in (m['cargos'] as List? ?? const []))
            (
              miembroId: (c as Map)['miembro_id'] as String,
              partidos: toInt(c['partidos']),
              importe: toDouble(c['importe']) ?? 0,
            ),
        ],
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

/// Equipación de un equipo: nombre («Blanco», «Petos»…) y color en hex (#RRGGBB); null = «de color» sin especificar.
class Equipacion {
  const Equipacion(this.nombre, [this.colorHex]);
  final String nombre;
  final String? colorHex;

  static const porDefecto = [
    Equipacion('Blanco', '#F4F4F2'),
    Equipacion('Color'),
    Equipacion('Negro', '#1E1E1E'),
    Equipacion('Petos', '#E8C21A'),
  ];

  factory Equipacion.fromMap(Map<String, dynamic> m) =>
      Equipacion((m['nombre'] ?? 'Equipo') as String, m['color'] as String?);

  Map<String, dynamic> toMap() => {'nombre': nombre, 'color': colorHex};
}

const nombresModalidad = <String, String>{
  'f3': 'Fútbol 3',
  'sala': 'Fútbol sala',
  'f7': 'Fútbol 7',
  'f8': 'Fútbol 8',
  'f11': 'Fútbol 11',
};


/// Niveles de liga (0045): qué se activa con cada uno. El avanzado parte del medio y se ajusta a mano.
const nivelesLiga = <(String, IconData, String, String)>[
  ('basico', Icons.directions_walk, 'Básico', 'Lista de quién va, equipos automáticos, resultados y pagos. Sin Fantasy.'),
  ('medio', Icons.directions_run, 'Medio', 'Lo básico más el Fantasy y estrellas a los compañeros tras el partido. El recomendado.'),
  ('avanzado', Icons.bolt, 'Avanzado', 'Todo a tu gusto: post-partido detallado, resultado esperado, cesiones y capitanes.'),
];

/// Valores de cada nivel. [extra] sobrescribe (lo que el admin elige en el modo avanzado).
Map<String, dynamic> ajustesNivel(String nivel, [Map<String, dynamic> extra = const {}]) => {
      'nivel': nivel,
      ...switch (nivel) {
        'basico' => {
            'fantasy_activo': false,
            'prediccion_activa': false,
            'valoracion_avanzada': false,
            'cesiones_activas': false,
            'modo_equipos': 'automatico',
          },
        'avanzado' => {
            'fantasy_activo': true,
            'prediccion_activa': true,
            'valoracion_avanzada': true,
            'cesiones_activas': false,
            'modo_equipos': 'admin',
          },
        _ => {
            'fantasy_activo': true,
            'prediccion_activa': true,
            'valoracion_avanzada': false,
            'cesiones_activas': false,
            'modo_equipos': 'automatico',
          },
      },
      ...extra,
    };

/// 0050: los cinco modos de convocatoria que puede elegir cada liga (valor, nombre, explicación).
const modosConvocatoria = <(String, String, String)>[
  ('apertura', 'Con apertura',
      'Los fijos están en la lista desde el principio. El resto se apunta cuando se abre, un rato después del partido anterior.'),
  ('clasica', 'Clásica',
      'Los fijos están en la lista desde el principio y el resto puede apuntarse en cuanto se crea el partido.'),
  ('libre', 'Por orden de llegada',
      'Nadie está apuntado de oficio. Todos se apuntan y entra quien antes llega, sin prioridad para los fijos.'),
  ('turnos', 'Por turnos',
      'Primero pueden apuntarse los fijos; unas horas después, las reservas; y al final, los invitados.'),
  ('minimo', 'Con mínimo de jugadores',
      'Todos se apuntan. Si a la hora límite no hay suficientes, el partido se cancela solo y se avisa a todos.'),
];

/// 0050: quién rellena el acta del post-partido (resultado, goles y asistencias).
const modosActa = <(String, String, String)>[
  ('jugadores', 'Todos los que jugaron', 'Cada uno pone lo que vio y la app cruza los partes. Lo más fiable.'),
  ('arbitro', 'El árbitro', 'Solo una persona rellena el acta y vale lo que ponga. Los demás solo ponen notas.'),
  ('capitanes', 'Los capitanes', 'El capitán de cada equipo rellena el acta. Los demás solo ponen notas.'),
];
