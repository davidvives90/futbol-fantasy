import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/compartir.dart';
import '../../core/idioma.dart';
import '../../core/liga_activa.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widget_inicio.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/partidos_repo.dart';

/// Un partido de cualquiera de mis ligas, con mi estado (0043, `mi_agenda`).
class CitaAgenda {
  CitaAgenda.fromMap(Map<String, dynamic> m)
      : partidoId = m['partido_id'] as String,
        ligaId = m['liga_id'] as String,
        liga = (m['liga'] ?? '') as String,
        fecha = DateTime.parse(m['fecha'] as String).toLocal(),
        horaConfirmada = (m['hora_confirmada'] ?? true) as bool,
        campo = m['campo'] as String?,
        plazas = toInt(m['plazas'], 10),
        ocupadas = toInt(m['ocupadas'], 0),
        miembroId = m['miembro_id'] as String,
        fijo = m['rango'] == 'fijo',
        miEstado = m['mi_estado'] == null
            ? null
            : EstadoInscripcion.values.firstWhere((e) => e.name == m['mi_estado'], orElse: () => EstadoInscripcion.duda),
        puesto = m['puesto'] == null ? null : toInt(m['puesto']),
        abreEn = m['abre_en'] == null ? null : DateTime.parse(m['abre_en'] as String).toLocal();

  final String partidoId, ligaId, liga, miembroId;
  final DateTime fecha;
  final bool horaConfirmada, fijo;
  final String? campo;
  final int plazas, ocupadas;
  final EstadoInscripcion? miEstado;
  final int? puesto;
  final DateTime? abreEn;
}

/// Los próximos 3 semanas de todas mis ligas.
final agendaProvider = FutureProvider.autoDispose<List<CitaAgenda>>((ref) async {
  final r = await sb.rpc('mi_agenda', params: {'p_dias': 21});
  return [for (final m in r as List) CitaAgenda.fromMap(Map<String, dynamic>.from(m as Map))];
});

/// Estado «visual» de una cita: color, icono y texto corto.
enum _Situacion { vas, responde, duda, suplente, noVas, cerrada }

({Color color, IconData icono, String texto}) _aspecto(BuildContext context, _Situacion s, int? puesto) {
  final c = AppColores.of(context);
  final cs = Theme.of(context).colorScheme;
  return switch (s) {
    _Situacion.vas => (color: c.exito, icono: Icons.check_circle, texto: tr('Vas')),
    _Situacion.responde => (color: c.aviso, icono: Icons.notifications_active, texto: tr('¡Responde!')),
    _Situacion.duda => (color: Colors.amber.shade700, icono: Icons.help, texto: tr('Duda')),
    _Situacion.suplente => (
        color: cs.tertiary,
        icono: Icons.hourglass_top,
        texto: puesto == null ? tr('Suplente') : trf('Suplente nº {n}', {'n': puesto})
      ),
    _Situacion.noVas => (color: cs.outline, icono: Icons.cancel, texto: tr('No vas')),
    _Situacion.cerrada => (color: cs.outline, icono: Icons.lock_clock, texto: tr('Aún cerrada')),
  };
}

_Situacion _situacion(EstadoInscripcion? e, bool fijo, DateTime? abreEn) => switch (e) {
      EstadoInscripcion.confirmado => _Situacion.vas,
      EstadoInscripcion.pendiente => _Situacion.responde,
      EstadoInscripcion.duda => _Situacion.duda,
      EstadoInscripcion.espera => _Situacion.suplente,
      EstadoInscripcion.baja => _Situacion.noVas,
      // 0050: el servidor ya da la apertura de cada persona (en «turnos» no es la misma para todos)
      null => (abreEn != null && abreEn.isAfter(DateTime.now())) ? _Situacion.cerrada : _Situacion.responde,
    };

/// Colores fijos por liga (en el orden de mis ligas), para distinguirlas de un vistazo.
const _coloresLiga = [Color(0xFF1E88E5), Color(0xFF8E24AA), Color(0xFFF4511E), Color(0xFF00897B), Color(0xFF6D4C41)];

/// Color de una liga (el mismo en la agenda y en lo pendiente).
Color colorDeLiga(List<MiLiga> ligas, String ligaId) {
  final i = ligas.indexWhere((l) => l.liga.id == ligaId);
  // 0061: si la liga tiene color propio, ese
  final propio = i < 0 ? null : ligas[i].liga.colorPropio;
  return propio ?? _coloresLiga[(i < 0 ? 0 : i) % _coloresLiga.length];
}

/// Inicio: mi agenda de TODAS mis ligas. Un calendario de 2 semanas con un punto por partido (de color según
/// si voy o no) y, debajo, cada partido con Voy / Duda / No voy a un toque. Tocar un partido lleva a él.
class AgendaPersonal extends ConsumerStatefulWidget {
  const AgendaPersonal({super.key, this.ligaId});
  /// Si no es null, solo los partidos de esa liga.
  final String? ligaId;

  @override
  ConsumerState<AgendaPersonal> createState() => _AgendaPersonalState();
}

class _AgendaPersonalState extends ConsumerState<AgendaPersonal> {
  final _claves = <String, GlobalKey>{};
  DateTime? _dia;

  @override
  Widget build(BuildContext context) {
    final agenda = ref.watch(agendaProvider);
    final ligas = ref.watch(misLigasProvider).valueOrNull ?? const <MiLiga>[];
    final orden = [for (final l in ligas) l.liga.id];
    Color colorLiga(String id) {
      final i = orden.indexOf(id);
      return _coloresLiga[(i < 0 ? 0 : i) % _coloresLiga.length];
    }

    final t = Theme.of(context).textTheme;
    return agenda.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: Cargando(filas: 2)),
      error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(agendaProvider)),
      data: (todas) {
        _actualizarWidget(todas); // el widget de la pantalla de inicio del móvil siempre con todas
        final citas = widget.ligaId == null ? todas : todas.where((c) => c.ligaId == widget.ligaId).toList();
        final hoy = DateTime.now();
        final dias = [for (var i = 0; i < 14; i++) DateTime(hoy.year, hoy.month, hoy.day + i)];
        bool mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
        final visibles = _dia == null ? citas : citas.where((c) => mismoDia(c.fecha, _dia!)).toList();
        final variasLigas = citas.map((c) => c.ligaId).toSet().length > 1 || ligas.length > 1;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Expanded(child: Text(tr('Mis partidos'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              if (_dia != null)
                TextButton(onPressed: () => setState(() => _dia = null), child: Text(tr('Ver todos'))),
            ]),
          ),
          // Calendario: 2 semanas, un punto de color por partido
          SizedBox(
            height: 78,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: dias.length,
              itemBuilder: (context, i) {
                final d = dias[i];
                final delDia = citas.where((c) => mismoDia(c.fecha, d)).toList();
                final sel = _dia != null && mismoDia(_dia!, d);
                final esHoy = i == 0;
                final cs = Theme.of(context).colorScheme;
                return GestureDetector(
                  onTap: delDia.isEmpty
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          setState(() => _dia = sel ? null : d);
                        },
                  child: Container(
                    width: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                    decoration: BoxDecoration(
                      color: sel ? cs.primary : (delDia.isNotEmpty ? cs.primaryContainer.withValues(alpha: 0.5) : null),
                      borderRadius: BorderRadius.circular(14),
                      border: esHoy && !sel ? Border.all(color: cs.primary, width: 1.5) : null,
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(DateFormat.E(idiomaActual).format(d).replaceAll('.', ''),
                          style: t.labelSmall?.copyWith(color: sel ? cs.onPrimary : cs.onSurfaceVariant)),
                      Text('${d.day}',
                          style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800, color: sel ? cs.onPrimary : (delDia.isEmpty ? cs.outline : null))),
                      const SizedBox(height: 3),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        // Icono además del color (✓ vas, campana responde, ✕ no vas…): se distingue sin ver colores
                        for (final c in delDia.take(3))
                          Builder(builder: (context) {
                            final a = _aspecto(context, _situacion(c.miEstado, c.fijo, c.abreEn), c.puesto);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 0.5),
                              child: Icon(a.icono, size: 12, color: sel ? cs.onPrimary : a.color, semanticLabel: a.texto),
                            );
                          }),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (citas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Vacio(
                'Cuando haya partido en alguna de tus ligas, lo verás aquí con un toque para apuntarte.',
                titulo: 'Sin partidos estas semanas',
                icono: Icons.event_available,
              ),
            ),
          for (final (i, c) in visibles.indexed)
            _TarjetaCita(
              key: _claves.putIfAbsent(c.partidoId, GlobalKey.new),
              cita: c,
              colorLiga: colorLiga(c.ligaId),
              mostrarLiga: variasLigas,
              // 0060: el primero, en grande: «Tu próximo partido»
              destacada: i == 0 && _dia == null,
            ),
        ]);
      },
    );
  }

  /// El widget del móvil muestra el primer partido de la agenda.
  void _actualizarWidget(List<CitaAgenda> citas) {
    if (citas.isEmpty) return;
    final c = citas.first;
    final a = _aspecto(context, _situacion(c.miEstado, c.fijo, c.abreEn), c.puesto);
    WidgetInicio.actualizar(
      ref.read(prefsProvider),
      titulo: fechaHora(c.fecha),
      linea: '${c.ocupadas}/${c.plazas} · ${c.liga}',
      estado: a.texto,
    );
  }
}

/// Una cita: liga (color), día y hora en grande, cuántos van, mi estado y los botones.
/// Escucha la convocatoria en tiempo real: lo que cambie cualquiera se ve al momento.
class _TarjetaCita extends ConsumerWidget {
  const _TarjetaCita(
      {super.key, required this.cita, required this.colorLiga, required this.mostrarLiga, this.destacada = false});
  final CitaAgenda cita;
  final Color colorLiga;
  final bool mostrarLiga, destacada;

  /// «Hoy», «Mañana» o «En 3 días»
  static String cuando(DateTime f) {
    final hoy = DateTime.now();
    final d = DateTime(f.year, f.month, f.day).difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
    if (d <= 0) return tr('Hoy');
    if (d == 1) return tr('Mañana');
    return trf('En {n} días', {'n': d});
  }

  Future<void> _compartir(BuildContext context, WidgetRef ref) async {
    final mi = ref.read(misLigasProvider).valueOrNull?.where((l) => l.liga.id == cita.ligaId).firstOrNull;
    if (mi == null) return;
    try {
      final r = Map<String, dynamic>.from(await sb.rpc('resumen_compartir', params: {'p_partido': cita.partidoId}) as Map);
      if (!context.mounted) return;
      await compartirTexto(context, textoPartido(r, mi.liga, cita.partidoId), tarjeta: TarjetaPartido(r: r, liga: mi.liga));
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  Future<void> _abrir(BuildContext context, WidgetRef ref) async {
    await ref.read(ligaActivaIdProvider.notifier).elegir(cita.ligaId);
    if (context.mounted) context.push('/partidos/${cita.partidoId}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mientras llega el tiempo real (o si viene vacío), vale lo que dijo el servidor
    final vivo = ref.watch(convocatoriaResumenProvider(cita.partidoId)).valueOrNull;
    final conv = (vivo == null || vivo.isEmpty) ? null : vivo;
    final mia = conv?.where((i) => i.miembroId == cita.miembroId).firstOrNull;
    final estado = conv == null ? cita.miEstado : mia?.estado;
    final ocupadas = conv == null ? cita.ocupadas : conv.where((i) => i.estado.ocupaPlaza).length;
    int? puesto = cita.puesto;
    if (conv != null && estado == EstadoInscripcion.espera) {
      final miembros = ref.watch(miembrosPorIdProvider(cita.ligaId));
      final esp = ordenarEspera(conv.where((i) => i.estado == EstadoInscripcion.espera).toList(), miembros,
          porPrioridad: ref.watch(misLigasProvider).valueOrNull?.where((l) => l.liga.id == cita.ligaId).firstOrNull
                  ?.liga.fijosPrimero ?? true);
      puesto = esp.indexWhere((i) => i.miembroId == cita.miembroId) + 1;
    }
    final sit = _situacion(estado, cita.fijo, cita.abreEn);
    final a = _aspecto(context, sit, puesto);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final dia = DateFormat('EEEE d MMM', idiomaActual).format(cita.fecha);
    final hora = DateFormat('HH:mm').format(cita.fecha);
    final faltan = cita.plazas - ocupadas;

    Future<void> cambiar(EstadoInscripcion e) async {
      HapticFeedback.selectionClick();
      final antes = estado;
      final ok = await ejecutar(context, () => PartidosRepo.cambiarEstado(cita.partidoId, cita.miembroId, e));
      if (ok && context.mounted && antes != null) {
        avisoDeshacer(context, tr('Cambiado'), () => PartidosRepo.cambiarEstado(cita.partidoId, cita.miembroId, antes));
      }
    }

    Widget mini(EstadoInscripcion e, String texto, IconData icono, Color color) {
      final sel = estado == e;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: SizedBox(
            height: 44,
            child: sel
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: color, padding: EdgeInsets.zero),
                    onPressed: () {},
                    icon: Icon(icono, size: 18),
                    label: Text(tr(texto)),
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.45)), padding: EdgeInsets.zero),
                    onPressed: () => cambiar(e),
                    icon: Icon(icono, size: 18),
                    label: Text(tr(texto)),
                  ),
          ),
        ),
      );
    }

    final dentro = estado != null && estado.ocupaPlaza;
    final Widget acciones;
    if (sit == _Situacion.cerrada) {
      acciones = Text(trf('Podrás apuntarte el {f}', {'f': fechaHora(cita.abreEn!)}), style: t.bodySmall);
    } else if (cita.fijo || dentro) {
      acciones = Row(children: [
        mini(EstadoInscripcion.confirmado, 'Voy', Icons.check, AppColores.of(context).exito),
        mini(EstadoInscripcion.duda, 'Duda', Icons.help_outline, Colors.amber.shade700),
        mini(EstadoInscripcion.baja, 'No voy', Icons.close, cs.error),
      ]);
    } else if (estado == EstadoInscripcion.espera) {
      acciones = Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: () => cambiar(EstadoInscripcion.baja), child: Text(tr('Quitarme'))),
      );
    } else {
      acciones = SizedBox(
        width: double.infinity,
        height: 44,
        child: FilledButton.icon(
          onPressed: () => cambiar(EstadoInscripcion.confirmado),
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: Text(tr('Apuntarme de suplente')),
        ),
      );
    }

    final cabecera = !destacada
        ? null
        : Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.3)!]),
            ),
            child: Row(children: [
              Icon(Icons.sports_soccer, size: 18, color: cs.onPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${tr('Tu próximo partido')} · ${cuando(cita.fecha)}',
                    style: t.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              ),
              IconButton(
                tooltip: tr('Compartir en WhatsApp'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.share, size: 20, color: cs.onPrimary),
                onPressed: () => _compartir(context, ref),
              ),
            ]),
          );
    return Card(
      margin: EdgeInsets.fromLTRB(16, destacada ? 8 : 6, 16, destacada ? 10 : 6),
      elevation: destacada ? 3 : null,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(destacada ? 20 : 16),
        side: sit == _Situacion.responde ? BorderSide(color: a.color, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _abrir(context, ref),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (cabecera != null) cabecera,
          IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 7, color: colorLiga),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (mostrarLiga)
                      Expanded(
                        child: Text(cita.liga.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelMedium?.copyWith(color: colorLiga, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                      )
                    else
                      const Spacer(),
                    // Mi estado, bien visible
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: a.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(a.icono, size: 16, color: a.color),
                        const SizedBox(width: 4),
                        Text(a.texto, style: t.labelLarge?.copyWith(color: a.color, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('${dia[0].toUpperCase()}${dia.substring(1)}', style: t.titleMedium),
                  Row(children: [
                    Text(hora, style: (destacada ? t.displaySmall : t.headlineMedium)?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
                    if (!cita.horaConfirmada) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: tr('Hora por confirmar'),
                        child: Icon(Icons.schedule, size: 18, color: AppColores.of(context).aviso),
                      ),
                    ],
                    const Spacer(),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('$ocupadas/${cita.plazas}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(faltan > 0 ? trf('faltan {n}', {'n': faltan}) : tr('completo'),
                          style: t.labelSmall?.copyWith(color: faltan > 0 ? AppColores.of(context).aviso : cs.onSurfaceVariant)),
                    ]),
                  ]),
                  if ((cita.campo ?? '').isNotEmpty)
                    Row(children: [
                      Icon(Icons.place_outlined, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Expanded(child: Text(cita.campo!, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  const SizedBox(height: 8),
                  acciones,
                ]),
              ),
            ),
          ]),
          ),
        ]),
      ),
    );
  }
}
