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
      labelLarge: t.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.1),
    );
  }


  /// Modo oscuro premium: carbón verdoso cálido, verde menta y oro (mismo lenguaje que el claro).
  static const fondoOscuro = Color(0xFF0F1513);
  static const tarjetaOscura = Color(0xFF171F1C);

  static const ColorScheme _esquemaOscuro = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF86CDAD),
    onPrimary: Color(0xFF00382A),
    primaryContainer: Color(0xFF1F4A3C),
    onPrimaryContainer: Color(0xFFC3EAD8),
    secondary: Color(0xFFA9C2B6),
    onSecondary: Color(0xFF15291F),
    secondaryContainer: Color(0xFF2A3A33),
    onSecondaryContainer: Color(0xFFD5E5DC),
    tertiary: Color(0xFFE2B65E),
    onTertiary: Color(0xFF2B1F05),
    tertiaryContainer: Color(0xFF4A3814),
    onTertiaryContainer: Color(0xFFF6E4BE),
    error: Color(0xFFF2A59E),
    onError: Color(0xFF5C1410),
    errorContainer: Color(0xFF6B1E18),
    onErrorContainer: Color(0xFFF9DEDB),
    surface: fondoOscuro,
    onSurface: Color(0xFFE8ECE8),
    onSurfaceVariant: Color(0xFFA6B1AB),
    surfaceDim: Color(0xFF0B100E),
    surfaceBright: Color(0xFF2B3531),
    surfaceContainerLowest: Color(0xFF0B100E),
    surfaceContainerLow: Color(0xFF131A17),
    surfaceContainer: Color(0xFF1C2421),
    surfaceContainerHigh: Color(0xFF232C28),
    surfaceContainerHighest: Color(0xFF2A3430),
    outline: Color(0xFF6F7C75),
    outlineVariant: Color(0xFF2B3631),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE8ECE8),
    onInverseSurface: Color(0xFF1B2420),
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
