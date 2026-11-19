import '../../core/supabase.dart';
import '../models.dart';

/// Partidos, convocatorias, equipos y operaciones del admin sobre el partido.
class PartidosRepo {
  static Future<List<Partido>> partidos(String ligaId) async {
    final rows =
        await sb.from('partidos').select().eq('liga_id', ligaId).order('fecha_hora', ascending: false).limit(100);
    return [for (final r in rows) Partido.fromMap(r)];
  }

  /// El partido en tiempo real (cambios de estado, hora confirmada...).
  static Stream<Partido?> partidoStream(String partidoId) => sb
      .from('partidos')
      .stream(primaryKey: ['id'])
      .eq('id', partidoId)
      .map((rows) => rows.isEmpty ? null : Partido.fromMap(rows.first));

  /// Devuelve el id del partido creado. Plazas y nº de equipos nulos = los de la liga.
  static Future<String> crear(
    String ligaId, {
    required DateTime fechaHora,
    double coste = 0,
    int? plazas,
    int? numEquipos,
    String? campoMapsUrl,
    bool horaConfirmada = false,
  }) async =>
      (await sb.rpc('crear_partido', params: {
        'p_liga': ligaId,
        'p_fecha_hora': fechaHora.toUtc().toIso8601String(),
        'p_coste': coste,
        'p_plazas': plazas,
        'p_num_equipos': numEquipos,
        'p_campo_maps_url': campoMapsUrl,
        'p_hora_confirmada': horaConfirmada,
      })) as String;

  static Future<void> actualizar(String partidoId, Map<String, dynamic> datos) async {
    await sb.from('partidos').update(datos).eq('id', partidoId);
  }

  // ---- Convocatoria --------------------------------------------------------

  static Stream<List<Inscripcion>> convocatoriaStream(String partidoId) => sb
      .from('convocatorias')
      .stream(primaryKey: ['partido_id', 'miembro_id'])
      .eq('partido_id', partidoId)
      .order('inscrito_en')
      .map((rows) => [for (final r in rows) Inscripcion.fromMap(r)]);

  /// El trigger de la base de datos pasa a 'espera' si no queda sitio.
  static Future<void> cambiarEstado(String partidoId, String miembroId, EstadoInscripcion estado) async {
    await sb.from('convocatorias').upsert({
      'partido_id': partidoId,
      'miembro_id': miembroId,
      'estado': estado.name,
    });
  }

  /// Guarda el equipo (1..4) de cada confirmado y pasa el partido a `equipos_hechos`.
  /// Con 2 equipos el backend crea el único encuentro; con 3-4 se crean aquí todos contra todos
  /// (el admin puede rehacerlos con [definirEncuentros]).
  static Future<void> guardarEquipos(String partidoId, Map<String, int> equipoPorMiembro, {int numEquipos = 2}) async {
    await sb.rpc('guardar_equipos', params: {'p_partido': partidoId, 'p_asignacion': equipoPorMiembro});
    if (numEquipos > 2) {
      await definirEncuentros(partidoId, [
        for (var a = 1; a <= numEquipos; a++)
          for (var b = a + 1; b <= numEquipos; b++) [a, b],
      ]);
    }
  }

  /// Enfrentamientos para 3-4 equipos: [[1, 2], [3, 1], ...].
  static Future<void> definirEncuentros(String partidoId, List<List<int>> lista) async {
    await sb.rpc('definir_encuentros', params: {'p_partido': partidoId, 'p_lista': lista});
  }

  static Future<List<Encuentro>> encuentros(String partidoId) async {
    final rows = await sb.from('encuentros').select().eq('partido_id', partidoId).order('n');
    return [for (final r in rows) Encuentro.fromMap(r)];
  }

  // ---- Acciones del admin --------------------------------------------------

  /// El partido se ha jugado: genera los cargos y abre la ventana de partes y valoraciones
  /// (duración: `ligas.horas_post_partido`). Requiere `equipos_hechos`.
  static Future<void> marcarJugado(String partidoId) async {
    await sb.rpc('marcar_jugado', params: {'p_partido': partidoId});
  }

  /// Cierra la ventana post-partido y cruza los partes. Devuelve el nuevo estado:
  /// `en_revision` si quedan disputas o `cerrado` si ya se han calculado los puntos.
  static Future<EstadoPartido> cerrarPostPartido(String partidoId) async {
    final r = await sb.rpc('cerrar_post_partido', params: {'p_partido': partidoId});
    return EstadoPartido.values.firstWhere((e) => e.name == r, orElse: () => EstadoPartido.en_revision);
  }

  /// Solo como respaldo: normalmente los puntos se calculan solos al cerrar o al resolver la última disputa.
  static Future<void> calcularPuntos(String partidoId) async {
    await sb.rpc('calcular_puntos', params: {'p_partido': partidoId});
  }
}
