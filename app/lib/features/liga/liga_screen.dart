import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/liga_activa.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repos/ligas_repo.dart';
import '../shell/home_shell.dart';
import 'chip_rango.dart';

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
      appBar: LigaAppBar(actions: [
        if (mi.soyAdmin)
          IconButton(tooltip: 'Editar liga', icon: const Icon(Icons.edit_outlined), onPressed: () => context.push('/liga/editar')),
      ]),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(miembrosProvider(liga.id));
          refrescarLigas(ref);
        },
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          _Datos(mi: mi),
          _Invitar(mi: mi),
          miembros.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Cargando()),
            error: (e, _) => ErrorVista(e, onRetry: () => ref.invalidate(miembrosProvider(liga.id))),
            data: (lista) => _Miembros(mi: mi, miembros: lista),
          ),
          if (mi.soyAdmin)
            ListTile(
              leading: const Icon(Icons.event_repeat),
              title: const Text('Convocatoria y cobro'),
              subtitle: const Text('Lista de espera, factura mensual y precio de reservas'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/liga/convocatoria'),
            ),
          if (mi.soyAdmin)
            ListTile(
              leading: const Icon(Icons.rule),
              title: const Text('Reglas de puntuación y aspectos'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/liga/reglas'),
            ),
          if (mi.soyAdmin)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Ajustes Fantasy'),
              subtitle: const Text('Encuesta de valoración y parámetros del mercado'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/liga/fantasy'),
            ),
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Abandonar la liga', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
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
            if (l.fantasy.bonusRoles) const Chip(label: Text('Bonus por rol en la alineación')),
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
                    tooltip: 'Abrir en Google Maps',
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
        title: const Text('Pre-crear jugadores'),
        content: TextField(
          controller: ctrl,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(hintText: 'Un nombre por línea\nPepe\nLuis\nCarlos'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              ctrl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList(),
            ),
            child: const Text('Crear'),
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
              title: Text('Envía a cada uno su enlace'),
              subtitle: Text('Al registrarse con él heredará su ficha y su historial.'),
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
          title: const Text('Código de la liga'),
          subtitle: SelectableText(codigo, style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: 4)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Copiar',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: codigo));
                if (context.mounted) mostrarOk(context, 'Código copiado');
              },
            ),
            IconButton(
              tooltip: 'Compartir',
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
              child: const Text('Regenerar código'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _precrear(context, ref),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Pre-crear jugadores'),
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
    final t = Theme.of(context).textTheme;
    final numFijos = activos.where((m) => m.rango == RangoMiembro.fijo).length;
    final plazasFijas = mi.liga.plazasFijas ?? mi.liga.plazas;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (mi.soyAdmin && solicitudes.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 4), child: Text('Solicitudes (${solicitudes.length})', style: t.titleSmall)),
        for (final m in solicitudes)
          ListTile(
            leading: CircleAvatar(child: Text(m.inicial)),
            title: Text(m.nombre),
            subtitle: Text(etiquetaPosicion(m.posicion)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Rechazar',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  await ejecutar(context, () => LigasRepo.aprobarSolicitud(m.id, false));
                  ref.invalidate(miembrosProvider(mi.liga.id));
                },
              ),
              IconButton(
                tooltip: 'Aceptar',
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
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(
          'Jugadores (${activos.length}) · $numFijos fijos · '
          '${activos.where((m) => m.rango == RangoMiembro.reserva).length} reservas · '
          '${activos.where((m) => m.rango == RangoMiembro.invitado).length} invitados',
          style: t.titleSmall,
        ),
      ),
      if (numFijos > plazasFijas)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text('Hay $numFijos fijos y $plazasFijas plazas'),
              subtitle: const Text('Los que no quepan quedarán en la lista de espera de cada partido.'),
            ),
          ),
        ),
      for (final m in activos)
        ListTile(
          leading: CircleAvatar(child: Text(m.inicial)),
          title: Row(children: [
            Flexible(child: Text(m.nombre + (m.id == mi.yo.id ? ' (tú)' : ''), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            ChipRango(m.rango),
          ]),
          subtitle: Text([
            if (m.esAdmin) 'Administrador',
            if (!m.registrado) 'Pendiente de registro' else etiquetaPosicion(m.posicion),
          ].join(' · ')),
          trailing: mi.soyAdmin
              ? PopupMenuButton<String>(
                  onSelected: (a) => _accion(context, ref, m, a),
                  itemBuilder: (_) => [
                    for (final r in RangoMiembro.values)
                      CheckedPopupMenuItem(value: 'rango_${r.name}', checked: m.rango == r, child: Text(r.etiqueta)),
                    if (m.id != mi.yo.id) ...[
                      const PopupMenuDivider(),
                      if (!m.registrado) const PopupMenuItem(value: 'invitar', child: Text('Reenviar enlace')),
                      if (m.registrado && !m.esAdmin) const PopupMenuItem(value: 'admin', child: Text('Nombrar administrador')),
                      if (m.esAdmin) const PopupMenuItem(value: 'quitar_admin', child: Text('Quitar administrador')),
                      const PopupMenuItem(value: 'expulsar', child: Text('Expulsar')),
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

