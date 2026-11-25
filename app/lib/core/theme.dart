import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Diseño visual: claro, premium y elegante (docs/diseno_visual.md).
///
/// Jerarquía de botones:
///  1 Principal ........ FilledButton (rojo Pachanga) — una por pantalla
///  2 Premium .......... FilledButton(style: AppButtons.premium(context)) — dinero Fantasy / premios
///  3 Secundaria ....... OutlinedButton (borde rojo)
///  4 Herramienta admin  FilledButton.tonal (rojo claro)
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
  static const bordeSuave = Color(0xFFE7E1DE);
  static const borde = Color(0xFFB3A9AA);
  static const texto = Color(0xFF1C1617);
  // Gris secundario con contraste ≥ 7:1 sobre el fondo claro (textos pequeños legibles al sol)
  static const textoSecundario = Color(0xFF524849);
  /// Colores del logo de Pachanga Fantasy: rojo #E2162A y oro #F2A229.
  static const marca = Color(0xFFE2162A);
  static const oroMarca = Color(0xFFF2A229);
  // Rojo de botones y enlaces: el del logo, un punto más oscuro para que el texto blanco se lea bien (5,9:1).
  static const verde = Color(0xFFC8102E); // nombre heredado: es el color principal
  static const verdeClaro = Color(0xFFFDE3E5);
  static const verdeOscuro = Color(0xFF5E0712);
  static const oro = Color(0xFFC4861A);
  static const sobreOro = Color(0xFF1E1606);
  static const oroClaro = Color(0xFFFBEBCB);
  // Errores y acciones peligrosas: granate, distinto del rojo de la marca
  static const rojo = Color(0xFF8C1D18);
  static const rojoClaro = Color(0xFFF6DEDB);
  static const exito = Color(0xFF2E7D4F);
  static const aviso = Color(0xFFB7791F);
  static const equipo1 = Color(0xFF1F4E79);
  static const equipo2 = Color(0xFF8E2C2C);
  static const equipo3 = Color(0xFFB08A1E);
  static const equipo4 = Color(0xFF5B3F8C);

  static const ColorScheme _esquemaClaro = ColorScheme(
    brightness: Brightness.light,
    primary: verde,
    onPrimary: Colors.white,
    primaryContainer: verdeClaro,
    onPrimaryContainer: verdeOscuro,
    secondary: Color(0xFF5A4F50),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF0E6E6),
    onSecondaryContainer: Color(0xFF2A1E1F),
    tertiary: oro,
    onTertiary: sobreOro,
    tertiaryContainer: oroClaro,
    onTertiaryContainer: Color(0xFF4A3008),
    error: rojo,
    onError: Colors.white,
    errorContainer: rojoClaro,
    onErrorContainer: Color(0xFF5C1410),
    surface: fondo,
    onSurface: texto,
    onSurfaceVariant: textoSecundario,
    surfaceDim: Color(0xFFE5E0DC),
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
    inverseSurface: Color(0xFF2E2627),
    onInverseSurface: Color(0xFFF5EFEE),
    inversePrimary: Color(0xFFFFB3B8),
    surfaceTint: Colors.transparent,
  );

  /// Tipografía: Figtree (sans moderna, humanista y muy legible; menos vista que Open Sans o Roboto).
  /// Títulos en peso alto con interletraje ligeramente cerrado; cuerpo regular.
  static TextTheme _texto(TextTheme base, Color color) {
    final t = GoogleFonts.figtreeTextTheme(base).apply(bodyColor: color, displayColor: color);
    TextStyle titulo(TextStyle? s, double size, FontWeight w, {double ls = -0.4}) =>
        (s ?? const TextStyle()).copyWith(fontSize: size, fontWeight: w, letterSpacing: ls, height: 1.15, color: color);
    return t.copyWith(
      displayLarge: titulo(t.displayLarge, 52, FontWeight.w800, ls: -1.2),
      displayMedium: titulo(t.displayMedium, 44, FontWeight.w800, ls: -1.0),
      displaySmall: titulo(t.displaySmall, 36, FontWeight.w800, ls: -0.8),
      headlineLarge: titulo(t.headlineLarge, 30, FontWeight.w800, ls: -0.6),
      headlineMedium: titulo(t.headlineMedium, 26, FontWeight.w700, ls: -0.5),
      headlineSmall: titulo(t.headlineSmall, 23, FontWeight.w700),
      titleLarge: titulo(t.titleLarge, 20, FontWeight.w700, ls: -0.2),
      titleMedium: t.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      titleSmall: t.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w400, height: 1.4),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w400, height: 1.4),
      // Textos pequeños: nunca por debajo de 13 / 12 px
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w400, height: 1.35),
      labelSmall: t.labelSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
      labelLarge: t.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.1),
    );
  }


  /// Modo oscuro premium: carbón cálido, rojo claro de la marca y oro (mismo lenguaje que el claro).
  static const fondoOscuro = Color(0xFF141112);
  static const tarjetaOscura = Color(0xFF1E1A1B);

  static const ColorScheme _esquemaOscuro = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFF8A92),
    onPrimary: Color(0xFF5E0712),
    primaryContainer: Color(0xFF7A1020),
    onPrimaryContainer: Color(0xFFFFDADC),
    secondary: Color(0xFFD8C2C3),
    onSecondary: Color(0xFF3B2D2E),
    secondaryContainer: Color(0xFF4A3A3B),
    onSecondaryContainer: Color(0xFFF2DEDF),
    tertiary: Color(0xFFF2B54A),
    onTertiary: Color(0xFF2B1F05),
    tertiaryContainer: Color(0xFF4A3814),
    onTertiaryContainer: Color(0xFFF6E4BE),
    error: Color(0xFFF2A59E),
    onError: Color(0xFF5C1410),
    errorContainer: Color(0xFF6B1E18),
    onErrorContainer: Color(0xFFF9DEDB),
    surface: fondoOscuro,
    onSurface: Color(0xFFEDE6E6),
    onSurfaceVariant: Color(0xFFBBAFB0),
    surfaceDim: Color(0xFF0F0D0D),
    surfaceBright: Color(0xFF3A3233),
    surfaceContainerLowest: Color(0xFF0F0D0D),
    surfaceContainerLow: Color(0xFF1A1617),
    surfaceContainer: Color(0xFF221D1E),
    surfaceContainerHigh: Color(0xFF2B2526),
    surfaceContainerHighest: Color(0xFF342D2E),
    outline: Color(0xFF8A7F80),
    outlineVariant: Color(0xFF3A3233),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFEDE6E6),
    onInverseSurface: Color(0xFF231D1E),
    inversePrimary: verde,
    surfaceTint: Colors.transparent,
  );

  static ThemeData claro() => _construir(_esquemaClaro, AppColores.claro, tarjeta);
  static ThemeData oscuro() => _construir(_esquemaOscuro, AppColores.oscuro, tarjetaOscura);

  /// Mismo sistema de componentes para claro y oscuro; solo cambian los colores.
  static ThemeData _construir(ColorScheme cs, AppColores colores, Color tarjeta) {
    final base = ThemeData(useMaterial3: true, brightness: cs.brightness, colorScheme: cs);
    final tt = _texto(base.textTheme, cs.onSurface);
    final radioBoton = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const tamBoton = Size(64, 48);
    final etiqueta = tt.labelLarge;
    final fondo = cs.surface;
    final texto = cs.onSurface;
    final textoSec = cs.onSurfaceVariant;
    final bordeSuave = cs.outlineVariant;

    return base.copyWith(
      scaffoldBackgroundColor: fondo,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
      canvasColor: fondo,
      textTheme: tt,
      dividerColor: bordeSuave,
      dividerTheme: DividerThemeData(color: bordeSuave, thickness: 1, space: 1),
      extensions: [colores],
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
          side: BorderSide(color: bordeSuave),
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
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.primary),
          textStyle: etiqueta,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          shape: radioBoton,
          textStyle: etiqueta,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          textStyle: WidgetStatePropertyAll(etiqueta),
          shape: WidgetStatePropertyAll(radioBoton),
          side: WidgetStatePropertyAll(BorderSide(color: bordeSuave)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? cs.primaryContainer : tarjeta,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? cs.onPrimaryContainer : texto,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainer,
        selectedColor: cs.primaryContainer,
        side: BorderSide(color: bordeSuave),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: tt.labelMedium?.copyWith(color: texto),
        secondaryLabelStyle: tt.labelMedium?.copyWith(color: cs.onPrimaryContainer),
        checkmarkColor: cs.onPrimaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tarjeta,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.error),
        ),
        labelStyle: tt.bodyMedium?.copyWith(color: textoSec),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tarjeta,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: cs.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => tt.labelMedium?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? cs.onPrimaryContainer : textoSec,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? cs.onPrimaryContainer : textoSec),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tarjeta,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: tt.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tarjeta,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      popupMenuTheme: PopupMenuThemeData(color: tarjeta, surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: tt.bodyMedium?.copyWith(color: cs.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // Fila seleccionada (p. ej. «tú» en listas) bien visible
      listTileTheme: ListTileThemeData(
        selectedColor: cs.onPrimaryContainer,
        selectedTileColor: cs.primaryContainer.withValues(alpha: 0.45),
        iconColor: textoSec,
        titleTextStyle: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: tt.bodyMedium?.copyWith(color: textoSec),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: cs.brightness == Brightness.light ? cs.onPrimaryContainer : cs.primary,
        unselectedLabelColor: textoSec,
        indicatorColor: cs.primary,
        dividerColor: bordeSuave,
        labelStyle: tt.labelLarge,
        unselectedLabelStyle: tt.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary, linearTrackColor: cs.surfaceContainer),
    );
  }

  /// Color estable para el equipo n (1..4).
  static Color colorEquipo(int equipo) => switch (equipo) {
        1 => equipo1,
        2 => equipo2,
        3 => equipo3,
        _ => equipo4,
      };

  /// Estilo para cifras grandes (marcadores, puntos, precios, saldos): peso alto con cifras tabulares.
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
    final sobre = cs.brightness == Brightness.dark ? const Color(0xFF0F1513) : Colors.white;
    final (fondo, texto) = switch (seleccionado) {
      'confirmado' || 'espera' => (c.exito, sobre),
      'duda' => (c.aviso, sobre),
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
