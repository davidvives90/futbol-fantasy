import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';

/// Clave (liga, miembro) para providers family.
typedef LigaMiembro = ({String ligaId, String miembroId});

final miManagerProvider = FutureProvider.autoDispose.family<Manager?, LigaMiembro>(
  (ref, k) => FantasyRepo.miManager(k.ligaId, k.miembroId),
);

final miPlantillaProvider = FutureProvider.autoDispose.family<List<JugadorPlantilla>, LigaMiembro>(
  // v_mi_plantilla ya filtra por el usuario autenticado; el miembro solo forma parte de la clave.
  (ref, k) => FantasyRepo.miPlantilla(k.ligaId),
);

final mercadoProvider = FutureProvider.autoDispose.family<List<JugadorMercado>, String>(
  (ref, ligaId) => FantasyRepo.mercado(ligaId),
);

final mercadoAbiertoProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, ligaId) => FantasyRepo.mercadoAbierto(ligaId),
);

final valoracionProvider = FutureProvider.autoDispose.family<ValoracionJugador?, LigaMiembro>(
  (ref, k) => FantasyRepo.valoracion(k.ligaId, k.miembroId),
);

final historialPreciosProvider = FutureProvider.autoDispose.family<List<PuntoPrecio>, LigaMiembro>(
  (ref, k) => FantasyRepo.historialPrecios(k.ligaId, k.miembroId),
);

final clasificacionManagersProvider = FutureProvider.autoDispose.family<List<ClasManager>, String>(
  (ref, ligaId) => FantasyRepo.clasificacion(ligaId),
);

final encuestasAbiertasProvider = FutureProvider.autoDispose.family<List<Encuesta>, String>(
  (ref, ligaId) => FantasyRepo.encuestasAbiertas(ligaId),
);

/// Encuestas abiertas que el usuario aún no ha completado (los 6 atributos).
final encuestasPendientesProvider = FutureProvider.autoDispose.family<List<Encuesta>, LigaMiembro>((ref, k) async {
  final abiertas = await ref.watch(encuestasAbiertasProvider(k.ligaId).future);
  final pendientes = <Encuesta>[];
  for (final e in abiertas) {
    // En una mini-encuesta el propio sujeto no se evalúa.
    if (e.sujetoId == k.miembroId) continue;
    final hechos = await FantasyRepo.atributosEnviados(e.id, k.miembroId);
    if (hechos.length < Atributo.values.length) pendientes.add(e);
  }
  return pendientes;
});

/// Rating 0–100 del mercado por jugador (vacío si aún no hay mercado).
final ratingsMercadoProvider = FutureProvider.autoDispose.family<Map<String, double>, String>((ref, ligaId) async {
  try {
    return await FantasyRepo.ratings(ligaId);
  } catch (_) {
    return const {}; // mercado aún no desplegado: el balanceo usa su fórmula propia
  }
});

/// Próximo partido de la liga que todavía no se ha jugado (el de la alineación).
final proximoPartidoProvider = Provider.autoDispose.family<Partido?, String>((ref, ligaId) {
  final lista = ref.watch(partidosProvider(ligaId)).valueOrNull ?? const <Partido>[];
  final ahora = DateTime.now();
  final candidatos = lista
      .where((p) => p.estado.antesDeJugar && p.fechaHora.isAfter(ahora.subtract(const Duration(hours: 3))))
      .toList()
    ..sort((a, b) => a.fechaHora.compareTo(b.fechaHora));
  return candidatos.firstOrNull;
});

/// Partido más reciente en curso de liquidación (jugado pero aún sin puntos): el mercado sigue cerrado hasta que se cierre.
final partidoSinLiquidarProvider = Provider.autoDispose.family<Partido?, String>((ref, ligaId) {
  final lista = ref.watch(partidosProvider(ligaId)).valueOrNull ?? const <Partido>[];
  final pend = lista
      .where((p) =>
          p.estado == EstadoPartido.jugado ||
          p.estado == EstadoPartido.post_partido ||
          p.estado == EstadoPartido.en_revision)
      .toList()
    ..sort((a, b) => a.fechaHora.compareTo(b.fechaHora));
  return pend.firstOrNull;
});

/// Refresca todo lo del Fantasy tras comprar, vender o guardar.
void refrescarFantasy(WidgetRef ref, LigaMiembro k) {
  ref.invalidate(miManagerProvider(k));
  ref.invalidate(miPlantillaProvider(k));
  ref.invalidate(mercadoProvider(k.ligaId));
  ref.invalidate(mercadoAbiertoProvider(k.ligaId));
  ref.invalidate(clasificacionManagersProvider(k.ligaId));
}
