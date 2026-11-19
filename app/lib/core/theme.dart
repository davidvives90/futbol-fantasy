import 'package:flutter/material.dart';

class AppTheme {
  static const _semilla = Color(0xFF1B8A3A);

  static ThemeData claro() => ThemeData(
        colorSchemeSeed: _semilla,
        useMaterial3: true,
        brightness: Brightness.light,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      );

  static ThemeData oscuro() => ThemeData(
        colorSchemeSeed: _semilla,
        useMaterial3: true,
        brightness: Brightness.dark,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      );

  /// Color estable para el equipo n (1..4).
  static Color colorEquipo(int equipo) => switch (equipo) {
        1 => Colors.blue,
        2 => Colors.red,
        3 => Colors.amber.shade700,
        _ => Colors.purple,
      };
}
