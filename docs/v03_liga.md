# Especificación v0.3 — Rangos, temporada, factura mensual y verificación de goles

Contrato común para backend (migraciones 0015+) y app. Decisiones del usuario (19-11-2026):
- Reparto de la factura entre fijos **según partidos jugados**.
- En el Fantasy, "invitado" (×1,5, máx. 1 por plantilla) = **rango Invitado** asignado por el admin (sustituye la regla automática por asistencia). Fijos y reservas, sin límite.
- Lista de espera por prioridad = **reservas antes que invitados**; dentro de cada grupo, por orden de apuntarse. Cada liga elige "por prioridad" o "por orden de apuntarse".

Producción: 0001–0014 ya desplegadas (copias exactas en `supabase/desplegado_v01/` y `desplegado_v02/`). Todo lo nuevo es **aditivo** (ALTER / CREATE OR REPLACE / migración de datos), con `set search_path = public` en todas las funciones, revocando de anon/authenticated las internas y concediendo solo las RPC de la app.

## 1. Rangos de jugador en la liga
- `miembros.rango` enum `fijo | reserva | invitado`. Migración: miembros existentes en estado activo o pendiente_registro → `fijo`; altas nuevas → `reserva` por defecto.
- RPC admin `cambiar_rango(p_miembro uuid, p_rango text)`.
- Al pasar a `fijo`: se le inscribe como confirmado en los partidos futuros en estado `abierto|completo` (si no hay plaza, primero en la espera). Al dejar de ser fijo no se toca lo ya inscrito.
- `ligas.plazas_fijas` informativo (por defecto = plazas). Si hay más fijos que plazas, se avisa en la app (no se bloquea).

## 2. Convocatoria con fijos y lista de espera
- Al crear un partido (trigger sobre `partidos` insert, o dentro de `crear_partido` y de la programación de temporada), los **fijos activos** se inscriben automáticamente como `confirmado` (orden por antigüedad `unido_en`, hasta llenar plazas; el resto en espera).
- Un fijo que no va marca **Baja** → entra automáticamente el primero de la lista de espera (ya existe `promover_espera`; hay que cambiar el ORDEN).
- `ligas.orden_espera` = `prioridad` (por defecto) | `anotacion`.
  - `prioridad`: fijos que vuelven primero, luego reservas, luego invitados; dentro de cada grupo por `inscrito_en`.
  - `anotacion`: solo por `inscrito_en`.
- Un fijo que se dio de baja y vuelve con el partido lleno queda el primero de la espera (no desplaza a quien ya entró).
- La app muestra junto a cada inscrito su rango (F / R / I).

## 3. Temporada: partidos recurrentes entre dos fechas
- Tabla `temporadas(id, liga_id, nombre, desde date, hasta date, dias_semana smallint[] (1=lunes … 7=domingo), hora time, hora_fija boolean, coste_partido numeric, excluir date[], creada_por, creada_en)` y `partidos.temporada_id`.
- RPC admin `programar_temporada(p_liga uuid, p_desde date, p_hasta date, p_dias_semana smallint[], p_hora time, p_hora_fija boolean default true, p_coste numeric default 0, p_excluir date[] default null, p_nombre text default null) returns int` (nº de partidos creados). Hora en zona `Europe/Madrid` (respeta cambios de horario de verano). `hora_fija = false` → los partidos se crean con `hora_confirmada = false` (hora tentativa) y el admin la confirma/cambia partido a partido. Máximo 120 partidos por llamada. No duplica si ya hay un partido de la liga ese mismo día.
- RPC admin `cancelar_temporada(p_temporada uuid, p_desde date default current_date)` → cancela (estado `cancelado`) los partidos futuros aún no jugados de esa temporada.
- RPC admin `cambiar_hora_partido(p_partido uuid, p_fecha_hora timestamptz, p_confirmada boolean default true)`.

## 4. Cobro: modo factura mensual con precio de invitado
- `ligas.modo_cobro` = `por_partido` (actual) | `factura_mensual`.
- `ligas.precio_invitado numeric null` (p. ej. 5). Null = precio variable: el no fijo paga la misma cuota por partido que los fijos (se calcula al liquidar la factura).
- En `factura_mensual`, al marcar el partido como jugado (`marcar_jugado` → `generar_cargos`):
  - Fijos: **no** se les carga nada por partido.
  - Reservas/invitados que jugaron: cargo `-precio_invitado` en ese momento (si `precio_invitado` no es null).
- `facturas` añade `periodo_desde date`, `periodo_hasta date`, `liquidada boolean default false`, `liquidada_en`.
- RPC admin `liquidar_factura(p_factura uuid) returns jsonb` (idempotente, falla si ya liquidada):
  - Partidos del periodo = partidos de la liga con `fecha_hora` dentro de [desde, hasta] en estado jugado/post_partido/en_revision/cerrado.
  - `pagado_invitados` = suma de lo cargado a no fijos en esos partidos (si `precio_invitado` es null: 0 y los no fijos entran al reparto).
  - `resto = importe − pagado_invitados` (si sale negativo: 0 y se informa).
  - `partidos_fijos` = nº total de asistencias (confirmado con equipo) de fijos en esos partidos (+ las de no fijos si precio variable).
  - `cuota = resto / partidos_fijos`; a cada fijo se le carga `cuota × sus partidos`, redondeando a céntimos y dejando la diferencia al primero por orden alfabético o de antigüedad.
  - Devuelve `{importe, pagado_invitados, resto, partidos, cuota, cargos: [{miembro_id, partidos, importe}]}` y la app lo muestra antes de confirmar (hay `simular_factura(p_factura)` con el mismo cálculo sin escribir).
  - El rango que cuenta es el del miembro **en el momento del partido**: guardar `convocatorias.rango` (copia al inscribirse / al jugar).

## 5. Fantasy: invitado por rango
- `es_no_habitual(miembro)` pasa a ser `rango = 'invitado'` (pre-creados sin cuenta ya no cuentan automáticamente; su rango decide). Se mantiene el nombre de la función y de la columna `no_habitual` para no romper vistas ni la app; en la UI se rotula "Invitado ×1,5".
- Al cambiar el rango se actualiza `mercado_jugador.no_habitual` al momento (no esperar a la jornada); las alineaciones ya congeladas no cambian.
- Límite: máx. 1 invitado por plantilla (incluida la cedida). Si un jugador pasa a invitado y un mánager ya tenía otro invitado, se conserva lo que tenía (solo bloquea compras nuevas).

## 6. Verificación de goles contra el resultado
Reglas (2 equipos, un encuentro; con 3–4 equipos se aplica sobre el total del partido):
- Goles a favor del equipo A = Σ goles de jugadores de A + Σ autogoles de jugadores de B. Debe ser igual a los goles de A en el resultado.
- **En cada parte** (servidor): nueva RPC `enviar_parte(p_partido uuid, p_resultados jsonb, p_jugadores jsonb)` que guarda en una transacción el resultado de cada encuentro y los datos de cada jugador del reportero y rechaza el parte si, para algún equipo, la suma de goles indicados (contando autogoles del rival) **supera** los goles de ese equipo en su propio resultado; si ha indicado goles de **todos** los jugadores de un equipo (ninguno "no sé"), la suma debe ser **igual**. Mensaje claro: "Has puesto 4 goles al equipo A pero el resultado que indicas es 1-1".
- **En el acta consolidada**: tras el consenso, si la suma por equipo no cuadra con el resultado consolidado, o algún jugador tiene más goles que su equipo, se abre una disputa de tipo `descuadre` (campo `goles_equipo_<n>`, valores = {resultado, suma_jugadores}) que bloquea `calcular_puntos` igual que las demás.
- Resolver un descuadre: el admin corrige los datos con `fijar_dato(p_partido, p_sujeto uuid null, p_n smallint null, p_campo text, p_valor smallint)` (marca disputa resuelta o crea una resuelta para ese campo) y después `revisar_descuadres`/`consolidar_acta` vuelve a comprobar; el descuadre se cierra solo cuando cuadra.
- La app valida lo mismo en el formulario en vivo (aviso por equipo "Suma 3 · Resultado 1") y no deja enviar un parte incoherente.

## 7. MVP y estadísticas: revisión
- Revisar `calcular_puntos` (0010) y `nota_partido`: MVP = mayor nota con ≥ 3 votantes; desempate goles + asistencias; empate persistente = compartido; nunca MVP con < 3 votantes; bonus MVP una sola vez; recalcular no duplica. Añadir tests: empate a nota con distinto G+A, empate total, nadie con 3 votos, un único votante, recálculo.
- Revisar `v_rendimiento`, `v_clasificacion`, `v_pichichi` (asistencias, MVPs, % victorias) con datos de varios partidos y corregir lo que falle. Añadir `v_mvps` si la app lo necesita.
