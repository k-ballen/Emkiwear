import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/services/voice_assistant_service.dart';

AppVoiceAction detect(String p) => VoiceAssistantService.detectActionForTest(p);
String? companion(String p) => VoiceAssistantService.extractCompanionNameForTest(p);

void main() {
  group('normalizeText / hasWord', () {
    test('quita tildes y puntuación, conserva ñ', () {
      expect(VoiceAssistantService.normalizeText('¡Caminé 30 minutos en la Mañana!'),
          'camine 30 minutos en la mañana');
    });
    test('ana no coincide dentro de mañana', () {
      expect(VoiceAssistantService.hasWord('camine en la mañana', 'ana'), isFalse);
    });
    test('tome no coincide dentro de tomate; cen no dentro de centro', () {
      expect(VoiceAssistantService.hasWord('ensalada de tomate', 'tome'), isFalse);
      expect(VoiceAssistantService.hasWord('fui al centro', 'cen'), isFalse);
      expect(VoiceAssistantService.hasWord('me tome la levodopa', 'me tome'), isTrue);
    });
  });

  group('acción Inicio', () {
    test('vuelve al inicio', () => expect(detect('Vuelve al inicio'), AppVoiceAction.openHome));
    test('regresa al menú principal',
        () => expect(detect('Regresa al menú principal'), AppVoiceAction.openHome));
    test('pantalla principal', () => expect(detect('llévame a la pantalla principal'), AppVoiceAction.openHome));
    test('atrás', () => expect(detect('atrás'), AppVoiceAction.openHome));
    test('regresa a medicamentos abre medicamentos',
        () => expect(detect('regresa a medicamentos'), AppVoiceAction.openMedication));
    test('me vuelve el temblor abre temblor',
        () => expect(detect('me vuelve el temblor'), AppVoiceAction.openTremor));
  });

  group('sin falsos positivos de compañeros', () {
    test('camine 30 minutos en la mañana NO abre a Ana', () {
      expect(detect('camine 30 minutos en la mañana'), AppVoiceAction.openHabitsActivity);
      expect(companion('camine 30 minutos en la mañana'), isNull);
    });
    test('comí ensalada de tomate es comida, no medicamento',
        () => expect(detect('comí ensalada de tomate a las 12'), AppVoiceAction.openHabitsFood));
    test('fui al centro no es cena', () => expect(detect('fui al centro'), AppVoiceAction.none));
    test('nombre sin palabra de contexto no abre perfil',
        () => expect(companion('hoy hablé con daniela'), isNull));
    test('abre el perfil de Daniela', () {
      expect(detect('Abre el perfil de Daniela'), AppVoiceAction.openCompanionProfile);
      expect(companion('Abre el perfil de Daniela'), 'Daniela');
    });
    test('ver a mi compañera María (con tilde)',
        () => expect(companion('quiero ver a mi compañera María'), 'María'));
    test('abre mi perfil es el perfil propio',
        () => expect(detect('abre mi perfil'), AppVoiceAction.openProfile));
  });

  group('intención de registro', () {
    test('me tomé la levodopa', () => expect(detect('me tomé la levodopa'), AppVoiceAction.openMedication));
    test('desayuné huevos', () => expect(detect('Desayuné huevos con arepa'), AppVoiceAction.openHabitsFood));
    test('hice ejercicio', () => expect(detect('hoy hice ejercicio quiero registrarlo'), AppVoiceAction.openHabitsActivity));
  });
}
