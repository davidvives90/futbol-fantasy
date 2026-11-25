import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';
import '../../data/repos/reglamento_repo.dart';
import '../liga/reglamento_screen.dart';

/// Reglas que se preguntan al crear la liga (las demás quedan con el valor estándar de la modalidad).
const _clavesPrincipales = ['cesion', 'fuera_de_juego', 'portero', 'cambios', 'saque_banda', 'entradas', 'calzado'];

/// Asistente tras crear una liga: 1) modalidad, 2) reglas principales, 3) jugadores fijos e invitación.
class AsistenteLigaScreen extends ConsumerStatefulWidget {
  const AsistenteLigaScreen({super.key});

  @override
  ConsumerState<AsistenteLigaScreen> createState() => _AsistenteLigaScreenState();
}

class _AsistenteLigaScreenState extends ConsumerState<AsistenteLigaScreen> {
  int _paso = 0;
  bool _trabajando = false;
  final _nombres = TextEditingController();
  bool _yoFijo = true;

  @override
  void dispose() {
    _nombres.dispose();
    super.dispose();
  }

  void _terminar() => context.go('/partidos');

  Future<void> _guardarFijos(MiLiga mi) async {
    final nombres = _nombres.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
    setState(() => _trabajando = true);
    final ok = await ejecutar(context, () async {
      if (_yoFijo) await LigasRepo.cambiarRango(mi.yo.id, RangoMiembro.fijo);
      if (nombres.isNotEmpty) {
        await LigasRepo.precrearJugadores(mi.liga.id, nombres, rango: RangoMiembro.fijo);
      }
    });
    if (!mounted) return;
    setState(() => _trabajando = false);
    if (ok) {
      ref.invalidate(miembrosProvider(mi.liga.id));
      refrescarLigas(ref);
      setState(() => _paso = 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final t = Theme.of(context).textTheme;

    final pasos = <(String, Widget)>[
      ('¿A qué jugáis?', _PasoModalidad(mi: mi)),
      ('Las reglas que más se discuten', _PasoReglas(mi: mi)),
      (
        'Jugadores fijos',
        ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Los fijos tienen plaza guardada en cada partido hasta 24 h antes. '
              'Escribe sus nombres (uno por línea) y les crearemos la ficha: cuando se registren con su enlace, la heredan.'),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Tx('Yo también soy fijo'),
            value: _yoFijo,
            onChanged: (v) => setState(() => _yoFijo = v),
          ),
          TextField(
            controller: _nombres,
            minLines: 5,
            maxLines: 12,
            decoration:  InputDecoration(labelText: tr('Nombres de los fijos'), hintText: 'Juan\nPedro\nLuis', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          Text('Los demás (reservas e invitados) pueden unirse luego con el código de la liga.',
              style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
      (
        '¡Liga lista!',
        ListView(padding: const EdgeInsets.all(16), children: [
          const Icon(Icons.celebration_outlined, size: 64),
          const SizedBox(height: 12),
          Tx('Invita al grupo', style: t.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Código de la liga: ${mi.liga.codigoInvitacion}', style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Share.share('⚽ Únete a «${mi.liga.nombre}» en Pachanga Fantasy.\n'
                'Entra en ${Env.webApp} (o en la app) y usa el código *${mi.liga.codigoInvitacion}*.\n'
                'Si te he creado ficha, en la pestaña Liga tienes tu enlace personal.'),
            icon: const Icon(Icons.share),
            label: const Tx('Compartir invitación'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go('/partidos/nuevo'),
            icon: const Icon(Icons.add),
            label: const Tx('Crear el primer partido'),
          ),
          const SizedBox(height: 8),
          Text('Los enlaces personales de cada fijo están en Liga › Jugadores. Puedes cambiar todo esto en Ajustes de la liga.',
              textAlign: TextAlign.center, style: t.bodySmall),
        ]),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(pasos[_paso].$1),
        actions: [if (_paso < 3) TextButton(onPressed: _terminar, child: const Tx('Saltar'))],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_paso + 1) / pasos.length),
        ),
      ),
      body: pasos[_paso].$2,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            if (_paso > 0 && _paso < 3)
              TextButton(onPressed: () => setState(() => _paso--), child: const Tx('Atrás')),
            const Spacer(),
            FilledButton(
              onPressed: _trabajando
                  ? null
                  : switch (_paso) {
                      0 || 1 => () => setState(() => _paso++),
                      2 => () => _guardarFijos(mi),
                      _ => _terminar,
                    },
              child: Text(switch (_paso) { 2 => 'Guardar y seguir', 3 => 'Empezar', _ => 'Siguiente' }),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PasoModalidad extends ConsumerWidget {
  const _PasoModalidad({required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final descripciones = {
      'f3': 'Jaula o pista pequeña, sin portero',
      'sala': 'Pista cubierta, 5 contra 5',
      'f7': 'Campo de fútbol 7',
      'f8': 'Campo de fútbol 8',
      'f11': 'Campo grande',
    };
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Tx('Según la modalidad, la app propone las reglas estándar (cesión, saques, cambios…).'),
      const SizedBox(height: 12),
      for (final e in nombresModalidad.entries)
        Card(
          color: mi.liga.modalidad == e.key ? Theme.of(context).colorScheme.primaryContainer : null,
          child: RadioListTile<String>(
            value: e.key,
            groupValue: mi.liga.modalidad,
            title: Text(tr(e.value)),
            subtitle: Text(descripciones[e.key] ?? ''),
            onChanged: (v) async {
              if (v == null) return;
              final ok = await ejecutar(context, () => ReglamentoRepo.cambiarModalidad(mi.liga.id, v));
              if (ok) {
                refrescarLigas(ref);
                ref.invalidate(reglamentoProvider(mi.liga.id));
              }
            },
          ),
        ),
    ]);
  }
}

class _PasoReglas extends ConsumerWidget {
  const _PasoReglas({required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reglas = ref.watch(reglamentoProvider(mi.liga.id));
    Future<void> cambiar(ReglaJuego r, dynamic v) async {
      final ok = await ejecutar(context, () => ReglamentoRepo.cambiarRegla(mi.liga.id, r.clave, v));
      if (ok) ref.invalidate(reglamentoProvider(mi.liga.id));
    }

    return reglas.when(
      loading: () => const Cargando(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(reglamentoProvider(mi.liga.id))),
      data: (lista) {
        final principales = [
          for (final c in _clavesPrincipales) ...lista.where((r) => r.clave == c),
        ];
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('${mi.liga.nombreModalidad}: estas son las estándar. Cambia lo que hagáis distinto; '
              'el resto lo tienes en Liga › Reglamento.'),
          const SizedBox(height: 8),
          for (final r in principales)
            if (r.tipo == 'si_no')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.titulo),
                subtitle: r.descripcion == null ? null : Text(r.descripcion!),
                value: r.valor == true,
                onChanged: (v) => cambiar(r, v),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.titulo),
                trailing: DropdownButton<String>(
                  value: r.valor as String?,
                  underline: const SizedBox.shrink(),
                  items: [for (final o in r.opciones) DropdownMenuItem(value: o.valor, child: Text(o.texto))],
                  onChanged: (v) => v == null ? null : cambiar(r, v),
                ),
              ),
        ]);
      },
    );
  }
}
