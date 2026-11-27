import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'compartir.dart';
import 'idioma.dart';
import 'liga_activa.dart';
import 'ventajas.dart';

/// 0060: tarjetas explicativas por pantalla. Se ven solas la primera vez (como aviso pequeño, nunca a la fuerza),
/// siempre desde el botón «?» de cada pantalla y desde Perfil › Cómo funciona. Cada tarjeta se comparte como imagen.
class TarjetaGuia {
  const TarjetaGuia(this.icono, this.color, this.titulo, this.texto, {this.masGuia});
  final IconData icono;
  final Color color;
  final String titulo, texto;

  /// Guía con más tarjetas sobre este tema («Saber más»).
  final String? masGuia;
}

class Guia {
  const Guia(this.id, this.titulo, this.icono, this.tarjetas);
  final String id, titulo;
  final IconData icono;
  final List<TarjetaGuia> tarjetas;
}

const _verde = Color(0xFF2E7D32), _azul = Color(0xFF1565C0), _morado = Color(0xFF6A1B9A), _rojo = Color(0xFFC8102E),
    _naranja = Color(0xFFE65100), _oro = Color(0xFFB7791F), _turquesa = Color(0xFF00838F);

/// Las 3 de bienvenida: cada una lleva a su guía con más detalle.
Guia guiaBienvenida({bool fantasy = true}) => Guia('bienvenida', 'Así funciona', Icons.waving_hand_outlined, [
      const TarjetaGuia(Icons.touch_app_rounded, _verde, 'Apúntate con un toque',
          'Cuando haya partido, pulsa «Voy». Si eres fijo ya estás en la lista; si no puedes, «No voy» y entra el primer suplente.',
          masGuia: 'partido'),
      const TarjetaGuia(Icons.sports_soccer_rounded, _azul, 'Juega y puntúa',
          'Al acabar, apunta el resultado y quién marcó, y da estrellas a tus compañeros. Así salen los puntos y la clasificación.',
          masGuia: 'post_partido'),
      fantasy
          ? const TarjetaGuia(Icons.shield_rounded, _morado, 'Ficha y gana',
              'En el Fantasy tienes dinero para fichar a jugadores de tu liga. Elige a quien creas que va a brillar: sus puntos son los tuyos.',
              masGuia: 'fantasy')
          : const TarjetaGuia(Icons.calendar_month_rounded, _morado, 'Todo de un vistazo',
              'En Inicio ves los partidos de todas tus ligas y lo que tienes pendiente: responder, votar o pagar.',
              masGuia: 'inicio'),
    ]);

const guias = <String, Guia>{
  'inicio': Guia('inicio', 'Inicio', Icons.home_outlined, [
    TarjetaGuia(Icons.event_available, _verde, 'Tu próximo partido',
        'Arriba del todo, en grande: día, hora, campo, cuántos vais y tus botones Voy, Duda y No voy. Con un toque, respondido.'),
    TarjetaGuia(Icons.notifications_active_outlined, _naranja, 'Lo pendiente',
        'Si tienes que votar, pagar o responder, sale aquí primero. Cuando no hay nada, no molesta.'),
    TarjetaGuia(Icons.layers_outlined, _azul, 'Todas tus ligas',
        'Si juegas en varias ligas, elige arriba «Todas mis ligas» o solo una. Cada liga tiene su color.'),
  ]),
  'partido': Guia('partido', 'Convocatoria', Icons.how_to_reg_outlined, [
    TarjetaGuia(Icons.touch_app_rounded, _verde, 'Voy, Duda o No voy',
        'Responde en cuanto puedas: así se sabe enseguida si hay partido. La app avisa el día antes y unas horas antes a quien no ha contestado.'),
    TarjetaGuia(Icons.hourglass_top_rounded, _naranja, 'Fijos y lista de espera',
        'Los fijos tienen plaza guardada. Si el partido está lleno, te apuntas de suplente: si alguien se borra, entras tú solo y te llega un aviso.'),
    TarjetaGuia(Icons.balance_rounded, _azul, 'Equipos nivelados',
        'La app reparte los equipos según puntos, goles y valoraciones de cada uno para que el partido esté igualado. También dice quién parte con ventaja.'),
    TarjetaGuia(Icons.share_rounded, _turquesa, 'Compártelo en el grupo',
        'Con el botón de compartir mandas la convocatoria, los equipos o el resultado al grupo de WhatsApp, en texto o como imagen.'),
  ]),
  'post_partido': Guia('post_partido', 'Después del partido', Icons.scoreboard_outlined, [
    TarjetaGuia(Icons.scoreboard_outlined, _azul, 'Apunta el resultado',
        'Cualquiera que haya jugado puede apuntar el resultado y quién marcó. Si varios lo apuntan, vale lo que dice la mayoría.'),
    TarjetaGuia(Icons.star_rounded, _oro, 'Valora a tus compañeros',
        'Da estrellas a los que jugaron contigo (a ti no). Cuenta la media de todos: un voto raro no estropea nada.'),
    TarjetaGuia(Icons.emoji_events_rounded, _naranja, 'El MVP',
        'Elige a los 3 mejores por orden. El más votado es el MVP y gana puntos extra.'),
    TarjetaGuia(Icons.leaderboard_rounded, _verde, 'Así salen los puntos',
        'Jugar, ganar, marcar, asistir, la nota de los compañeros y el MVP suman puntos. Con ellos se hacen la clasificación y el Fantasy.'),
  ]),
  'clasificacion': Guia('clasificacion', 'Clasificación', Icons.leaderboard_outlined, [
    TarjetaGuia(Icons.leaderboard_rounded, _verde, 'Rankings',
        'Puntos, goles, asistencias, MVP y nota media. Desliza para ver cada ranking; arriba eliges esta temporada o el histórico.'),
    TarjetaGuia(Icons.star_rounded, _oro, 'Equipo ideal',
        'Los que más puntos sacaron en la última jornada o en el último mes. Compártelo en el grupo como imagen.'),
    TarjetaGuia(Icons.compare_arrows_rounded, _rojo, 'Cara a cara',
        'En la ficha de cada jugador ves su balance contra cada compañero y con quién gana más cuando juegan juntos.'),
    TarjetaGuia(Icons.workspace_premium_rounded, _morado, 'Temporadas y palmarés',
        'Al cerrar una temporada se reparten los trofeos: campeón, pichichi, MVP… y quedan en la vitrina de cada uno.'),
  ]),
  'fantasy': Guia('fantasy', 'Fantasy', Icons.shield_outlined, [
    TarjetaGuia(Icons.shield_rounded, _morado, 'Tu equipo Fantasy',
        'Eres mánager: tienes dinero para fichar a jugadores de tu liga. Cuando ellos juegan bien, tú sumas sus puntos.'),
    TarjetaGuia(Icons.storefront_rounded, _verde, 'Fichar en el mercado',
        'Cada jugador tiene un precio que sube si juega bien y baja si no (verde sube, rojo baja). Ficha barato al que va a brillar.'),
    TarjetaGuia(Icons.format_list_numbered_rounded, _azul, 'La alineación',
        'Antes de cada partido elige tus titulares y el banquillo con un toque. Si un titular no juega, entra el primero del banquillo.'),
    TarjetaGuia(Icons.trending_up_rounded, _oro, 'Puntos y dinero',
        'Sumas los puntos de tus titulares (el capitán, doble). Cada punto te da dinero para seguir fichando.'),
    TarjetaGuia(Icons.sell_rounded, _rojo, 'Vender, subastar y ceder',
        'Desde la ficha de tu jugador: vender ya al mercado, ponerlo en subasta con tu precio, subirle la cláusula para que no te lo quiten o cederlo una jornada.'),
  ]),
  'porra': Guia('porra', 'Porra', Icons.casino_outlined, [
    TarjetaGuia(Icons.casino_rounded, _naranja, 'La porra',
        'Antes del partido, pronostica quién gana, el resultado, el MVP o si alguien marca. Se juega con el dinero o los puntos del Fantasy, nunca con dinero real.'),
    TarjetaGuia(Icons.savings_rounded, _oro, 'El bote',
        'Como la quiniela: pagas una entrada y pronosticas el resultado. El pleno se lleva el 70 % y el 1X2 reparte el 30 %. Si nadie acierta, se acumula. La liga pone el primer fondo.'),
    TarjetaGuia(Icons.visibility_rounded, _turquesa, 'Todo a la vista',
        'Las apuestas y el bote son públicos: todos ven lo que juega cada uno y el resumen de aciertos de la liga.'),
    TarjetaGuia(Icons.calculate_rounded, _azul, 'Cuotas',
        'Las cuotas salen de las estadísticas de cada equipo: lo fácil paga poco y lo difícil, mucho. Se cierra cuando empieza el partido.'),
    TarjetaGuia(Icons.health_and_safety_rounded, _verde, 'Con cabeza',
        'Hay un máximo por partido y por boleto, y la porra solo existe en ligas donde todos son mayores de 18 años.'),
  ]),
  'caja': Guia('caja', 'Pagos', Icons.payments_outlined, [
    TarjetaGuia(Icons.account_balance_wallet_rounded, _verde, 'Cuentas claras',
        'Cada partido sabe cuánto toca pagar por cabeza. En Pagos ves quién debe y cuánto, sin hojas de cálculo.'),
    TarjetaGuia(Icons.check_circle_rounded, _azul, '«Ya he pagado»',
        'Cuando pagues (Bizum, efectivo…), pulsa «Ya he pagado». El administrador lo confirma y desaparece de la lista.'),
    TarjetaGuia(Icons.campaign_rounded, _naranja, 'Recordatorios',
        'Si la liga quiere, la app recuerda las deudas cada semana o cada mes. Nadie tiene que ir persiguiendo a nadie.'),
  ]),
};

/// Todas las guías, para Perfil › Cómo funciona.
List<Guia> todasLasGuias({bool fantasy = true, bool porra = false}) => [
      guias['inicio']!, guias['partido']!, guias['post_partido']!, guias['clasificacion']!,
      if (fantasy) guias['fantasy']!,
      if (porra) guias['porra']!,
      guias['caja']!,
    ];

String _claveVista(String id) => 'guia_vista_$id';

/// Abre una guía a pantalla completa.
Future<void> abrirGuia(BuildContext context, Guia g) async {
  await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => SinPublicidad(child: VisorGuia(guia: g))));
}

/// Botón «?» para la barra de cada pantalla.
class BotonGuia extends ConsumerWidget {
  const BotonGuia(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = guias[id];
    if (g == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: tr('Cómo funciona'),
      icon: const Icon(Icons.help_outline),
      onPressed: () {
        ref.read(prefsProvider).setBool(_claveVista(id), true);
        abrirGuia(context, g);
      },
    );
  }
}

/// Aviso pequeño la primera vez que entras en una pantalla: «¿Primera vez? Míralo en N tarjetas». Se quita solo.
class AvisoGuia extends ConsumerStatefulWidget {
  const AvisoGuia(this.id, {super.key});
  final String id;

  @override
  ConsumerState<AvisoGuia> createState() => _AvisoGuiaState();
}

class _AvisoGuiaState extends ConsumerState<AvisoGuia> {
  bool _oculto = false;

  void _marcar() {
    ref.read(prefsProvider).setBool(_claveVista(widget.id), true);
    setState(() => _oculto = true);
  }

  @override
  Widget build(BuildContext context) {
    final g = guias[widget.id];
    if (g == null || _oculto || (ref.watch(prefsProvider).getBool(_claveVista(widget.id)) ?? false)) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final color = g.tarjetas.first.color;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: Color.alphaBlend(color.withValues(alpha: 0.10), cs.surface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withValues(alpha: 0.4))),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _marcar();
          abrirGuia(context, g);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            Icon(g.icono, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trf('¿Primera vez en {s}?', {'s': tr(g.titulo)}), style: Theme.of(context).textTheme.titleSmall),
                Text(trf('Míralo en {n} tarjetas', {'n': g.tarjetas.length}), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            IconButton(tooltip: tr('Cerrar'), icon: const Icon(Icons.close, size: 18), onPressed: _marcar),
          ]),
        ),
      ),
    );
  }
}

/// Visor: tarjetas deslizables con «Saber más» (otra guía) y «Compartir» (como imagen).
class VisorGuia extends StatefulWidget {
  const VisorGuia({super.key, required this.guia});
  final Guia guia;

  @override
  State<VisorGuia> createState() => _VisorGuiaState();
}

class _VisorGuiaState extends State<VisorGuia> {
  final _pc = PageController(viewportFraction: 0.88);
  int _i = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tarjetas = widget.guia.tarjetas;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ultima = _i == tarjetas.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
            child: Row(children: [
              Expanded(child: Text(tr(widget.guia.titulo), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => Navigator.pop(context), child: Tx(ultima ? 'Cerrar' : 'Saltar')),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pc,
              onPageChanged: (i) => setState(() => _i = i),
              children: [
                for (var k = 0; k < tarjetas.length; k++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
                    child: VistaTarjetaGuia(
                      tarjeta: tarjetas[k],
                      numero: k + 1,
                      total: tarjetas.length,
                      onMas: tarjetas[k].masGuia == null || guias[tarjetas[k].masGuia] == null
                          ? null
                          : () => abrirGuia(context, guias[tarjetas[k].masGuia]!),
                      onCompartir: () => compartirImagen(
                        context,
                        SizedBox(width: 360, height: 480, child: VistaTarjetaGuia(tarjeta: tarjetas[k], paraImagen: true)),
                        nombre: 'pachanga-fantasy.png',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < tarjetas.length; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: k == _i ? 22 : 8,
                height: 8,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: k == _i ? cs.primary : cs.outlineVariant),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => ultima
                    ? Navigator.pop(context)
                    : _pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(tr(ultima ? 'Entendido' : 'Siguiente'), style: const TextStyle(fontSize: 17)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Una tarjeta: cabecera de color con el icono y el texto debajo. [paraImagen]: con la marca y sin botones.
class VistaTarjetaGuia extends StatelessWidget {
  const VistaTarjetaGuia(
      {super.key, required this.tarjeta, this.numero, this.total, this.onMas, this.onCompartir, this.paraImagen = false});
  final TarjetaGuia tarjeta;
  final int? numero, total;
  final VoidCallback? onMas, onCompartir;
  final bool paraImagen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final color = tarjeta.color;
    final fondo = paraImagen ? Colors.white : cs.surfaceContainerLow;
    final tinta = paraImagen ? const Color(0xFF1F1F1F) : cs.onSurface;
    final tintaSuave = paraImagen ? const Color(0xFF555555) : cs.onSurfaceVariant;
    return Material(
      color: fondo,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: paraImagen ? null : Border.all(color: cs.outlineVariant),
        ),
        child: Column(children: [
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, Color.lerp(color, Colors.black, 0.35)!],
                ),
              ),
              child: Stack(children: [
                Positioned(right: -30, bottom: -30, child: Icon(tarjeta.icono, size: 200, color: Colors.white.withValues(alpha: 0.08))),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                    child: Icon(tarjeta.icono, size: 72, color: Colors.white),
                  ),
                ),
                if (numero != null && total != null)
                  Positioned(
                    left: 18,
                    top: 16,
                    child: Text('$numero/$total', style: t.labelLarge?.copyWith(color: Colors.white70, fontWeight: FontWeight.w700)),
                  ),
                if (onCompartir != null)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: IconButton(
                      tooltip: tr('Compartir como imagen'),
                      icon: const Icon(Icons.share, color: Colors.white),
                      onPressed: onCompartir,
                    ),
                  ),
                if (paraImagen)
                  const Positioned(
                    left: 18,
                    top: 16,
                    child: Text('PACHANGA FANTASY',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 12)),
                  ),
              ]),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(tarjeta.titulo), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: tinta)),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    physics: paraImagen ? const NeverScrollableScrollPhysics() : null,
                    child: Text(tr(tarjeta.texto), style: t.bodyLarge?.copyWith(color: tintaSuave, height: 1.35)),
                  ),
                ),
                if (onMas != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onMas,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.chevron_right),
                      label: const Tx('Saber más'),
                    ),
                  ),
                if (paraImagen)
                  Text('pachangafantasy.com', style: t.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Perfil › Cómo funciona: todas las guías.
class GuiasScreen extends StatelessWidget {
  const GuiasScreen({super.key, this.fantasy = true, this.porra = false});
  final bool fantasy, porra;

  @override
  Widget build(BuildContext context) {
    final lista = [guiaBienvenida(fantasy: fantasy), ...todasLasGuias(fantasy: fantasy, porra: porra)];
    return Scaffold(
      appBar: AppBar(title: const Tx('Cómo funciona')),
      body: ListView(children: [
        for (final g in lista)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: g.tarjetas.first.color.withValues(alpha: 0.15),
              child: Icon(g.icono, color: g.tarjetas.first.color),
            ),
            title: Text(tr(g.titulo)),
            subtitle: Text(trf('{n} tarjetas', {'n': g.tarjetas.length})),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => abrirGuia(context, g),
          ),
      ]),
    );
  }
}
