// Pruebas de la lógica pura de la app (sin servidor): textos para compartir, calendario, bajas y reglas.
import 'package:flutter_test/flutter_test.dart';
import 'package:futbol_fantasy/core/calendario.dart';
import 'package:futbol_fantasy/core/compartir.dart';
import 'package:futbol_fantasy/data/models.dart';
import 'package:futbol_fantasy/data/repos/reglamento_repo.dart';
import 'package:intl/date_symbol_data_local.dart';

Liga _liga() => Liga.fromMap({
      'id': 'l1',
      'nombre': 'Lunes',
      'jugadores_por_equipo': 5,
      'num_equipos': 2,
      'campo_nombre': 'La Salle',
      'duracion_partido_min': 60,
    });

Partido _partido() => Partido(
      id: 'p1',
      ligaId: 'l1',
      fechaHora: DateTime.utc(2026, 12, 14, 20),
      horaConfirmada: true,
      plazas: 10,
      numEquipos: 2,
      costeTotal: 50,
      estado: EstadoPartido.abierto,
    );

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('Compartir', () {
    test('convocatoria: confirmados numerados y cuántos faltan', () {
      final t = textoPartido({
        'liga': 'Lunes',
        'fecha': '2026-12-14T20:00:00Z',
        'campo': 'La Salle',
        'plazas': 10,
        'confirmados': ['Ana', 'Luis', 'Pepe'],
        'espera': [],
        'equipos': {},
        'encuentros': [],
      }, _liga(), 'p1');
      expect(t, contains('*3/10 confirmados*'));
      expect(t, contains('1. Ana'));
      expect(t, contains('¡Faltan 7!'));
      expect(t, contains('#/partidos/p1'));
    });

    test('equipos hechos: nombre de la equipación', () {
      final t = textoPartido({
        'liga': 'Lunes',
        'fecha': '2026-12-14T20:00:00Z',
        'plazas': 4,
        'confirmados': ['Ana', 'Luis', 'Pepe', 'Rosa'],
        'equipos': {'1': ['Ana', 'Luis'], '2': ['Pepe', 'Rosa']},
        'encuentros': [{'n': 1, 'local': 1, 'visitante': 2, 'goles_local': null, 'goles_visitante': null}],
      }, _liga(), 'p1');
      expect(t, contains('*Blanco*: Ana, Luis'));
      expect(t, contains('*Color*: Pepe, Rosa'));
      expect(t, isNot(contains('confirmados')));
    });

    test('resultado: marcador, goleadores y MVP', () {
      final t = textoPartido({
        'liga': 'Lunes',
        'fecha': '2026-12-14T20:00:00Z',
        'plazas': 4,
        'equipos': {'1': ['Ana'], '2': ['Pepe']},
        'encuentros': [{'n': 1, 'local': 1, 'visitante': 2, 'goles_local': 5, 'goles_visitante': 3}],
        'goleadores': [{'nombre': 'Ana', 'goles': 3}, {'nombre': 'Pepe', 'goles': 1}],
        'mvp': ['Ana'],
      }, _liga(), 'p1');
      expect(t, contains('Blanco 5 – 3 Color'));
      expect(t, contains('Ana (3), Pepe'));
      expect(t, contains('MVP: Ana'));
    });
  });

  group('Calendario', () {
    test('.ics válido con hora en UTC, duración y aviso', () {
      final ics = icsDePartidos([_partido()], _liga());
      expect(ics, startsWith('BEGIN:VCALENDAR'));
      expect(ics, contains('DTSTART:20261214T200000Z'));
      expect(ics, contains('DTEND:20261214T210000Z'));
      expect(ics, contains('LOCATION:La Salle'));
      expect(ics, contains('TRIGGER:-PT2H'));
      expect(ics, contains('\r\n'));
    });

    test('enlace de Google Calendar', () {
      final u = enlaceGoogleCalendar(_partido(), _liga());
      expect(u.host, 'calendar.google.com');
      expect(u.queryParameters['dates'], '20261214T200000Z/20261214T210000Z');
    });
  });

  group('Bajas', () {
    test('una baja cubre sus días (incluidos los extremos)', () {
      final a = Ausencia({'id': 'a', 'miembro_id': 'm', 'desde': '2026-12-01', 'hasta': '2026-12-15', 'motivo': 'lesion'});
      expect(a.cubre(DateTime(2026, 12, 1, 21)), isTrue);
      expect(a.cubre(DateTime(2026, 12, 15, 21)), isTrue);
      expect(a.cubre(DateTime(2026, 12, 16, 10)), isFalse);
      expect(a.cubre(DateTime(2026, 11, 30, 10)), isFalse);
    });

    test('sin fecha de vuelta cubre todo lo posterior', () {
      final a = Ausencia({'id': 'a', 'miembro_id': 'm', 'desde': '2026-12-01', 'hasta': null});
      expect(a.cubre(DateTime(2027, 6, 1)), isTrue);
    });
  });

  group('Reglamento', () {
    test('textos de los valores', () {
      final cesion = ReglaJuego({'clave': 'cesion', 'grupo': 'juego', 'titulo': 'Cesión', 'tipo': 'si_no', 'valor': false});
      expect(cesion.textoValor, 'No');
      final saque = ReglaJuego({
        'clave': 'saque_banda',
        'grupo': 'juego',
        'titulo': 'Saque de banda',
        'tipo': 'opcion',
        'valor': 'pie',
        'opciones': [{'valor': 'mano', 'texto': 'Con la mano'}, {'valor': 'pie', 'texto': 'Con el pie'}],
      });
      expect(saque.textoValor, 'Con el pie');
      expect(saque.valoresPosibles, ['mano', 'pie']);
      final minutos = ReglaJuego({'clave': 'm', 'grupo': 'partido', 'titulo': 'Min', 'tipo': 'numero', 'valor': 25, 'unidad': 'min'});
      expect(minutos.textoValor, '25 min');
    });
  });

  test('modalidades con nombre', () {
    expect(nombresModalidad['sala'], 'Fútbol sala');
    expect(_liga().nombreModalidad, 'Fútbol 7'); // sin dato: valor por defecto
  });
}
