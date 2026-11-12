import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/models/emergency_contact.dart';
import 'package:mi_primer_app/services/voice_assistant_service.dart';

void main() {
  const maria = EmergencyContact(name: 'María Gómez', phone: '3001234567', relation: 'hija');
  const juan = EmergencyContact(name: 'Juan', phone: '3109876543', relation: 'esposo');
  const contacts = [maria, juan];

  group('se siente mal', () {
    for (final p in [
      'me siento mal', 'Me siento muy mal', 'me caí', 'me caí y no me puedo levantar',
      'me duele el pecho', 'no puedo respirar', '¡ayuda!', 'auxilio', 'estoy mareada',
    ]) {
      test(p, () => expect(VoiceAssistantService.isDistress(p), isTrue));
    }
  });

  group('NO es emergencia', () {
    for (final p in [
      'ayúdame a registrar mi comida', 'me siento bien hoy', '¿cómo está mi temblor hoy?',
      'quiero poner un recordatorio',
    ]) {
      test(p, () => expect(VoiceAssistantService.isDistress(p), isFalse));
    }
  });

  group('a quién llamar', () {
    EmergencyContact? who(String p) =>
        VoiceAssistantService.matchContact(VoiceAssistantService.callTargetPhrase(p)!, contacts);

    test('"llama a mi hija" -> María', () => expect(who('llama a mi hija')?.phone, maria.phone));
    test('"llama a Juan" -> Juan', () => expect(who('Llama a Juan')?.phone, juan.phone));
    test('"llámale a mi esposo" -> Juan', () => expect(who('llámale a mi esposo')?.phone, juan.phone));
    test('"llama a mi contacto de emergencia" -> el primero',
        () => expect(who('llama a mi contacto de emergencia')?.phone, maria.phone));
    test('"llama a una ambulancia" -> 123', () => expect(who('llama a una ambulancia')?.phone, '123'));
    test('nombre desconocido -> null', () => expect(who('llama a Pedro'), isNull));
    test('no es pedido de llamada',
        () => expect(VoiceAssistantService.callTargetPhrase('me tomé la levodopa'), isNull));
  });
}
