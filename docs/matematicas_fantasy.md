# Matemáticas del Fantasy (noviembre 2026, v0.9 · Fase 4)

## 0. Cómo se decide el acta del partido (0047, 0050)
- Quién rellena el acta (resultado, goles, asistencias) lo elige cada liga en Ajustes › Quién rellena el acta:
  - Todos los que jugaron (por defecto): la app cruza los partes como se explica abajo.
  - El árbitro: solo él (el del partido o el de la liga; si no hay, el admin). Su parte pesa 3, así que manda.
  - Los capitanes: solo los capitanes del partido (si no hay capitanes, todos los que jugaron).
  - El admin puede rellenar el acta siempre. Las notas y el MVP los ponen siempre todos los que jugaron.
- Cada jugador envía su parte; cada parte pesa 1 (el del admin, 1,5; el del árbitro designado, 3).
- Resultado: si más de la mitad del peso dice el mismo marcador, vale ese. Si no, la mediana ponderada de cada marcador. Con un solo parte, vale ese parte.
- Conflicto en el resultado (se pregunta al admin) solo si no hay mayoría y además los partes difieren en 2 o más goles o al menos un tercio del peso dice otro ganador.
- Goles y asistencias de cada jugador: media ponderada de los partes. Después se reparten en enteros (restos mayores) respetando el marcador. Si los partes suman de más se reduce en proporción; si suman de menos, no se inventan goleadores.
- Conflicto en un jugador: solo si al menos 2 partes hablan de él y el valor final lo respalda la mitad o menos del peso.

## 1. Puntos de cada jugador en un partido (iguales para todos, sin importar la posición)
| Acción | Puntos |
|---|---|
| Jugar el partido | +2 |
| Victoria / empate (por cada encuentro) | +3 / +1 |
| Gol (×2 en jornada de «goles dobles») | +5 |
| Asistencia | +3 |
| Cada 2 paradas clave | +1 |
| Penalti parado | +3 |
| Penalti fallado / autogol | −2 |
| Valoración de los compañeros (modo notas) | 0 a +4 |
| Podio (modo Podio Top 3): 1.º / 2.º / 3.º | +5 / +3 / +1 |
| 1.º del partido (MVP) | +3 |
| 2.º / 3.º del partido | +2 / +1 |

### Votación tras el partido (0053)
- **Podio Top 3**: cada uno elige 1.º, 2.º y 3.º (no puede votarse). Puntos de votación 5 / 3 / 1 (configurable, máx. 20). El que más suma es el MVP; desempate: votos de 1.º, de 2.º, goles + asistencias. La «valoración» son los puntos de podio de su puesto final; fuera del podio, 0.
- **Notas del 1 al 5**: nota media en escala 1–10. Puntos = 4 × (nota − 4) / 6, entre 0 y 4, a medios puntos. Podio por nota (con mínimo de votantes), desempate «Mi MVP» y goles + asistencias.
- **Detallada por aspectos**: igual que notas, por aspecto.

### Equipo de la jornada (0053)
- Los N mejores por puntos Fantasy (N = jugadores por equipo). Con posiciones: 1 portero, 40 % defensas, 20 % delanteros (mín. 1), resto medios.

## 2. Economía (0054): escala de 50 M
- **Valor base** = 50 M (un jugador de calidad 50). Precio = mín + (máx − mín) × (calidad / 100)², con mín 15 y máx 155 → calidad 50 = 50 M, 80 ≈ 105 M, 30 ≈ 28 M.
- **Presupuesto** = jugadores por equipo × base + base / 5 → F5 260 M, F7 360 M, F11 560 M. El admin puede fijar otro.
- Cambiar el valor base (Asistente) multiplica todo el dinero de la liga (saldos, precios, cláusulas, historial) en proporción.
- Ligas existentes: reescaladas ×13,33 (de calidad 50 = 3,75 M a 50 M). Su presupuesto para mánagers nuevos = dinero inicial anterior + lo que vale un reparto (5 × 50 M), porque ahora el reparto se cobra. Su prima por punto se mantuvo proporcional (1,33 M/pt); las ligas nuevas tienen 0,5 M/pt.

## 3. Dinero que se gana
- Prima por punto: puntos de la jornada × prima (0,5 M por defecto). 30 puntos = 15 M.
- **Prima inversa** (opcional): extra X × (puesto − 1) / (mánagers − 1). El último de la jornada cobra X entero; el primero, nada.
- **Porra** en modo dinero (0055): ver apartado 13.

## 4. Copias (0054)
- C = ⌈M × (N + 1) / P⌉, mínimo 1 y máximo M (M = mánagers, N = jugadores por equipo, P = jugadores de la liga). Así siempre hay copias para que todos tengan alineación completa + 1 reserva. Se recalcula al entrar mánagers o jugadores; nunca se quitan copias con dueño.
- Un mánager no puede tener dos copias del mismo jugador. La plantilla siempre admite N + suplentes (mín. N + 1).
- **Ediciones (rareza)**: copia #1 Única ×1,25 pts y ×1,5 precio; #2-#3 Titular ×1,10 y ×1,2; resto Base ×1.
- **Inflación por escasez**: cada copia con dueño encarece las libres un 10 %.
- Precio de una copia = valor de mercado × rareza × escasez. Vender cobra valor × rareza × (1 − comisión).

## 5. Inicio de la liga (0054)
- **Reparto equilibrado**: alineación completa al azar de valor parecido (objetivo: valor medio × N, sin pasar del 96 % del presupuesto), pagada del presupuesto. Si ninguna combinación cabe en el saldo (precios inflados por rareza y escasez), se dan los más baratos y se cobra como mucho el saldo que tenga (0056): nadie se queda sin alineación ni en negativo.
- **Mercado libre**: 0 jugadores, presupuesto entero.
- **Subasta diaria**: 0 jugadores. Cada día a la hora fijada salen N copias (una por jugador) durante X horas. Puja mínima = precio de la copia (o fija). Abierta: hay que superar la mejor en máx(0,5 M, 2 %); pujar en los 2 últimos minutos alarga 2 min. Ciega: no se ven las pujas. Gana la puja más alta que se pueda pagar (si no, la siguiente). En este modo no se compran libres directamente.
- **Draft**: 0 jugadores. El admin lo inicia: orden aleatorio en serpiente, N + 1 rondas. Cada elección paga el precio de la copia; se puede pasar. El mercado se abre al terminar.
- Interruptor: permitir o no ficharse a uno mismo.

## 6. Cláusulas, cesiones y compraventa
- Cláusula al fichar = 150 % de lo pagado (100–300 %, configurable), nunca menos que el valor de mercado. El dueño puede subirla pagando el 10 % de la subida (blindaje). Quien la paga se lleva al jugador y el dinero va al dueño; 7 días de protección.
- Cesiones por 1 jornada (opcionales). Mercado cerrado desde 2 h antes del partido hasta que se calculan los puntos.

## 7. Puntos del mánager en la jornada (0054)
- Alineación **táctica** (1 portero; con 4 o más, al menos 1 defensa y 1 delantero) o **libre**. Se puede alinear con menos jugadores; los huecos valen 0.
- Por jugador: (puntos + bonus de rol) × invitado (1,5) × rareza × capitán (×2) + ariete (+3 si marca). Todo × 2 en jornada de «doble puntuación».
- **Suplentes** (0–2): si un titular no juega, entra el primer suplente que sí jugó, con el rol del titular (el ×2 de capitán no pasa al suplente).
- Si no alinea, se copia la alineación anterior (con capitán, ariete y suplentes) o sus jugadores más valiosos.

## 8. Temporadas (0054)
- Al cerrar: seguir igual, **reinicio total** (precios iguales), **heredar valor** (se vacía todo pero cada jugador conserva su precio) o **heredar bonus** (como heredar valor + 10 % del patrimonio final: saldo + valor de su plantilla).

## 9. Historial importado (0053)
- Se suma en rendimiento, equipos nivelados y logros. Opcional: «Valor de mercado según el historial» da calidad 35–65 según el percentil de puntos por partido estimados.

## 10. Quién puede cambiar qué
- Admin, Asistente Fantasy: valor base, presupuesto, prima por punto e inversa, modo de copias, inflación, % de cláusula, modo de inicio y subasta, auto-fichaje, alineación táctica/libre, suplentes, capitán, ariete y herencia de temporada.
- Admin, Ajustes Fantasy › Opciones avanzadas: precio mín/máx, plantilla, cierre, comisión, coste de subir cláusula, protección, cesiones.
- Admin, menú del partido: jornada especial (doble puntuación o goles dobles).
- Admin, Ajustes de la liga › Porra del partido: activar, modo (puntos o dinero Fantasy) y tope por partido. Ajustes de la liga › Avisos con humor.
- Cada jugador, Perfil › Preferencias › Avisos con humor.
- Fijo en la app: ±15 % de precio por jornada, 65/35, 8 partidos con peso 0,75, curva al cuadrado, factor de demanda, multiplicadores de rareza, +10 % de escasez, anti-sniping de 2 min, bonus de herencia del 10 %, margen de la porra (0,92), seguro (50 % / 70 %), umbrales de los logros.

## 11. Modos de convocatoria (0050)
| Modo | Quién está en la lista al crear | Cuándo se apunta cada uno | Lista de espera |
|---|---|---|---|
| Con apertura | Fijos (pendientes) | Resto: X h después de acabar el partido anterior | Fijos primero |
| Clásica | Fijos (pendientes) | Resto: desde que se crea | Fijos primero |
| Por orden de llegada | Nadie | Todos desde que se crea | Orden de llegada |
| Por turnos | Nadie | Fijos al abrir; reservas +T h; invitados +2T h | Fijos primero |
| Con mínimo | Nadie | Todos desde que se crea | Orden de llegada |

## 12. Privacidad (0053)
- `politicas` (versión, fecha, URL) y `user_consents` (usuario, versión, fecha UTC, opciones). Al publicar versión nueva, la app vuelve a pedir la aceptación.

## 13. Porra del partido (0055 · Fase 3)
- **Cuándo**: se activa por liga. Abre cuando el partido está en «equipos hechos» con 2 equipos y cierra a la hora de inicio. Hasta el inicio cada uno solo ve sus boletos; después se ven todos. Se puede cancelar un boleto mientras esté abierta.
- **Mercados**:
  - 1-X-2 (equipo 1 / empate / equipo 2). Goles esperados de cada jugador = (goles + 3 × media de la liga) / (partidos + 3); se suman por equipo (mín. 0,3) y se cruzan con Poisson (0 a 25 goles).
  - Goleador: probabilidad = 1 − e^(−goles esperados).
  - MVP: probabilidad proporcional a (puntos medios + 3)², mínimo 1.
  - Cuota = 0,92 / probabilidad, entre 1,05 y 25. Las cuotas se recalculan si cambian los equipos y quedan fijadas en el boleto al apostar.
- **Boletos**: sencilla (1 pronóstico), combinada (2 o más, todos deben acertar; cuota = producto), múltiple (3 o 4 pronósticos; el importe se reparte entre todas las parejas y cada pareja acertada paga importe / parejas × cuota1 × cuota2). Máximo un 1-X-2 y un MVP por boleto; sin repetidos.
- **Seguro** (opcional): si el retorno bruto ≥ importe, cobras importe + 70 % del beneficio; si no, recuperas el mayor entre el retorno bruto y el 50 % del importe. El boleto muestra ambos escenarios antes de confirmar.
- **Economía**: modo puntos (solo ranking «Mejor pronosticador») o modo dinero Fantasy (se descuenta del saldo y se cobra el retorno; necesita Fantasy activo). Tope por partido = el que fije el admin o, por defecto, 100 pts / la mitad del valor base (25 M).
- **Liquidación automática** al cerrar el partido (acta y MVP cerrados): 1-X-2 por la suma de goles de los encuentros, goleador si marcó ≥ 1, MVP según puntos Fantasy. Estado: ganada (todo acertado), parcial (cobra algo), perdida. Si el partido se cancela, se anulan los boletos y se devuelve el importe. Aviso push con el resultado.
- **Ranking «Mejor pronosticador»**: beneficio (retorno − importe) y, en empate, boletos ganados.

## 14. Logros (0056 · Fase 4)
- **150 logros** = 30 familias × 5 niveles: Bronce 🥉, Plata 🥈, Oro 🥇, Diamante 💎, Leyenda 👑. Código = familia_umbral (p. ej. `goles_25`).
- Cada familia mide una cifra del jugador (con el historial importado cuando aplica) y cada nivel es un umbral:

| Categoría | Familia: cifra (umbrales) |
|---|---|
| Ataque | Pichichi de barrio: goles (1, 10, 25, 50, 100) · Socio ideal: asistencias (1, 10, 25, 50, 100) · Noche mágica: goles en un partido (2, 3, 4, 5, 7) · Olfato de gol: partidos seguidos marcando (2, 3, 5, 7, 10) · Partidazo: puntos Fantasy en un partido (15, 20, 25, 30, 40) |
| Portería | El Muro: porterías a cero (1, 5, 10, 25, 50) · Manos de santo: paradas clave (5, 25, 50, 100, 250) · Superhéroe del penalti: penaltis parados (1, 3, 5, 10, 20) |
| Constancia | Fijo en la convocatoria: partidos (10, 25, 50, 100, 200) · Nunca falla: partidos de la liga seguidos sin faltar (5, 10, 20, 30, 50) · Madrugador: veces el primero en apuntarse, sin empate (1, 5, 15, 30, 60) |
| Resultados | Ganador nato: victorias (5, 25, 50, 100, 200) · Invicto: seguidos sin perder (3, 5, 10, 15, 20) · Imparable: victorias seguidas (3, 5, 7, 10, 15) |
| Reconocimiento | Estrella del partido: MVP (1, 5, 10, 25, 50) · Siempre en el podio: top 3 del partido (1, 5, 15, 30, 60) · Matrícula de honor: nota media ≥ 8 (1, 5, 15, 30, 60) · Juez imparcial: post-partidos votados (5, 15, 30, 60, 100) · Vitrina llena: premios de temporada (1, 3, 5, 10, 20) |
| Con humor (secretos) | Fichaje del rival: autogoles (1, 3, 5, 10, 20) · Panenka fallida: penaltis fallados (1, 3, 5, 8, 12) · Mártir del fútbol: derrotas (5, 15, 30, 60, 100) · Gafe oficial: derrotas seguidas (3, 5, 7, 10, 15) · Sequía histórica: seguidos sin marcar (10, 20, 30, 50, 75) |
| Fantasy | Míster de la jornada: jornadas con más puntos de mánager (1, 3, 10, 25, 50) · Director deportivo: fichajes (1, 10, 25, 50, 100) · Clausulazo: cláusulas pagadas (1, 3, 5, 10, 20) · Tiburón del mercado: ventas (1, 10, 25, 50, 100) |
| Porra | Pitoniso: boletos acertados (1, 5, 15, 30, 60) · Golpe de suerte: cuota del mejor boleto acertado (3, 5, 10, 20, 50) |

- Rachas = la más larga de la historia (un logro nunca se pierde).
- **Cuándo se revisan**: al cerrar cada partido (todos los miembros activos de la liga, después de la jornada Fantasy y de la porra) y cada hora (cron `ff_logros`, ligas con movimiento reciente).
- **Avisos**: solo del nivel más alto de cada familia conseguido a la vez. A toda la liga se anuncian los de Diamante y Leyenda, y los de humor desde Plata.
- Logros antiguos conservados: primer_gol → goles_1, hat_trick → noche_3, manita → noche_5.

## 15. Avisos con humor (0056)
- Tipos con frases (3 por tipo, 9 idiomas): puntos, convocatoria abierta, post-partido, equipos hechos, alineación pendiente, último aviso para votar, partido cancelado, entras en la convocatoria, capitán, deuda, cláusula pagada, cambio de hora, subasta y oferta.
- Se elige una al azar como título; el cuerpo mantiene la información (si no había cuerpo, el título serio pasa al cuerpo).
- Se desactiva por jugador (Perfil › Preferencias) o para toda la liga (Ajustes de la liga). Logros y porra conservan sus títulos.
