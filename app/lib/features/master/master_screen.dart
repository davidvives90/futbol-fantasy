import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/models_fantasy.dart';
import '../../data/repos/ligas_repo.dart';
import '../../data/repos/master_repo.dart';

final esMasterProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await MasterRepo.soyMaster();
  } catch (_) {
    return false;
  }
});

final _resumenProvider = FutureProvider.autoDispose((ref) => MasterRepo.resumen());
final _ligasProvider = FutureProvider.autoDispose((ref) => MasterRepo.ligas());
final _codigosProvider = FutureProvider.autoDispose((ref) => MasterRepo.codigos());
final _auditoriaProvider = FutureProvider.autoDispose((ref) => MasterRepo.auditoria());
final _erroresProvider = FutureProvider.autoDispose((ref) => MasterRepo.errores());
final _usuariosProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, q) => MasterRepo.usuarios(q));

String _fecha(dynamic v) => v == null ? '—' : fechaHora(DateTime.parse(v as String));

/// Panel máster: control interno de toda la plataforma. Solo visible para cuentas de la tabla `masters`
/// (el servidor lo vuelve a comprobar en cada acción y las audita).
class MasterScreen extends ConsumerWidget {
  const MasterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = ref.watch(esMasterProvider);
    if (es.isLoading) return const Scaffold(body: Cargando());
    if (es.value != true) {
      return Scaffold(appBar: AppBar(), body: const Vacio('Solo para la cuenta máster.', icono: Icons.lock_outline));
    }
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Tx('Panel máster'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Resumen'),
            Tab(text: 'Ligas'),
            Tab(text: 'Códigos'),
            Tab(text: 'Usuarios'),
            Tab(text: 'Registro'),
            Tab(text: 'Errores'),
          ]),
        ),
        body: const TabBarView(children: [_Resumen(), _Ligas(), _Codigos(), _Usuarios(), _Registro(), _Errores()]),
      ),
    );
  }
}

Widget _async<T>(WidgetRef ref, AsyncValue<T> v, ProviderOrFamily p, Widget Function(T) ok) => v.when(
      data: ok,
      loading: () => const Cargando(),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(p)),
    );

class _Resumen extends ConsumerWidget {
  const _Resumen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _async(ref, ref.watch(_resumenProvider), _resumenProvider, (r) {
      final partidos = (r['partidos'] as Map?) ?? const {};
      Widget cifra(String t, Object? v, {IconData? icono}) => Card(
            child: ListTile(
              leading: Icon(icono ?? Icons.insights_outlined),
              title: Text(t),
              trailing: Text('${v ?? 0}', style: AppTheme.numero(context, size: 22)),
            ),
          );
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(_resumenProvider),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          cifra('Usuarios', r['usuarios'], icono: Icons.person_outline),
          cifra('Ligas', r['ligas'], icono: Icons.groups_outlined),
          cifra('Miembros activos', r['miembros'], icono: Icons.badge_outlined),
          cifra('Disputas abiertas', r['disputas_abiertas'], icono: Icons.report_outlined),
          cifra('Códigos activos', r['codigos_activos'], icono: Icons.redeem_outlined),
          cifra('Canjes', r['canjes'], icono: Icons.card_giftcard_outlined),
          Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Dinero regalado con códigos'),
              trailing: Text(millones(r['dinero_promo'] as num?), style: AppTheme.numero(context, size: 22)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Partidos por estado', style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in partidos.entries) Chip(label: Text('${e.key}: ${e.value}')),
          ]),
          const SizedBox(height: 16),
          Text(
            'Como máster eres administrador de todas las ligas: dentro de una liga puedes usar todas las '
            'herramientas de admin. Para cambios de datos que no estén aquí, usa el panel de Supabase.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      );
    });
  }
}

class _Ligas extends ConsumerWidget {
  const _Ligas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _async(ref, ref.watch(_ligasProvider), _ligasProvider, (ligas) {
      if (ligas.isEmpty) return const Vacio('No hay ligas.');
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(_ligasProvider),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final l in ligas)
            Card(
              child: ListTile(
                title: Text(l['nombre'] as String),
                subtitle: Text('${l['miembros']} miembros · ${l['partidos']} partidos'
                    '${(l['disputas'] as num) > 0 ? ' · ⚠ ${l['disputas']} disputas' : ''}\n'
                    'Admins: ${l['admins'] ?? '—'}\nPróximo: ${_fecha(l['proximo'])}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/master/liga/${l['id']}?nombre=${Uri.encodeComponent(l['nombre'] as String)}'),
              ),
            ),
        ]),
      );
    });
  }
}

class _Codigos extends ConsumerWidget {
  const _Codigos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _crear(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo código'),
      ),
      body: _async(ref, ref.watch(_codigosProvider), _codigosProvider, (codigos) {
        if (codigos.isEmpty) {
          return const Vacio('Crea códigos de dinero Fantasy gratis para promociones o compensar incidencias.',
              icono: Icons.redeem_outlined);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
          for (final c in codigos)
            Card(
              child: SwitchListTile(
                value: c['activo'] == true,
                onChanged: (v) async {
                  if (await ejecutar(context, () => MasterRepo.activarCodigo(c['id'] as String, v))) {
                    ref.invalidate(_codigosProvider);
                  }
                },
                title: Text('${c['codigo']}  ·  ${millones(c['importe'] as num)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                subtitle: Text([
                  c['liga'] ?? 'Todas las ligas',
                  'usos ${c['usos']}${c['usos_max'] == null ? '' : ' / ${c['usos_max']}'}',
                  if (c['caduca'] != null) 'caduca ${_fecha(c['caduca'])}',
                  if ((c['nota'] ?? '').toString().isNotEmpty) c['nota'],
                ].join(' · ')),
              ),
            ),
        ]);
      }),
    );
  }

  Future<void> _crear(BuildContext context, WidgetRef ref) async {
    final ligas = ref.read(_ligasProvider).valueOrNull ?? await MasterRepo.ligas();
    if (!context.mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormCodigo(ligas: ligas),
    );
    if (ok == true) ref.invalidate(_codigosProvider);
  }
}

class _FormCodigo extends StatefulWidget {
  const _FormCodigo({required this.ligas});
  final List<Map<String, dynamic>> ligas;

  @override
  State<_FormCodigo> createState() => _FormCodigoState();
}

class _FormCodigoState extends State<_FormCodigo> {
  final _codigo = TextEditingController();
  final _importe = TextEditingController(text: '5');
  final _usos = TextEditingController();
  final _nota = TextEditingController();
  String? _liga;
  int? _dias;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Nuevo código promocional', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _codigo,
            textCapitalization: TextCapitalization.characters,
            decoration:  InputDecoration(labelText: 'Código (3–24: letras, números, - _)', hintText: tr('BIENVENIDA')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _importe,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Dinero Fantasy (M)', suffixText: 'M'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            value: _liga,
            decoration:  InputDecoration(labelText: tr('Liga')),
            items: [
              const DropdownMenuItem(value: null, child: Tx('Todas las ligas')),
              for (final l in widget.ligas)
                DropdownMenuItem(value: l['id'] as String, child: Text(l['nombre'] as String)),
            ],
            onChanged: (v) => setState(() => _liga = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _usos,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Usos máximos (vacío = sin límite)'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int?>(
            value: _dias,
            decoration: const InputDecoration(labelText: 'Caduca'),
            items: const [
              DropdownMenuItem(value: null, child: Tx('Nunca')),
              DropdownMenuItem(value: 1, child: Tx('En 24 horas')),
              DropdownMenuItem(value: 7, child: Tx('En 7 días')),
              DropdownMenuItem(value: 30, child: Tx('En 30 días')),
            ],
            onChanged: (v) => setState(() => _dias = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _nota, decoration: const InputDecoration(labelText: 'Nota interna (opcional)')),
          const SizedBox(height: 16),
          FilledButton(
            style: AppButtons.premium(context),
            onPressed: () async {
              final importe = double.tryParse(_importe.text.replaceAll(',', '.'));
              if (importe == null || importe <= 0) {
                mostrarError(context, 'Indica un importe válido');
                return;
              }
              final ok = await ejecutar(
                context,
                () => MasterRepo.crearCodigo(
                  codigo: _codigo.text,
                  importe: importe,
                  ligaId: _liga,
                  usosMax: int.tryParse(_usos.text),
                  caduca: _dias == null ? null : DateTime.now().add(Duration(days: _dias!)),
                  nota: _nota.text.trim().isEmpty ? null : _nota.text.trim(),
                ),
                ok: 'Código creado',
              );
              if (ok && context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Crear código'),
          ),
        ]),
      ),
    );
  }
}

class _Usuarios extends ConsumerStatefulWidget {
  const _Usuarios();

  @override
  ConsumerState<_Usuarios> createState() => _UsuariosState();
}

class _UsuariosState extends ConsumerState<_Usuarios> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(_usuariosProvider(_q));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por email o nombre'),
          onSubmitted: (t) => setState(() => _q = t.trim()),
        ),
      ),
      Expanded(
        child: _async(ref, v, _usuariosProvider(_q), (lista) {
          if (lista.isEmpty) return const Vacio('Sin resultados.');
          return ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final u in lista)
              Card(
                child: ListTile(
                  leading: Icon(u['master'] == true ? Icons.shield : Icons.person_outline),
                  title: Text(u['nombre'] as String? ?? '(sin perfil)'),
                  subtitle: Text('${u['email'] ?? ''}\n'
                      'Alta ${_fecha(u['creado_en'])} · último acceso ${_fecha(u['ultimo_acceso'])}\n'
                      '${((u['ligas'] as List?) ?? const []).map((l) => '${l['liga']} (${l['rol']}, ${l['estado']})').join(' · ')}'),
                  isThreeLine: true,
                ),
              ),
          ]);
        }),
      ),
    ]);
  }
}

class _Registro extends ConsumerWidget {
  const _Registro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _async(ref, ref.watch(_auditoriaProvider), _auditoriaProvider, (lista) {
      if (lista.isEmpty) return const Vacio('Aún no hay acciones de máster registradas.', icono: Icons.history);
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(_auditoriaProvider),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final a in lista)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history),
              title: Text('${a['accion']}${a['liga'] == null ? '' : ' · ${a['liga']}'}'),
              subtitle: Text('${_fecha(a['creado_en'])} · ${a['quien'] ?? ''}\n${a['detalle']}'),
              isThreeLine: true,
            ),
        ]),
      );
    });
  }
}

class _Errores extends ConsumerWidget {
  const _Errores();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _async(ref, ref.watch(_erroresProvider), _erroresProvider, (lista) {
      if (lista.isEmpty) return const Vacio('Sin errores registrados. ¡Bien!', icono: Icons.verified_outlined);
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(_erroresProvider),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final e in lista)
            Card(
              child: ExpansionTile(
                leading: Icon(Icons.bug_report_outlined, color: Theme.of(context).colorScheme.error),
                title: Text(e['mensaje'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${e['veces']}× · ${_fecha(e['ultimo_en'])} · v${e['version'] ?? '?'} · '
                    '${e['pantalla'] ?? ''} · ${e['quien'] ?? ''}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  SelectableText('${e['mensaje']}\n\n${e['traza'] ?? ''}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ],
              ),
            ),
        ]),
      );
    });
  }
}

// ─────────────────────────────── Liga (vista máster) ───────────────────────────────

class MasterLigaScreen extends ConsumerStatefulWidget {
  const MasterLigaScreen({super.key, required this.ligaId, required this.nombre});
  final String ligaId, nombre;

  @override
  ConsumerState<MasterLigaScreen> createState() => _MasterLigaScreenState();
}

class _MasterLigaScreenState extends ConsumerState<MasterLigaScreen> {
  late Future<List<Miembro>> _miembros;
  late Future<List<Map<String, dynamic>>> _managers;
  late Future<List<Map<String, dynamic>>> _partidos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _miembros = LigasRepo.miembros(widget.ligaId);
    _managers = MasterRepo.managers(widget.ligaId);
    _partidos = MasterRepo.partidos(widget.ligaId);
  }

  void _recargar() => setState(_cargar);

  Future<String?> _pedirMotivo(String titulo, {bool importe = false}) async {
    final motivo = TextEditingController();
    final cantidad = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (importe)
            TextField(
              controller: cantidad,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Importe (M, negativo para quitar)', suffixText: 'M'),
            ),
          const SizedBox(height: 8),
          TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (queda registrado)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Tx('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(c, importe ? '${cantidad.text}|${motivo.text}' : motivo.text),
            child: const Tx('Aplicar'),
          ),
        ],
      ),
    );
    return r;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.nombre),
          bottom: const TabBar(tabs: [Tab(text: 'Miembros'), Tab(text: 'Fantasy'), Tab(text: 'Partidos')]),
        ),
        body: TabBarView(children: [
          // ───── Miembros
          FutureBuilder<List<Miembro>>(
            future: _miembros,
            builder: (_, s) {
              if (s.hasError) return ErrorVista(s.error!, onRetry: _recargar);
              if (!s.hasData) return const Cargando();
              return ListView(padding: const EdgeInsets.all(12), children: [
                for (final m in s.data!)
                  Card(
                    child: ListTile(
                      title: Text(m.nombre),
                      subtitle: Text('${m.rol.name} · ${m.rango.etiqueta} · ${m.estado.name}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) async {
                          final ok = await ejecutar(context, () async {
                            switch (a) {
                              case 'admin':
                                await LigasRepo.cambiarRol(m.id, m.esAdmin ? RolLiga.jugador : RolLiga.admin);
                              case 'fijo':
                                await LigasRepo.cambiarRango(m.id, RangoMiembro.fijo);
                              case 'reserva':
                                await LigasRepo.cambiarRango(m.id, RangoMiembro.reserva);
                              case 'invitado':
                                await LigasRepo.cambiarRango(m.id, RangoMiembro.invitado);
                              case 'expulsar':
                                await LigasRepo.expulsar(m.id);
                            }
                          }, ok: 'Hecho');
                          if (ok) _recargar();
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'admin', child: Text(m.esAdmin ? 'Quitar admin' : 'Hacer admin')),
                          const PopupMenuItem(value: 'fijo', child: Tx('Rango: fijo')),
                          const PopupMenuItem(value: 'reserva', child: Tx('Rango: reserva')),
                          const PopupMenuItem(value: 'invitado', child: Tx('Rango: invitado')),
                          const PopupMenuItem(value: 'expulsar', child: Tx('Expulsar')),
                        ],
                      ),
                    ),
                  ),
              ]);
            },
          ),
          // ───── Fantasy: saldos
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _managers,
            builder: (_, s) {
              if (s.hasError) return ErrorVista(s.error!, onRetry: _recargar);
              if (!s.hasData) return const Cargando();
              if (s.data!.isEmpty) return const Vacio('El Fantasy de esta liga aún no ha empezado.');
              return ListView(padding: const EdgeInsets.all(12), children: [
                for (final m in s.data!)
                  Card(
                    child: ListTile(
                      title: Text(m['nombre'] as String? ?? '—'),
                      subtitle: Text('Puntos ${m['puntos']}'),
                      trailing: TextButton(
                        onPressed: () async {
                          final r = await _pedirMotivo('Ajustar saldo de ${m['nombre']}', importe: true);
                          if (r == null || !mounted) return;
                          final partes = r.split('|');
                          final importe = double.tryParse(partes[0].replaceAll(',', '.'));
                          if (importe == null) {
                            mostrarError(context, 'Importe no válido');
                            return;
                          }
                          final ok = await ejecutar(
                            context,
                            () => MasterRepo.ajustarSaldo(widget.ligaId, m['miembro_id'] as String, importe, partes[1]),
                            ok: 'Saldo ajustado',
                          );
                          if (ok) _recargar();
                        },
                        child: Text(millones(m['saldo'] as num?)),
                      ),
                    ),
                  ),
              ]);
            },
          ),
          // ───── Partidos: forzar estado
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _partidos,
            builder: (_, s) {
              if (s.hasError) return ErrorVista(s.error!, onRetry: _recargar);
              if (!s.hasData) return const Cargando();
              if (s.data!.isEmpty) return const Vacio('Sin partidos.');
              return ListView(padding: const EdgeInsets.all(12), children: [
                for (final p in s.data!)
                  Card(
                    child: ListTile(
                      title: Text(_fecha(p['fecha_hora'])),
                      subtitle: Text('${p['estado']} · ${p['confirmados']} confirmados'
                          '${(p['disputas'] as num) > 0 ? ' · ⚠ ${p['disputas']} disputas' : ''}'),
                      trailing: p['estado'] == 'cerrado'
                          ? const Icon(Icons.lock_outline)
                          : PopupMenuButton<String>(
                              tooltip: 'Forzar estado',
                              icon: const Icon(Icons.build_outlined),
                              onSelected: (estado) async {
                                final motivo = await _pedirMotivo('Pasar a «$estado»');
                                if (motivo == null || !mounted) return;
                                final ok = await ejecutar(
                                  context,
                                  () => MasterRepo.forzarEstado(p['id'] as String, estado, motivo),
                                  ok: 'Estado cambiado',
                                );
                                if (ok) _recargar();
                              },
                              itemBuilder: (_) => [
                                for (final e in EstadoPartido.values.where((e) => e != EstadoPartido.cerrado))
                                  PopupMenuItem(value: e.name, child: Text(e.etiqueta)),
                              ],
                            ),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
