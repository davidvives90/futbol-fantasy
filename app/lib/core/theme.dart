import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Diseño visual: claro, premium y elegante (docs/diseno_visual.md).
///
/// Jerarquía de botones:
///  1 Principal ........ FilledButton (verde bosque) — una por pantalla
///  2 Premium .......... FilledButton(style: AppButtons.premium(context)) — dinero Fantasy / premios
///  3 Secundaria ....... OutlinedButton (borde verde)
///  4 Herramienta admin  FilledButton.tonal (verde claro)
///  5 Terciaria ........ TextButton
///  6 Destructiva ...... TextButton/OutlinedButton(style: AppButtons.peligro(context));
///                       en el diálogo de confirmación FilledButton(style: AppButtons.peligroRelleno(context))
class AppTheme {
  // ───────── Paleta ─────────
  static const fondo = Color(0xFFF6F5F1);
  static const tarjeta = Color(0xFFFFFFFF);
  static const contenedor = Color(0xFFEFEDE7);
  static const contenedorBajo = Color(0xFFF3F1EC);
  static const contenedorAlto = Color(0xFFE9E7E0);
  static const contenedorMasAlto = Color(0xFFE3E1D9);
  static const bordeSuave = Color(0xFFE4E1D8);
  static const borde = Color(0xFFA9B0AA);
  static const texto = Color(0xFF14201B);
  static const textoSecundario = Color(0xFF5E6A64);
  static const verde = Color(0xFF0E4B3A);
  static const verdeClaro = Color(0xFFDCEBE4);
  static const verdeOscuro = Color(0xFF0A3A2D);
  static const oro = Color(0xFFB8892E);
  static const sobreOro = Color(0xFF1E1606);
  static const oroClaro = Color(0xFFF4EAD3);
  static const rojo = Color(0xFFB3261E);
  static const rojoClaro = Color(0xFFF9E3E1);
  static const exito = Color(0xFF2E7D4F);
  static const aviso = Color(0xFFB7791F);
  static const equipo1 = Color(0xFF1F4E79);
  static const equipo2 = Color(0xFF8E2C2C);
  static const equipo3 = Color(0xFFB08A1E);
  static const equipo4 = Color(0xFF5B3F8C);

  static const _semilla = Color(0xFF1B8A3A);

  static const ColorScheme _esquemaClaro = ColorScheme(
    brightness: Brightness.light,
    primary: verde,
    onPrimary: Colors.white,
    primaryContainer: verdeClaro,
    onPrimaryContainer: verdeOscuro,
    secondary: Color(0xFF3F5A50),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE2E8E4),
    onSecondaryContainer: Color(0xFF1C2D26),
    tertiary: oro,
    onTertiary: sobreOro,
    tertiaryContainer: oroClaro,
    onTertiaryContainer: Color(0xFF4A3510),
    error: rojo,
    onError: Colors.white,
    errorContainer: rojoClaro,
    onErrorContainer: Color(0xFF5C1410),
    surface: fondo,
    onSurface: texto,
    onSurfaceVariant: textoSecundario,
    surfaceDim: Color(0xFFE2E0D9),
    surfaceBright: tarjeta,
    surfaceContainerLowest: tarjeta,
    surfaceContainerLow: contenedorBajo,
    surfaceContainer: contenedor,
    surfaceContainerHigh: contenedorAlto,
    surfaceContainerHighest: contenedorMasAlto,
    outline: borde,
    outlineVariant: bordeSuave,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF26302B),
    onInverseSurface: Color(0xFFF2F1EC),
    inversePrimary: Color(0xFF9FD0BB),
    surfaceTint: Colors.transparent,
  );

  static TextTheme _texto(TextTheme base, Color color) {
    final cuerpo = GoogleFonts.manropeTextTheme(base).apply(bodyColor: color, displayColor: color);
    TextStyle serif(TextStyle? s, double size, FontWeight w) =>
        GoogleFonts.fraunces(textStyle: s, fontSize: size, fontWeight: w, color: color, height: 1.15);
    return cuerpo.copyWith(
      displayLarge: serif(cuerpo.displayLarge, 52, FontWeight.w700),
      displayMedium: serif(cuerpo.displayMedium, 44, FontWeight.w700),
      displaySmall: serif(cuerpo.displaySmall, 36, FontWeight.w700),
      headlineLarge: serif(cuerpo.headlineLarge, 30, FontWeight.w600),
      headlineMedium: serif(cuerpo.headlineMedium, 26, FontWeight.w600),
      headlineSmall: serif(cuerpo.headlineSmall, 24, FontWeight.w600),
      titleLarge: serif(cuerpo.titleLarge, 20, FontWeight.w600),
      titleMedium: cuerpo.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: cuerpo.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: cuerpo.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: cuerpo.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      labelLarge: cuerpo.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
    );
  }

  static ThemeData claro() {
    const cs = _esquemaClaro;
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light, colorScheme: cs);
    final tt = _texto(base.textTheme, cs.onSurface);
    final radioBoton = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const tamBoton = Size(64, 48);
    final etiqueta = tt.labelLarge;

    return base.copyWith(
      scaffoldBackgroundColor: fondo,
      canvasColor: fondo,
      textTheme: tt,
      dividerColor: bordeSuave,
      dividerTheme: const DividerThemeData(color: bordeSuave, thickness: 1, space: 1),
      extensions: const [AppColores.claro],
      appBarTheme: AppBarTheme(
        backgroundColor: fondo,
        foregroundColor: texto,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: tt.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: tarjeta,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: bordeSuave),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: tamBoton,
          shape: radioBoton,
          textStyle: etiqueta,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: tamBoton,
          shape: radioBoton,
          foregroundColor: verde,
          side: const BorderSide(color: verde),
          textStyle: etiqueta,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: verde,
          shape: radioBoton,
          textStyle: etiqueta,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          textStyle: WidgetStatePropertyAll(etiqueta),
          shape: WidgetStatePropertyAll(radioBoton),
          side: const WidgetStatePropertyAll(BorderSide(color: bordeSuave)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? verdeClaro : tarjeta,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? verdeOscuro : texto,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: verde,
        foregroundColor: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: contenedor,
        selectedColor: verdeClaro,
        side: const BorderSide(color: bordeSuave),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: tt.labelMedium?.copyWith(color: texto),
        secondaryLabelStyle: tt.labelMedium?.copyWith(color: verdeOscuro),
        checkmarkColor: verdeOscuro,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tarjeta,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borde),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: verde, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: rojo),
        ),
        labelStyle: tt.bodyMedium?.copyWith(color: textoSecundario),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tarjeta,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: verdeClaro,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => tt.labelMedium?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? verdeOscuro : textoSecundario,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? verdeOscuro : textoSecundario),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tarjeta,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: tt.titleLarge,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: tarjeta,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF26302B),
        contentTextStyle: tt.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textoSecundario,
        titleTextStyle: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: tt.bodyMedium?.copyWith(color: textoSecundario),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: verdeOscuro,
        unselectedLabelColor: textoSecundario,
        indicatorColor: verde,
        dividerColor: bordeSuave,
        labelStyle: tt.labelLarge,
        unselectedLabelStyle: tt.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: verde, linearTrackColor: contenedor),
    );
  }

  /// Tema oscuro (secundario): el de siempre, desde semilla.
  static ThemeData oscuro() => ThemeData(
        colorSchemeSeed: _semilla,
        useMaterial3: true,
        brightness: Brightness.dark,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        extensions: const [AppColores.oscuro],
      );

  /// Color estable para el equipo n (1..4).
  static Color colorEquipo(int equipo) => switch (equipo) {
        1 => equipo1,
        2 => equipo2,
        3 => equipo3,
        _ => equipo4,
      };

  /// Estilo para cifras grandes (marcadores, puntos, precios, saldos): serif con cifras tabulares.
  static TextStyle numero(BuildContext context, {double size = 36, Color? color}) {
    final base = Theme.of(context).textTheme.displaySmall ?? const TextStyle();
    return base.copyWith(
      fontSize: size,
      color: color ?? base.color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Cifras tabulares sobre cualquier estilo (listas de precios, puntos).
  static TextStyle? tabular(TextStyle? s) =>
      s?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

/// Colores de estado y equipos que no están en el ColorScheme.
@immutable
class AppColores extends ThemeExtension<AppColores> {
  const AppColores({
    required this.exito,
    required this.aviso,
    required this.exitoClaro,
    required this.avisoClaro,
    required this.equipo1,
    required this.equipo2,
    required this.equipo3,
    required this.equipo4,
  });

  final Color exito;
  final Color aviso;
  final Color exitoClaro;
  final Color avisoClaro;
  final Color equipo1;
  final Color equipo2;
  final Color equipo3;
  final Color equipo4;

  static const claro = AppColores(
    exito: AppTheme.exito,
    aviso: AppTheme.aviso,
    exitoClaro: Color(0xFFDDEFE3),
    avisoClaro: Color(0xFFF6EAD6),
    equipo1: AppTheme.equipo1,
    equipo2: AppTheme.equipo2,
    equipo3: AppTheme.equipo3,
    equipo4: AppTheme.equipo4,
  );

  static const oscuro = AppColores(
    exito: Color(0xFF6FCF97),
    aviso: Color(0xFFF2C26B),
    exitoClaro: Color(0xFF1E3A2A),
    avisoClaro: Color(0xFF3A2E17),
    equipo1: Color(0xFF7FA8D6),
    equipo2: Color(0xFFD98A8A),
    equipo3: Color(0xFFE0C068),
    equipo4: Color(0xFFB39DDB),
  );

  /// Acceso cómodo: `AppColores.of(context).exito`.
  static AppColores of(BuildContext context) => Theme.of(context).extension<AppColores>() ?? claro;

  Color equipo(int n) => switch (n) {
        1 => equipo1,
        2 => equipo2,
        3 => equipo3,
        _ => equipo4,
      };

  @override
  AppColores copyWith({
    Color? exito,
    Color? aviso,
    Color? exitoClaro,
    Color? avisoClaro,
    Color? equipo1,
    Color? equipo2,
    Color? equipo3,
    Color? equipo4,
  }) =>
      AppColores(
        exito: exito ?? this.exito,
        aviso: aviso ?? this.aviso,
        exitoClaro: exitoClaro ?? this.exitoClaro,
        avisoClaro: avisoClaro ?? this.avisoClaro,
        equipo1: equipo1 ?? this.equipo1,
        equipo2: equipo2 ?? this.equipo2,
        equipo3: equipo3 ?? this.equipo3,
        equipo4: equipo4 ?? this.equipo4,
      );

  @override
  AppColores lerp(ThemeExtension<AppColores>? other, double t) {
    if (other is! AppColores) return this;
    return AppColores(
      exito: Color.lerp(exito, other.exito, t)!,
      aviso: Color.lerp(aviso, other.aviso, t)!,
      exitoClaro: Color.lerp(exitoClaro, other.exitoClaro, t)!,
      avisoClaro: Color.lerp(avisoClaro, other.avisoClaro, t)!,
      equipo1: Color.lerp(equipo1, other.equipo1, t)!,
      equipo2: Color.lerp(equipo2, other.equipo2, t)!,
      equipo3: Color.lerp(equipo3, other.equipo3, t)!,
      equipo4: Color.lerp(equipo4, other.equipo4, t)!,
    );
  }
}

/// Estilos de botón fuera de la jerarquía por defecto.
class AppButtons {
  /// Premium (dorado): mueve dinero Fantasy o da premio. Úsalo con FilledButton.
  static ButtonStyle premium(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(backgroundColor: cs.tertiary, foregroundColor: cs.onTertiary);
  }

  /// Destructiva (rojo) para TextButton / OutlinedButton.
  static ButtonStyle peligro(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton.styleFrom(foregroundColor: cs.error, side: BorderSide(color: cs.error));
  }

  /// Destructiva para TextButton (sin borde).
  static ButtonStyle peligroTexto(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton.styleFrom(foregroundColor: cs.error);
  }

  /// Botón final rojo del diálogo de confirmación de una acción destructiva (FilledButton).
  static ButtonStyle peligroRelleno(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError);
  }

  /// SegmentedButton Voy / Duda / No voy: el segmento seleccionado toma el color de su estado
  /// (Voy = éxito, Duda = aviso, No voy = gris neutro; no es destructivo).
  static ButtonStyle segmentoEstado(BuildContext context, String? seleccionado) {
    final cs = Theme.of(context).colorScheme;
    final c = AppColores.of(context);
    final (fondo, texto) = switch (seleccionado) {
      'confirmado' || 'espera' => (c.exito, Colors.white),
      'duda' => (c.aviso, Colors.white),
      'baja' => (cs.surfaceContainerHighest, cs.onSurface),
      _ => (cs.primaryContainer, cs.onPrimaryContainer),
    };
    return SegmentedButton.styleFrom(
      selectedBackgroundColor: fondo,
      selectedForegroundColor: texto,
      backgroundColor: cs.surfaceContainerLowest,
    );
  }
}
