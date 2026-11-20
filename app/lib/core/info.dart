import 'package:flutter/material.dart';

/// Botón «i»: abre una hoja con la explicación de algo que no es evidente.
/// Usar el texto de [Ayuda] para que la misma explicación se lea igual en toda la app.
class InfoBoton extends StatelessWidget {
  const InfoBoton(this.ayuda, {super.key, this.tamano = 18});
  final (String, String) ayuda;
  final double tamano;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Qué es «${ayuda.$1}»',
        visualDensity: VisualDensity.compact,
        iconSize: tamano,
        icon: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onSurfaceVariant),
        onPressed: () => mostrarAyuda(context, ayuda),
      );
}

void mostrarAyuda(BuildContext context, (String, String) ayuda) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline, color: Theme.of(c).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(ayuda.$1, style: Theme.of(c).textTheme.titleLarge)),
          ]),
          const SizedBox(height: 12),
          Text(ayuda.$2, style: Theme.of(c).textTheme.bodyLarge),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido')),
          ),
        ]),
      ),
    ),
  );
}

/// Textos de ayuda (título, explicación). Una sola fuente para la «i» y para la Guía.
abstract final class Ayuda {
  static const rangos = ('Fijo, reserva e invitado',
      'Fijo: entra solo en cada partido y paga la factura del campo. Si no puede ir, marca «No voy».\n\n'
          'Reserva: se apunta con «Voy» y entra en la lista de espera; pasa dentro en cuanto queda una plaza libre.\n\n'
          'Invitado: alguien de fuera. Entra el último de la lista de espera y, en el Fantasy, cada mánager puede tener como mucho uno.');
  static const listaEspera = ('Lista de espera',
      'Cuando no quedan plazas, los que pulsan «Voy» esperan aquí. Si alguien se da de baja, entra automáticamente el primero '
          'y le llega un aviso.\n\nEl orden lo elige el administrador: por prioridad (fijos, luego reservas, luego invitados) '
          'o por orden de apuntarse.');
  static const noMeFije = ('«No me fijé»',
      'Si no sabes quién marcó en un equipo, márcalo y no envías datos de ese equipo. Cuentan los partes del resto, '
          'así que no pasa nada: es mejor que inventarse un gol.');
  static const cotejo = ('Goles asignados',
      'La suma de goles de los jugadores (más los autogoles del rival) tiene que coincidir con el resultado. '
          'Verde: cuadra. Ámbar: faltan goles por asignar. Rojo: sobran.');
  static const notas = ('Notas del 1 al 5',
      '3 es un partido normal; empiezan todos ahí, así que solo tienes que tocar a quien se salió de lo normal.\n\n'
          'Las notas son anónimas. Cuentan cuando valoran al menos 3 compañeros: la media da hasta 4 puntos en la clasificación.');
  static const mvp = ('MVP',
      'Cada uno vota a su MVP (no puedes votarte). El MVP del partido es el de mejor nota media; si hay empate, '
          'decide quién tiene más votos de MVP y después goles + asistencias. Suma 3 puntos.');
  static const destacados = ('«Destacó en…»',
      'Opcional: marca en qué destacó un compañero (hasta 2 cosas). No suma puntos, pero alimenta sus estadísticas '
          '(«Destacó en defensa ×5») y ayuda a hacer equipos equilibrados.');
  static const disputas = ('Datos en disputa',
      'Cada jugador envía su parte y la app se queda con lo que dice la mayoría. Si no hay mayoría clara (o no hay '
          'suficientes partes), el dato queda en disputa y el administrador decide el valor correcto.\n\n'
          'Un descuadre es cuando los goles de los jugadores no suman el resultado: se arregla corrigiendo los goles o el resultado.');
  static const puntos = ('Cómo se puntúa',
      'Jugar: 2 · Victoria: 3 · Empate: 1 · Gol: 5 · Asistencia: 3 · Cada 2 paradas clave: 1 · Penalti parado: 3 · '
          'Penalti fallado: −2 · Autogol: −2 · Nota de los compañeros: hasta 4 · MVP: 3.\n\n'
          'El administrador puede cambiar estos valores en Ajustes → Puntuación.');
  static const valorMercado = ('Valor de mercado',
      'Parte de la encuesta inicial (6 rankings: calidad, velocidad, resistencia, defensa, regate y portería) y, '
          'a partir del 3.er partido, se mueve con el rendimiento real y con la demanda: como mucho ±15 % por jornada.');
  static const fichas = ('Fichas',
      'Cada jugador tiene un número limitado de fichas (copias) para que no todo el mundo tenga al mismo. '
          'Si no quedan, solo puedes conseguirlo comprándoselo a otro mánager o pagando su cláusula.');
  static const clausula = ('Cláusula de rescisión',
      'Precio al que cualquiera puede quitarte un jugador sin preguntarte. Tú la fijas: subirla cuesta un porcentaje de la subida; '
          'bajarla es gratis, pero será más fácil que te lo quiten. Recién fichado está protegido unas jornadas.');
  static const cesion = ('Cesión',
      'Prestas un jugador una jornada a otro mánager a cambio de un porcentaje de su valor que fijas tú. '
          'Puntúa para él esa jornada y luego vuelve a tu plantilla.');
  static const alineacion = ('Alineación',
      'Elige a quién alineas en cada partido. Se cierra unas horas antes (lo fija el admin) y ya no se puede cambiar. '
          'Solo puntúan los alineados.');
  static const rolesBonus = ('Bonus por rol',
      'Si la liga lo tiene activado, el rol que pones en la alineación da puntos extra: portero con portería a cero o '
          'el menos goleado, defensa del equipo menos goleado, medio que asiste y delantero que marca. '
          'Si está desactivado, el rol es solo estético.');
  static const multiplicadorInvitado = ('Multiplicador de invitados',
      'Si está activado, los puntos de un invitado se multiplican (por ejemplo ×1,5) para quien lo tenga alineado: '
          'premia arriesgar con alguien que viene poco. Desactivado, puntúa como todos.');
  static const facturaMensual = ('Factura mensual',
      'El campo cobra a mes vencido. Al subir la factura, la app resta lo que han pagado reservas e invitados y '
          'reparte el resto entre los fijos según los partidos que ha jugado cada uno.');
}
