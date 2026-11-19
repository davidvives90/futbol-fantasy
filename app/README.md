# Fútbol Fantasy (app Flutter)

App Android de gestión de partidos de fútbol amateur + liga Fantasy. Backend: Supabase
(migraciones en `../supabase/migrations`).

## Requisitos

- Flutter 3.24 o superior (canal stable), Android SDK.
- Un proyecto de Supabase con las migraciones aplicadas, el bucket privado `facturas` creado
  y Realtime activado en `convocatorias` y `partidos`.
- En Supabase → Authentication → URL Configuration, añadir `io.futbolfantasy://login`
  a las Redirect URLs. Para Google, activar el proveedor y configurar sus credenciales.

## Primera vez

Este repositorio solo incluye `lib/`, `test/` y el `AndroidManifest.xml`. Genera el resto de
carpetas de plataforma sin sobrescribir lo existente:

```bash
cd app
flutter create . --org com.futbolfantasy --project-name futbol_fantasy --platforms android
# flutter create no pisa lib/ ni el AndroidManifest.xml si ya existen; si lo hiciera,
# restaura el manifest desde git.
flutter pub get
flutter test
```

## Ejecutar y compilar

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=tu_clave_anon

flutter build apk --release \
  --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=tu_clave_anon
# APK en build/app/outputs/flutter-apk/app-release.apk
```

La clave anónima puede ir en el APK: la seguridad la ponen las políticas RLS. Nunca incluyas la
clave `service_role`.

## Estructura

```
lib/
  main.dart              arranque, Supabase, enlaces de invitación
  core/                  configuración, router, tema, utilidades, liga activa
  data/                  modelos, repositorios (Supabase) y providers de Riverpod
  features/
    auth/                login y perfil
    onboarding/          crear liga, unirse, buscar ligas
    shell/               barra inferior y puerta de sesión
    partidos/            lista, creación, detalle y convocatoria
    equipos/             algoritmo de balanceo y pestaña de equipos (usa el rating del mercado si existe)
    fantasy/             mercado Fantasy: mi equipo y alineación, mercado, mánagers,
                         encuesta inicial y ajustes Fantasy (admin)
    post_partido/        asistente post-partido, revisión de disputas, resultado
    caja/                saldos, pagos y facturas
    liga/                datos, miembros, invitaciones, reglas y aspectos
    stats/               clasificaciones y ficha de jugador
    perfil/              perfil propio y ligas
test/
  balanceo_test.dart
```

## Navegación

Barra inferior de 5 destinos (máximo recomendado por Material 3): **Partidos · Fantasy · Clasificación · Caja · Liga**.
El **Perfil** se abre desde el avatar de la barra superior (ruta `/perfil`).

## Mercado Fantasy

Especificación: `../docs/mercado_fantasy.md`. Necesita la migración `0008_mercado_fantasy.sql`.

- **Fantasy › Mi equipo**: saldo, valor de plantilla, jugadores (máx. 6, un no habitual ×1,5) y alineación del
  próximo partido (hasta `plazas / num_equipos`), con el estado de cada uno en la convocatoria y cuenta atrás hasta
  el cierre (`fecha_hora − horas_cierre_alineacion`). Mantener pulsado un jugador para venderlo.
- **Fantasy › Mercado**: `v_mercado` con búsqueda, orden y filtro; ficha con valoración por atributos e historial
  de precios (gráfico propio con `CustomPainter`, sin dependencias nuevas).
- **Fantasy › Mánagers**: `v_clasificacion_managers`; al tocar un mánager, su plantilla y última alineación.
- **Encuesta**: tarjeta en Partidos y Fantasy si hay una abierta sin completar; 6 rankings con `ReorderableListView`.
- **Liga › Ajustes Fantasy** (admin): abrir/cerrar encuestas, mini-encuesta para un jugador nuevo, parámetros del mercado.
- **Resultado** del partido: «Tus puntos de mánager» con el ×1,5 de los no habituales.

## Enlaces de invitación

- `io.futbolfantasy://invite/<token>` abre la app y llama a `unirse(<token>)`.
- `https://futbolfantasy.app/i/<token>` es la página web (fuera de este repo) con el botón de
  descarga del APK, el botón "Abrir en la app" y el código para copiarlo.
- Un APK instalado fuera de Google Play no recibe el token a través de la instalación: tras
  instalar, el jugador vuelve a tocar el enlace o pega el código en "Unirse".

## Versión 0.2: fichas, cláusulas, ofertas, cesiones y roles

Requiere las migraciones `0010`–`0014` en Supabase (ver `../supabase/README.md`). Contrato exacto en `../docs/contrato_app_backend.md` (sección "Ampliación 0.2").

- **Mercado con fichas limitadas**: cada jugador tiene N fichas. Si quedan libres se compran al precio de mercado; si no, en su ficha de mercado aparecen los dueños con su cláusula para **pagarla** (el dueño no puede negarse; las fichas recién fichadas quedan protegidas una jornada) o **hacerles una oferta**.
- **Mi equipo**: cada ficha tiene menú con *Cambiar cláusula* (subirla cuesta el 10 % de la subida; bajarla es gratis, mínimo el valor), *Vender al mercado* y *Ofrecer en cesión* (% entre el mínimo y el máximo de la liga). La ficha recibida en cesión aparece aparte como plaza extra.
- **Pestaña Ofertas** (Fantasy): ofertas recibidas (Aceptar/Rechazar), enviadas (Cancelar) y cesiones disponibles para el próximo partido (1 cedida y 1 recibida por jornada).
- **Alineación con roles** dibujada sobre un campo: exactamente 1 portero y el resto defensa/medio/delantero. Con `bonus_roles` activo se muestra la leyenda de bonus de cada rol (claves `rol_*`).
- **Posiciones flexibles**: los puntos del partido real ya no dependen de la posición (la del perfil es solo "preferida"); paradas y penaltis se pueden reportar para cualquiera; el balanceo de equipos ya no penaliza porteros y, si hay encuesta, iguala con poco peso la habilidad media bajo palos.
- **Ajustes Fantasy** (admin): coste de subir cláusula, protección, % de cesión, caducidad de ofertas, partidos antes de que cuente el rendimiento y el interruptor de bonus por rol.

## Versión 0.3: rangos, temporada, factura mensual y cotejo de goles

Especificación: `../docs/v03_liga.md` · contrato: `../docs/contrato_app_backend.md` (sección v0.3).

- **Rangos** (Liga → Jugadores): cada jugador es Fijo, Reserva o Invitado; el admin lo cambia desde el menú. Aviso si hay más fijos que plazas. En convocatorias aparece la inicial (F/R/I).
- **Convocatoria y cobro** (Liga → Convocatoria y cobro, admin): orden de la lista de espera (por prioridad: fijos que vuelven, reservas, invitados; o por orden de apuntarse), modo de cobro (por partido o factura mensual) y precio fijo o variable para reservas e invitados.
- **Programar temporada** (Partidos → icono de calendario, admin): partidos recurrentes entre dos fechas, días de la semana, hora fija o variable, coste y fechas excluidas, con vista previa. Cancelar los partidos futuros de una temporada. En cada partido: «Confirmar hora» y «Cambiar fecha u hora».
- **Factura mensual** (Caja → Facturas): al subirla se indica el periodo (por defecto el mes anterior); «Liquidar» muestra el reparto (importe − pagado por reservas/invitados, cuota por partido de fijo, cargo por fijo) y lo aplica.
- **Cotejo de goles** (Post-partido): la suma de goles de los jugadores (+ autogoles del rival) no puede superar el resultado y, si nadie está en «No sé», debe coincidir; el parte se envía con `enviar_parte`. En Revisión, los descuadres se corrigen con «Corregir datos».
- **Fantasy**: el ×1,5 es para el rango Invitado («Invitado ×1,5», máximo 1 por plantilla).
