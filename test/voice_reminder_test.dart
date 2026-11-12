import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/services/voice_assistant_service.dart';

AppVoiceAction detect(String p) => VoiceAssistantService.detectActionForTest(p);
String? med(String p) => VoiceAssistantService.extractReminderMedication(p);

void main() {
  group('pedido de recordatorio (frases reales de la prueba)', () {
    test('"Quiero poner un recordatorio de que me tengo que tomar la amoxicilina"', () {
      const p = 'Quiero poner un recordatorio de que me tengo que tomar la amoxicilina';
      expect(detect(p), AppVoiceAction.openReminders);
      expect(med(p), 'Amoxicilina');
    });
    test('frase cortada: "...me tengo que tomar la"', () {
      const p = 'Quiero poner un recordatorio de que me tengo que tomar la';
      expect(detect(p), AppVoiceAction.openReminders);
      expect(med(p), isNull); // se abre el editor sin nombre
    });
  });

  group('otras formas', () {
    test('recuérdame tomar la levodopa a las 8', () {
      expect(detect('recuérdame tomar la levodopa a las 8'), AppVoiceAction.openReminders);
      expect(med('recuérdame tomar la levodopa a las 8'), 'Levodopa');
    });
    test('recordatorio de losartán', () => expect(med('ponme un recordatorio de losartán'), 'Losartán'));
    test('prográmame una alarma para mis pastillas',
        () => expect(detect('prográmame una alarma para mis pastillas'), AppVoiceAction.openReminders));
    test('una toma ya hecha NO es recordatorio',
        () => expect(detect('me tomé la levodopa a las 8'), AppVoiceAction.openMedication));
    test('es comando que interrumpe un registro',
        () => expect(VoiceAssistantService.isNavigationCommand('recuérdame la levodopa'), isTrue));
  });
}
