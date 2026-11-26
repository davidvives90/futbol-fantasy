import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';

int _canales = 0;

/// Dato «en vivo» a prueba de fallos del tiempo real.
///
/// Antes se usaba `.stream()` de Supabase, que carga y escucha por el mismo canal: si el canal tarda en
/// unirse (el servidor de tiempo real de Supabase arranca en frío cuando nadie lo usaba) o se cae al volver
/// de segundo plano, el stream da error y la pantalla pedía «Reintentar». Ahora:
///  · los datos se cargan por la API normal (siempre responde),
///  · el canal de tiempo real solo avisa de que algo cambió y se recarga; si falla, se reintenta solo,
///  · al volver a la app y cada [respaldo] se recarga igualmente, por si se perdió algún aviso.
/// Solo se muestra un error si no se pudo cargar nunca.
Stream<T> datoVivo<T>({
  required Future<T> Function() cargar,
  required String tabla,
  required String columna,
  required String valor,
  Duration respaldo = const Duration(seconds: 45),
}) {
  late StreamController<T> ctrl;
  RealtimeChannel? canal;
  Timer? temporizador;
  Timer? reintento;
  Timer? espera;
  AppLifecycleListener? ciclo;
  var cargado = false;
  var cerrado = false;
  var cargando = false;
  var pendiente = false;
  var intentos = 0;

  Future<void> recargar() async {
    if (cerrado) return;
    if (cargando) {
      pendiente = true;
      return;
    }
    cargando = true;
    try {
      final v = await cargar();
      if (!cerrado) {
        cargado = true;
        ctrl.add(v);
      }
    } catch (e, st) {
      // Con datos ya mostrados, un fallo puntual (p. ej. sin cobertura) no tapa la pantalla.
      if (!cerrado && !cargado) ctrl.addError(e, st);
    } finally {
      cargando = false;
      if (pendiente && !cerrado) {
        pendiente = false;
        unawaited(recargar());
      }
    }
  }

  // Varios cambios seguidos (p. ej. al hacer equipos) → una sola recarga
  void avisar() {
    espera?.cancel();
    espera = Timer(const Duration(milliseconds: 250), recargar);
  }

  void suscribir() {
    if (cerrado) return;
    final viejo = canal;
    if (viejo != null) unawaited(sb.removeChannel(viejo));
    canal = sb
        .channel('vivo:$tabla:$valor:${_canales++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: tabla,
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: columna, value: valor),
          callback: (_) => avisar(),
        )
        .subscribe((estado, error) {
      if (cerrado) return;
      if (estado == RealtimeSubscribeStatus.subscribed) {
        // Lo que cambiase mientras el canal se unía
        if (intentos > 0) avisar();
        intentos = 0;
      } else if (estado == RealtimeSubscribeStatus.channelError || estado == RealtimeSubscribeStatus.timedOut) {
        // Reintento con espera creciente (2, 4, 8… hasta 60 s), sin molestar al usuario
        intentos++;
        reintento?.cancel();
        final s = (1 << intentos.clamp(1, 5)).clamp(2, 60);
        reintento = Timer(Duration(seconds: s), suscribir);
      }
    });
  }

  ctrl = StreamController<T>(
    onListen: () {
      unawaited(recargar());
      suscribir();
      temporizador = Timer.periodic(respaldo, (_) => recargar());
      ciclo = AppLifecycleListener(onResume: () {
        unawaited(recargar());
        suscribir(); // el canal puede haberse caído en segundo plano
      });
    },
    onCancel: () async {
      cerrado = true;
      temporizador?.cancel();
      reintento?.cancel();
      espera?.cancel();
      ciclo?.dispose();
      final c = canal;
      canal = null;
      if (c != null) await sb.removeChannel(c);
    },
  );
  return ctrl.stream;
}
