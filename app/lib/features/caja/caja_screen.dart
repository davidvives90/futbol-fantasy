import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/caja_repo.dart';
import '../shell/home_shell.dart';

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

class _MiSaldo extends ConsumerWidget {
  const _MiSaldo({required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldos = ref.watch(saldosProvider(mi.liga.id));
    final movs = ref.watch(_movimientosProvider(mi.yo.id));
    final saldo = saldos.valueOrNull?.where((s) => s.miembroId == mi.yo.id).firstOrNull?.saldo ?? 0;
    final color = saldo < 0 ? Colors.red : Colors.green;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(saldosProvider(mi.liga.id));
        ref.invalidate(_movimientosProvider(mi.yo.id));
      },
      child: ListView(children: [
        const SizedBox(height: 24),
        Center(child: Text(euros(saldo), style: Theme.of(context).textTheme.displaySmall?.copyWith(color: color))),
        Center(child: Text(saldo < 0 ? 'Debes a la caja' : (saldo > 0 ? 'A tu favor' : 'Estás al día'))),
        const SizedBox(height: 24),
        const Divider(),
        ...movs.when(
          loading: () => [const Padding(padding: EdgeInsets.all(24), child: Cargando())],
          error: (e, _) => [ErrorVista(e)],
          data: (lista) => lista.isEmpty
              ? [const Padding(padding: EdgeInsets.all(24), child: Text('Sin movimientos todavía.'))]
              : [
                  for (final m in lista)
                    ListTile(
                      leading: Icon(m.importe < 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          color: m.importe < 0 ? Colors.red : Colors.green),
                      title: Text(m.concepto ?? m.tipo),
                      subtitle: Text(fechaCorta(m.fecha)),
                      trailing: Text(euros(m.importe)),
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
                ButtonSegment(value: 'pago', label: Text('Pago')),
                ButtonSegment(value: 'ajuste', label: Text('Ajuste')),
              ],
              selected: {tipo},
              onSelectionChanged: (s) => setD(() => tipo = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: importe,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: 'Importe',
                suffixText: '€',
                helperText: tipo == 'ajuste' ? 'Negativo = cargo, positivo = abono' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: concepto, decoration: const InputDecoration(labelText: 'Concepto')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Registrar')),
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
            ListTile(
              title: const Text('Total pendiente de cobro'),
              trailing: Text(euros(-pendiente), style: Theme.of(context).textTheme.titleLarge),
            ),
            const Divider(),
            for (final s in ordenados)
              if (miembros[s.miembroId] != null)
                ListTile(
                  leading: CircleAvatar(child: Text(miembros[s.miembroId]!.inicial)),
                  title: Text(miembros[s.miembroId]!.nombre),
                  trailing: Text(euros(s.saldo), style: TextStyle(color: s.saldo < 0 ? Colors.red : null)),
                  onTap: () => _registrar(context, ref, miembros[s.miembroId]!, -s.saldo),
                ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Toca a un jugador para registrar un pago o un ajuste.'),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(f.name, overflow: TextOverflow.ellipsis),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: importe,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Importe', suffixText: '€'),
          ),
          const SizedBox(height: 12),
          TextField(controller: notas, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Subir')),
        ],
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
        subidaPor: mi.yo.id,
      ),
      ok: 'Factura subida',
    );
    ref.invalidate(_facturasProvider(mi.liga.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facturas = ref.watch(_facturasProvider(mi.liga.id));
    return Scaffold(
      floatingActionButton: mi.soyAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _subir(context, ref),
              icon: const Icon(Icons.upload_file),
              label: const Text('Subir factura'),
            )
          : null,
      body: facturas.when(
        loading: () => const Cargando(),
        error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(_facturasProvider(mi.liga.id))),
        data: (lista) => lista.isEmpty
            ? const Vacio('No hay facturas subidas.', icono: Icons.receipt_long_outlined)
            : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                for (final f in lista)
                  ListTile(
                    leading: Icon(f.archivoPath.endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image_outlined),
                    title: Text(f.nombreArchivo ?? 'Factura'),
                    subtitle: Text([fechaCorta(f.fecha), if (f.notas != null) f.notas!].join(' · ')),
                    trailing: Text(euros(f.importe)),
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
