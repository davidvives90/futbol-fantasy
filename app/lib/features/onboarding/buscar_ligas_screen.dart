import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

/// Buscador de ligas públicas por nombre o ciudad.
class BuscarLigasScreen extends ConsumerStatefulWidget {
  const BuscarLigasScreen({super.key});

  @override
  ConsumerState<BuscarLigasScreen> createState() => _BuscarLigasScreenState();
}

class _BuscarLigasScreenState extends ConsumerState<BuscarLigasScreen> {
  final _texto = TextEditingController();
  Timer? _espera;
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  final _solicitadas = <String>{};

  @override
  void dispose() {
    _espera?.cancel();
    _texto.dispose();
    super.dispose();
  }

  void _alEscribir(String v) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), _buscar);
  }

  Future<void> _buscar() async {
    final t = _texto.text.trim();
    if (t.length < 2) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final r = await LigasRepo.buscar(t);
      if (mounted) setState(() => _resultados = r);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _solicitar(String ligaId) async {
    final ok = await ejecutar(context, () => LigasRepo.solicitarUnirse(ligaId), ok: 'Solicitud enviada');
    if (ok && mounted) {
      setState(() => _solicitadas.add(ligaId));
      refrescarLigas(ref); // por si la liga no requiere aprobación
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ligas en las que ya estoy: no se ofrece «Solicitar»
    final misLigas = {for (final m in ref.watch(misLigasProvider).valueOrNull ?? const []) m.liga.id};
    return Scaffold(
      appBar: AppBar(title: const Tx('Buscar ligas')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _texto,
            autofocus: true,
            onChanged: _alEscribir,
            decoration: InputDecoration(
              labelText: tr('Nombre o ciudad'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _buscando ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
          ),
        ),
        Expanded(
          child: _resultados.isEmpty
              ? const Vacio('Escribe al menos 2 letras para buscar', icono: Icons.travel_explore)
              : ListView.separated(
                  itemCount: _resultados.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final l = _resultados[i];
                    final id = l['id'] as String;
                    final enviada = _solicitadas.contains(id);
                    final yaEstoy = misLigas.contains(id);
                    final n = (l['num_miembros'] as num?)?.toInt() ?? 0;
                    return ListTile(
                      title: Text(l['nombre'] as String),
                      subtitle: Text([
                        if (l['ciudad'] != null) l['ciudad'],
                        if (l['campo_nombre'] != null) l['campo_nombre'],
                        'Fútbol ${l['jugadores_por_equipo']}',
                        n == 1 ? tr('1 miembro') : trf('{n} miembros', {'n': n}),
                      ].join(' · ')),
                      trailing: yaEstoy
                          ? const Chip(label: Tx('Ya estás'))
                          : enviada
                          ? const Chip(label: Tx('Enviada'))
                          : FilledButton.tonal(onPressed: () => _solicitar(id), child: const Tx('Solicitar')),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
