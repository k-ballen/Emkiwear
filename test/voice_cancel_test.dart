import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/services/voice_assistant_service.dart';

bool cancel(String p) => VoiceAssistantService.isCancel(p);
bool nav(String p) => VoiceAssistantService.isNavigationCommand(p);

void main() {
  group('isCancel: sí cancela', () {
    for (final p in [
      'Cancela', 'cancelar', 'Cancélalo', 'olvídalo', 'Déjalo', 'ya no',
      'mejor no', 'no gracias', 'detente', 'No', 'no, cancela eso',
      'olvídalo, ya no quiero', 'no lo registres',
    ]) {
      test(p, () => expect(cancel(p), isTrue));
    }
  });

  group('isCancel: NO cancela', () {
    for (final p in [
      'Levodopa', 'no me he tomado la levodopa', 'ya no me tiembla tanto la mano hoy',
      'a las 8', 'nadé media hora', 'hoy no desayuné nada en la mañana temprano',
    ]) {
      test(p, () => expect(cancel(p), isFalse));
    }
  });

  group('isNavigationCommand', () {
    test('vuelve al inicio', () => expect(nav('vuelve al inicio'), isTrue));
    test('abre comunidad', () => expect(nav('abre comunidad'), isTrue));
    test('muéstrame mi temblor', () => expect(nav('muéstrame mi temblor'), isTrue));
    test('abre medicamentos', () => expect(nav('abre medicamentos'), isTrue));
    test('"Levodopa" NO es navegación', () => expect(nav('Levodopa'), isFalse));
    test('"a las 8" NO es navegación', () => expect(nav('a las 8'), isFalse));
    test('"huevos con arepa" NO es navegación', () => expect(nav('huevos con arepa'), isFalse));
  });
}
