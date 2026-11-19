import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/providers.dart';
import '../../data/repos/fantasy_repo.dart';
import '../../data/repos/ligas_repo.dart';
import 'fantasy_providers.dart';

/// Liga > Ajustes Fantasy (solo admins): encuestas de valoración y parámetros del mercado.
class AjustesFantasyScreen extends ConsumerStatefulWidget {
  const AjustesFantasyScreen({super.key});

  @override
  ConsumerState<AjustesFantasyScreen> createState() => _AjustesFantasyScreenState();
}

class _AjustesFantasyScreenState extends ConsumerState<AjustesFantasyScreen> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  String? _ligaCargada;
  bool _guardando = false;

  static const _campos = <(String, String, String?)>[
    ('precio_min', 'Precio mínimo (M)', null),
    ('precio_max', 'Precio máximo (M)', null),
    ('max_plantilla', 'Jugadores por plantilla', null),
    ('bonus_no_habitual', 'Multiplicador no habitual', 'Ej.: 1,5'),
    ('horas_cierre_alineacion', 'Cierre de alineación (horas antes)', null),
    ('ingreso_por_punto', 'Ingreso por punto (M)', null),
    ('comision_venta', 'Comisión de venta (%)', 'Ej.: 5'),
  ];

  void _rellenar(ParamsFantasy p) {
    final v = <String, num>{
      'precio_min': p.precioMin,
      'precio_max': p.precioMax,
      'max_plantilla': p.maxPlantilla,
      'bonus_no_habitual': p.bonusNoHabitual,
      'horas_cierre_alineacion': p.horasCierreAlineacion,
      'ingreso_por_punto': p.ingresoPorPunto,
      'comision_venta': p.comisionVenta * 100,
    };
    for (final (clave, _, _) in _campos) {
      final n = v[clave]!;
      (_c[clave] ??= TextEditingController()).text =
          (n % 1 == 0 ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String clave) => double.tryParse(_c[clave]!.text.trim().replaceAll(',', '.'));

  Future<void> _guardar(MiLiga mi) async {
    if (!_form.currentState!.validate()) return;
    final datos = {
      'precio_min': _num('precio_min'),
      'precio_max': _num('precio_max'),
      'max_plantilla': _num('max_plantilla')!.round(),
      'bonus_no_habitual': _num('bonus_no_habitual'),
      'horas_cierre_alineacion': _num('horas_cierre_alineacion')!.round(), // columna smallint
      'ingreso_por_punto': _num('ingreso_por_punto'),
      'comision_venta': _num('comision_venta')! / 100,
    };
    setState(() => _guardando = true);
    final ok = await ejecutar(context, () => LigasRepo.actualizarLiga(mi.liga.id, datos), ok: 'Parámetros guardados');
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) refrescarLigas(ref);
  }

  String? _validar(String clave, String? v) {
    final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
    if (n == null) return 'Número no válido';
    return switch (clave) {
      'precio_min' => n <= 0 ? 'Debe ser mayor que 0' : null,
      'precio_max' => n <= (_num('precio_min') ?? 0) ? 'Debe ser mayor que el mínimo' : null,
      'max_plantilla' => n < 1 || n > 15 || n % 1 != 0 ? 'Entero entre 1 y 15' : null,
      'bonus_no_habitual' => n < 1 || n > 3 ? 'Entre 1 y 3' : null,
      'horas_cierre_alineacion' => n < 0 || n > 72 || n % 1 != 0 ? 'Horas enteras entre 0 y 72' : null,
      'ingreso_por_punto' => n < 0 ? 'No puede ser negativo' : null,
      'comision_venta' => n < 0 || n > 50 ? 'Entre 0 y 50' : null,
      _ => null,
    };
  }

  Future<void> _miniEncuesta(MiLiga mi) async {
    final miembros = (await ref.read(miembrosProvider(mi.liga.id).future))
        .where((m) => m.estado == EstadoMiembro.activo || m.estado == EstadoMiembro.pendiente_registro)
        .toList();
    if (!mounted) return;
    final elegido = await showDialog<Miembro>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('¿A quién hay que colocar?'),
        children: [
          for (final m in miembros) SimpleDialogOption(onPressed: () => Navigator.pop(c, m), child: Text(m.nombre)),
        ],
      ),
    );
    if (elegido == null || !mounted) return;
    final ok = await ejecutar(context, () => FantasyRepo.abrirEncuesta(mi.liga.id, sujetoId: elegido.id),
        ok: 'Mini-encuesta abierta para ${elegido.nombre}');
    if (ok) ref.invalidate(encuestasAbiertasProvider(mi.liga.id));
  }

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    if (_ligaCargada != mi.liga.id) {
      _ligaCargada = mi.liga.id;
      _rellenar(mi.liga.fantasy);
    }
    final encuestas = ref.watch(encuestasAbiertasProvider(mi.liga.id));
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    final activos = miembros.values.where((m) => m.estado == EstadoMiembro.activo).length;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes Fantasy')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Encuestas de valoración', style: t.titleMedium),
        const SizedBox(height: 4),
        const Text('Cada mánager ordena a todos los jugadores en 6 rankings. Al cerrar la encuesta general se fijan '
            'las valoraciones, los precios iniciales y el presupuesto de cada mánager. Se recomienda cerrarla con al '
            'menos el 60 % de respuestas.'),
        encuestas.when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Cargando()),
          error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(encuestasAbiertasProvider(mi.liga.id))),
          data: (lista) => Column(children: [
            for (final e in lista) _FilaEncuesta(encuesta: e, mi: mi, activos: activos, miembros: miembros),
            if (lista.where((e) => !e.esMini).isEmpty)
              ListTile(
                leading: const Icon(Icons.how_to_vote_outlined),
                title: const Text('Abrir encuesta general'),
                subtitle: const Text('Antes de empezar la liga Fantasy, o para recalibrar valoraciones'),
                onTap: () async {
                  if (!await confirmar(context, 'Abrir encuesta', 'Todos los miembros verán la encuesta en la app.')) return;
                  if (!context.mounted) return;
                  final ok = await ejecutar(context, () => FantasyRepo.abrirEncuesta(mi.liga.id), ok: 'Encuesta abierta');
                  if (ok) ref.invalidate(encuestasAbiertasProvider(mi.liga.id));
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Mini-encuesta para un jugador nuevo'),
              subtitle: const Text('Hasta entonces empieza con valoración 50'),
              onTap: () => _miniEncuesta(mi),
            ),
          ]),
        ),
        const Divider(height: 32),
        Text('Parámetros del mercado', style: t.titleMedium),
        const SizedBox(height: 12),
        Form(
          key: _form,
          child: Column(children: [
            for (final (clave, etiqueta, ayuda) in _campos)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _c[clave],
                  decoration: InputDecoration(labelText: etiqueta, helperText: ayuda),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  validator: (v) => _validar(clave, v),
                ),
              ),
          ]),
        ),
        const Text('Los cambios de precio mínimo y máximo se aplican a partir de la siguiente jornada.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _guardando ? null : () => _guardar(mi),
          child: const Text('Guardar parámetros'),
        ),
      ]),
    );
  }
}

class _FilaEncuesta extends ConsumerStatefulWidget {
  const _FilaEncuesta({required this.encuesta, required this.mi, required this.activos, required this.miembros});
  final Encuesta encuesta;
  final MiLiga mi;
  final int activos;
  final Map<String, Miembro> miembros;

  @override
  ConsumerState<_FilaEncuesta> createState() => _FilaEncuestaState();
}

class _FilaEncuestaState extends ConsumerState<_FilaEncuesta> {
  int? _completos;
  int? _managers;
  bool _sinDato = false;

  @override
  void initState() {
    super.initState();
    FantasyRepo.progresoEncuesta(widget.encuesta.id).then((p) {
      if (!mounted) return;
      setState(() {
        if (p == null) {
          _sinDato = true;
        } else {
          _completos = p.completadas;
          _managers = p.managers;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.encuesta;
    final total = _managers ?? widget.activos;
    final pct = (_completos == null || total == 0) ? null : _completos! / total;
    return Card(
      child: ListTile(
        title: Text(e.esMini ? 'Mini-encuesta: ${widget.miembros[e.sujetoId]?.nombre ?? '…'}' : 'Encuesta general'),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (e.creadaEn != null) Text('Abierta el ${fechaCorta(e.creadaEn!)}'),
          if (pct != null) ...[
            Text('$_completos de $total mánagers (${(pct * 100).round()} %)'),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: pct.clamp(0.0, 1.0)),
          ] else if (_sinDato)
            const Text('Progreso no disponible'),
        ]),
        trailing: TextButton(
          onPressed: () async {
            final aviso = pct != null && pct < 0.6 ? ' Solo ha respondido el ${(pct * 100).round()} %.' : '';
            if (!await confirmar(context, 'Cerrar encuesta',
                'Se calcularán las valoraciones${e.esMini ? '' : ', los precios iniciales y los presupuestos'}.$aviso',
                accion: 'Cerrar')) {
              return;
            }
            if (!context.mounted) return;
            final ok = await ejecutar(context, () => FantasyRepo.cerrarEncuesta(e.id), ok: 'Encuesta cerrada');
            if (ok) {
              ref.invalidate(encuestasAbiertasProvider(widget.mi.liga.id));
              refrescarFantasy(ref, (ligaId: widget.mi.liga.id, miembroId: widget.mi.yo.id));
            }
          },
          child: const Text('Cerrar'),
        ),
      ),
    );
  }
}
