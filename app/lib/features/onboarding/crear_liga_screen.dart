import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:share_plus/share_plus.dart';

import '../../core/liga_activa.dart';
import '../../core/supabase.dart';
import '../../data/repos/partidos_repo.dart';
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
    if (!widget.editar) return const _NuevaLiga();
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


/// Alta de liga en 3 pasos: nombre y formato · cuándo y dónde · invitar. Todo lo demás, por defecto
/// (se cambia luego en Ajustes de la liga).
class _NuevaLiga extends ConsumerStatefulWidget {
  const _NuevaLiga();

  @override
  ConsumerState<_NuevaLiga> createState() => _NuevaLigaState();
}

class _NuevaLigaState extends ConsumerState<_NuevaLiga> {
  int _paso = 0;
  final _nombre = TextEditingController();
  final _campo = TextEditingController();
  final _precio = TextEditingController();
  int _jugadores = 5;
  final _dias = <int>{1};
  TimeOfDay _hora = const TimeOfDay(hour: 21, minute: 0);
  bool _programar = true;
  bool _trabajando = false;
  String? _codigo;

  static const _formatos = <(int, String, String)>[
    (5, 'Fútbol sala', '5 contra 5'),
    (7, 'Fútbol 7', '7 contra 7'),
    (8, 'Fútbol 8', '8 contra 8'),
    (11, 'Fútbol 11', '11 contra 11'),
    (3, 'Fútbol 3', '3 contra 3'),
  ];

  @override
  void dispose() {
    for (final c in [_nombre, _campo, _precio]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _horaTexto => '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}';

  Future<void> _crear() async {
    setState(() => _trabajando = true);
    final precio = double.tryParse(_precio.text.trim().replaceAll(',', '.'));
    final ok = await ejecutar(context, () async {
      final id = await LigasRepo.crearLiga({
        'nombre': _nombre.text.trim(),
        'campo_nombre': _campo.text.trim().isEmpty ? null : _campo.text.trim(),
        'precio_estimado': precio,
        'jugadores_por_equipo': _jugadores,
        'num_equipos': 2,
        'visibilidad': 'privada',
        'requiere_aprobacion': true,
      });
      await ref.read(ligaActivaIdProvider.notifier).elegir(id);
      // Quien crea la liga juega: queda como fijo
      final yo = await sb.from('miembros').select('id').eq('liga_id', id).eq('perfil_id', uidActual!).maybeSingle();
      if (yo != null) {
        try {
          await LigasRepo.cambiarRango(yo['id'] as String, RangoMiembro.fijo);
        } catch (_) {}
      }
      if (_programar && _dias.isNotEmpty) {
        final hoy = DateTime.now();
        await PartidosRepo.programarTemporada(
          id,
          desde: DateTime(hoy.year, hoy.month, hoy.day),
          hasta: DateTime(hoy.month > 6 ? hoy.year + 1 : hoy.year, 6, 30),
          diasSemana: _dias.toList()..sort(),
          hora: _horaTexto,
          horaFija: true,
          coste: precio == null ? 0 : precio * _jugadores * 2,
        );
      }
      final l = await sb.from('ligas').select('codigo_invitacion').eq('id', id).single();
      _codigo = l['codigo_invitacion'] as String?;
    });
    if (!mounted) return;
    setState(() => _trabajando = false);
    if (ok) {
      refrescarLigas(ref);
      setState(() => _paso = 2);
    }
  }

  void _compartir() => Share.share(trf(
      '⚽ Únete a «{liga}» en Fútbol Fantasy.\nEntra en {web} (o en la app) y usa el código *{codigo}*.',
      {'liga': _nombre.text.trim(), 'web': Env.webApp, 'codigo': _codigo ?? ''}));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final titulos = ['Tu liga', '¿Cuándo jugáis?', '¡Liga creada!'];

    final cuerpo = switch (_paso) {
      0 => ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _nombre,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Nombre de la liga'), hintText: tr('Ej.: Los lunes del barrio')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Tx('¿A qué jugáis?', style: t.titleMedium),
          const SizedBox(height: 8),
          for (final (n, nombre, desc) in _formatos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_jugadores == n ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: _jugadores == n ? cs.primary : null),
              onTap: () => setState(() => _jugadores = n),
              title: Text(tr(nombre)),
              subtitle: Text(tr(desc)),
            ),
        ]),
      1 => ListView(padding: const EdgeInsets.all(16), children: [
          Tx('Día de partido', style: t.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(nombresDiasCortos[d - 1]),
                selected: _dias.contains(d),
                onSelected: (v) => setState(() => v ? _dias.add(d) : _dias.remove(d)),
              ),
          ]),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(trf('Hora: {h}', {'h': _horaTexto})),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final r = await showTimePicker(context: context, initialTime: _hora);
              if (r != null) setState(() => _hora = r);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _campo,
            decoration: InputDecoration(labelText: tr('Campo (opcional)'), prefixIcon: const Icon(Icons.place_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _precio,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Precio por jugador (opcional)'), suffixText: '€'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Crear ya los partidos de la temporada'),
            subtitle: const Tx('Hasta el 30 de junio. Se pueden cambiar o cancelar uno a uno.'),
            value: _programar,
            onChanged: (v) => setState(() => _programar = v),
          ),
        ]),
      _ => ListView(padding: const EdgeInsets.all(24), children: [
          Icon(Icons.celebration_outlined, size: 64, color: cs.primary),
          const SizedBox(height: 12),
          Tx('Invita al grupo', style: t.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(trf('Código de la liga: {c}', {'c': _codigo ?? '…'}), style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _compartir,
            icon: const Icon(Icons.share),
            label: const Tx('Compartir por WhatsApp'),
          ),
          const SizedBox(height: 12),
          Tx('Todo lo demás (reglas, fijos, Fantasy…) ya está listo con valores por defecto. '
              'Lo puedes cambiar cuando quieras en Liga › Ajustes.',
              style: t.bodySmall, textAlign: TextAlign.center),
        ]),
    };

    final puedeSeguir = switch (_paso) {
      0 => _nombre.text.trim().length >= 3,
      1 => _dias.isNotEmpty || !_programar,
      _ => true,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(titulos[_paso])),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_paso + 1) / 3),
        ),
      ),
      body: cuerpo,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            if (_paso == 1) TextButton(onPressed: () => setState(() => _paso = 0), child: const Tx('Atrás')),
            const Spacer(),
            FilledButton(
              onPressed: _trabajando || !puedeSeguir
                  ? null
                  : switch (_paso) {
                      0 => () => setState(() => _paso = 1),
                      1 => _crear,
                      _ => () => context.go('/partidos'),
                    },
              child: Text(tr(switch (_paso) { 0 => 'Siguiente', 1 => 'Crear liga', _ => 'Ir a mi liga' })),
            ),
          ]),
        ),
      ),
    );
  }
}
