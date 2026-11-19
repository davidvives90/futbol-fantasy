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
final invitacionPendienteProvider = StateProvider<String?>((ref) => null);
