# v0.3b — Post-partido rápido (objetivo: < 1 minuto)

Petición del usuario: depurar la votación para que sea mucho más sencilla y rápida, sin comprometer demasiado las variables (se pueden simplificar).

## Antes (0.3)
Resultado + goles/asistencias/autogoles/paradas/penaltis de cada jugador con contadores, y 5 aspectos de 1 a 10 por cada compañero (≈ 45 valores con 10 jugadores). Varias pantallas.

## Después: una sola pantalla con 3 bloques y un botón fijo abajo «Enviar»

### 1. Resultado
Dos contadores grandes (−/+) por encuentro, empiezan en 0.

### 2. ¿Quién marcó y quién asistió?
- Dos columnas por equipo (o una lista por equipos con 3–4) con todos los jugadores; el propio usuario incluido.
- Cada jugador: chip «⚽ n» y chip «🅰 n». **Tocar suma 1**, mantener pulsado resta 1. Por defecto todos a 0.
- Cabecera de cada equipo: «Goles asignados 2 / 3» en vivo con el resultado del bloque 1. Verde si cuadra, ámbar si faltan, rojo si sobran (no deja enviar si sobran).
- Interruptor por equipo «No me fijé en este equipo» → sus jugadores se envían sin datos (null = «no sé») y no se exige cuadre.
- Autogol, paradas clave y penaltis: dentro de «Más datos (opcional)» plegado; por defecto no se envían (null), salvo autogoles = 0 cuando el equipo rival está marcado como «me fijé».
- Regla de cuadre: igual que enviar_parte (si el equipo está «me fijé», la suma de goles + autogoles rivales debe IGUALAR el resultado; con «no me fijé» no se comprueba).
  → Con el resultado y los toques ya se envía: típicamente 2–8 toques.

### 3. Notas (una por compañero, no 5)
- Lista de compañeros (todos menos yo) con una **nota general de 1 a 10**, preseleccionada en **6 = «normal»**. Fila con chips rápidos 4 · 5 · 6 · 7 · 8 · 9 · 10 (1–3 en «…» por si acaso). Solo hay que tocar a quien se salió de lo normal.
- Botón «Mi MVP» (estrella) en un jugador: le pone 10 y lo marca como voto MVP (máx. 1).
- Opcional, plegado por jugador: chips de «Destacó en» (Ataque · Defensa · Pase · Esfuerzo · Juego limpio · Portería), máx. 2, solo positivos. Mantienen las estadísticas por aspecto sin pedir números.
- Al final: «Enviar» guarda parte y notas en una sola llamada. Se puede reabrir y corregir hasta que cierre la ventana.

## Variables que se conservan
- Resultado, goles, asistencias (y opcionalmente autogoles, paradas, penaltis): igual que antes, con consenso y descuadres.
- Nota de compañeros: ahora 1 nota general por votante (antes la media de sus 5 aspectos) → nota_partido, tramos 0–4 y MVP no cambian.
- MVP: sigue siendo la mejor nota (≥ 3 votantes); **los votos «Mi MVP» desempatan antes que goles + asistencias**. Se guarda el recuento de votos MVP.
- Aspectos: pasan de nota 1–10 a «destacados» (recuento). v_notas_aspecto se sustituye/complementa por v_destacados (veces destacado por aspecto, % de partidos).
- Ligas que quieran el modo antiguo: `ligas.modo_valoracion` = 'rapida' (por defecto) | 'detallada' (5 aspectos 1–10 como hasta ahora).

## Backend (migración aditiva 0020_votacion_rapida.sql)
- `ligas.modo_valoracion text default 'rapida' check in ('rapida','detallada')`.
- Aspecto `general` ('Nota general', orden 0, aplica_a 'todos', activo) en todas las ligas (existentes y sembrar_liga_defecto). En modo rápido la app solo envía `general`.
- Tabla `valoracion_destacados(partido_id, liga_id, votante_id, votado_id, aspecto text, primary key(partido_id, votante_id, votado_id, aspecto))`, aspecto ∈ claves de aspectos (sin 'general'), máx. 2 por votante y votado; RLS como `valoraciones` (solo el propio votante lee las suyas).
- Tabla `votos_mvp(partido_id, liga_id, votante_id, votado_id, primary key(partido_id, votante_id))`; RLS: solo el propio.
- RPC `enviar_post_partido(p_partido uuid, p_resultados jsonb, p_jugadores jsonb, p_notas jsonb, p_mvp uuid default null)`:
  - p_resultados / p_jugadores: mismo formato que enviar_parte (lo reutiliza, misma validación).
  - p_notas: `[{"votado_id":…, "nota":7, "destacados":["ataque","esfuerzo"], "aspectos":{"ataque":7,…}}]` — `aspectos` solo en modo detallada; en rápida se guarda `nota` como aspecto `general`.
  - Sustituye de forma atómica las valoraciones, destacados y voto MVP previos de ese votante en ese partido. Valida: votante y votados jugaron, no se vota a sí mismo, nota 1–10, máx. 2 destacados, MVP jugó y no es él mismo.
  - Devuelve jsonb {parte: n, notas: n}.
- calcular_puntos: desempate del MVP = más votos_mvp, luego goles + asistencias, luego compartido. desglose.notas en modo rápido = {"general": x} + {"destacados": {"ataque": 3, …}}; añadir `votos_mvp` al desglose.
- Vistas: `v_destacados` (liga, miembro, aspecto, veces, partidos) security_invoker; mantener v_notas_aspecto (funciona con 'general' y con los aspectos del modo detallado).
- Seguridad: revocar internas, conceder solo la RPC nueva, search_path en todo.
- Tests: escenario_votacion.sql (en run.sh): envío rápido completo, sobrescribir, MVP por votos desempata, destacados máx 2, auto-voto rechazado, modo detallada sigue funcionando, puntos idénticos a 0.3 cuando las notas generales equivalen a las medias antiguas.

## App
- Reescribir la pestaña Post-partido como pantalla única descrita arriba, con estado local que sobrevive a salir y volver (borrador en memoria/SharedPreferences por partido) y un indicador «≈ 1 min».
- Precarga si ya envió algo (para corregir).
- Revisión y Resultado: mostrar votos MVP y destacados («Destacó en ataque ×3»).
- Ajustes de la liga (admin): «Valoración: rápida / detallada».
