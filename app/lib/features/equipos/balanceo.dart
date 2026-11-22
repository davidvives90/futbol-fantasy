import 'dart:math';

/// Jugador tal como lo ve el algoritmo de balanceo.
class JugadorBalanceo {
  const JugadorBalanceo({required this.id, required this.nombre, required this.rating, this.habilidadPortero});
  final String id;
  final String nombre;

  /// Valoración 0..100.
  final double rating;

  /// Habilidad bajo palos 0..100 (ranking "portero" de la encuesta), si se conoce.
  /// En la liga no hay portero fijo: todos rotan, así que solo se usa para que la habilidad
  /// media en la portería quede pareja entre equipos (con poco peso).
  final double? habilidadPortero;

  @override
  String toString() => '$nombre(${rating.toStringAsFixed(0)})';
}

/// Métricas históricas de un jugador para calcular su valoración.
class MetricasJugador {
  const MetricasJugador({required this.partidos, this.puntosMedia, this.notaMedia, this.golesPartido});
  final int partidos;
  final double? puntosMedia, notaMedia, golesPartido;
}

/// Pesos de la valoración (configurables por liga en el futuro).
class PesosBalanceo {
  const PesosBalanceo({this.puntos = 0.5, this.nota = 0.3, this.goles = 0.2, this.k = 3});
  final double puntos, nota, goles;

  /// Partidos "ficticios" con la media del grupo que se mezclan con los reales (suavizado).
  final int k;
}

/// Calcula la valoración 0..100 de cada jugador:
/// 1) suaviza cada métrica hacia la media del grupo según los partidos jugados,
/// 2) normaliza min–max entre los convocados, 3) combina con los pesos.
/// Un jugador sin historial queda exactamente en la media del grupo.
Map<String, double> calcularRatings(
  Map<String, MetricasJugador> metricas, {
  PesosBalanceo pesos = const PesosBalanceo(),
  Map<String, double> manuales = const {},
}) {
  if (metricas.isEmpty) return {};

  double media(double? Function(MetricasJugador) f) {
    final v = metricas.values.where((m) => m.partidos > 0 && f(m) != null).map((m) => f(m)!).toList();
    return v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  }

  Map<String, double> suavizada(double? Function(MetricasJugador) f) {
    final mu = media(f);
    return {
      for (final e in metricas.entries)
        e.key: (e.value.partidos * (f(e.value) ?? mu) + pesos.k * mu) / (e.value.partidos + pesos.k),
    };
  }

  Map<String, double> normalizada(Map<String, double> x) {
    final mn = x.values.reduce(min), mx = x.values.reduce(max);
    return {for (final e in x.entries) e.key: mx - mn < 1e-9 ? 0.5 : (e.value - mn) / (mx - mn)};
  }

  final p = normalizada(suavizada((m) => m.puntosMedia));
  final n = normalizada(suavizada((m) => m.notaMedia));
  final g = normalizada(suavizada((m) => m.golesPartido));
  final suma = pesos.puntos + pesos.nota + pesos.goles;

  return {
    for (final id in metricas.keys)
      id: manuales[id] ?? 100 * (pesos.puntos * p[id]! + pesos.nota * n[id]! + pesos.goles * g[id]!) / suma,
  };
}

/// Un reparto: lista de equipos (índice 0 = equipo 1).
class Reparto {
  Reparto(this.equipos, this.coste);
  final List<List<JugadorBalanceo>> equipos;
  final double coste;

  List<double> get sumas => [for (final e in equipos) e.fold<double>(0, (s, j) => s + j.rating)];

  /// Diferencia entre el equipo más fuerte y el más débil, en % del más fuerte.
  double get diferenciaPct {
    final s = sumas;
    final mx = s.reduce(max);
    return mx == 0 ? 0 : 100 * (mx - s.reduce(min)) / mx;
  }

  /// miembroId → número de equipo (1..k).
  Map<String, int> get asignacion => {
        for (var i = 0; i < equipos.length; i++)
          for (final j in equipos[i]) j.id: i + 1,
      };
}

/// Peso de la diferencia de habilidad media en la portería entre equipos (0 = ignorarla).
/// Pequeño a propósito: lo que manda es la fuerza total.
const pesoPorteria = 0.15;

/// Coste de un reparto: diferencia de fuerza entre el equipo más fuerte y el más débil
/// (comparando la media por jugador escalada al tamaño mayor, para que un equipo con
/// un jugador más no salga siempre como "el fuerte"). Si todos tienen habilidad de portero
/// conocida, se suma un término pequeño para igualar la media de esa habilidad entre equipos.
/// Ya no hay penalización por porteros fijos: en la liga todos rotan en la portería.
double costeReparto(List<List<JugadorBalanceo>> equipos) {
  final tamMax = equipos.map((e) => e.length).reduce(max);
  final fuerzas = [
    for (final e in equipos) e.isEmpty ? 0.0 : e.fold<double>(0, (s, j) => s + j.rating) / e.length * tamMax,
  ];
  var coste = fuerzas.reduce(max) - fuerzas.reduce(min);

  final todos = equipos.expand((e) => e);
  if (pesoPorteria > 0 && todos.isNotEmpty && todos.every((j) => j.habilidadPortero != null)) {
    final medias = [
      for (final e in equipos)
        if (e.isNotEmpty) e.fold<double>(0, (s, j) => s + j.habilidadPortero!) / e.length,
    ];
    if (medias.length > 1) coste += pesoPorteria * (medias.reduce(max) - medias.reduce(min));
  }
  return coste;
}

/// Reparte [jugadores] en [numEquipos] equipos equilibrados.
/// Devuelve los mejores repartos encontrados, del mejor al peor.
/// - 2 equipos y hasta [maxExhaustivo] jugadores: búsqueda exhaustiva (óptimo).
/// - En otro caso: serpiente + intercambios (óptimo local).
List<Reparto> balancear(
  List<JugadorBalanceo> jugadores,
  int numEquipos, {
  int top = 5,
  int maxExhaustivo = 16,
  Random? rng,
  Map<String, int> fijos = const {},
}) {
  if (numEquipos < 2) throw ArgumentError('Se necesitan al menos 2 equipos');
  if (fijos.isNotEmpty && jugadores.length >= numEquipos) {
    return _conFijos(jugadores, numEquipos, top: top, maxExhaustivo: maxExhaustivo, rng: rng ?? Random(), fijos: fijos);
  }
  if (jugadores.length < numEquipos) {
    return [
      Reparto([for (var i = 0; i < numEquipos; i++) i < jugadores.length ? [jugadores[i]] : <JugadorBalanceo>[]], 0)
    ];
  }
  if (numEquipos == 2 && jugadores.length <= maxExhaustivo) {
    return _exhaustivo(jugadores, top);
  }
  return _serpienteConIntercambios(jugadores, numEquipos, top, rng ?? Random());
}

/// Elige al azar entre los repartos a menos de [margen] del mejor, para dar variedad.
Reparto elegirConVariedad(List<Reparto> repartos, {double margen = 2, Random? rng}) {
  final base = repartos.first.coste;
  final candidatos = repartos.where((r) => r.coste - base <= margen).toList();
  return candidatos[(rng ?? Random()).nextInt(candidatos.length)];
}

List<Reparto> _exhaustivo(List<JugadorBalanceo> js, int top) {
  final n = js.length;
  final tamA = n ~/ 2; // con impares, el equipo 2 lleva uno más
  final mejores = <Reparto>[];

  void evaluar(List<int> sel) {
    final enA = sel.toSet();
    final a = [for (final k in sel) js[k]];
    final b = [for (var k = 0; k < n; k++) if (!enA.contains(k)) js[k]];
    final r = Reparto([a, b], costeReparto([a, b]));
    if (mejores.length < top || r.coste < mejores.last.coste) {
      mejores
        ..add(r)
        ..sort((x, y) => x.coste.compareTo(y.coste));
      if (mejores.length > top) mejores.removeLast();
    }
  }

  void recorrer(int i, List<int> sel) {
    if (sel.length == tamA) {
      evaluar(sel);
      return;
    }
    if (i >= n || n - i < tamA - sel.length) return;
    recorrer(i + 1, [...sel, i]); // i va al equipo 1
    // El jugador 0 siempre en el equipo 1 (evita evaluar cada reparto dos veces),
    // salvo con impares, donde los dos tamaños son distintos y no hay simetría.
    if (i != 0 || n.isOdd) recorrer(i + 1, sel);
  }

  recorrer(0, []);
  return mejores;
}

List<Reparto> _serpienteConIntercambios(List<JugadorBalanceo> js, int k, int top, Random rng) {
  final resultados = <Reparto>[];
  // Varias semillas: la serpiente pura y versiones con empates barajados.
  for (var intento = 0; intento < max(top, 3); intento++) {
    final orden = [...js];
    if (intento > 0) orden.shuffle(rng);
    orden.sort((a, b) => b.rating.compareTo(a.rating));
    if (intento > 0) {
      // Pequeña perturbación: intercambia vecinos con probabilidad 1/3.
      for (var i = 0; i + 1 < orden.length; i++) {
        if (rng.nextInt(3) == 0) {
          final t = orden[i];
          orden[i] = orden[i + 1];
          orden[i + 1] = t;
        }
      }
    }

    final equipos = List.generate(k, (_) => <JugadorBalanceo>[]);
    for (var i = 0; i < orden.length; i++) {
      final ronda = i ~/ k, pos = i % k;
      equipos[ronda.isEven ? pos : k - 1 - pos].add(orden[i]);
    }

    _mejorarConIntercambios(equipos);
    resultados.add(Reparto(equipos, costeReparto(equipos)));
  }

  resultados.sort((a, b) => a.coste.compareTo(b.coste));
  // Quita duplicados exactos.
  final vistos = <String>{};
  final unicos = <Reparto>[];
  for (final r in resultados) {
    final firma = (r.equipos.map((e) => (e.map((j) => j.id).toList()..sort()).join(',')).toList()..sort()).join('|');
    if (vistos.add(firma)) unicos.add(r);
  }
  return unicos.take(top).toList();
}

/// Reparto con jugadores fijos en un equipo ([fijos]: id → índice de equipo 0-based), p. ej. los capitanes.
/// Parte de los mejores repartos libres, los recoloca para respetar a los fijos y vuelve a equilibrar
/// intercambiando solo a los demás.
List<Reparto> _conFijos(List<JugadorBalanceo> js, int k,
    {required int top, required int maxExhaustivo, required Random rng, required Map<String, int> fijos}) {
  final base = balancear(js, k, top: top * 4, maxExhaustivo: maxExhaustivo, rng: rng);
  final resultados = <Reparto>[];
  for (final r in base) {
    final equipos = [for (final e in r.equipos) [...e]];
    // Cada fijo a su equipo, cambiándolo por el no fijo de su equipo destino con nivel más parecido
    for (final f in fijos.entries) {
      final destino = f.value;
      if (destino < 0 || destino >= k) continue;
      final origen = equipos.indexWhere((e) => e.any((j) => j.id == f.key));
      if (origen < 0 || origen == destino) continue;
      final x = equipos[origen].firstWhere((j) => j.id == f.key);
      final candidatos = equipos[destino].where((j) => !fijos.containsKey(j.id)).toList();
      equipos[origen].remove(x);
      if (candidatos.isEmpty) {
        equipos[destino].add(x);
        continue;
      }
      candidatos.sort((a, b) => (a.rating - x.rating).abs().compareTo((b.rating - x.rating).abs()));
      final y = candidatos.first;
      equipos[destino].remove(y);
      equipos[destino].add(x);
      equipos[origen].add(y);
    }
    _mejorarConIntercambios(equipos, bloqueados: fijos.keys.toSet());
    resultados.add(Reparto(equipos, costeReparto(equipos)));
  }
  resultados.sort((a, b) => a.coste.compareTo(b.coste));
  final vistos = <String>{};
  final unicos = <Reparto>[];
  for (final r in resultados) {
    final firma = [for (final e in r.equipos) (e.map((j) => j.id).toList()..sort()).join(',')].join('|');
    if (vistos.add(firma)) unicos.add(r);
  }
  return unicos.take(top).toList();
}

/// Intercambia parejas de jugadores entre equipos mientras baje el coste ([bloqueados] no se mueven).
void _mejorarConIntercambios(List<List<JugadorBalanceo>> equipos,
    {int maxIteraciones = 500, Set<String> bloqueados = const {}}) {
  var coste = costeReparto(equipos);
  for (var it = 0; it < maxIteraciones; it++) {
    var mejoro = false;
    for (var a = 0; a < equipos.length && !mejoro; a++) {
      for (var b = a + 1; b < equipos.length && !mejoro; b++) {
        for (var i = 0; i < equipos[a].length && !mejoro; i++) {
          for (var j = 0; j < equipos[b].length && !mejoro; j++) {
            final x = equipos[a][i], y = equipos[b][j];
            if (bloqueados.contains(x.id) || bloqueados.contains(y.id)) continue;
            equipos[a][i] = y;
            equipos[b][j] = x;
            final nuevo = costeReparto(equipos);
            if (nuevo + 1e-9 < coste) {
              coste = nuevo;
              mejoro = true;
            } else {
              equipos[a][i] = x;
              equipos[b][j] = y;
            }
          }
        }
      }
    }
    if (!mejoro) break;
  }
}
