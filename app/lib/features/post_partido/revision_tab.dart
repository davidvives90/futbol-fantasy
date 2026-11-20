import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';
import '../../data/repos/post_partido_repo.dart';
import '../../core/info.dart';
import '../../core/equipaciones.dart';

final _disputasProvider = FutureProvider.autoDispose.family<List<Disputa>, String>(
  (ref, partidoId) => PostPartidoRepo.disputas(partidoId),
);

final _encuentrosProvider = FutureProvider.autoDispose.family<List<Encuentro>, String>(
  (ref, partidoId) => PartidosRepo.encuentros(partidoId),
);

const _nombresCampo = {
  'goles': 'goles',
  'asistencias': 'asistencias',
  'autogoles': 'autogoles',
  'porteria_cero': 'portería a cero',
  'paradas_clave': 'paradas clave',
  'penaltis_parados': 'penaltis parados',
  'penaltis_fallados': 'penaltis fallados',
  'goles_local': 'goles del local',
  'goles_visitante': 'goles del visitante',
};

/// Revisión del admin: cruza los partes, resuelve disputas y cierra el partido.
class RevisionTab extends ConsumerWidget {
  const RevisionTab({super.key, required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  void _refrescar(WidgetRef ref) {
    ref.invalidate(_disputasProvider(partido.id));
    ref.invalidate(_encuentrosProvider(partido.id));
  }

  /// Equipo de un descuadre a partir del campo `goles_equipo_<n>`.
  static int? _equipoDescuadre(Disputa d) => int.tryParse((d.campo ?? '').replaceFirst('goles_equipo_', ''));

  /// v0.3: el admin corrige los goles de los jugadores (y, si hace falta, el marcador) hasta que cuadren.
  Future<void> _corregirDescuadre(BuildContext context, WidgetRef ref, Disputa d) async {
    final equipo = _equipoDescuadre(d);
    final conv = ref.read(convocatoriaProvider(partido.id)).valueOrNull ?? const <Inscripcion>[];
    final List<Encuentro> encuentros;
    final Map<String, Map<String, dynamic>> acta;
    try {
      acta = await PostPartidoRepo.acta(partido.id);
      encuentros = await PartidosRepo.encuentros(partido.id);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
      return;
    }
    if (!context.mounted) return;
    final miembros = ref.read(miembrosPorIdProvider(mi.liga.id));

    final jugadores = conv
        .where((i) => i.estado == EstadoInscripcion.confirmado && i.equipo != null && (equipo == null || i.equipo == equipo))
        .toList();
    final goles = {for (final j in jugadores) j.miembroId: toInt(acta[j.miembroId]?['goles'])};
    final originalGoles = Map<String, int>.from(goles);
    // Marcadores editables de los encuentros de ese equipo.
    final marcador = <(int, String), int>{
      for (final e in encuentros)
        if (equipo == null || e.equipoLocal == equipo || e.equipoVisitante == equipo) ...{
          (e.n, 'goles_local'): e.golesLocal,
          (e.n, 'goles_visitante'): e.golesVisitante,
        },
    };
    final originalMarcador = Map<(int, String), int>.from(marcador);

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          Widget contador(int valor, ValueChanged<int> set) => Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: valor > 0 ? () => setD(() => set(valor - 1)) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(width: 22, child: Text('$valor', textAlign: TextAlign.center)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setD(() => set(valor + 1)),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]);
          final suma = goles.values.fold<int>(0, (a, g) => a + g);
          return AlertDialog(
            title: Text(equipo == null ? 'Corregir goles' : 'Corregir goles del equipo $equipo'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(shrinkWrap: true, children: [
                Text('Suma de goles de los jugadores: $suma'),
                const SizedBox(height: 8),
                for (final e in encuentros.where((e) => marcador.containsKey((e.n, 'goles_local'))))
                  Row(children: [
                    Expanded(child: Text('E${e.equipoLocal} – E${e.equipoVisitante}')),
                    contador(marcador[(e.n, 'goles_local')]!, (v) => marcador[(e.n, 'goles_local')] = v),
                    const Text('-'),
                    contador(marcador[(e.n, 'goles_visitante')]!, (v) => marcador[(e.n, 'goles_visitante')] = v),
                  ]),
                const Divider(),
                for (final j in jugadores)
                  Row(children: [
                    Expanded(child: Text(miembros[j.miembroId]?.nombre ?? '…', overflow: TextOverflow.ellipsis)),
                    contador(goles[j.miembroId]!, (v) => goles[j.miembroId] = v),
                  ]),
                const SizedBox(height: 8),
                const Text('Los autogoles del rival también cuentan para este equipo.', style: TextStyle(fontSize: 12)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;

    final ejecutado = await ejecutar(context, () async {
      for (final e in marcador.entries) {
        if (originalMarcador[e.key] != e.value) {
          await PostPartidoRepo.fijarDato(partidoId: partido.id, n: e.key.$1, campo: e.key.$2, valor: e.value);
        }
      }
      for (final g in goles.entries) {
        if (originalGoles[g.key] != g.value) {
          await PostPartidoRepo.fijarDato(partidoId: partido.id, sujetoId: g.key, campo: 'goles', valor: g.value);
        }
      }
    }, ok: 'Datos corregidos');
    if (ejecutado) {
      _refrescar(ref);
      ref.invalidate(rendimientoProvider(mi.liga.id));
    }
  }

  /// Los valores llegan como texto ('2', '3'); resolver_disputa espera un smallint.
  int _aNumero(String v) => int.tryParse(v) ?? num.tryParse(v)?.round() ?? 0;

  String _verValor(String campo, String v) => v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputas = ref.watch(_disputasProvider(partido.id));
    // Mantiene viva la convocatoria (equipos) para poder corregir descuadres.
    ref.watch(convocatoriaProvider(partido.id));
    final encuentros = ref.watch(_encuentrosProvider(partido.id)).valueOrNull ?? const <Encuentro>[];
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));

    return RefreshIndicator(
      onRefresh: () async => _refrescar(ref),
      child: disputas.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => _refrescar(ref)),
        data: (lista) {
          final pendientes = lista.where((d) => !d.resuelta).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
              'Cada asistente ha enviado su parte. Al cruzarlos, lo que coincide en la mayoría se da por bueno '
              'y lo que no, aparece aquí como disputa para que lo decidas.',
            ),
            const SizedBox(height: 12),
            // Solo durante el plazo: cierra la ventana, consolida y, si no hay disputas, puntúa.
            if (partido.estado == EstadoPartido.post_partido)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Cerrar plazo y cruzar partes'),
                onPressed: () async {
                  await ejecutar(context, () => PartidosRepo.cerrarPostPartido(partido.id), ok: 'Partes cruzados');
                  _refrescar(ref);
                  ref.invalidate(rendimientoProvider(mi.liga.id));
                },
              ),
            if (encuentros.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(children: [
                Text('Resultado consolidado', style: Theme.of(context).textTheme.titleSmall),
                const InfoBoton(Ayuda.disputas),
              ]),
              for (final e in encuentros)
                ListTile(
                  dense: true,
                  title: Text('${nombreEquipo(context, e.equipoLocal)} ${e.golesLocal} - ${e.golesVisitante} ${nombreEquipo(context, e.equipoVisitante)}'),
                  subtitle: e.confianza == null ? null : Text('Coincidencia ${e.confianza!.round()} %'),
                  trailing: e.enDisputa
                      ? Icon(Icons.warning_amber, color: AppColores.of(context).aviso)
                      : Icon(Icons.check, color: AppColores.of(context).exito),
                ),
            ],
            const SizedBox(height: 16),
            Text('Disputas pendientes (${pendientes.length})', style: Theme.of(context).textTheme.titleSmall),
            if (pendientes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No hay disputas: los datos cuadran.'),
              ),
            for (final d in pendientes.where((d) => d.tipo == 'descuadre'))
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _equipoDescuadre(d) == null
                          ? 'Los goles no cuadran con el resultado'
                          : 'Equipo ${_equipoDescuadre(d)}: los goles no cuadran con el resultado',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text('Resultado: ${d.valores['resultado'] ?? '?'} · '
                        'suma de goles de los jugadores: ${d.valores['suma_jugadores'] ?? '?'}'),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.edit),
                      label: const Text('Corregir datos'),
                      onPressed: () => _corregirDescuadre(context, ref, d),
                    ),
                  ]),
                ),
              ),
            for (final d in pendientes.where((d) => d.tipo != 'descuadre'))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      d.tipo == 'encuentro'
                          ? 'Encuentro #${d.n ?? 1}: ${_nombresCampo[d.campo] ?? d.campo}'
                          : '${miembros[d.sujetoId]?.nombre ?? '…'}: ${_nombresCampo[d.campo] ?? d.campo}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text('Votos de los asistentes (toca el valor correcto):'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final v in (d.valores.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                        ActionChip(
                          label: Text('${_verValor(d.campo ?? '', v.key)}  ·  ${v.value} voto${v.value == 1 ? '' : 's'}'),
                          onPressed: () async {
                            final ok = await ejecutar(
                              context,
                              () => PostPartidoRepo.resolverDisputa(d.id, _aNumero(v.key)),
                              ok: 'Disputa resuelta',
                            );
                            if (ok) {
                              _refrescar(ref);
                              ref.invalidate(rendimientoProvider(mi.liga.id));
                            }
                          },
                        ),
                    ]),
                  ]),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.emoji_events),
              label: const Text('Cerrar partido y calcular puntos'),
              // Respaldo: al resolver la última disputa los puntos ya se calculan solos.
              onPressed: pendientes.isNotEmpty || encuentros.isEmpty || partido.estado != EstadoPartido.en_revision
                  ? null
                  : () async {
                      if (!await confirmar(context, 'Cerrar partido',
                          'Se calcularán los puntos Fantasy con el acta consolidada y las valoraciones.')) {
                        return;
                      }
                      if (context.mounted) {
                        await ejecutar(context, () => PartidosRepo.calcularPuntos(partido.id), ok: 'Puntos calculados');
                      }
                      ref.invalidate(rendimientoProvider(mi.liga.id));
                    },
            ),
            if (pendientes.isNotEmpty || encuentros.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Primero cruza los partes y resuelve las disputas.', textAlign: TextAlign.center),
              ),
          ]);
        },
      ),
    );
  }
}
