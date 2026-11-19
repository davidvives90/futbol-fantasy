# Sistema de puntuación Fantasy — referencia LaLiga Fantasy y adaptación amateur

Fecha: 19/11/2026

## 1. Cómo puntúa LaLiga Fantasy

LaLiga Fantasy ha cambiado de socio de medios varias veces, y la estructura se ha mantenido: **puntos por eventos objetivos** más **0–4 puntos de "valoración"**.

| Etapa | Puntos de valoración (0–4) | Fuente |
|---|---|---|
| LaLiga Fantasy MARCA (2016–2023) | Nota de los cronistas de MARCA, convertida a 0–4 puntos | laliga.com, 2016 |
| LaLiga Fantasy Relevo (2023–2025) | "Puntos Relevo", de 0 a 4, calculados con estadísticas de Opta según la posición, sin cronistas | jornadaperfecta.com, 2023 |
| LaLiga Fantasy (2025-26) | "Puntos DAZN", de 0 a 4, calculados con un algoritmo objetivo que se suma a los puntos de rendimiento de Opta | laliga.com, julio 2025 |

### Tabla oficial de eventos publicada por LaLiga (sistema MARCA)

| Evento | Portero | Defensa | Centrocampista | Delantero |
|---|---|---|---|---|
| Jugar más de 60 min / menos de 60 min | +2 / +1 | +2 / +1 | +2 / +1 | +2 / +1 |
| Gol | +6 | +6 | +5 | +4 |
| Asistencia (último pase que acaba en gol) | +3 | +3 | +3 | +3 |
| Ocasión clara generada sin gol | +1 | +1 | +1 | +1 |
| Portería a cero (más de 60 min) | +4 | +4 | +2 | +1 |
| Cada 2 goles encajados | −2 | −2 | −1 | −1 |
| Cada 2 paradas | +1 | — | — | — |
| Penalti parado / provocado / fallado | +5 / +2 / −2 | +2 / −2 | +2 / −2 | +2 / −2 |
| Gol en propia puerta | −2 | −2 | −2 | −2 |
| Amarilla / doble amarilla / roja directa | −1 / −1 / −3 | igual | igual | igual |
| Bonus de ataque: cada 2 remates a puerta, regates o llegadas al área | +1 | +1 | +1 | +1 |
| Bonus defensivo: cada 5 recuperaciones o despejes / cada 10 balones perdidos | +1 / −1 | igual | igual | igual |
| Valoración de los cronistas de MARCA | 0 a +4 | 0 a +4 | 0 a +4 | 0 a +4 |

Lo que conviene copiar de este sistema:

1. **El gol vale más cuanto más atrasada es la posición del jugador.** Así se compensa que el defensa marque menos.
2. **La portería a cero premia a la defensa** y los goles encajados restan.
3. **La valoración subjetiva está acotada (0–4)**: influye, pero no pesa más que los eventos objetivos.
4. Las estadísticas finas (regates, recuperaciones, despejes) necesitan un proveedor como Opta. En amateur no se pueden registrar con fiabilidad, así que **se sustituyen por la valoración de los compañeros, desglosada por aspectos**.

## 2. Adaptación para fútbol amateur (datos manuales verificados por consenso)

Principios: pocos eventos, fáciles de recordar después del partido y verificables por los demás asistentes. Lo que nadie puede contar con fiabilidad (regates, recuperaciones) entra a través de la valoración por aspectos.

### 2.1 Eventos objetivos que se registran

| Evento | Quién lo informa | Verificación |
|---|---|---|
| Resultado de cada encuentro | Todos los asistentes | Valor más votado (moda) entre los informes |
| Goles por jugador | Cada asistente informa los suyos y los de los demás | Moda; si hay empate o menos de un 60 % de acuerdo, queda en disputa y decide un admin |
| Asistencias por jugador | Igual que los goles | Igual que los goles |
| Goles en propia puerta | Igual que los goles | Igual que los goles |
| Paradas clave (solo portero, opcional) | Compañeros de equipo del portero | Mediana de los informes |
| Penalti parado / fallado (opcional) | Todos los asistentes | Moda |
| Portería a cero | Se deriva del resultado verificado | No se informa aparte |

No se registran tarjetas (en una pachanga no hay árbitro); el juego sucio penaliza a través del aspecto *Juego limpio*.

### 2.2 Tabla de reglas (`reglas_puntuacion(clave, puntos)`)

| clave | puntos | Notas |
|---|---|---|
| `jugado` | 2 | Haber asistido al partido |
| `victoria` | 3 | Por partido; con 3 o más equipos, se multiplica por la fracción de encuentros ganados |
| `empate` | 1 | Igual que `victoria` |
| `gol_portero` | 6 | Gol de un jugador que ese día jugó de portero |
| `gol_defensa` | 6 | |
| `gol_medio` | 5 | |
| `gol_delantero` | 4 | Coincide con el `gol` = 4 actual |
| `gol` | 4 | Valor plano cuando la liga desactiva la puntuación por posición, o el jugador no tiene posición |
| `asistencia` | 3 | Antes 2; se sube a 3 como en LaLiga Fantasy |
| `porteria_cero_portero` | 4 | Por encuentro sin goles encajados (raro en fútbol 5/7) |
| `porteria_cero_defensa` | 2 | La mitad que en LaLiga, porque en amateur las posiciones rotan |
| `goles_encajados_3` | −1 | Solo porteros: −1 por cada 3 goles encajados. En LaLiga es −2 por cada 2, pero en amateur se marcan muchos más goles |
| `parada_clave_2` | 1 | Portero: +1 por cada 2 paradas clave verificadas |
| `penalti_parado` | 3 | Opcional |
| `penalti_fallado` | −2 | Opcional |
| `autogol` | −2 | Igual que en LaLiga |
| `valoracion_max` | 4 | Tope de los puntos por valoración de compañeros, como los 0–4 de MARCA/Relevo/DAZN |
| `mvp` | 3 | Bonus para la mejor media general del partido |

**Posición.** Por defecto se usa la posición del perfil. En el post-partido, cada jugador puede indicar la posición en la que jugó ese día (`portero`, `defensa`, `medio` o `delantero`), y esa es la que cuenta. Con el interruptor de liga `puntuar_por_posicion = false` todos los goles valen `gol`.

### 2.3 Aspectos de valoración subjetiva (`aspectos_valoracion(clave, nombre)`)

Escala de 1 a 10. Cada asistente valora a todos los demás asistentes (de los dos equipos) en 5 aspectos. Hay atajos: "pon un 6 en todo" y una nota general que se reparte a todos los aspectos.

| clave | nombre | Qué se valora |
|---|---|---|
| `ataque` | Ataque | Peligro, regates, disparo, desmarques (sustituye a los bonus de ataque de LaLiga) |
| `defensa` | Defensa | Recuperaciones, cortes, ayudas, presión (sustituye a los bonus defensivos) |
| `pase_vision` | Pase y visión | Pases que generan ocasiones, juego de equipo |
| `esfuerzo` | Esfuerzo | Intensidad y trabajo durante todo el partido |
| `juego_limpio` | Juego limpio | Deportividad, sin entradas peligrosas ni discusiones (sustituye a las tarjetas) |
| `porteria` | Portería | Solo para quien jugó de portero; sustituye a `ataque` en su media |

**Cálculo de la nota de cada jugador**

1. Media de cada aspecto, descartando votos extremos: si hay 5 votos o más, se quitan la nota más alta y la más baja (media recortada).
2. Nota general = media de sus aspectos (5 aspectos, con `porteria` en lugar de `ataque` para los porteros).
3. Hacen falta al menos 3 votantes; con menos, la nota no da puntos de valoración ni opta al MVP.

**Conversión de la nota general a puntos** (equivalente a los 0–4 puntos MARCA):

| Nota general | Puntos |
|---|---|
| < 5,0 | 0 |
| 5,0 – 5,9 | 1 |
| 6,0 – 6,9 | 2 |
| 7,0 – 7,9 | 3 |
| ≥ 8,0 | 4 |

**MVP (+3).** Es para la mejor nota general del partido, con un mínimo de 3 votantes. Si hay empate, gana quien tenga más goles + asistencias verificados. Si sigue el empate, los dos reciben el MVP.

**Control de abusos.** El voto propio no cuenta. Si un votante se aleja de forma sistemática de la media de los demás votantes, por ejemplo con más de 3 puntos de diferencia en más de la mitad de sus votos, sus votos de ese partido pesan la mitad.

### 2.4 Ejemplo

Un defensa gana el partido, marca 1 gol, da 1 asistencia y saca una nota general de 7,4:
2 (jugado) + 3 (victoria) + 6 (gol de defensa) + 3 (asistencia) + 3 (valoración) = **17 puntos**. Si además es el MVP, suma 3 más: **20 puntos**.

## 3. Resumen para la base de datos

- `reglas_puntuacion`: `jugado` 2, `victoria` 3, `empate` 1, `gol_portero` 6, `gol_defensa` 6, `gol_medio` 5, `gol_delantero` 4, `gol` 4, `asistencia` 3, `porteria_cero_portero` 4, `porteria_cero_defensa` 2, `goles_encajados_3` −1, `parada_clave_2` 1, `penalti_parado` 3, `penalti_fallado` −2, `autogol` −2, `valoracion_max` 4, `mvp` 3.
- `aspectos_valoracion`: `ataque` Ataque, `defensa` Defensa, `pase_vision` Pase y visión, `esfuerzo` Esfuerzo, `juego_limpio` Juego limpio, `porteria` Portería (solo porteros).
- Interruptor de liga: `puntuar_por_posicion` (por defecto, `true`).

## Fuentes

- [Así es el nuevo sistema de puntuación de LaLiga Fantasy MARCA — laliga.com (2016)](https://www.laliga.com/noticias/asi-es-el-nuevo-sistema-de-puntuacion-de-laliga-fantasy-marca)
- [Recapping the LaLiga Fantasy MARCA scoring system — laliga.com (2016)](https://www.laliga.com/en-GB/news/recapping-the-laliga-fantasy-marca-scoring-system)
- [¿Qué son los puntos Relevo y cómo funcionan? — jornadaperfecta.com (agosto 2023)](https://www.jornadaperfecta.com/guias/puntos-relevo/)
- [LaLiga Fantasy 25/26 llega cargada de novedades — laliga.com (julio 2025)](https://www.laliga.com/noticias/laliga-fantasy-25-26-llega-cargada-de-novedades-tras-el-exito-de-la-ultima-temporada)

Nota: la tabla detallada de eventos es la publicada oficialmente para el sistema MARCA. Para las etapas Relevo y DAZN, LaLiga solo ha publicado el principio (0–4 puntos calculados con datos de Opta), no la tabla completa de valores. Una guía de 2024 de comuniate.com da otros valores (gol de delantero +6, asistencia +4…), pero no se han incluido porque no están confirmados por una fuente oficial.
