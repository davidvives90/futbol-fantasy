import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/equipaciones.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

/// El admin elige la equipación de cada equipo (p. ej. «Blanco» y «Color»), para que cada uno sepa qué llevar.
class EquipacionesScreen extends ConsumerStatefulWidget {
  const EquipacionesScreen({super.key});

  @override
  ConsumerState<EquipacionesScreen> createState() => _EquipacionesScreenState();
}

class _EquipacionesScreenState extends ConsumerState<EquipacionesScreen> {
  List<Equipacion>? _eq;
  final _nombres = <TextEditingController>[];
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in _nombres) {
      c.dispose();
    }
    super.dispose();
  }

  Color? _hex(String? h) => h == null ? null : Color(0xFF000000 | int.parse(h.substring(1), radix: 16));

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    if (_eq == null) {
      _eq = [
        for (var i = 0; i < 4; i++) i < mi.liga.equipaciones.length ? mi.liga.equipaciones[i] : Equipacion.porDefecto[i],
      ];
      for (final e in _eq!) {
        _nombres.add(TextEditingController(text: e.nombre));
      }
    }
    final n = mi.liga.numEquipos.clamp(2, 4);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Tx('Equipaciones')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text('Elige qué lleva cada equipo. Se verá en los equipos, el post-partido y el resultado.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        for (var i = 0; i < n; i++)
          Card(
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Equipo ${i + 1}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (nombre, hex) in paletaEquipaciones)
                    ChoiceChip(
                      avatar: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _hex(hex) ?? cs.surfaceContainerHighest,
                          border: Border.all(color: cs.outline),
                        ),
                        child: hex == null ? Icon(Icons.palette_outlined, size: 12, color: cs.onSurfaceVariant) : null,
                      ),
                      label: Text(nombre),
                      selected: _eq![i].colorHex == hex && (hex != null || _eq![i].colorHex == null),
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        _eq![i] = Equipacion(nombre, hex);
                        _nombres[i].text = nombre;
                      }),
                    ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _nombres[i],
                  maxLength: 20,
                  decoration:  InputDecoration(
                    labelText: tr('Nombre que verá todo el mundo'),
                    helperText: tr('Ej.: «Blancos», «De color», «Petos naranjas»'),
                    counterText: '',
                  ),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _guardando
              ? null
              : () async {
                  setState(() => _guardando = true);
                  final lista = [
                    for (var i = 0; i < 4; i++)
                      Equipacion(_nombres[i].text.trim().isEmpty ? _eq![i].nombre : _nombres[i].text.trim(), _eq![i].colorHex)
                          .toMap(),
                  ];
                  final ok = await ejecutar(context, () => LigasRepo.actualizarLiga(mi.liga.id, {'equipaciones': lista}),
                      ok: 'Equipaciones guardadas');
                  if (!mounted) return;
                  setState(() => _guardando = false);
                  if (ok) {
                    refrescarLigas(ref);
                    Navigator.of(context).maybePop();
                  }
                },
          child: const Tx('Guardar'),
        ),
      ]),
    );
  }
}
