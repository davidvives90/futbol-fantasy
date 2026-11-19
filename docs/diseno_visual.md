# Diseño visual — claro, premium y elegante

Petición del usuario: color claro, aspecto premium y elegante sin perder funcionalidad, y una regla clara de qué botones van en cada color.

## Principios
- Fondo claro cálido, mucho aire, tarjetas blancas con borde fino (sin sombras duras). Un único color de acción fuerte por pantalla.
- El verde bosque es "la acción"; el dorado es "dinero Fantasy / premio"; el rojo solo para lo que no tiene vuelta atrás.
- Números grandes y tabulares (marcadores, puntos, precios) como protagonistas.

## Paleta (Material 3, ColorScheme claro hecho a mano, no desde semilla)
| Rol | Color | Uso |
|---|---|---|
| background / surface | #F6F5F1 | Fondo de pantallas (marfil cálido) |
| surfaceContainerLowest (tarjetas) | #FFFFFF | Tarjetas y hojas |
| surfaceContainer | #EFEDE7 | Barras, chips no seleccionados |
| outlineVariant | #E4E1D8 | Bordes de tarjetas y divisores |
| outline | #A9B0AA | Bordes de campos |
| onSurface | #14201B | Texto principal |
| onSurfaceVariant | #5E6A64 | Texto secundario |
| primary | #0E4B3A | Verde bosque: acción principal |
| onPrimary | #FFFFFF | |
| primaryContainer | #DCEBE4 | Botones tonales (admin), chips seleccionados |
| onPrimaryContainer | #0A3A2D | |
| tertiary (premium) | #B8892E | Dorado: dinero Fantasy, MVP, Tienda |
| onTertiary | #1E1606 | Texto oscuro sobre dorado |
| tertiaryContainer | #F4EAD3 | Fondos de insignias premium |
| error | #B3261E · container #F9E3E1 | Acciones destructivas |
| éxito / aviso (extensión) | #2E7D4F / #B7791F | Estados "Voy", "Duda", saldo positivo/negativo |
| equipos 1–4 | #1F4E79 azul marino · #8E2C2C granate · #B08A1E mostaza · #5B3F8C morado | Petos/columnas de equipos |

Tema oscuro: mantener el que hay generado desde semilla con primary verde (secundario; el claro es el principal).

## Tipografía (paquete google_fonts)
- Títulos y números grandes: **Fraunces** (serif elegante), pesos 600–700; `fontFeatures: [FontFeature.tabularFigures()]` en números.
- Texto e interfaz: **Manrope**, 400/500/600.
- Escala: displaySmall 36 (marcadores), headlineSmall 24, titleLarge 20, titleMedium 16 w600, bodyLarge 16, bodyMedium 14, labelLarge 14 w600 (botones, sin mayúsculas).

## Forma y espaciado
- Radio: tarjetas 16, botones 12, chips 10, campos 12. Altura de botón 48. Padding de pantalla 20. Separación entre tarjetas 12.
- Tarjetas: elevación 0, borde 1 px outlineVariant. AppBar del color de fondo, sin sombra al hacer scroll (scrolledUnderElevation 0), título en Fraunces.
- NavigationBar: fondo blanco, indicador primaryContainer, iconos outline/filled.

## Jerarquía de botones (qué color lleva cada uno)
| Nivel | Widget | Aspecto | Cuándo | Ejemplos |
|---|---|---|---|---|
| 1 Principal | `FilledButton` | Verde bosque, texto blanco | La acción principal de la pantalla; **una por pantalla** | Voy · Guardar alineación · Enviar parte · Crear partido · Confirmar equipos · Recibir enlace de acceso |
| 2 Premium | `FilledButton` con estilo `AppButtons.premium` | Dorado, texto oscuro | Mueve dinero Fantasy o da premio | Comprar ficha · Pagar cláusula · Aceptar oferta/cesión · Ver vídeo +0,1 M · Tienda |
| 3 Secundaria | `OutlinedButton` | Borde y texto verde | Alternativa a la principal | Duda · Hacer oferta · Ver ficha · Compartir enlace · Abrir en Maps · Otra opción (equipos) |
| 4 Herramienta admin | `FilledButton.tonal` | Fondo verde claro, texto verde oscuro | Acciones de gestión solo para admins | Generar equipos · Programar temporada · Cerrar plazo y cruzar partes · Resolver disputa · Liquidar factura (antes de confirmar) |
| 5 Terciaria | `TextButton` | Texto verde | Cancelar, ver más, navegación | Cancelar · Ver todo · Usar otro email |
| 6 Destructiva | `TextButton`/`OutlinedButton` con `AppButtons.peligro` (rojo); en el diálogo de confirmación, `FilledButton` rojo | Rojo | Irreversible | Expulsar · Vender ficha · Cancelar temporada · Rechazar · Abandonar liga · Quitar admin |

Voy / Duda / No voy (SegmentedButton de la convocatoria): seleccionado Voy = verde éxito, Duda = ámbar, No voy = gris neutro (no rojo: no es destructivo).
Insignias: MVP e "Invitado ×1,5" en dorado (tertiaryContainer + texto onTertiary); rango F/R/I en chips neutros; saldo positivo verde, negativo rojo.

## Implementación (app)
- `lib/core/theme.dart`: ColorScheme claro a mano con los valores de arriba, `textTheme` con google_fonts (Fraunces títulos/display/headline, Manrope resto), temas de FilledButton/OutlinedButton/TextButton/SegmentedButton/Card/Chip/InputDecoration/AppBar/NavigationBar/Dialog/SnackBar/ListTile coherentes, y una `ThemeExtension` `AppColores` con exito, aviso, equipos 1–4.
- `AppButtons.premium(context)` y `AppButtons.peligro(context)` (ButtonStyle) en el mismo fichero.
- Recorrer las pantallas y aplicar la tabla de jerarquía (una principal por pantalla; acciones de dinero en dorado; admin en tonal; destructivas en rojo con diálogo). Sustituir colores fijos sueltos (Colors.blue, Colors.red, etc.) por los del tema.
- Sin pérdida de funcionalidad: no se mueve ni se quita ninguna acción.

## Modo oscuro (v0.3c)
- Perfil → Opciones → Apariencia: **Claro** (por defecto), **Oscuro** o **Sistema**. Se guarda en el dispositivo.
- Antes la app seguía el modo del móvil: con el móvil en oscuro se veía un tema genérico. Ahora el claro es el predeterminado.
- El oscuro usa el mismo sistema de componentes (`AppTheme._construir`) con otra paleta: fondo carbón verdoso #0F1513, tarjetas #171F1C, verde menta #86CDAD como principal, oro #E2B65E para premium, rojo suave #F2A59E para destructivo. Colores de equipo y estados aclarados (`AppColores.oscuro`).
- Regla para pantallas nuevas: nunca colores fijos de la paleta clara; usar `Theme.of(context).colorScheme` y `AppColores.of(context)`.
