import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/liga_activa.dart';
import '../core/supabase.dart';
import 'models.dart';
import 'repos/caja_repo.dart';
import 'repos/ligas_repo.dart';
import 'repos/partidos_repo.dart';
import 'repos/stats_repo.dart';

/// Cambios de sesión (login, logout, refresco de token).
final authStateProvider = StreamProvider<AuthState>((ref) => sb.auth.onAuthStateChange);

/// Id del usuario actual; se recalcula al cambiar la sesión.
final uidProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return uidActual;
});

final miPerfilProvider = FutureProvider<Perfil?>((ref) async {
  if (ref.watch(uidProvider) == null) return null;
  return LigasRepo.miPerfil();
});

final misLigasProvider = FutureProvider<List<MiLiga>>((ref) async {
  if (ref.watch(uidProvider) == null) return [];
  return LigasRepo.misLigas();
});

/// Liga seleccionada (la persistida si sigue siendo válida; si no, la primera).
final ligaActualProvider = Provider<MiLiga?>((ref) {
  final ligas = ref.watch(misLigasProvider).valueOrNull ?? const <MiLiga>[];
  if (ligas.isEmpty) return null;
  final id = ref.watch(ligaActivaIdProvider);
  return ligas.where((l) => l.liga.id == id).firstOrNull ?? ligas.first;
});

/// Miembros de una liga (todos los estados), para resolver nombres.
final miembrosProvider = FutureProvider.autoDispose.family<List<Miembro>, String>(
  (ref, ligaId) => LigasRepo.miembros(ligaId),
);

/// Atajo: miembroId → Miembro.
final miembrosPorIdProvider = Provider.autoDispose.family<Map<String, Miembro>, String>((ref, ligaId) {
  final lista = ref.watch(miembrosProvider(ligaId)).valueOrNull ?? const <Miembro>[];
  return {for (final m in lista) m.id: m};
});

final partidosProvider = FutureProvider.autoDispose.family<List<Partido>, String>(
  (ref, ligaId) => PartidosRepo.partidos(ligaId),
);

final partidoProvider = StreamProvider.autoDispose.family<Partido?, String>(
  (ref, partidoId) => PartidosRepo.partidoStream(partidoId),
);

final convocatoriaProvider = StreamProvider.autoDispose.family<List<Inscripcion>, String>(
  (ref, partidoId) => PartidosRepo.convocatoriaStream(partidoId),
);

/// Convocatoria para tarjetas de listas (Partidos, agenda de Inicio): una consulta, sin canal de tiempo real.
final convocatoriaResumenProvider = FutureProvider.autoDispose.family<List<Inscripcion>, String>(
  (ref, partidoId) => PartidosRepo.convocatoria(partidoId),
);

final rendimientoProvider = FutureProvider.autoDispose.family<List<Rendimiento>, String>(
  (ref, ligaId) => StatsRepo.rendimiento(ligaId),
);

final saldosProvider = FutureProvider.autoDispose.family<List<Saldo>, String>(
  (ref, ligaId) => CajaRepo.saldos(ligaId),
);

final aspectosActivosProvider = FutureProvider.autoDispose.family<List<Aspecto>, String>(
  (ref, ligaId) => LigasRepo.aspectos(ligaId, soloActivos: true),
);

/// Refresca todo lo que depende de las ligas del usuario.
void refrescarLigas(WidgetRef ref) {
  ref.invalidate(misLigasProvider);
  ref.invalidate(miPerfilProvider);
}
