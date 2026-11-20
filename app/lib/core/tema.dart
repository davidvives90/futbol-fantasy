import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'liga_activa.dart';

const _clave = 'tema_app';

/// Apariencia elegida en Perfil → Opciones. Por defecto, la del móvil (claro u oscuro automático).
class TemaNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => switch (ref.watch(prefsProvider).getString(_clave)) {
        'oscuro' => ThemeMode.dark,
        'claro' => ThemeMode.light,
        _ => ThemeMode.system,
      };

  Future<void> elegir(ThemeMode modo) async {
    state = modo;
    await ref.read(prefsProvider).setString(
          _clave,
          switch (modo) { ThemeMode.dark => 'oscuro', ThemeMode.system => 'sistema', _ => 'claro' },
        );
  }
}

final temaProvider = NotifierProvider<TemaNotifier, ThemeMode>(TemaNotifier.new);
