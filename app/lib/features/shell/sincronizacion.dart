import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../caja/caja_screen.dart';
import '../equipos/prediccion_card.dart';
import '../fantasy/fantasy_providers.dart';
import '../fantasy/subastas_draft.dart';
import '../fantasy/tarjetas_jugador.dart';
import '../partidos/agenda.dart';
import '../porra/porra_tab.dart';

/// 0062 · Sincronización en tiempo real: «adiós a cerrar y abrir la app».
///
/// Un canal por liga y otro por partido abierto. Los datos se siguen cargando por la API normal; el canal solo
/// avisa de QUÉ tabla cambió y se invalidan los datos afectados en todos los móviles conectados. Si el canal cae
/// (segundo plano, cobertura, arranque en frío del servidor), se reintenta solo y al volver se recarga todo.
///
/// [latidoProvider] es un contador por clave ('liga:<id>:fantasy', 'partido:<id>'): los datos privados de una
/// pantalla lo observan con `ref.watch(latidoProvider(...))` para recargarse con cada cambio.
final latidoProvider = StateProvider.family<int, String>((ref, clave) => 0);

int _n = 0;

/// Canal de avisos de cambios con reintentos, recarga al volver a la app y un respaldo periódico opcional.
class _Canal {
  _Canal(this.nombre, this.tablas, this.alCambiar, {this.respaldo});
  final String nombre;

  /// (tabla, columna del filtro o null, valor)
  final List<(String, String?, String)> tablas;
  final void Function(String tabla, Map<String, dynamic> fila) alCambiar;
  final Duration? respaldo;

  RealtimeChannel? _canal;
  Timer? _reintento, _periodico;
  AppLifecycleListener? _ciclo;
  int _intentos = 0;
  bool _cerrado = false;

  void abrir() {
    _suscribir();
    _ciclo = AppLifecycleListener(onResume: () {
      alCambiar('*', const {});
      _suscribir();
    });
    if (respaldo != null) _periodico = Timer.periodic(respaldo!, (_) => alCambiar('*', const {}));
  }

  void _suscribir() {
    if (_cerrado) return;
    final viejo = _canal;
    if (viejo != null) unawaited(sb.removeChannel(viejo));
    var c = sb.channel('sync:$nombre:${_n++}');
    for (final (tabla, columna, valor) in tablas) {
      c = c.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: tabla,
        filter: columna == null ? null : PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: columna, value: valor),
        callback: (p) => alCambiar(tabla, p.newRecord.isNotEmpty ? p.newRecord : p.oldRecord),
      );
    }
    _canal = c.subscribe((estado, _) {
      if (_cerrado) return;
      if (estado == RealtimeSubscribeStatus.subscribed) {
        if (_intentos > 0) alCambiar('*', const {}); // lo que cambió mientras no había canal
        _intentos = 0;
      } else if (estado == RealtimeSubscribeStatus.channelError || estado == RealtimeSubscribeStatus.timedOut) {
        _intentos++;
        _reintento?.cancel();
        _reintento = Timer(Duration(seconds: (1 << _intentos.clamp(1, 5)).clamp(2, 60)), _suscribir);
      }
    });
  }

  Future<void> cerrar() async {
    _cerrado = true;
    _reintento?.cancel();
    _periodico?.cancel();
    _ciclo?.dispose();
    final c = _canal;
    _canal = null;
    if (c != null) await sb.removeChannel(c);
  }
}

/// Agrupa varios avisos seguidos (p. ej. al hacer equipos cambian 10 filas) en una sola recarga.
class _Agrupador {
  final _pendientes = <String>{};
  Timer? _t;
  void avisar(String clave, void Function(Set<String>) aplicar) {
    _pendientes.add(clave);
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), () {
      final s = {..._pendientes};
      _pendientes.clear();
      aplicar(s);
    });
  }

  void cancelar() => _t?.cancel();
}

/// Escucha todas mis ligas mientras la app está abierta (va dentro de HomeShell).
class SincronizacionLigas extends ConsumerStatefulWidget {
  const SincronizacionLigas({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SincronizacionLigas> createState() => _SincronizacionLigasState();
}

class _SincronizacionLigasState extends ConsumerState<SincronizacionLigas> {
  final _canales = <String, _Canal>{};
  final _agrupador = _Agrupador();

  static const _fantasy = {'fichas', 'mercado_jugador', 'fantasy_managers', 'subastas', 'transacciones_fantasy', 'ofertas', 'cesiones'};

  void _aplicar(String ligaId, Set<String> tablas) {
    if (!mounted) return;
    final todo = tablas.contains('*');
    bool hay(Iterable<String> t) => todo || t.any(tablas.contains);
    if (hay(['partidos'])) {
      ref.invalidate(partidosProvider(ligaId));
      ref.invalidate(agendaProvider);
      ref.invalidate(convocatoriaResumenProvider);
      ref.invalidate(porraProvider); // al hacer equipos la porra se abre sola en todos los móviles
      ref.invalidate(prediccionProvider);
      ref.invalidate(mercadoAbiertoProvider(ligaId));
    }
    if (hay(['miembros'])) {
      ref.invalidate(miembrosProvider(ligaId));
      ref.invalidate(rendimientoProvider(ligaId));
    }
    if (hay(['ligas', 'miembros']) && (todo || tablas.contains('ligas') || tablas.contains('miembros:yo'))) {
      ref.invalidate(misLigasProvider);
    }
    if (hay(_fantasy)) {
      ref.invalidate(mercadoProvider(ligaId));
      ref.invalidate(miPlantillaProvider);
      ref.invalidate(miManagerProvider);
      ref.invalidate(subastasProvider(ligaId));
      ref.invalidate(draftProvider(ligaId));
      ref.invalidate(resumenFantasyProvider(ligaId));
      ref.invalidate(clasificacionManagersProvider(ligaId));
      ref.invalidate(fichasJugadorProvider);
      ref.invalidate(valoracionProvider);
      ref.invalidate(historialPreciosProvider);
      ref.invalidate(misOfertasProvider(ligaId));
      ref.invalidate(cesionesDisponiblesProvider(ligaId));
      ref.read(latidoProvider('liga:$ligaId:fantasy').notifier).state++;
    }
    if (hay(['apuestas', 'quinielas'])) ref.invalidate(porraProvider);
    if (hay(['movimientos', 'avisos_pago'])) {
      ref.invalidate(saldosProvider(ligaId));
      ref.invalidate(avisosPagoProvider(ligaId));
    }
    ref.read(latidoProvider('liga:$ligaId').notifier).state++;
  }

  void _sincronizar(List<String> ids) {
    for (final id in _canales.keys.toList()) {
      if (!ids.contains(id)) unawaited(_canales.remove(id)!.cerrar());
    }
    for (final id in ids) {
      if (_canales.containsKey(id)) continue;
      final uid = sb.auth.currentUser?.id;
      final c = _Canal(
        'liga:$id',
        [
          ('ligas', 'id', id),
          for (final t in ['partidos', 'miembros', 'apuestas', 'quinielas', 'movimientos', 'avisos_pago', ..._fantasy])
            (t, 'liga_id', id),
        ],
        (tabla, fila) => _agrupador.avisar(
          tabla == 'miembros' && fila['perfil_id'] == uid ? 'miembros:yo' : tabla,
          (s) => _aplicar(id, s.contains('miembros:yo') ? {...s, 'miembros'} : s),
        ),
      )..abrir();
      _canales[id] = c;
    }
  }

  @override
  void dispose() {
    _agrupador.cancelar();
    for (final c in _canales.values) {
      unawaited(c.cerrar());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ids = <String>[for (final l in ref.watch(misLigasProvider).valueOrNull ?? const <MiLiga>[]) l.liga.id];
    _sincronizar(ids);
    return widget.child;
  }
}

/// Escucha un partido mientras su pantalla está abierta: convocatoria, equipos, acta, valoraciones y porra.
class SincronizacionPartido extends ConsumerStatefulWidget {
  const SincronizacionPartido({super.key, required this.partidoId, required this.child});
  final String partidoId;
  final Widget child;

  @override
  ConsumerState<SincronizacionPartido> createState() => _SincronizacionPartidoState();
}

class _SincronizacionPartidoState extends ConsumerState<SincronizacionPartido> {
  _Canal? _canal;
  final _agrupador = _Agrupador();

  @override
  void initState() {
    super.initState();
    final id = widget.partidoId;
    _canal = _Canal(
      'partido:$id',
      [
        for (final t in ['convocatorias', 'encuentros', 'acta_jugador', 'reportes_encuentro', 'puntos_fantasy',
                         'disputas', 'apuestas', 'quinielas', 'valoraciones'])
          (t, 'partido_id', id),
        ('partidos', 'id', id),
      ],
      (tabla, _) => _agrupador.avisar(tabla, (_) {
        if (!mounted) return;
        ref.invalidate(convocatoriaResumenProvider(id));
        ref.invalidate(porraProvider(id));
        ref.invalidate(prediccionProvider(id));
        ref.read(latidoProvider('partido:$id').notifier).state++;
      }),
      // Los votos de los demás no llegan por el canal (son privados): se recuenta cada 30 s
      respaldo: const Duration(seconds: 30),
    )..abrir();
  }

  @override
  void dispose() {
    _agrupador.cancelar();
    unawaited(_canal?.cerrar());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Deslizar hacia abajo para recargar todo lo del partido (por si acaso: normalmente ya llega solo).
class RefrescarPartido extends ConsumerWidget {
  const RefrescarPartido({super.key, required this.partidoId, required this.child});
  final String partidoId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(partidoProvider(partidoId));
          ref.invalidate(convocatoriaProvider(partidoId));
          ref.invalidate(convocatoriaResumenProvider(partidoId));
          ref.invalidate(porraProvider(partidoId));
          ref.invalidate(prediccionProvider(partidoId));
          ref.read(latidoProvider('partido:$partidoId').notifier).state++;
          await Future<void>.delayed(const Duration(milliseconds: 600));
        },
        child: child,
      );
}
