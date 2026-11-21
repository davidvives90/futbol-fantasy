import '../../core/calendario.dart';
import '../../core/liga_activa.dart';
import '../../core/widget_inicio.dart';
import '../liga/votaciones_screen.dart';
import '../liga/asistencia_screen.dart';
import '../../data/repos/reglamento_repo.dart';
import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/avatar.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/post_partido_repo.dart';
import '../shell/home_shell.dart';
import 'agenda.dart';
import 'selector_asistencia.dart';

/// Partidos en post-partido en los que jugué y aún no he enviado nada.
final _votacionesPendientesProvider =
    FutureProvider.autoDispose.family<List<Partido>, ({String ligaId, String yo})>((ref, k) async {
  final partidos = await ref.watch(partidosProvider(k.ligaId).future);
  final abiertos = partidos.where((p) => p.estado == EstadoPartido.post_partido).toList();
  if (abiertos.isEmpty) return const [];
  final jugados = await sb
      .from('convocatorias')
      .select('partido_id')
      .eq('miembro_id', k.yo)
      .eq('estado', 'confirmado')
      .not('equipo', 'is', null)
      .inFilter('partido_id', [for (final p in abiertos) p.id]);
  final ids = {for (final r in jugados as List) r['partido_id'] as String};
  final pendientes = <Partido>[];
  for (final p in abiertos.where((p) => ids.contains(p.id))) {
    final mio = await PostPartidoRepo.miPostPartido(p.id);
    final enviado = (mio['resultados'] as List? ?? const []).isNotEmpty || (mio['notas'] as List? ?? const []).isNotEmpty;
    if (!enviado) pendientes.add(p);
  }
  return pendientes;
});

/// Inicio: el próximo partido (con «Voy» a un toque y quién va), lo que tengo pendiente y el calendario.
class PartidosScreen extends ConsumerStatefulWidget {
  const PartidosScreen({super.key});

  @override
  ConsumerState<PartidosScreen> createState() => _PartidosScreenState();
}

class _PartidosScreenState extends ConsumerState<PartidosScreen> {
  bool _verTodosAnteriores = false;

  String _saludo(MiLiga mi) {
    final h = DateTime.now().hour;
    final s = tr(h < 6 ? 'Buenas noches' : (h < 14 ? 'Buenos días' : (h < 21 ? 'Buenas tardes' : 'Buenas noches')));
    return '$s, ${mi.yo.nombre.split(' ').first}';
  }

  Future<void> _elegirLiga(BuildContext context) async {
    final ligas = ref.read(misLigasProvider).valueOrNull ?? const <MiLiga>[];
    final actual = ref.read(ligaActualProvider)?.liga.id;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final l in ligas)
            ListTile(
              leading: CircleAvatar(radius: 8, backgroundColor: colorDeLiga(ligas, l.liga.id)),
              title: Text(l.liga.nombre),
              trailing: l.liga.id == actual ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, l.liga.id),
            ),
        ]),
      ),
    );
    if (id != null) await ref.read(ligaActivaIdProvider.notifier).elegir(id);
  }

  @override
  Widget build(BuildContext context) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final partidos = ref.watch(partidosProvider(mi.liga.id));
    final t = Theme.of(context).textTheme;

    return Scaffold(
      // Inicio es de todas mis ligas: sin selector de liga arriba, solo el saludo
      appBar: LigaAppBar(titulo: _saludo(mi)),
      floatingActionButton: mi.soyAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/partidos/nuevo'),
              isExtended: false, // solo «+»: así no tapa los botones de las tarjetas
              tooltip: tr('Nuevo partido'),
              icon: const Icon(Icons.add),
              label: const Tx('Nuevo partido'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(saldosProvider(mi.liga.id));
          ref.invalidate(miembrosProvider(mi.liga.id));
          ref.invalidate(agendaProvider);
          await ref.refresh(partidosProvider(mi.liga.id).future);
        },
        child: partidos.when(
          loading: () => ListView(children: const [Cargando(filas: 5)]),
          error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(partidosProvider(mi.liga.id))),
          data: (lista) {
            final ahora = DateTime.now();
            final proximos = lista
                .where((p) => p.fechaHora.isAfter(ahora.subtract(const Duration(hours: 3))) && p.estado.antesDeJugar)
                .toList()
              ..sort((a, b) => a.fechaHora.compareTo(b.fechaHora));
            final anteriores = lista.where((p) => !proximos.contains(p)).toList()
              ..sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
            final anterioresVisibles = _verTodosAnteriores ? anteriores : anteriores.take(3).toList();

            return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              // Lo urgente arriba; luego mis partidos de TODAS mis ligas (calendario + Voy / No voy)
              _Pendientes(mi: mi),
              const AgendaPersonal(),
              if (proximos.isEmpty && mi.soyAdmin)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Vacio(
                    mi.soyAdmin
                        ? 'Programa la temporada (p. ej. todos los lunes) o crea un partido suelto.'
                        : 'Cuando el administrador convoque, lo verás aquí.',
                    titulo: 'No hay partidos a la vista',
                    icono: Icons.sports_soccer,
                    accion: mi.soyAdmin ? 'Programar temporada' : null,
                    onAccion: mi.soyAdmin ? () => context.push('/temporada') : null,
                  ),
                ),
              if (anteriores.isNotEmpty) ...[
                _Cabecera(trf('Resultados · {l}', {'l': mi.liga.nombre}),
                    accion: (ref.watch(misLigasProvider).valueOrNull?.length ?? 0) > 1 ? 'Otra liga' : null,
                    onAccion: () => _elegirLiga(context)),
                for (final p in anterioresVisibles) _FilaPartido(p, mi: mi),
                if (anteriores.length > 3)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _verTodosAnteriores = !_verTodosAnteriores),
                      child: Text(_verTodosAnteriores ? 'Ver menos' : 'Ver todos (${anteriores.length})'),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => suscribirCalendario(context, mi.liga, lista),
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(trf('Añadir los partidos de {l} a mi calendario', {'l': mi.liga.nombre})),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera(this.texto, {this.accion, this.onAccion});
  final String texto;
  final String? accion;
  final VoidCallback? onAccion;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
        child: Row(children: [
          Expanded(child: Text(tr(texto), style: Theme.of(context).textTheme.titleMedium)),
          if (accion != null) TextButton(onPressed: onAccion, child: Text(tr(accion!))),
        ]),
      );
}

class _ProximoPartido extends ConsumerWidget {
  const _ProximoPartido({required this.partido, required this.mi});
  final Partido partido;
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(convocatoriaProvider(partido.id)).valueOrNull ?? const [];
    final miembros = ref.watch(miembrosPorIdProvider(mi.liga.id));
    // 0042: van = confirmados + fijos sin confirmar + en duda (ocupan plaza)
    final confirmados = conv.where((i) => i.estado.ocupaPlaza).toList();
    final mia = conv.where((i) => i.miembroId == mi.yo.id).firstOrNull?.estado;
    final suplentes = ordenarEspera(conv.where((i) => i.estado == EstadoInscripcion.espera).toList(), miembros,
        porPrioridad: false);
    final puesto = mia == EstadoInscripcion.espera ? suplentes.indexWhere((i) => i.miembroId == mi.yo.id) + 1 : null;
    final importe = confirmados.isEmpty ? null : partido.costeTotal / confirmados.length;
    final faltan = partido.plazas - confirmados.length;
    final abreEn = mi.liga.abreConvocatoria(partido, ref.watch(partidosProvider(mi.liga.id)).valueOrNull ?? const []);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final dias = DateTime(partido.fechaHora.year, partido.fechaHora.month, partido.fechaHora.day)
        .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
        .inDays;
    final cuando = switch (dias) { 0 => 'Hoy', 1 => 'Mañana', _ when dias < 7 => 'En $dias días', _ => 'Próximo partido' };
    // Widget del móvil: el mismo resumen que esta tarjeta
    WidgetInicio.actualizar(
      ref.read(prefsProvider),
      titulo: '${tr(cuando)} · ${fechaHora(partido.fechaHora)}',
      linea: '${confirmados.length}/${partido.plazas} · ${mi.liga.nombre}',
      estado: switch (mia) {
        EstadoInscripcion.confirmado => tr('Vas ✅'),
        EstadoInscripcion.pendiente => tr('Estás en la lista: confirma si vas'),
        EstadoInscripcion.duda => tr('Marcado como «Duda»'),
        EstadoInscripcion.espera => tr('Eres suplente: entras si queda sitio'),
        EstadoInscripcion.baja => tr('No vas'),
        _ => tr('¿Vas? Toca para responder'),
      },
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/partidos/${partido.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(20)),
                child: Text(cuando.toUpperCase(),
                    style: t.labelSmall?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              ),
              const Spacer(),
              if (!partido.horaConfirmada)
                Row(children: [
                  Icon(Icons.schedule, size: 16, color: AppColores.of(context).aviso),
                  const SizedBox(width: 4),
                  Tx('Hora por confirmar', style: t.labelMedium?.copyWith(color: AppColores.of(context).aviso)),
                ]),
            ]),
            const SizedBox(height: 10),
            Text(fechaHora(partido.fechaHora), style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            InkWell(
              onTap: () => abrirUrl(context, partido.campoMapsUrl ?? mi.liga.campoMapsUrl),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(Icons.place_outlined, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(mi.liga.campoNombre ?? 'Ver campo en Maps',
                        style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              PilaAvatares([for (final i in confirmados) miembros[i.miembroId]]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  faltan > 0 ? '${confirmados.length}/${partido.plazas} · faltan $faltan' : '¡Completo! ${confirmados.length}/${partido.plazas}',
                  style: t.titleMedium,
                ),
              ),
              if (importe != null)
                Text('${euros(importe)}/jug.', style: t.labelLarge)
              else if (mi.liga.precioEstimado != null)
                Text('~${euros(mi.liga.precioEstimado)}/jug.', style: t.labelLarge),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: partido.plazas == 0 ? 0 : (confirmados.length / partido.plazas).clamp(0.0, 1.0).toDouble(),
              ),
            ),
            const SizedBox(height: 14),
            if (abreEn != null && mi.yo.rango != RangoMiembro.fijo)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.lock_clock, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(child: Text(trf('Podrás apuntarte de suplente el {f}', {'f': fechaHora(abreEn)}), style: t.labelLarge)),
                ]),
              )
            else
              SizedBox(width: double.infinity, child: SelectorAsistencia(partido: partido, mi: mi, actual: mia, puesto: puesto)),
          ]),
        ),
      ),
    );
  }
}

/// Lo que tengo pendiente, solo si hay algo: votar, pagar, encuesta del Fantasy, solicitudes (admin).
/// Lo urgente de TODAS mis ligas (votar, pagar, votaciones, solicitudes, baja), por orden de urgencia.
/// Con varias ligas, cada tarea lleva su etiqueta de color; al tocarla se cambia a esa liga.
class _Pendientes extends ConsumerWidget {
  const _Pendientes({required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ligas = ref.watch(misLigasProvider).valueOrNull ?? [mi];
    final varias = ligas.length > 1;
    final tareas = <_Tarea>[
      for (final l in ligas)
        ..._tareasDe(context, ref, l, etiqueta: varias ? l.liga.nombre : null, colorLiga: colorDeLiga(ligas, l.liga.id)),
    ]..sort((a, b) => a.prioridad.compareTo(b.prioridad));
    if (tareas.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _AccionPrincipal(tareas.first),
      if (tareas.length > 1) ...[
        const _Cabecera('También pendiente'),
        ...tareas.skip(1),
      ],
    ]);
  }

  List<_Tarea> _tareasDe(BuildContext context, WidgetRef ref, MiLiga mi, {String? etiqueta, required Color colorLiga}) {
    final votar = ref.watch(_votacionesPendientesProvider((ligaId: mi.liga.id, yo: mi.yo.id))).valueOrNull ?? const [];
    final saldos = ref.watch(saldosProvider(mi.liga.id)).valueOrNull ?? const [];
    final miSaldo = saldos.where((s) => s.miembroId == mi.yo.id).firstOrNull?.saldo ?? 0;
    final solicitudes = mi.soyAdmin
        ? (ref.watch(miembrosProvider(mi.liga.id)).valueOrNull ?? const [])
            .where((m) => m.estado == EstadoMiembro.solicitud)
            .length
        : 0;
    final cs = Theme.of(context).colorScheme;
    final abiertas = (ref.watch(votacionesProvider(mi.liga.id)).valueOrNull ?? const <Votacion>[]).where((v) => v.abierta);
    final sinVotar = abiertas.where((v) {
      final r = ref.watch(resultadoVotacionProvider(v.id));
      return r.hasValue && !r.value!.heVotado;
    }).toList();
    final miBaja = (ref.watch(ausenciasMiembroProvider(mi.yo.id)).valueOrNull ?? const <Ausencia>[])
        .where((a) => a.actual)
        .firstOrNull;

    // Antes de ir, se cambia a la liga de la tarea
    VoidCallback ir(void Function() accion) => () async {
          if (ref.read(ligaActivaIdProvider) != mi.liga.id) {
            await ref.read(ligaActivaIdProvider.notifier).elegir(mi.liga.id);
          }
          if (context.mounted) accion();
        };
    _Tarea t({required int prioridad, required IconData icono, required Color color, required String titulo,
            required String subtitulo, required String boton, required VoidCallback onTap}) =>
        _Tarea(
          prioridad: prioridad,
          icono: icono,
          color: color,
          titulo: titulo,
          subtitulo: subtitulo,
          boton: boton,
          onTap: onTap,
          liga: etiqueta,
          colorLiga: colorLiga,
        );

    return [
      for (final p in votar)
        t(
          prioridad: 0,
          icono: Icons.how_to_vote_outlined,
          color: cs.primary,
          titulo: trf('Vota el partido del {f}', {'f': fechaHora(p.fechaHora)}),
          subtitulo: 'Resultado y notas · 1 minuto',
          boton: 'Votar',
          onTap: ir(() => context.push('/partidos/${p.id}')),
        ),
      if (miSaldo < -0.005)
        t(
          prioridad: 1,
          icono: Icons.account_balance_wallet_outlined,
          color: cs.error,
          titulo: trf('Debes {x}', {'x': euros(-miSaldo)}),
          subtitulo: 'Págalo y pulsa «Ya he pagado» en Caja',
          boton: 'Ir a Caja',
          onTap: ir(() => context.go('/caja')),
        ),
      for (final v in sinVotar)
        t(
          prioridad: 2,
          icono: Icons.ballot_outlined,
          color: cs.secondary,
          titulo: v.titulo,
          subtitulo: trf('Votación de la liga · cierra {f}', {'f': fechaHora(v.cierraEn)}),
          boton: 'Votar',
          onTap: ir(() => context.push('/votaciones')),
        ),
      if (solicitudes > 0)
        t(
          prioridad: 3,
          icono: Icons.person_add_alt_1_outlined,
          color: cs.tertiary,
          titulo: solicitudes == 1 ? tr('1 solicitud para unirse') : trf('{n} solicitudes para unirse', {'n': solicitudes}),
          subtitulo: 'Acéptalas o recházalas en Liga',
          boton: 'Revisar',
          onTap: ir(() => context.go('/liga')),
        ),
      if (miBaja != null)
        t(
          prioridad: 4,
          icono: Icons.healing,
          color: Colors.amber.shade700,
          titulo: 'Estás de baja',
          subtitulo: trf('{x} · Toca si ya has vuelto', {'x': textoBaja(miBaja)}),
          boton: 'He vuelto',
          onTap: () async {
            if (!await confirmar(context, '¿Has vuelto?', 'Se termina tu baja y vuelves a recibir las convocatorias.',
                accion: 'He vuelto')) {
              return;
            }
            if (!context.mounted) return;
            final ok = await ejecutar(context, () => ReglamentoRepo.terminarAusencia(miBaja.id), ok: '¡Bienvenido de vuelta!');
            if (ok) ref.invalidate(ausenciasMiembroProvider(mi.yo.id));
          },
        ),
    ];
  }
}

/// Etiqueta de liga (color + nombre) para distinguir de qué grupo es cada cosa.
class _EtiquetaLiga extends StatelessWidget {
  const _EtiquetaLiga(this.nombre, this.color);
  final String nombre;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(nombre.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
        ),
      ]);
}

/// La tarea más urgente, destacada arriba del todo con un botón grande.
class _AccionPrincipal extends StatelessWidget {
  const _AccionPrincipal(this.t);
  final _Tarea t;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: t.color.withValues(alpha: 0.10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (t.liga != null)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: _EtiquetaLiga(t.liga!, t.colorLiga ?? t.color)),
          Row(children: [
            Icon(t.icono, color: t.color),
            const SizedBox(width: 10),
            Expanded(child: Text(tr(t.titulo), style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Text(tr(t.subtitulo), style: tt.bodyMedium),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: t.color),
              onPressed: t.onTap,
              child: Text(tr(t.boton ?? 'Hacerlo ahora')),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Tarea extends StatelessWidget {
  const _Tarea({required this.icono, required this.color, required this.titulo, required this.subtitulo, this.onTap, this.boton,
      this.prioridad = 9, this.liga, this.colorLiga});
  final IconData icono;
  final int prioridad;

  /// Nombre y color de la liga (solo si tengo varias).
  final String? liga;
  final Color? colorLiga;
  final String? boton;
  final Color color;
  final String titulo, subtitulo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icono, color: color),
          ),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (liga != null) _EtiquetaLiga(liga!, colorLiga ?? color),
            Text(tr(titulo)),
          ]),
          subtitle: Text(tr(subtitulo)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class _FilaPartido extends ConsumerWidget {
  const _FilaPartido(this.p, {required this.mi});
  final Partido p;
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final colores = AppColores.of(context);
    final (Color color, IconData icono) = switch (p.estado) {
      EstadoPartido.cerrado => (colores.exito, Icons.emoji_events_outlined),
      EstadoPartido.cancelado => (cs.outline, Icons.event_busy_outlined),
      EstadoPartido.post_partido || EstadoPartido.en_revision || EstadoPartido.jugado => (cs.primary, Icons.how_to_vote_outlined),
      _ => (cs.onSurfaceVariant, Icons.event_outlined),
    };
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icono, color: color, size: 20),
      ),
      title: Text(fechaHora(p.fechaHora)),
      subtitle: Text(p.estado.etiqueta + (!p.horaConfirmada && p.estado.antesDeJugar ? ' · hora por confirmar' : '')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/partidos/${p.id}'),
    );
  }
}
