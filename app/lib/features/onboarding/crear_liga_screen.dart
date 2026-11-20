import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/liga_activa.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';

/// Alta de liga o edición de la liga activa ([editar]).
class CrearLigaScreen extends ConsumerStatefulWidget {
  const CrearLigaScreen({super.key, this.editar = false});
  final bool editar;

  @override
  ConsumerState<CrearLigaScreen> createState() => _CrearLigaScreenState();
}

class _CrearLigaScreenState extends ConsumerState<CrearLigaScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _ciudad = TextEditingController();
  final _campo = TextEditingController();
  final _maps = TextEditingController();
  final _precio = TextEditingController();
  int _jugadoresPorEquipo = 5;
  int _numEquipos = 2;
  bool _publica = false;
  bool _requiereAprobacion = true;
  bool _guardando = false;
  Liga? _original;

  @override
  void initState() {
    super.initState();
    if (widget.editar) {
      final l = ref.read(ligaActualProvider)?.liga;
      if (l != null) {
        _original = l;
        _nombre.text = l.nombre;
        _descripcion.text = l.descripcion ?? '';
        _ciudad.text = l.ciudad ?? '';
        _campo.text = l.campoNombre ?? '';
        _maps.text = l.campoMapsUrl ?? '';
        _precio.text = l.precioEstimado?.toStringAsFixed(2) ?? '';
        _jugadoresPorEquipo = l.jugadoresPorEquipo;
        _numEquipos = l.numEquipos;
        _publica = l.publica;
        _requiereAprobacion = l.requiereAprobacion;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_nombre, _descripcion, _ciudad, _campo, _maps, _precio]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _nulo(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Map<String, dynamic> _datos() => {
        'nombre': _nombre.text.trim(),
        'descripcion': _nulo(_descripcion),
        'ciudad': _nulo(_ciudad),
        'campo_nombre': _nulo(_campo),
        'campo_maps_url': _nulo(_maps),
        'precio_estimado': double.tryParse(_precio.text.replaceAll(',', '.')),
        'jugadores_por_equipo': _jugadoresPorEquipo,
        'num_equipos': _numEquipos,
        'visibilidad': _publica ? 'publica' : 'privada',
        'requiere_aprobacion': _requiereAprobacion,
      };

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      if (widget.editar && _original != null) {
        await LigasRepo.actualizarLiga(_original!.id, _datos());
      } else {
        final id = await LigasRepo.crearLiga(_datos());
        await ref.read(ligaActivaIdProvider.notifier).elegir(id);
      }
      refrescarLigas(ref);
      // Liga nueva: asistente de modalidad, reglas y fijos. Edición: de vuelta a la app.
      if (mounted) context.go(widget.editar ? '/partidos' : '/liga/asistente');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plazas = _jugadoresPorEquipo * _numEquipos;
    return Scaffold(
      appBar: AppBar(title: Text(widget.editar ? 'Editar liga' : 'Nueva liga')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _nombre,
            decoration:  InputDecoration(labelText: tr('Nombre de la liga')),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v == null || v.trim().length < 3) ? 'Mínimo 3 caracteres' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descripcion,
            decoration:  InputDecoration(labelText: tr('Descripción (opcional)')),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _ciudad, decoration:  InputDecoration(labelText: tr('Ciudad'))),
          const SizedBox(height: 24),
          Text('Campo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(controller: _campo, decoration:  InputDecoration(labelText: tr('Nombre del campo'))),
          const SizedBox(height: 12),
          TextFormField(
            controller: _maps,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: tr('Enlace de Google Maps'),
              helperText: tr('En Maps: Compartir → Copiar enlace'),
              suffixIcon: IconButton(
                tooltip: tr('Abrir en Maps'),
                icon: const Icon(Icons.map_outlined),
                onPressed: () => abrirUrl(context, _nulo(_maps)),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              return esEnlaceMaps(v) ? null : 'No parece un enlace de Google Maps';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _precio,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:  InputDecoration(labelText: tr('Precio estimado por jugador y partido'), suffixText: '€'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final d = double.tryParse(v.replaceAll(',', '.'));
              return (d == null || d < 0) ? 'Importe no válido' : null;
            },
          ),
          const SizedBox(height: 24),
          Text('Formato', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Jugadores por equipo: fútbol $_jugadoresPorEquipo'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var n = 3; n <= 11; n++)
              ChoiceChip(
                label: Text('F$n'),
                selected: _jugadoresPorEquipo == n,
                onSelected: (_) => setState(() => _jugadoresPorEquipo = n),
              ),
          ]),
          const SizedBox(height: 16),
          const Tx('Número de equipos'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {_numEquipos},
            onSelectionChanged: (s) => setState(() => _numEquipos = s.first),
          ),
          const SizedBox(height: 8),
          Text('Plazas por partido: $plazas', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          Text('Reglas', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Liga pública'),
            subtitle: const Tx('Aparece en el buscador'),
            value: _publica,
            onChanged: (v) => setState(() => _publica = v),
          ),
          if (_publica)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Tx('Aprobar a quien llegue del buscador'),
              value: _requiereAprobacion,
              onChanged: (v) => setState(() => _requiereAprobacion = v),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: Text(widget.editar ? 'Guardar cambios' : 'Crear liga'),
          ),
        ]),
      ),
    );
  }
}
