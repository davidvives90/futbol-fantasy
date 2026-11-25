import 'package:flutter/material.dart';
import 'idioma.dart';

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
            child: TextButton(onPressed: () => Navigator.pop(c), child: const Tx('Entendido')),
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
  static const apertura = ('Apertura de la convocatoria',
      'La convocatoria de cada partido empieza vacía y se abre unas horas después de acabar el anterior '
          '(2 h por defecto). Entonces todos, también los fijos, pulsan «Voy», «Duda» o «No voy».\n\n'
          'Los fijos tienen su plaza guardada hasta 24 h antes del partido. Si no contestan a tiempo, '
          'su plaza pasa al primero de la lista de espera.');
  static const repartoInicial = ('Equipo inicial del Fantasy',
      'Al empezar, cada mánager recibe 5 jugadores al azar pero compensados: todos los equipos valen más o menos lo mismo. '
          'Además recibe un dinero inicial pequeño (1,5 veces el precio medio de un jugador) para su primer fichaje. '
          'Los jugadores que no se reparten se quedan en el mercado.');
  static const listaEspera = ('Suplentes',
      'Los fijos están siempre en la lista. Los demás se apuntan de suplentes y, en cuanto un fijo dice «No voy», '
          'entra el primero de la lista (por orden de apuntarse) y le llega un aviso.');
  static const noMeFije = ('«No me fijé»',
      'Si no sabes quién marcó en un equipo, márcalo y no envías datos de ese equipo. Cuentan los partes del resto, '
          'así que no pasa nada: es mejor que inventarse un gol.');
  static const cotejo = ('Goles asignados',
      'La suma de goles de los jugadores (más los autogoles del rival) tiene que coincidir con el resultado. '
          'Verde: cuadra. Ámbar: faltan goles por asignar. Rojo: sobran. Cada asistencia es de un gol: no puede haber más '
          'asistencias que goles.');
  static const notas = ('Notas del 1 al 5',
      '3 es un partido normal; empiezan todos ahí, así que solo tienes que tocar a quien se salió de lo normal.\n\n'
          'Las notas son anónimas. Cuentan cuando valoran al menos 3 compañeros: la media da hasta 4 puntos en la clasificación.');
  static const mvp = ('MVP',
      'Cada uno vota a su MVP (no puedes votarte). El MVP del partido es el de mejor nota media; si hay empate, '
          'decide quién tiene más votos de MVP y después goles + asistencias. Suma 3 puntos.');
  static const podio = ('Podio Top 3',
      'Cada uno elige a los 3 mejores del partido por orden (no puedes votarte). Cada voto suma puntos de votación '
          '(5, 3 y 1 por defecto). El que más suma es el MVP; si empatan, decide quién tiene más votos de 1.º, '
          'luego de 2.º y luego goles + asistencias. Los 3 primeros suman puntos Fantasy según su puesto.');
  static const destacados = ('«Destacó en…»',
      'Opcional: marca en qué destacó un compañero (hasta 2 cosas). No suma puntos, pero alimenta sus estadísticas '
          '(«Destacó en defensa ×5») y ayuda a hacer equipos equilibrados.');
  static const disputas = ('Cómo se cruzan los partes',
      'Cada jugador envía su parte y la app los pondera (el del admin pesa un poco más). Si la mayoría dice lo mismo, '
          'vale eso. Si no, se queda con el valor del medio y reparte goles y asistencias para que siempre cuadren con '
          'el resultado: un equipo no puede tener más goles que los que marcó ni más asistencias que goles.\n\n'
          'Solo se pregunta al administrador lo que de verdad no está claro (por ejemplo, si no se ponen de acuerdo en '
          'quién ganó). La app propone lo más probable y basta con un toque para aceptarlo.');
  static const puntos = ('Cómo se puntúa',
      'Jugar: 2 · Victoria: 3 · Empate: 1 · Gol: 5 · Asistencia: 3 · Cada 2 paradas clave: 1 · Penalti parado: 3 · '
          'Penalti fallado: −2 · Autogol: −2 · Nota de los compañeros: hasta 4 · MVP: 3.\n\n'
          'El administrador puede cambiar estos valores en Ajustes → Puntuación.');
  static const valorMercado = ('Valor de mercado',
      'Todos empiezan con un valor parecido. Después de cada partido se recalcula:\n'
          '• Rendimiento (8 últimos partidos, los recientes pesan más): 65 % sus puntos Fantasy y 35 % la nota de los '
          'compañeros, comparados con el resto de la liga.\n'
          '• Con pocos partidos pesa más su valor de partida; a los 3 partidos ya cuenta la mitad su rendimiento.\n'
          '• Si muchos mánagers lo tienen, sube un poco más (demanda).\n'
          'Como mucho cambia un 15 % por jornada.');
  static const calidad = ('Calidad',
      'Un único número del 1 al 100 que resume lo bueno que es el jugador en esta liga.\n'
          '• Sale de sus últimos partidos (puntos Fantasy y nota de los compañeros), comparados con el resto.\n'
          '• Si la liga hace valoraciones, la opinión de los compañeros también cuenta.\n'
          '• Es lo que mueve su valor de mercado y lo que usa el generador para hacer equipos igualados.');
  static const fichas = ('Copias de cada jugador',
      'Cada jugador tiene 5 copias, así que hasta 5 mánagers pueden tenerlo a la vez.\n'
          '• Comprar una copia libre no se la quita a nadie.\n'
          '• Pagar la cláusula de la copia de otro mánager sí: él lo pierde y cobra lo que pagas.\n'
          '• Si no quedan copias libres, solo puedes conseguirlo con la cláusula o con una oferta.');
  static const clausula = ('Cláusula',
      'Precio al que cualquiera puede quitarte un jugador sin preguntarte. Tú la fijas: subirla cuesta un porcentaje de la subida; '
          'bajarla es gratis, pero será más fácil que te lo quiten. Recién fichado está protegido 7 días (lo fija el admin).');
  static const cesion = ('Cesión',
      'Prestas un jugador una jornada a otro mánager a cambio de un porcentaje de su valor que fijas tú. '
          'Puntúa para él esa jornada y luego vuelve a tu plantilla.');
  static const alineacion = ('Alineación',
      'Elige a quién alineas en cada partido. Se cierra unas horas antes (lo fija el admin) y ya no se puede cambiar. '
          'Solo puntúan los alineados. Si se te olvida, juegas con tu última alineación o, si no tienes, '
          'con tus mejores jugadores.');
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
