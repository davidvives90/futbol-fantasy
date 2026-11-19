import '../../core/supabase.dart';
import '../models.dart';

/// Perfil, ligas, membresías, invitaciones y ajustes de liga.
class LigasRepo {
  // ---- Perfil --------------------------------------------------------------

  static Future<Perfil?> miPerfil() async {
    final uid = uidActual;
    if (uid == null) return null;
    final m = await sb.from('perfiles').select().eq('id', uid).maybeSingle();
    return m == null ? null : Perfil.fromMap(m);
  }

  static Future<void> guardarPerfil(Perfil p) async {
    await sb.from('perfiles').upsert(p.toMap());
  }

  // ---- Mis ligas -------------------------------------------------------------

  static Future<List<MiLiga>> misLigas() async {
    final uid = uidActual;
    if (uid == null) return [];
    final rows = await sb
        .from('miembros')
        .select('${Miembro.select}, liga:ligas(*)')
        .eq('perfil_id', uid)
        .eq('estado', 'activo');
    return [
      for (final r in rows) MiLiga(Liga.fromMap(r['liga'] as Map<String, dynamic>), Miembro.fromMap(r)),
    ]..sort((a, b) => a.liga.nombre.compareTo(b.liga.nombre));
  }

  /// Solicitudes enviadas desde el buscador que aún no se han aprobado.
  static Future<List<String>> misSolicitudesPendientes() async {
    final uid = uidActual;
    if (uid == null) return [];
    final rows =
        await sb.from('miembros').select('liga:ligas(nombre)').eq('perfil_id', uid).eq('estado', 'solicitud');
    return [for (final r in rows) (r['liga'] as Map)['nombre'] as String];
  }

  // ---- Alta y búsqueda -----------------------------------------------------

  /// Devuelve el id de la liga creada.
  static Future<String> crearLiga(Map<String, dynamic> datos) async =>
      (await sb.rpc('crear_liga', params: {'p': datos})) as String;

  static Future<void> actualizarLiga(String ligaId, Map<String, dynamic> datos) async {
    await sb.from('ligas').update(datos).eq('id', ligaId);
  }

  /// Token personal o código general. Devuelve el id de la liga.
  static Future<String> unirse(String codigo) async =>
      (await sb.rpc('unirse', params: {'p_codigo': codigo.trim()})) as String;

  static Future<List<Map<String, dynamic>>> buscar(String texto) async {
    final r = await sb.rpc('buscar_ligas', params: {'p_texto': texto.trim()});
    return List<Map<String, dynamic>>.from(r as List);
  }

  static Future<void> solicitarUnirse(String ligaId) async {
    await sb.rpc('solicitar_unirse', params: {'p_liga': ligaId});
  }

  // ---- Miembros y administración ------------------------------------------

  static Future<List<Miembro>> miembros(String ligaId) async {
    final rows = await sb.from('miembros').select(Miembro.select).eq('liga_id', ligaId).order('unido_en');
    return [for (final r in rows) Miembro.fromMap(r)];
  }

  /// Devuelve filas {miembro_id, nombre, token}.
  static Future<List<Map<String, dynamic>>> precrearJugadores(String ligaId, List<String> nombres) async {
    final r = await sb.rpc('precrear_jugadores', params: {'p_liga': ligaId, 'p_nombres': nombres});
    return List<Map<String, dynamic>>.from(r as List);
  }

  static Future<void> aprobarSolicitud(String miembroId, bool aceptar) async {
    await sb.rpc('aprobar_solicitud', params: {'p_miembro': miembroId, 'p_aceptar': aceptar});
  }

  static Future<void> cambiarRol(String miembroId, RolLiga rol) async {
    await sb.rpc('cambiar_rol', params: {'p_miembro': miembroId, 'p_rol': rol.name});
  }

  static Future<void> expulsar(String miembroId) async {
    await sb.rpc('expulsar', params: {'p_miembro': miembroId});
  }

  static Future<void> abandonar(String ligaId) async {
    await sb.rpc('abandonar_liga', params: {'p_liga': ligaId});
  }

  /// Enlaces personales pendientes (solo admins): filas {miembro_id, nombre, contacto, token}.
  static Future<List<Map<String, dynamic>>> enlacesInvitacion(String ligaId) async {
    final r = await sb.rpc('enlaces_invitacion', params: {'p_liga': ligaId});
    return List<Map<String, dynamic>>.from(r as List);
  }

  static Future<String> regenerarCodigo(String ligaId) async =>
      (await sb.rpc('regenerar_codigo', params: {'p_liga': ligaId})).toString();

  // ---- Reglas y aspectos ---------------------------------------------------

  static Future<List<Regla>> reglas(String ligaId) async {
    final rows = await sb.from('reglas_puntuacion').select().eq('liga_id', ligaId);
    final lista = [for (final r in rows) Regla.fromMap(r)];
    final orden = nombresReglas.keys.toList();
    int idx(String c) => orden.contains(c) ? orden.indexOf(c) : 999;
    lista.sort((a, b) => idx(a.clave).compareTo(idx(b.clave)));
    return lista;
  }

  static Future<void> guardarRegla(String ligaId, String clave, double puntos) async {
    await sb
        .from('reglas_puntuacion')
        .update({'puntos': puntos})
        .eq('liga_id', ligaId)
        .eq('clave', clave)
        .isFilter('posicion', null); // solo la regla general; las de posición se editan aparte
  }

  static Future<List<Aspecto>> aspectos(String ligaId, {bool soloActivos = false}) async {
    var q = sb.from('aspectos_valoracion').select().eq('liga_id', ligaId);
    if (soloActivos) q = q.eq('activo', true);
    final rows = await q.order('orden');
    return [for (final r in rows) Aspecto.fromMap(r)];
  }

  static Future<void> guardarAspecto(String ligaId, Aspecto a) async {
    await sb.from('aspectos_valoracion').upsert({
      'liga_id': ligaId,
      'clave': a.clave,
      'nombre': a.nombre,
      'orden': a.orden,
      'activo': a.activo,
      'aplica_a': a.aplicaA,
    }, onConflict: 'liga_id,clave');
  }
}
