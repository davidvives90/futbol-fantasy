import 'package:flutter/material.dart';
import '../../core/idioma.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'asistencia_screen.dart';
import '../../data/repos/reglamento_repo.dart';

import '../../core/liga_activa.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';
import '../shell/home_shell.dart';
import 'chip_rango.dart';
import '../../core/avatar.dart';
import '../../core/info.dart';

String _enlacePersonal(String token) => '${Env.webInvitacion}/$token';

String _textoInvitacion(String liga, String? nombre, String codigo) =>
    '${nombre == null ? '¡Hola!' : '¡Hola, $nombre!'} Te invito a la liga "$liga" en Fútbol Fantasy. '
    'Descarga la app y únete desde este enlace: ${_enlacePersonal(codigo)}\n'
    'Si ya tienes la app, pega este código en "Unirse": $codigo';

class LigaScreen extends ConsumerWidget {
  const LigaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mi = ref.watch(ligaActualProvider);
    if (mi == null) return const Scaffold(body: Cargando());
    final liga = mi.liga;
    final miembros = ref.watch(miembrosProvider(liga.id));

    return Scaffold(
      appBar: const LigaAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(miembrosProvider(liga.id));
          refrescarLigas(ref);
        },
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          _Datos(mi: mi),
          // Lo del administrador, junto y separado de lo que ve todo el mundo
          if (mi.soyAdmin) const _PanelAdmin(),
          _Accesos(mi: mi),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: const Tx('Reglamento'),
                subtitle: Text('${mi.liga.nombreModalidad}: cesión, saques, cambios, calzado…'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/reglamento'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.how_to_vote_outlined),
                title: const Tx('Votaciones'),
                subtitle: const Tx('Lo que se decide entre todos'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/votaciones'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.event_busy_outlined),
                title: const Tx('Asistencia y bajas'),
                subtitle: const Tx('Quién viene, quién falta y quién está lesionado'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/asistencia'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Tx('Guía y normas de la liga'),
                subtitle: const Tx('Lo acordado, cómo puntúa y cómo funciona el Fantasy'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/guia'),
              ),
            ]),
          ),
          miembros.when(
            loading: () => const Cargando(),
            error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(miembrosProvider(liga.id))),
            data: (lista) => _Miembros(mi: mi, miembros: lista),
          ),
          const SizedBox(height: 8),
          _Invitar(mi: mi),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              icon: const Icon(Icons.logout, size: 18),
              label: const Tx('Abandonar la liga'),
              onPressed: () async {
              if (!await confirmar(context, 'Abandonar ${liga.nombre}',
                  'Dejarás de ver sus partidos. Tu historial y tus deudas se conservan.', accion: 'Abandonar', tipo: TipoConfirmacion.peligro)) {
                return;
              }
              if (!context.mounted) return;
              final ok = await ejecutar(context, () => LigasRepo.abandonar(liga.id), ok: 'Has salido de la liga');
              if (ok) {
                await ref.read(ligaActivaIdProvider.notifier).elegir(null);
                refrescarLigas(ref);
              }
            },
            ),
          ),
        ]),
      ),
    );
  }
}

class _Datos extends StatelessWidget {
  const _Datos({required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context) {
    final l = mi.liga;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.nombre, style: Theme.of(context).textTheme.headlineSmall),
          if (l.descripcion != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.descripcion!)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(avatar: const Icon(Icons.sports_soccer, size: 18), label: Text(l.formato)),
            Chip(avatar: const Icon(Icons.groups, size: 18), label: Text('${l.plazas} plazas')),
            if (l.precioEstimado != null)
              Chip(avatar: const Icon(Icons.euro, size: 18), label: Text('~${euros(l.precioEstimado)}/jugador')),
            Chip(
              avatar: Icon(l.publica ? Icons.public : Icons.lock_outline, size: 18),
              label: Text(l.publica ? 'Pública' : 'Privada'),
            ),
            Chip(
              avatar: Icon(nivelesLiga.firstWhere((n) => n.$1 == l.nivel, orElse: () => nivelesLiga.last).$2, size: 18),
              label: Text(trf('Modo {n}', {'n': tr(nivelesLiga.firstWhere((n) => n.$1 == l.nivel, orElse: () => nivelesLiga.last).$3).toLowerCase()})),
            ),
            if (l.esAvanzada && l.fantasy.bonusRoles) const Chip(label: Tx('Bonus por rol en la alineación')),
          ]),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(l.campoNombre ?? 'Campo sin indicar'),
            subtitle: l.ciudad == null ? null : Text(l.ciudad!),
            trailing: l.campoMapsUrl == null
                ? null
                : IconButton(
                    tooltip: tr('Abrir en Google Maps'),
                    icon: const Icon(Icons.map),
                    onPressed: () => abrirUrl(context, l.campoMapsUrl),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _Invitar extends ConsumerWidget {
  const _Invitar({required this.mi});
  final MiLiga mi;

  Future<void> _precrear(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final nombres = await showDialog<List<String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Tx('Pre-crear jugadores'),
        content: TextField(
          controller: ctrl,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(hintText: 'Un nombre por línea\nPepe\nLuis\nCarlos'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Tx('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              ctrl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList(),
            ),
            child: const Tx('Crear'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nombres == null || nombres.isEmpty || !context.mounted) return;

    try {
      final filas = await LigasRepo.precrearJugadores(mi.liga.id, nombres);
      ref.invalidate(miembrosProvider(mi.liga.id));
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const ListTile(
              title: Tx('Envía a cada uno su enlace'),
              subtitle: Tx('Al registrarse con él heredará su ficha y su historial.'),
            ),
            for (final f in filas)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(f['nombre'] as String),
                trailing: IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () => Share.share(
                    _textoInvitacion(mi.liga.nombre, f['nombre'] as String, f['token'] as String),
                  ),
                ),
              ),
          ]),
        ),
      );
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codigo = mi.liga.codigoInvitacion;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.vpn_key_outlined),
          title: const Tx('Código de la liga'),
          subtitle: SelectableText(codigo, style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: 4)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: tr('Copiar'),
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: codigo));
                if (context.mounted) mostrarOk(context, 'Código copiado');
              },
            ),
            IconButton(
              tooltip: tr('Compartir'),
              icon: const Icon(Icons.share),
              onPressed: () => Share.share(_textoInvitacion(mi.liga.nombre, null, codigo)),
            ),
          ]),
        ),
        if (mi.soyAdmin)
          OverflowBar(alignment: MainAxisAlignment.end, children: [
            TextButton(
              style: AppButtons.peligroTexto(context),
              onPressed: () async {
                if (!await confirmar(context, 'Regenerar código', 'El código actual dejará de funcionar.',
                    accion: 'Regenerar', tipo: TipoConfirmacion.peligro)) {
                  return;
                }
                if (!context.mounted) return;
                await ejecutar(context, () => LigasRepo.regenerarCodigo(mi.liga.id), ok: 'Código regenerado');
                refrescarLigas(ref);
              },
              child: const Tx('Regenerar código'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _precrear(context, ref),
              icon: const Icon(Icons.person_add_alt),
              label: const Tx('Pre-crear jugadores'),
            ),
          ]),
      ]),
    );
  }
}

class _Miembros extends ConsumerWidget {
  const _Miembros({required this.mi, required this.miembros});
  final MiLiga mi;
  final List<Miembro> miembros;

  Future<void> _accion(BuildContext context, WidgetRef ref, Miembro m, String accion) async {
    Future<void> Function()? op;
    String? ok;
    switch (accion) {
      case 'admin':
        op = () => LigasRepo.cambiarRol(m.id, RolLiga.admin);
        ok = '${m.nombre} ahora es administrador';
      case 'quitar_admin':
        op = () => LigasRepo.cambiarRol(m.id, RolLiga.jugador);
        ok = '${m.nombre} ya no es administrador';
      case 'expulsar':
        if (!await confirmar(
          context,
          'Expulsar a ${m.nombre}',
          'Perderá el acceso a la liga y no podrá volver con el código. '
              'Sus inscripciones a próximos partidos se cancelarán. Su historial y sus deudas se conservan.',
          accion: 'Expulsar',
          tipo: TipoConfirmacion.peligro,
        )) {
          return;
        }
        op = () => LigasRepo.expulsar(m.id);
        ok = '${m.nombre} expulsado';
      case 'rango_fijo' || 'rango_reserva' || 'rango_invitado':
        final rango = RangoMiembro.values.firstWhere((r) => 'rango_${r.name}' == accion);
        if (rango == m.rango) return;
        op = () => LigasRepo.cambiarRango(m.id, rango);
        ok = '${m.nombre} ahora es ${rango.etiqueta.toLowerCase()}';
      case 'baja':
        // Lesión o ausencia larga: no se le apunta solo hasta que vuelva
        await registrarBaja(context, ref, mi, miembroId: m.id);
        return;
      case 'invitar':
        // El token no es legible por columna: solo los admins lo obtienen con enlaces_invitacion().
        try {
          final enlaces = await LigasRepo.enlacesInvitacion(mi.liga.id);
          final fila = enlaces.where((e) => e['miembro_id'] == m.id).firstOrNull;
          if (fila == null || fila['token'] == null) {
            if (context.mounted) mostrarError(context, 'Este jugador ya no tiene enlace pendiente');
            return;
          }
          await Share.share(_textoInvitacion(mi.liga.nombre, m.nombre, fila['token'] as String));
        } catch (e) {
          if (context.mounted) mostrarError(context, e);
        }
        return;
    }
    if (op == null || !context.mounted) return;
    await ejecutar(context, op, ok: ok);
    ref.invalidate(miembrosProvider(mi.liga.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solicitudes = miembros.where((m) => m.estado == EstadoMiembro.solicitud).toList();
    final activos = miembros
        .where((m) => m.estado == EstadoMiembro.activo || m.estado == EstadoMiembro.pendiente_registro)
        .toList()
      ..sort((a, b) {
        if (a.esAdmin != b.esAdmin) return a.esAdmin ? -1 : 1;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    final expulsados = miembros.where((m) => m.estado == EstadoMiembro.expulsado).toList();
    final deBaja = {
      for (final a in ref.watch(bajasLigaProvider(mi.liga.id)).valueOrNull ?? const <Ausencia>[])
        if (a.actual) a.miembroId
    };
    final t = Theme.of(context).textTheme;
    final numFijos = activos.where((m) => m.rango == RangoMiembro.fijo).length;
    final plazasFijas = mi.liga.plazasFijas ?? mi.liga.plazas;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (mi.soyAdmin && solicitudes.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 4), child: Text('Solicitudes (${solicitudes.length})', style: t.titleSmall)),
        for (final m in solicitudes)
          ListTile(
            leading: AvatarMiembro(m),
            title: Text(m.nombre),
            subtitle: Text([etiquetaPosicion(m.posicion), if (textoEdad(m) != null) textoEdad(m)!].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: tr('Rechazar'),
                icon: const Icon(Icons.close),
                onPressed: () async {
                  await ejecutar(context, () => LigasRepo.aprobarSolicitud(m.id, false));
                  ref.invalidate(miembrosProvider(mi.liga.id));
                },
              ),
              IconButton(
                tooltip: tr('Aceptar'),
                icon: const Icon(Icons.check),
                onPressed: () async {
                  await ejecutar(context, () => LigasRepo.aprobarSolicitud(m.id, true), ok: '${m.nombre} aceptado');
                  ref.invalidate(miembrosProvider(mi.liga.id));
                },
              ),
            ]),
          ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 4, 4),
        child: Row(children: [
          Expanded(
            child: Text(
              'Jugadores (${activos.length}) · $numFijos fijos · '
              '${activos.where((m) => m.rango == RangoMiembro.reserva).length} reservas · '
              '${activos.where((m) => m.rango == RangoMiembro.invitado).length} invitados',
              style: t.titleSmall,
            ),
          ),
          const InfoBoton(Ayuda.rangos),
        ]),
      ),
      if (numFijos > plazasFijas)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text('Hay $numFijos fijos y $plazasFijas plazas'),
              subtitle: const Tx('Los que no quepan quedarán en la lista de espera de cada partido.'),
            ),
          ),
        ),
      for (final m in activos)
        ListTile(
          leading: AvatarMiembro(m),
          onTap: () => context.push('/clasificacion/jugador/${m.id}'),
          title: Row(children: [
            Flexible(child: Text(m.nombre + (m.id == mi.yo.id ? ' (tú)' : ''), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            ChipRango(m.rango),
            if (deBaja.contains(m.id)) ...[
              const SizedBox(width: 6),
              Tooltip(message: 'De baja', child: Icon(Icons.healing, size: 18, color: Colors.amber.shade700)),
            ],
          ]),
          subtitle: Text([
            if (m.esAdmin) 'Administrador',
            if (!m.registrado) 'Pendiente de registro' else etiquetaPosicion(m.posicion),
            if (textoEdad(m) != null) textoEdad(m)!,
          ].join(' · ')),
          trailing: mi.soyAdmin
              ? PopupMenuButton<String>(
                  onSelected: (a) => _accion(context, ref, m, a),
                  itemBuilder: (_) => [
                    for (final r in RangoMiembro.values)
                      CheckedPopupMenuItem(value: 'rango_${r.name}', checked: m.rango == r, child: Text(r.etiqueta)),
                    if (m.id != mi.yo.id) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'baja', child: Tx('Baja larga (lesión…)')),
                      if (!m.registrado) const PopupMenuItem(value: 'invitar', child: Tx('Reenviar enlace')),
                      if (m.registrado && !m.esAdmin) const PopupMenuItem(value: 'admin', child: Tx('Nombrar administrador')),
                      if (m.esAdmin) const PopupMenuItem(value: 'quitar_admin', child: Tx('Quitar administrador')),
                      const PopupMenuItem(value: 'expulsar', child: Tx('Expulsar')),
                    ],
                  ],
                )
              : null,
        ),
      if (mi.soyAdmin && expulsados.isNotEmpty)
        ExpansionTile(
          title: Text('Expulsados (${expulsados.length})'),
          children: [for (final m in expulsados) ListTile(dense: true, title: Text(m.nombre))],
        ),
    ]);
  }
}



/// Clasificación y Caja (antes pestañas propias): dos accesos grandes arriba de Liga.
/// Caja solo aparece si la liga mueve dinero (precio, saldo o admin).
class _Accesos extends ConsumerWidget {
  const _Accesos({required this.mi});
  final MiLiga mi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldos = ref.watch(saldosProvider(mi.liga.id)).valueOrNull ?? const [];
    final miSaldo = saldos.where((s) => s.miembroId == mi.yo.id).firstOrNull?.saldo ?? 0;
    final usaCaja = mi.soyAdmin || mi.liga.precioEstimado != null || miSaldo.abs() > 0.005;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget acceso(IconData icono, String titulo, String sub, String ruta, {Color? color}) => Expanded(
          child: Card(
            margin: const EdgeInsets.all(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.go(ruta),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icono, color: color ?? cs.primary),
                  const SizedBox(height: 8),
                  Text(tr(titulo), style: t.titleMedium),
                  Text(sub, style: t.bodySmall?.copyWith(color: color ?? cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        acceso(Icons.leaderboard_outlined, 'Clasificación', tr('Puntos, goles y récords'), '/clasificacion'),
        if (usaCaja)
          acceso(
            Icons.account_balance_wallet_outlined,
            'Caja',
            miSaldo < -0.005 ? trf('Debes {x}', {'x': euros(-miSaldo)}) : tr('Al día'),
            '/caja',
            color: miSaldo < -0.005 ? cs.error : null,
          ),
      ]),
    );
  }
}


/// Solo admin: atajos a la gestión, con texto (no un icono suelto en la barra).
class _PanelAdmin extends StatelessWidget {
  const _PanelAdmin();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget boton(IconData i, String texto, String ruta) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push(ruta),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: [
                Icon(i, color: cs.onSecondaryContainer),
                const SizedBox(height: 4),
                Text(tr(texto),
                    textAlign: TextAlign.center,
                    style: t.labelMedium?.copyWith(color: cs.onSecondaryContainer, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(children: [
              Icon(Icons.admin_panel_settings_outlined, size: 18, color: cs.onSecondaryContainer),
              const SizedBox(width: 6),
              Tx('Gestionar la liga', style: t.titleSmall?.copyWith(color: cs.onSecondaryContainer)),
            ]),
          ),
          Row(children: [
            boton(Icons.tune, 'Ajustes', '/liga/ajustes'),
            boton(Icons.event_repeat, 'Temporada', '/temporada'),
            boton(Icons.how_to_reg_outlined, 'Convocatoria y cobro', '/liga/convocatoria'),
          ]),
        ]),
      ),
    );
  }
}
