import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/caja_repo.dart';
import '../shell/home_shell.dart';
import '../../core/avatar.dart';

final _movimientosProvider = FutureProvider.autoDispose.family<List<Movimiento>, String>(
  (ref, miembroId) => CajaRepo.movimientos(miembroId),
);

final _facturasProvider = FutureProvider.autoDispose.family<List<Factura>, String>(
  (ref, ligaId) => CajaRepo.facturas(ligaId),
);

class CajaScreen extends ConsumerWidget {
  const CajaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());

    final tabs = [
      const Tab(text: 'Mi saldo'),
      if (mi.soyAdmin) const Tab(text: 'Deudores'),
      const Tab(text: 'Facturas'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: LigaAppBar(bottom: TabBar(tabs: tabs)),
        body: TabBarView(children: [
          _MiSaldo(mi: mi),
          if (mi.soyAdmin) _Deudores(mi: mi),
          _Facturas(mi: mi),
        ]),
      ),
    );
  }
}

final avisosPagoProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, ligaId) => CajaRepo.avisosPago(ligaId),
);

/// «Pagar con Bizum» (copia teléfono, importe y concepto) y «Ya he pagado» (aviso al admin para que lo confirme).
class _Pagar extends ConsumerWidget {
  const _Pagar({required this.mi, required this.deuda});
  final MiLiga mi;
  final double deuda;

  Future<void> _yaHePagado(BuildContext context, WidgetRef ref) async {
    final importe = TextEditingController(text: deuda.toStringAsFixed(2));
    var metodo = 'bizum';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Tx('Ya he pagado'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Tx('El administrador recibirá un aviso para confirmarlo; cuando lo haga, quedará apuntado.'),
            const SizedBox(height: 12),
            TextField(
              controller: importe,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:  InputDecoration(labelText: tr('Importe'), suffixText: '€'),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [
              for (final e in const {'bizum': 'Bizum', 'efectivo': 'Efectivo', 'transferencia': 'Transferencia'}.entries)
                ChoiceChip(label: Text(e.value), selected: metodo == e.key, onSelected: (_) => setD(() => metodo = e.key)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Tx('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Tx('Avisar')),
          ],
        ),
      ),
    );
    final valor = double.tryParse(importe.text.replaceAll(',', '.'));
    importe.dispose();
    if (ok != true || valor == null || !context.mounted) return;
    final hecho = await ejecutar(context, () => CajaRepo.avisarPago(mi.liga.id, valor, metodo),
        ok: 'Aviso enviado al administrador');
    if (hecho) ref.invalidate(avisosPagoProvider(mi.liga.id));
  }

  Future<void> _bizum(BuildContext context) async {
    final tel = mi.liga.bizumTelefono!;
    final texto = '${deuda.toStringAsFixed(2).replaceAll('.', ',')} € · Fútbol ${mi.liga.nombre} · ${mi.yo.nombre}';
    await Clipboard.setData(ClipboardData(text: tel.replaceAll(' ', '')));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Tx('Pagar con Bizum'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Tx('Abre la app de tu banco › Bizum › Enviar dinero, y usa estos datos:'),
          const SizedBox(height: 12),
          _DatoCopiable('Teléfono', tel),
          _DatoCopiable('Importe', '${deuda.toStringAsFixed(2).replaceAll('.', ',')} €'),
          _DatoCopiable('Concepto', texto),
          const SizedBox(height: 8),
          const Tx('Cuando lo hayas enviado, pulsa «Ya he pagado».'),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Tx('Entendido'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendiente = (ref.watch(avisosPagoProvider(mi.liga.id)).valueOrNull ?? const [])
        .where((a) => a['miembro_id'] == mi.yo.id)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(children: [
        if (pendiente != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.hourglass_top),
              title: Text('Has avisado de un pago de ${euros((pendiente['importe'] as num).toDouble())}'),
              subtitle: const Tx('Pendiente de que lo confirme el administrador'),
            ),
          ),
        Row(children: [
          if (mi.liga.bizumTelefono != null) ...[
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _bizum(context),
                icon: const Icon(Icons.phone_iphone),
                label: const Tx('Pagar con Bizum'),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _yaHePagado(context, ref),
              icon: const Icon(Icons.check),
              label: const Tx('Ya he pagado'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _DatoCopiable extends StatelessWidget {
  const _DatoCopiable(this.etiqueta, this.valor);
  final String etiqueta, valor;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(etiqueta),
        subtitle: Text(valor, style: Theme.of(context).textTheme.titleMedium),
        trailing: IconButton(
          tooltip: tr('Copiar'),
          icon: const Icon(Icons.copy, size: 20),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: valor));
            mostrarOk(context, '$etiqueta copiado');
          },
        ),
      );
}

class _MiSaldo extends ConsumerWidget {
  const _MiSaldo({required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldos = ref.watch(saldosProvider(mi.liga.id));
    final movs = ref.watch(_movimientosProvider(mi.yo.id));
    final saldo = saldos.valueOrNull?.where((s) => s.miembroId == mi.yo.id).firstOrNull?.saldo ?? 0;
    final colores = AppColores.of(context);
    final color = saldo < 0 ? Theme.of(context).colorScheme.error : colores.exito;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(saldosProvider(mi.liga.id));
        ref.invalidate(_movimientosProvider(mi.yo.id));
      },
      child: ListView(children: [
        const SizedBox(height: 24),
        Center(child: Text(euros(saldo), style: AppTheme.numero(context, size: 40, color: color))),
        Center(child: Text(tr(saldo < 0 ? 'Debes a la caja' : (saldo > 0 ? 'A tu favor' : 'Estás al día')))),
        if (saldo < -0.005) _Pagar(mi: mi, deuda: -saldo),
        const SizedBox(height: 24),
        const Divider(),
        ...movs.when(
          loading: () => [const Padding(padding: EdgeInsets.all(24), child: Cargando())],
          error: (e, _) => [ErrorVista(e)],
          data: (lista) => lista.isEmpty
              ? [const Padding(padding: EdgeInsets.all(24), child: Tx('Sin movimientos todavía.'))]
              : [
                  for (final m in lista)
                    ListTile(
                      leading: Icon(m.importe < 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          color: m.importe < 0 ? Theme.of(context).colorScheme.error : colores.exito),
                      title: Text(m.concepto ?? m.tipo),
                      subtitle: Text(fechaCorta(m.fecha)),
                      trailing: Text(euros(m.importe), style: AppTheme.tabular(Theme.of(context).textTheme.bodyLarge)),
                    ),
                ],
        ),
      ]),
    );
  }
}

class _Deudores extends ConsumerWidget {
  const _Deudores({required this.mi});
  final MiLiga mi;

  Future<void> _registrar(BuildContext context, WidgetRef ref, Miembro m, double sugerido) async {
    final importe = TextEditingController(text: sugerido > 0 ? sugerido.toStringAsFixed(2) : '');
    final concepto = TextEditingController(text: 'Pago');
    var tipo = 'pago';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Movimiento de ${m.nombre}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pago', label: Tx('Pago')),
                ButtonSegment(value: 'ajuste', label: Tx('Ajuste')),
              ],
              selected: {tipo},
              onSelectionChanged: (s) => setD(() => tipo = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: importe,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: tr('Importe'),
                suffixText: '€',
                helperText: tipo == 'ajuste' ? 'Negativo = cargo, positivo = abono' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: concepto, decoration:  InputDecoration(labelText: tr('Concepto'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Tx('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Tx('Registrar')),
          ],
        ),
      ),
    );
    final valor = double.tryParse(importe.text.replaceAll(',', '.'));
    importe.dispose();
    final textoConcepto = concepto.text.trim();
    concepto.dispose();
    if (ok != true || valor == null || !context.mounted) return;

    await ejecutar(
      context,
      () => CajaRepo.registrarMovimiento(
        miembroId: m.id,
        tipo: tipo,
        importe: tipo == 'pago' ? valor.abs() : valor,
        concepto: textoConcepto.isEmpty ? null : textoConcepto,
      ),
      ok: 'Movimiento registrado',
    );
    ref.invalidate(saldosProvider(mi.liga.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldos = ref.watch(saldosProvider(mi.liga.id));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));

    return saldos.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(saldosProvider(mi.liga.id))),
      data: (lista) {
        final ordenados = [...lista]..sort((a, b) => a.saldo.compareTo(b.saldo));
        final pendiente = lista.where((s) => s.saldo < 0).fold<double>(0, (a, s) => a + s.saldo);
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(saldosProvider(mi.liga.id)),
          child: ListView(children: [
            _AvisosPendientes(mi: mi),
            ListTile(
              title: const Tx('Total pendiente de cobro'),
              trailing: Text(euros(-pendiente), style: AppTheme.numero(context, size: 22)),
            ),
            const Divider(),
            for (final s in ordenados)
              if (miembros[s.miembroId] != null)
                ListTile(
                  leading: AvatarMiembro(miembros[s.miembroId]),
                  title: Text(miembros[s.miembroId]!.nombre),
                  trailing: Text(euros(s.saldo),
                      style: AppTheme.tabular(Theme.of(context).textTheme.bodyLarge)
                          ?.copyWith(color: s.saldo < 0 ? Theme.of(context).colorScheme.error : null)),
                  onTap: () => _registrar(context, ref, miembros[s.miembroId]!, -s.saldo),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: OutlinedButton.icon(
                onPressed: pendiente.abs() < 0.005
                    ? null
                    : () async {
                        if (!await confirmar(context, 'Recordar a los que deben',
                            'Cada jugador con deuda recibirá un aviso con su importe.', accion: 'Enviar')) {
                          return;
                        }
                        if (!context.mounted) return;
                        await ejecutar(context, () async {
                          final n = await CajaRepo.recordarDeudas(mi.liga.id);
                          if (context.mounted) mostrarOk(context, n == 1 ? 'Aviso enviado a 1 jugador' : 'Avisos enviados a $n jugadores');
                        });
                      },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Tx('Recordar a todos los que deben'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Toca a un jugador para registrar un pago o un ajuste. '
                  'Recordatorio automático: ${const {'nunca': 'desactivado', 'semanal': 'cada semana', 'mensual': 'cada mes', 'trimestral': 'cada trimestre'}[mi.liga.recordatorioDeudas] ?? mi.liga.recordatorioDeudas} '
                  '(se cambia en Ajustes › Convocatoria y cobro).'),
            ),
          ]),
        );
      },
    );
  }
}

class _Facturas extends ConsumerWidget {
  const _Facturas({required this.mi});
  final MiLiga mi;

  Future<void> _subir(BuildContext context, WidgetRef ref) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final f = res?.files.single;
    if (f == null || f.bytes == null || !context.mounted) return;

    final importe = TextEditingController();
    final notas = TextEditingController();
    // v0.3: en ligas con factura mensual, por defecto la factura es del mes anterior (llega a mes vencido).
    var mensual = mi.liga.facturaMensual;
    final hoy = DateTime.now();
    var desde = DateTime(hoy.year, hoy.month - 1, 1);
    var hasta = DateTime(hoy.year, hoy.month, 0); // día 0 = último día del mes anterior
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(f.name, overflow: TextOverflow.ellipsis),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: importe,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration:  InputDecoration(labelText: tr('Importe total'), suffixText: '€'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: mensual,
                onChanged: (v) => setD(() => mensual = v),
                title: const Tx('Factura de un periodo'),
                subtitle: const Tx('Se reparte entre los fijos según los partidos jugados'),
              ),
              if (mensual)
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text('${fechaCorta(desde)} – ${fechaCorta(hasta)}'),
                  onPressed: () async {
                    final r = await showDateRangePicker(
                      context: c,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(hoy.year + 1, 12, 31),
                      initialDateRange: DateTimeRange(start: desde, end: hasta),
                      helpText: 'Periodo de la factura',
                    );
                    if (r != null) {
                      setD(() {
                        desde = r.start;
                        hasta = r.end;
                      });
                    }
                  },
                ),
              const SizedBox(height: 12),
              TextField(controller: notas, decoration:  InputDecoration(labelText: tr('Notas (opcional)'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Tx('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Tx('Subir')),
          ],
        ),
      ),
    );
    final valor = double.tryParse(importe.text.replaceAll(',', '.'));
    final textoNotas = notas.text.trim();
    importe.dispose();
    notas.dispose();
    if (ok != true || !context.mounted) return;

    await ejecutar(
      context,
      () => CajaRepo.subirFactura(
        ligaId: mi.liga.id,
        bytes: f.bytes!,
        extension: f.extension ?? 'pdf',
        nombreArchivo: f.name,
        importe: valor,
        notas: textoNotas.isEmpty ? null : textoNotas,
        periodoDesde: mensual ? desde : null,
        periodoHasta: mensual ? hasta : null,
        subidaPor: mi.yo.id,
      ),
      ok: mensual ? 'Factura subida: ahora puedes liquidarla' : 'Factura subida',
    );
    ref.invalidate(_facturasProvider(mi.liga.id));
  }

  /// v0.3: muestra el reparto calculado por `simular_factura` y, si el admin confirma, `liquidar_factura`.
  Future<void> _liquidar(BuildContext context, WidgetRef ref, Factura f) async {
    LiquidacionFactura sim;
    try {
      sim = await CajaRepo.simularFactura(f.id);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
      return;
    }
    if (!context.mounted) return;
    final miembros = ref.read(miembrosPorIdProvider(mi.liga.id));
    final cargos = [...sim.cargos]..sort((a, b) => b.importe.compareTo(a.importe));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Tx('Liquidar factura'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            _filaDesglose('Importe de la factura', euros(sim.importe)),
            _filaDesglose('Pagado por reservas e invitados', '− ${euros(sim.pagadoInvitados)}'),
            _filaDesglose('A repartir entre fijos', euros(sim.resto), negrita: true),
            _filaDesglose('Partidos jugados por fijos', '${sim.partidos}'),
            _filaDesglose('Cuota por partido', euros(sim.cuota), negrita: true),
            const Divider(),
            for (final cg in cargos)
              _filaDesglose(
                '${miembros[cg.miembroId]?.nombre ?? '…'} · ${cg.partidos} partido${cg.partidos == 1 ? '' : 's'}',
                euros(cg.importe),
              ),
            if (cargos.isEmpty) const Tx('No hay partidos de fijos en ese periodo: no se cargará nada.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Tx('Cancelar')),
          FilledButton(onPressed: cargos.isEmpty ? null : () => Navigator.pop(c, true), child: const Tx('Cargar a los fijos')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ejecutar(context, () => CajaRepo.liquidarFactura(f.id), ok: 'Factura liquidada: cargos generados');
    ref.invalidate(_facturasProvider(mi.liga.id));
    ref.invalidate(saldosProvider(mi.liga.id));
  }

  static Widget _filaDesglose(String etiqueta, String valor, {bool negrita = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(etiqueta)),
          Text(valor, style: negrita ? const TextStyle(fontWeight: FontWeight.bold) : null),
        ]),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facturas = ref.watch(_facturasProvider(mi.liga.id));
    return Scaffold(
      floatingActionButton: mi.soyAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _subir(context, ref),
              icon: const Icon(Icons.upload_file),
              label: const Tx('Subir factura'),
            )
          : null,
      body: facturas.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(_facturasProvider(mi.liga.id))),
        data: (lista) => lista.isEmpty
            ? const Vacio('Sube aquí la factura del campo (foto o PDF) y la app reparte el importe.', titulo: 'Sin facturas', icono: Icons.receipt_long_outlined)
            : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                for (final f in lista)
                  ListTile(
                    leading: Icon(f.archivoPath.endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image_outlined),
                    title: Text(f.nombreArchivo ?? 'Factura'),
                    subtitle: Text([
                      if (f.esMensual) 'Periodo ${fechaCorta(f.periodoDesde!)} – ${fechaCorta(f.periodoHasta!)}' else fechaCorta(f.fecha),
                      if (f.esMensual) f.liquidada ? 'Liquidada' : 'Pendiente de liquidar',
                      if (f.notas != null) f.notas!,
                    ].join(' · ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(euros(f.importe)),
                      if (f.esMensual && f.liquidada)
                        Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.check_circle, color: AppColores.of(context).exito, size: 20)),
                      if (mi.soyAdmin && f.esMensual && !f.liquidada)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                            onPressed: () => _liquidar(context, ref, f),
                            child: const Tx('Liquidar'),
                          ),
                        ),
                    ]),
                    onTap: () async {
                      try {
                        final url = await CajaRepo.urlFactura(f.archivoPath);
                        if (context.mounted) await abrirUrl(context, url);
                      } catch (e) {
                        if (context.mounted) mostrarError(context, e);
                      }
                    },
                  ),
              ]),
      ),
    );
  }
}

/// Avisos de «Ya he pagado» pendientes de confirmar (admin).
class _AvisosPendientes extends ConsumerWidget {
  const _AvisosPendientes({required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avisos = ref.watch(avisosPagoProvider(mi.liga.id)).valueOrNull ?? const [];
    if (avisos.isEmpty) return const SizedBox.shrink();
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    Future<void> resolver(String id, bool ok) async {
      final hecho = await ejecutar(context, () => CajaRepo.resolverAviso(id, ok), ok: ok ? 'Pago apuntado' : 'Aviso rechazado');
      if (hecho) {
        ref.invalidate(avisosPagoProvider(mi.liga.id));
        ref.invalidate(saldosProvider(mi.liga.id));
      }
    }

    return Card(
      margin: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Column(children: [
        const ListTile(leading: Icon(Icons.payments_outlined), title: Tx('Pagos por confirmar')),
        for (final a in avisos)
          ListTile(
            leading: AvatarMiembro(miembros[a['miembro_id']], radio: 16),
            title: Text('${miembros[a['miembro_id']]?.nombre ?? '…'} · ${euros((a['importe'] as num).toDouble())}'),
            subtitle: Text('${a['metodo']} · ${fechaCorta(DateTime.parse(a['creado_en'] as String))}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: tr('No lo encuentro'), icon: const Icon(Icons.close), onPressed: () => resolver(a['id'] as String, false)),
              IconButton.filled(tooltip: tr('Confirmar'), icon: const Icon(Icons.check), onPressed: () => resolver(a['id'] as String, true)),
            ]),
          ),
      ]),
    );
  }
}
