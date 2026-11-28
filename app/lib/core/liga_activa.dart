import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Se sobrescribe en main() con la instancia real.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

const _clave = 'liga_activa_id';

/// Id de la liga elegida en el selector, persistido entre sesiones.
class LigaActivaNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(prefsProvider).getString(_clave);

  Future<void> elegir(String? ligaId) async {
    state = ligaId;
    final prefs = ref.read(prefsProvider);
    if (ligaId == null) {
      await prefs.remove(_clave);
    } else {
      await prefs.setString(_clave, ligaId);
    }
  }
}

final ligaActivaIdProvider = NotifierProvider<LigaActivaNotifier, String?>(LigaActivaNotifier.new);

/// Token o código recibido por enlace antes de que el usuario haya iniciado sesión.
/// 0062: se guarda en el móvil para que sobreviva al registro, al login con Google o a que Android cierre la app;
/// se usa en cuanto hay sesión y perfil (HomeShell) y caduca a los 7 días.
class InvitacionPendienteNotifier extends Notifier<String?> {
  static const _k = 'invitacion_pendiente', _kEn = 'invitacion_pendiente_en';

  @override
  String? build() {
    final p = ref.watch(prefsProvider);
    final en = p.getInt(_kEn) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - en > const Duration(days: 7).inMilliseconds) return null;
    return p.getString(_k);
  }

  @override
  set state(String? v) {
    super.state = v;
    final p = ref.read(prefsProvider);
    if (v == null) {
      p.remove(_k);
      p.remove(_kEn);
    } else {
      p.setString(_k, v);
      p.setInt(_kEn, DateTime.now().millisecondsSinceEpoch);
    }
  }
}

final invitacionPendienteProvider = NotifierProvider<InvitacionPendienteNotifier, String?>(InvitacionPendienteNotifier.new);
