import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:futbol_fantasy/features/equipos/balanceo.dart';

List<JugadorBalanceo> _jugadores(List<double> ratings, {List<double>? porteria}) => [
      for (var i = 0; i < ratings.length; i++)
        JugadorBalanceo(id: 'j$i', nombre: 'J$i', rating: ratings[i], habilidadPortero: porteria?[i]),
    ];

void _todosUnaVez(Reparto r, List<JugadorBalanceo> js) {
  final ids = [for (final e in r.equipos) ...e.map((j) => j.id)];
  expect(ids.length, js.length);
  expect(ids.toSet(), js.map((j) => j.id).toSet());
}

void main() {
  group('capitanes fijos', () {
    test('cada capitán queda en su equipo y el reparto sigue equilibrado', () {
      final js = _jugadores([90, 85, 70, 60, 55, 50, 40, 30, 20, 10]);
      // Los dos mejores son capitanes de equipos distintos
      final fijos = {'j0': 0, 'j1': 1};
      for (var semilla = 0; semilla < 20; semilla++) {
        final r = balancear(js, 2, fijos: fijos, rng: Random(semilla)).first;
        _todosUnaVez(r, js);
        expect(r.equipos[0].any((j) => j.id == 'j0'), isTrue);
        expect(r.equipos[1].any((j) => j.id == 'j1'), isTrue);
        expect(r.diferenciaPct, lessThan(10));
      }
    });

    test('también con 3 equipos', () {
      final js = _jugadores([95, 90, 80, 75, 70, 65, 60, 55, 50, 45, 40, 30, 25, 20, 15, 10, 8, 5, 3]);
      final fijos = {'j18': 0, 'j17': 1, 'j0': 2};
      final r = balancear(js, 3, fijos: fijos, rng: Random(1)).first;
      _todosUnaVez(r, js);
      expect(r.equipos[0].any((j) => j.id == 'j18'), isTrue);
      expect(r.equipos[1].any((j) => j.id == 'j17'), isTrue);
      expect(r.equipos[2].any((j) => j.id == 'j0'), isTrue);
    });
  });

  group('balancear con 2 equipos (exhaustivo)', () {
    test('encuentra el reparto perfecto cuando existe', () {
      // 90+10+50+50 = 200 = 80+20+60+40
      final js = _jugadores([90, 80, 60, 50, 50, 40, 20, 10]);
      final r = balancear(js, 2).first;
      _todosUnaVez(r, js);
      expect(r.equipos[0].length, 4);
      expect(r.equipos[1].length, 4);
      expect(r.coste, closeTo(0, 1e-9));
    });

    test('con impares un equipo lleva un jugador más', () {
      final js = _jugadores([70, 60, 55, 50, 45, 40, 30]);
      final r = balancear(js, 2).first;
      _todosUnaVez(r, js);
      final tams = r.equipos.map((e) => e.length).toList()..sort();
      expect(tams, [3, 4]);
    });

    test('con fuerza igual, reparte la habilidad en la portería (todos rotan)', () {
      // Misma fuerza para todos; los dos mejores bajo palos (j0, j1) deben ir a equipos distintos.
      final js = _jugadores([50, 50, 50, 50, 50, 50, 50, 50, 50, 50],
          porteria: [95, 90, 20, 20, 20, 20, 20, 20, 20, 20]);
      final r = balancear(js, 2).first;
      final eq0 = r.equipos.indexWhere((e) => e.any((j) => j.id == 'j0'));
      final eq1 = r.equipos.indexWhere((e) => e.any((j) => j.id == 'j1'));
      expect(eq0, isNot(eq1));
    });

    test('la habilidad en la portería pesa poco frente a la fuerza total', () {
      expect(pesoPorteria, lessThan(0.5));
    });

    test('devuelve como mucho top repartos ordenados por coste', () {
      final js = _jugadores([88, 75, 70, 66, 61, 58, 52, 47, 40, 33]);
      final rs = balancear(js, 2, top: 5);
      expect(rs.length, lessThanOrEqualTo(5));
      for (var i = 1; i < rs.length; i++) {
        expect(rs[i].coste, greaterThanOrEqualTo(rs[i - 1].coste));
      }
    });
  });

  group('balancear con 3 y 4 equipos (serpiente + intercambios)', () {
    test('3 equipos de 5 quedan equilibrados', () {
      final rng = Random(42);
      final js = _jugadores([for (var i = 0; i < 15; i++) 30 + rng.nextDouble() * 60]);
      final r = balancear(js, 3, rng: Random(1)).first;
      _todosUnaVez(r, js);
      expect(r.equipos.map((e) => e.length), everyElement(5));
      expect(r.diferenciaPct, lessThan(10));
    });

    test('4 equipos con 18 jugadores: tamaños 4 o 5', () {
      final js = _jugadores([for (var i = 0; i < 18; i++) (i * 7 % 50) + 25.0]);
      final r = balancear(js, 4, rng: Random(3)).first;
      _todosUnaVez(r, js);
      for (final e in r.equipos) {
        expect(e.length, inInclusiveRange(4, 5));
      }
    });

    test('más de 16 jugadores en 2 equipos usa la heurística y reparte bien', () {
      final js = _jugadores([for (var i = 0; i < 22; i++) 20.0 + i * 3]);
      final r = balancear(js, 2, rng: Random(7)).first;
      _todosUnaVez(r, js);
      expect(r.diferenciaPct, lessThan(5));
    });
  });

  group('calcularRatings', () {
    test('un jugador sin partidos queda en la media del grupo', () {
      final r = calcularRatings({
        'a': const MetricasJugador(partidos: 10, puntosMedia: 12, notaMedia: 8, golesPartido: 1.5),
        'b': const MetricasJugador(partidos: 10, puntosMedia: 4, notaMedia: 5, golesPartido: 0.2),
        'nuevo': const MetricasJugador(partidos: 0),
      });
      expect(r['a']!, greaterThan(r['nuevo']!));
      expect(r['nuevo']!, greaterThan(r['b']!));
    });

    test('las valoraciones manuales tienen prioridad', () {
      final r = calcularRatings(
        {'a': const MetricasJugador(partidos: 3, puntosMedia: 5)},
        manuales: {'a': 77},
      );
      expect(r['a'], 77);
    });
  });
}
