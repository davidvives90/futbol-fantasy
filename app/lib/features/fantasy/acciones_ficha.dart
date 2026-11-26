import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/idioma.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/repos/fantasy_repo.dart';
import 'fantasy_dialogs.dart';
import 'fantasy_providers.dart';
import 'subastas_draft.dart';

/// Todo lo que puedes hacer con un jugador tuyo, en la ficha del jugador y con una explicación corta:
/// subir la cláusula, venderlo ya al mercado, ponerlo en subasta (tú fijas el precio) o cederlo una jornada.
class AccionesMiJugador extends ConsumerWidget {
  const AccionesMiJugador({
    super.key,
    required this.mi,
    required this.jugador,
    required this.nombre,
    required this.saldo,
    required this.abierto,
  });
  final MiLiga mi;
  final JugadorPlantilla jugador;
  final String nombre;
  final double? saldo;
  final bool abierto;

  LigaMiembro get _k => (ligaId: mi.liga.id, miembroId: mi.yo.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = mi.liga.fantasy;
    final j = jugador;
    final fichaId = j.fichaId;
    final t = Theme.of(context).textTheme;
    final proximo = ref.watch(proximoPartidoProvider(mi.liga.id));
    final subasta = (ref.watch(subastasProvider(mi.liga.id)).valueOrNull ?? const <Subasta>[])
        .where((s) => s.abierta && s.fichaId != null && s.fichaId == fichaId && s.vendedorId == mi.yo.id)
        .firstOrNull;
    final ocupada = j.cedidaAOtro || j.enCesionOfrecida || subasta != null;
    final motivoCerrado = !abierto ? tr('El mercado está cerrado hasta que se calculen los puntos del partido.') : null;

    void refrescar() {
      refrescarFantasy(ref, _k);
      ref.invalidate(subastasProvider(mi.liga.id));
    }

    Future<void> subirClausula() async {
      if (fichaId == null) return;
      final nueva = await dialogoClausula(context,
          jugador: nombre, params: p, actual: j.clausula ?? j.precio, precioMercado: j.precio, saldo: saldo);
      if (nueva == null || !context.mounted) return;
      final ok = await ejecutar(context, () => FantasyRepo.fijarClausula(fichaId, nueva),
          ok: trf('Cláusula de {n}: {x}', {'n': nombre, 'x': millones(nueva)}));
      if (ok) refrescar();
    }

    Future<void> venderYa() async {
      final recibes = p.precioVenta(j.precio);
      if (!await confirmar(
        context,
        trf('Vender a {n}', {'n': nombre}),
        trf('Vuelve al mercado al momento. Precio {p} − {c} % de comisión: recibes {r}.', {
          'p': millones(j.precio),
          'c': (p.comisionVenta * 100).toStringAsFixed(0),
          'r': millones(recibes),
        }),
        accion: 'Vender',
        tipo: TipoConfirmacion.peligro,
      )) {
        return;
      }
      if (!context.mounted) return;
      final ok = await ejecutar(context, () => FantasyRepo.vender(mi.liga.id, j.jugadorId, fichaId: fichaId),
          ok: trf('{n} vendido', {'n': nombre}));
      if (ok) refrescar();
    }

    Future<void> subastar() async {
      if (fichaId == null) return;
      final r = await showDialog<(double, int)>(context: context, builder: (_) => _DialogoSubasta(nombre: nombre, precio: j.precio));
      if (r == null || !context.mounted) return;
      final ok = await ejecutar(context, () => FantasyRepo.ponerEnSubasta(fichaId, r.$1, r.$2),
          ok: trf('{n} está en subasta', {'n': nombre}));
      if (ok) refrescar();
    }

    Future<void> cancelarSubasta(Subasta s) async {
      final ok = await ejecutar(context, () => FantasyRepo.cancelarSubasta(s.id), ok: tr('Subasta cancelada'));
      if (ok) refrescar();
    }

    Future<void> ceder() async {
      if (fichaId == null) return;
      final pct = await dialogoCesion(context, jugador: nombre, params: p, precioMercado: j.precio);
      if (pct == null || !context.mounted) return;
      final ok = await ejecutar(context, () => FantasyRepo.ofrecerCesion(fichaId, pct),
          ok: trf('{n} ofrecido en cesión al {x}', {'n': nombre, 'x': pctTexto(pct)}));
      if (ok) refrescar();
    }

    Future<void> retirarCesion() async {
      if (fichaId == null) return;
      final ok = await ejecutar(context, () async {
        final id = await FantasyRepo.miCesionOfrecida(mi.liga.id, fichaId);
        if (id == null) throw tr('La cesión ya no está disponible (aceptada o cerrada).');
        await FantasyRepo.cancelarCesion(id);
      }, ok: tr('Cesión retirada'));
      if (ok) refrescar();
    }

    Widget accion({
      required IconData icono,
      required String titulo,
      required String texto,
      required VoidCallback? onPressed,
      String? boton,
      bool peligro = false,
    }) {
      final cs = Theme.of(context).colorScheme;
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            Icon(icono, color: peligro ? cs.error : cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(texto, style: t.bodySmall),
              ]),
            ),
            const SizedBox(width: 8),
            peligro
                ? OutlinedButton(onPressed: onPressed, child: Text(boton ?? titulo))
                : FilledButton.tonal(onPressed: onPressed, child: Text(boton ?? titulo)),
          ]),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('Tu jugador'), style: t.titleMedium),
      const SizedBox(height: 4),
      if (motivoCerrado != null)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(motivoCerrado, style: t.bodySmall)),
      if (j.cedidaAOtro)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Tx('Está cedido esta jornada: vuelve después del partido.', style: t.bodySmall)),
      // 1. Cláusula
      accion(
        icono: Icons.shield_outlined,
        titulo: tr('Subir cláusula'),
        texto: trf('Ahora {x}. Cuanto más alta, más le cuesta a otro llevárselo. Pagas el {c} % de la subida.', {
          'x': millones(j.clausula ?? j.precio),
          'c': (p.costeSubidaClausula * 100).toStringAsFixed(0),
        }),
        boton: tr('Subir'),
        onPressed: !abierto || j.cedidaAOtro ? null : subirClausula,
      ),
      // 2. Vender ya
      accion(
        icono: Icons.sell_outlined,
        titulo: tr('Vender ya al mercado'),
        texto: trf('Cobras {x} al momento (precio menos comisión).', {'x': millones(p.precioVenta(j.precio))}),
        boton: tr('Vender'),
        peligro: true,
        onPressed: !abierto || ocupada ? null : venderYa,
      ),
      // 3. Subasta
      if (subasta == null)
        accion(
          icono: Icons.gavel,
          titulo: tr('Poner en subasta'),
          texto: tr('Tú fijas el precio de salida y se lo lleva la puja más alta. Si nadie puja, sigue siendo tuyo.'),
          boton: tr('Subastar'),
          onPressed: !abierto || ocupada ? null : subastar,
        )
      else
        accion(
          icono: Icons.gavel,
          titulo: tr('En subasta'),
          texto: [
            trf('Salida {x}', {'x': millones(subasta.precioSalida)}),
            trf('{n} pujas', {'n': subasta.numPujas}),
            if (subasta.mejor != null) trf('mejor {x}', {'x': millones(subasta.mejor)}),
            trf('cierra {f}', {'f': fechaHora(subasta.cierraEn)}),
          ].join(' · '),
          boton: tr('Cancelar'),
          onPressed: subasta.numPujas == 0 ? () => cancelarSubasta(subasta) : null,
        ),
      // 4. Cesión
      if (p.cesionesActivas)
        j.enCesionOfrecida
            ? accion(
                icono: Icons.swap_horiz,
                titulo: tr('Ofrecido en cesión'),
                texto: tr('Otro mánager puede aceptarlo para el próximo partido.'),
                boton: tr('Retirar'),
                onPressed: retirarCesion,
              )
            : accion(
                icono: Icons.swap_horiz,
                titulo: tr('Ceder una jornada'),
                texto: proximo == null
                    ? tr('Cuando haya un partido convocado podrás cederlo para esa jornada.')
                    : tr('Otro mánager lo alinea en el próximo partido y te paga un % de su valor. Luego vuelve contigo.'),
                boton: tr('Ceder'),
                onPressed: j.cedidaAOtro || subasta != null || proximo == null ? null : ceder,
              ),
    ]);
  }
}

class _DialogoSubasta extends StatefulWidget {
  const _DialogoSubasta({required this.nombre, required this.precio});
  final String nombre;
  final double precio;

  @override
  State<_DialogoSubasta> createState() => _DialogoSubastaState();
}

class _DialogoSubastaState extends State<_DialogoSubasta> {
  late final _c = TextEditingController(text: widget.precio.toStringAsFixed(1));
  int _horas = 24;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final precio = double.tryParse(_c.text.trim().replaceAll(',', '.'));
    return AlertDialog(
      title: Text(trf('Subastar a {n}', {'n': widget.nombre})),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trf('Valor de mercado: {x}. Pon el precio mínimo al que lo vendes.', {'x': millones(widget.precio)})),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr('Precio de salida'), suffixText: 'M'),
        ),
        const SizedBox(height: 12),
        Text(tr('Duración'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 12, label: Text('12 h')),
            ButtonSegment(value: 24, label: Text('24 h')),
            ButtonSegment(value: 48, label: Text('48 h')),
          ],
          selected: {_horas},
          onSelectionChanged: (s) => setState(() => _horas = s.first),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Tx('Cancelar')),
        FilledButton(
          onPressed: precio == null || precio <= 0 ? null : () => Navigator.pop(context, (precio, _horas)),
          child: const Tx('Subastar'),
        ),
      ],
    );
  }
}
