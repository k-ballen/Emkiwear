import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/services/voice_assistant_service.dart';

AppVoiceAction q(String p) => VoiceAssistantService.detectDayQuery(p);

void main() {
  group('consulta de temblor de hoy', () {
    for (final p in [
      '¿Cómo ha estado mi temblor hoy?',
      'cómo va mi temblor',
      'Emki, ¿cómo estuvo mi temblor hoy?',
      'dime un resumen de mi temblor de hoy',
      '¿cuánto he temblado hoy?',
    ]) {
      test(p, () => expect(q(p), AppVoiceAction.queryTremorToday));
    }
  });

  group('consulta de medicamentos de hoy', () {
    for (final p in [
      '¿Qué medicamentos tengo hoy?',
      'qué pastillas me tocan hoy',
      '¿cuáles medicamentos me faltan?',
      'dime qué remedios tengo pendientes',
    ]) {
      test(p, () => expect(q(p), AppVoiceAction.queryMedicationToday));
    }
  });

  group('NO son consultas', () {
    for (final p in [
      'siento que tengo mucho temblor hoy',
      'me tomé la levodopa hoy',
      'abre medicamentos',
      'registra un medicamento',
      'muéstrame la gráfica', // navegación, no consulta del día
    ]) {
      test(p, () => expect(q(p), AppVoiceAction.none));
    }
  });

  test('la consulta interrumpe un registro como comando',
      () => expect(VoiceAssistantService.isNavigationCommand('¿qué medicamentos tengo hoy?'), isTrue));
}
