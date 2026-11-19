import 'dart:async';

import 'package:flutter/material.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar ligas')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _texto,
            autofocus: true,
            onChanged: _alEscribir,
            decoration: InputDecoration(
              labelText: 'Nombre o ciudad',
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
                    return ListTile(
                      title: Text(l['nombre'] as String),
                      subtitle: Text([
                        if (l['ciudad'] != null) l['ciudad'],
                        if (l['campo_nombre'] != null) l['campo_nombre'],
                        'Fútbol ${l['jugadores_por_equipo']}',
                        '${l['num_miembros'] ?? 0} miembros',
                      ].join(' · ')),
                      trailing: enviada
                          ? const Chip(label: Text('Enviada'))
                          : FilledButton.tonal(onPressed: () => _solicitar(id), child: const Text('Solicitar')),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
