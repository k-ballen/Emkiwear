import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/services/voice_assistant_service.dart';

void main() {
  // Referencia fija: 10 de noviembre de 2026, 23:05 (como en la prueba que falló).
  final now = DateTime(2026, 11, 10, 23, 5);
  DateTime? t(String p) => VoiceAssistantService.extractEventDateTime(p, now);

  group('sin hora concreta -> null (preguntar)', () {
    test('camine 30 minutos en la mañana', () => expect(t('camine 30 minutos en la mañana'), isNull));
    test('Caminé treinta minutos a intensidad media',
        () => expect(t('Caminé treinta minutos a intensidad media'), isNull));
    test('hoy hice ejercicio quiero registrarlo',
        () => expect(t('hoy hice ejercicio quiero registrarlo'), isNull));
    test('me tomé la levodopa', () => expect(t('me tomé la levodopa'), isNull));
    test('ensalada de tomate (sin hora)', () => expect(t('comí ensalada de tomate'), isNull));
  });

  group('horas concretas', () {
    test('a las 9 de la mañana', () => expect(t('Desayuné huevos con arepa a las 9 de la mañana'), DateTime(2026, 11, 10, 9, 0)));
    test('a las 12', () => expect(t('comí ensalada de tomate a las 12'), DateTime(2026, 11, 10, 12, 0)));
    test('a las 8 de la (frase cortada) -> 20:00, la más reciente no futura',
        () => expect(t('poner que me tomé la levodopa a las 8 de la'), DateTime(2026, 11, 10, 20, 0)));
    test('a las ocho y media de la noche', () => expect(t('a las ocho y media de la noche'), DateTime(2026, 11, 10, 20, 30)));
    test('8:15 pm', () => expect(t('a las 8:15 pm'), DateTime(2026, 11, 10, 20, 15)));
    test('a las 7 menos cuarto de la mañana', () => expect(t('a las 7 menos cuarto de la mañana'), DateTime(2026, 11, 10, 6, 45)));
    test('mediodía', () => expect(t('almorcé al mediodía'), DateTime(2026, 11, 10, 12, 0)));
    test('respuesta corta "8"', () => expect(t('8'), DateTime(2026, 11, 10, 20, 0)));
    test('respuesta corta "las 7 y media"', () => expect(t('las 7 y media'), DateTime(2026, 11, 10, 19, 30)));
    test('30 minutos a las 6 de la tarde', () => expect(t('caminé 30 minutos a las 6 de la tarde'), DateTime(2026, 11, 10, 18, 0)));
  });

  group('relativas', () {
    test('hace media hora', () => expect(t('Desayuné huevos con arepa hace media hora'), DateTime(2026, 11, 10, 22, 35)));
    test('hace un rato = 20 min', () => expect(t('me la tomé hace un rato'), DateTime(2026, 11, 10, 22, 45)));
    test('hace 2 horas', () => expect(t('cené hace 2 horas'), DateTime(2026, 11, 10, 21, 5)));
    test('hace una hora y media', () => expect(t('hace una hora y media'), DateTime(2026, 11, 10, 21, 35)));
    test('ahorita', () => expect(t('ahorita me la tomé'), now));
  });

  test('a la 1 dicho a las 00:30 -> ayer 13:00 (no futura)', () {
    final early = DateTime(2026, 11, 11, 0, 30);
    expect(VoiceAssistantService.extractEventDateTime('almorcé a la una', early), DateTime(2026, 11, 10, 13, 0));
  });

  test('actividad normalizada', () {
    expect(VoiceAssistantService.normalizeActivityName('Camine 30 minutos en la mañana'), 'Caminata');
    expect(VoiceAssistantService.normalizeActivityName('troté'), 'Trote');
  });
}
