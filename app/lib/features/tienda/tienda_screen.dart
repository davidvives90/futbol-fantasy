import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/idioma.dart';
import '../../core/utils.dart';
import '../../core/ventajas.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/master_repo.dart';
import '../fantasy/fantasy_providers.dart';

/// Productos (precios orientativos: los definitivos se fijan en Google Play Console).
const _sinAnuncios = <(String, String, String, String?)>[
  ('ads_1_anio', '1 año sin anuncios', '2,99 €', null),
  ('ads_siempre', 'Para siempre · pagas una vez', '7,99 €', 'Mejor opción'),
];
const _packsDinero = <(String, double, String)>[
  ('dinero_1', 1, '0,99 €'),
  ('dinero_3', 3, '1,99 €'),
  ('dinero_6', 6, '2,99 €'),
];

/// Tienda: quitar anuncios (cuenta) y dinero Fantasy (liga activa), y canjear códigos de los dos tipos.
/// Los pagos con Google Play se activan cuando la app esté publicada; los códigos ya funcionan.
class TiendaScreen extends ConsumerStatefulWidget {
  const TiendaScreen({super.key});

  @override
  ConsumerState<TiendaScreen> createState() => _TiendaScreenState();
}

class _TiendaScreenState extends ConsumerState<TiendaScreen> {
  final _codigo = TextEditingController();
  bool _canjeando = false;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _canjear(MiLiga? mi) async {
    final codigo = _codigo.text.trim();
    if (codigo.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _canjeando = true);
    Map<String, dynamic>? r;
    final ok = await ejecutar(context, () async => r = await MasterRepo.canjear(codigo, ligaId: mi?.liga.id));
    if (!mounted) return;
    setState(() => _canjeando = false);
    if (!ok || r == null) return;
    _codigo.clear();
    ref.invalidate(ventajasProvider);
    if (mi != null) refrescarFantasy(ref, (ligaId: mi.liga.id, miembroId: mi.yo.id));
    final res = r!;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(res['tipo'] == 'sin_anuncios' ? Icons.verified_rounded : Icons.payments_rounded, size: 48),
        title: Text(tr('¡Código canjeado!')),
        content: Text(res['tipo'] == 'sin_anuncios'
            ? (res['para_siempre'] == true
                ? tr('Ya no verás anuncios nunca más. ¡Gracias!')
                : trf('Sin anuncios hasta el {f}.', {'f': DateFormat.yMMMd(idiomaActual).format(DateTime.parse(res['hasta'] as String).toLocal())}))
            : trf('Has sumado {m} en {liga}. Saldo: {s}.',
                {'m': millones(res['importe'] as num), 'liga': mi?.liga.nombre ?? '', 's': millones(res['saldo'] as num)})),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Tx('Genial'))],
      ),
    );
  }

  void _comprar(String producto) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (c) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.rocket_launch_outlined, size: 48, color: Theme.of(c).colorScheme.primary),
            const SizedBox(height: 12),
            Tx('Muy pronto', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Tx('Los pagos llegarán con la app en Google Play. Mientras tanto, si tienes un código, canjéalo aquí arriba.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Tx('Entendido')),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    final v = ref.watch(ventajasProvider).valueOrNull ?? const Ventajas();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final fantasy = mi != null && mi.liga.fantasyActivo;

    return SinPublicidad(
      child: Scaffold(
        appBar: AppBar(title: const Tx('Tienda')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          // Estado de los anuncios
          _EstadoAnuncios(v: v),
          const SizedBox(height: 16),

          // Código: arriba, porque es lo que más se usa
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.redeem_rounded, color: cs.tertiary),
                  const SizedBox(width: 8),
                  Tx('¿Tienes un código?', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                Tx('Sirve para quitar anuncios o para sumar dinero Fantasy.', style: t.bodyMedium),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _codigo,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _canjear(mi),
                      decoration: InputDecoration(hintText: tr('Escribe el código'), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canjeando ? null : () => _canjear(mi),
                    child: _canjeando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Tx('Canjear'),
                  ),
                ]),
                if (fantasy) ...[
                  const SizedBox(height: 8),
                  Text(trf('El dinero Fantasy se suma en {liga}.', {'liga': mi!.liga.nombre}), style: t.bodySmall),
                ],
              ]),
            ),
          ),

          // Quitar anuncios
          if (!v.paraSiempre) ...[
            _Titulo(icono: Icons.block, texto: tr('Quitar anuncios')),
            Tx('En el móvil y en la web, en todas tus ligas.', style: t.bodyMedium),
            const SizedBox(height: 10),
            Row(children: [
              for (final (id, nombre, precio, etiqueta) in _sinAnuncios) ...[
                Expanded(
                  child: _Producto(
                    icono: id == 'ads_siempre' ? Icons.all_inclusive : Icons.calendar_today_outlined,
                    titulo: tr(nombre),
                    precio: precio,
                    etiqueta: etiqueta == null ? null : tr(etiqueta),
                    destacado: etiqueta != null,
                    onTap: () => _comprar(id),
                  ),
                ),
                if (id != _sinAnuncios.last.$1) const SizedBox(width: 10),
              ],
            ]),
          ],

          // Dinero Fantasy
          if (fantasy) ...[
            _Titulo(icono: Icons.payments_outlined, texto: tr('Dinero Fantasy')),
            if (!mi!.liga.comprasDinero)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(trf('En {liga} el admin lo ha desactivado', {'liga': mi!.liga.nombre})),
                  subtitle: const Tx('Todos juegan solo con lo que ganan en los partidos.'),
                ),
              )
            else ...[
              Text(trf('Para tu equipo en {liga}.', {'liga': mi!.liga.nombre}), style: t.bodyMedium),
              const SizedBox(height: 10),
              Row(children: [
                for (final (id, m, precio) in _packsDinero) ...[
                  Expanded(
                    child: _Producto(
                      icono: Icons.savings_outlined,
                      titulo: '+${millones(m)}',
                      precio: precio,
                      premium: true,
                      onTap: () => _comprar(id),
                    ),
                  ),
                  if (id != _packsDinero.last.$1) const SizedBox(width: 10),
                ],
              ]),
              const SizedBox(height: 8),
              Tx('El admin de la liga puede desactivarlo para que todos jueguen igual.', style: t.bodySmall),
            ],
          ],
        ]),
      ),
    );
  }
}

class _EstadoAnuncios extends StatelessWidget {
  const _EstadoAnuncios({required this.v});
  final Ventajas v;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final sin = v.sinAnuncios;
    final color = sin ? const Color(0xFF2E7D32) : cs.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.3)!]),
      ),
      child: Row(children: [
        Icon(sin ? Icons.verified_rounded : Icons.campaign_outlined, color: Colors.white, size: 40),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(sin ? 'Sin anuncios' : 'Versión gratuita'),
                style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              sin
                  ? (v.paraSiempre || v.hasta == null
                      ? tr('Para siempre. ¡Gracias por apoyar la app!')
                      : trf('Hasta el {f}', {'f': DateFormat.yMMMd(idiomaActual).format(v.hasta!)}))
                  : tr('Los anuncios mantienen la app gratis. Puedes quitarlos cuando quieras.'),
              style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 4),
        child: Row(children: [
          Icon(icono, size: 20),
          const SizedBox(width: 8),
          Text(texto, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Producto extends StatelessWidget {
  const _Producto({
    required this.icono,
    required this.titulo,
    required this.precio,
    required this.onTap,
    this.etiqueta,
    this.destacado = false,
    this.premium = false,
  });
  final IconData icono;
  final String titulo, precio;
  final String? etiqueta;
  final bool destacado, premium;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final acento = premium ? cs.tertiary : cs.primary;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: destacado ? acento : cs.outlineVariant, width: destacado ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(children: [
            SizedBox(
              height: 22,
              child: etiqueta == null
                  ? null
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: acento, borderRadius: BorderRadius.circular(20)),
                      child: Text(etiqueta!, style: t.labelSmall?.copyWith(color: cs.onPrimary)),
                    ),
            ),
            Icon(icono, color: acento, size: 30),
            const SizedBox(height: 8),
            Text(titulo,
                textAlign: TextAlign.center, maxLines: 2, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onTap,
                style: FilledButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                child: Text(precio),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
