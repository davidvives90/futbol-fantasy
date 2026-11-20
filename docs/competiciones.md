# Competiciones entre equipos (diseño, fase siguiente)

Petición: que la app sirva también para gestionar **solo convocatorias** (Fantasy desactivable — hecho en 0026)
y para **ligas de equipos** (p. ej. autonómicas o regionales, 25 equipos) con **sorteos**, calendario y
**estadísticas públicas**.

## Conceptos
- **Competición**: nombre, ámbito (local, regional, autonómica), temporada, formato (liga a una o dos vueltas,
  grupos + eliminatoria, copa), puntos por victoria/empate, criterios de desempate, visibilidad pública.
- **Equipo**: nombre, escudo, colores (reutiliza Equipaciones), delegado (admin del equipo), plantilla de jugadores
  (perfiles de la app o fichas sin cuenta). Un equipo puede ser una «liga de amigos» existente.
- **Jornada / Encuentro**: local, visitante, fecha, campo, árbitro opcional, resultado, acta (goles, asistencias,
  tarjetas), estado (programado, jugado, aplazado).
- **Sorteo**: genera el calendario (algoritmo de Berger para todos contra todos; con número impar, descanso),
  reparte grupos por bombos, cruza eliminatorias. Semilla visible para que sea verificable.
- **Acta**: la rellenan los dos delegados; si coinciden se valida sola (mismo sistema de consenso que el
  post-partido); si no, decide el organizador.

## Estadísticas públicas (sin iniciar sesión, enlace compartible)
Clasificación, resultados y calendario; goleadores, asistentes, porteros menos goleados, fair play (tarjetas);
rachas, local/visitante, últimos 5; ficha de equipo y de jugador; goles esperados (reutiliza el modelo xG de 0028)
para previas de cada jornada.

## Roles
Organizador (crea la competición, aprueba equipos, sortea, valida actas) · Delegado de equipo · Jugador · Público.

## Plan
1. Modelo de datos (competiciones, equipos, plantillas, jornadas, encuentros, actas) + RLS con lectura pública.
2. Sorteo y calendario (Berger) + clasificación con desempates.
3. Actas por los delegados con consenso.
4. Web/enlace público de estadísticas y vista en la app.
5. Inscripción de equipos por solicitud y pago de inscripción (fuera de Google Play, como las reservas de pistas).
