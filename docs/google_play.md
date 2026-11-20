# Preparación para Google Play

## Qué ya está hecho
- Identificador de la app: `com.futbolfantasy.futbol_fantasy` (válido para Play; no se puede cambiar después de publicar).
- Icono adaptativo, nombre «Fútbol Fantasy», minSdk 24, targetSdk el de Flutter estable.
- Política de privacidad: `docs/web/privacidad.html`, publicada con la web.
- CI: si existen los secretos de firma, además del APK genera el **App Bundle (.aab)** firmado, que es lo que pide Play.
- Consentimiento de anuncios (UMP) y opción «Privacidad y anuncios» en el perfil.

## Lo que tiene que hacer David
1. **Cuenta de desarrollador de Google Play** (pago único de 25 $). Las cuentas personales nuevas deben hacer una prueba cerrada con al menos 12 testers durante 14 días antes de poder publicar en producción.
2. **Política de privacidad**: se publica sola junto a la versión web en `https://davidvives90.github.io/futbol-fantasy/privacidad.html` (o `https://<tu dominio>/privacidad.html`).
3. **Crear la clave de subida** (una vez, en tu ordenador con Java instalado):
   ```
   keytool -genkey -v -keystore subida.jks -keyalg RSA -keysize 2048 -validity 10000 -alias subida
   base64 -w0 subida.jks > subida.b64   # en macOS: base64 -i subida.jks -o subida.b64
   ```
   Guarda `subida.jks` y las contraseñas en un sitio seguro (si se pierden, hay que pedir a Google un reseteo).
4. **Secretos en GitHub** (Settings › Secrets and variables › Actions › New repository secret):
   `ANDROID_KEYSTORE_BASE64` (contenido de subida.b64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (= subida), `ANDROID_KEY_PASSWORD`.
   Ojo: con la nueva firma, el APK deja de poder instalarse encima del actual (firma distinta): habrá que desinstalar una vez.
5. **AdMob**: crear la app en AdMob y un bloque intersticial; poner en GitHub › Variables: `ADMOB_APP_ID` (ca-app-pub-…~…) y `ADMOB_INTERSTICIAL` (ca-app-pub-…/…). Configurar el mensaje de consentimiento GDPR en AdMob › Privacidad y mensajes.
6. **Ficha de Play Console**: textos de abajo, capturas (mínimo 2 de móvil), icono 512×512 (`app/assets/icono/icono.png`) y gráfico destacado 1024×500.
7. **Cuestionarios de Play Console**: clasificación de contenido (sin violencia; «simula apuestas»: NO, el dinero es ficticio y no se puede comprar), público objetivo (+16 recomendado por los anuncios), anuncios: SÍ, seguridad de los datos (ver tabla).

## Textos de la ficha
**Nombre**: Fútbol Fantasy · Partidos con amigos

**Descripción breve (80)**: Organiza el fútbol con tus amigos y compite en una liga Fantasy con vuestros partidos.

**Descripción completa**:
¿Cansado de cuadrar el partido por WhatsApp? Fútbol Fantasy lo organiza todo y además convierte vuestros partidos en una liga Fantasy.

ORGANIZA
• Convocatoria con plazas, lista de espera y recordatorios automáticos.
• Equipos equilibrados en un toque según el rendimiento de cada uno, con predicción del resultado.
• Caja de la liga: quién ha pagado, cuánto debe cada uno y facturas del campo.

PUNTÚA
• Acta del partido: goles, asistencias y porterías a cero.
• Tras el partido, cada jugador valora a sus compañeros del 1 al 5 y vota al MVP.
• Clasificaciones: Fantasy, pichichi, asistencias, MVP, % de victorias y récords de la liga.

JUEGA AL FANTASY
• Empiezas con 5 jugadores reales de tu grupo y un presupuesto ficticio.
• Ficha, vende, paga cláusulas y alinea a los que crees que brillarán el próximo partido.
• Sin dinero real: todo es para pique entre amigos.

¿Solo queréis organizar? Desactiva el Fantasy y úsala como gestor de partidos.

## Seguridad de los datos (formulario de Play)
| Dato | Se recoge | Se comparte | Finalidad | Opcional |
|---|---|---|---|---|
| Correo electrónico | Sí | No | Gestión de cuenta | No |
| Nombre | Sí | No | Funcionalidad de la app | No |
| Fotos | Sí | No | Funcionalidad (foto de perfil) | Sí |
| Fecha de nacimiento (otra info personal) | Sí | No | Funcionalidad | Sí |
| Interacciones en la app | Sí | No | Funcionalidad, analítica | No |
| Registros de fallos | Sí | No | Analítica (corregir errores) | No |
| ID de dispositivo / publicidad | Sí | Sí (AdMob) | Publicidad | No |
Cifrado en tránsito: Sí. El usuario puede pedir la eliminación de datos: Sí (por correo).

## Pendiente técnico antes de producción
- Hecho: «Eliminar mi cuenta» en Perfil (RPC eliminar_mi_cuenta) y enlace a la política de privacidad.
