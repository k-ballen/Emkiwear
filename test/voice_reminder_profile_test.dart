import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/services/voice_assistant_service.dart';

void main() {
  final now = DateTime(2026, 11, 12, 16, 0); // jueves
  final draft = (String p) => VoiceAssistantService.extractReminderDraft(p, now);

  group('borrador de recordatorio (frases reales)', () {
    test('"Quiero poner un recordatorio para tomar la amoxicilina A las 6 de la mañana"', () {
      final d = draft('Quiero poner un recordatorio para tomar la amoxicilina A las 6 de la mañana');
      expect(d.name, 'Amoxicilina');
      expect(d.times, [const TimeOfDay(hour: 6, minute: 0)]);
      expect(d.weekdays, isEmpty); // todos los días
      expect(d.endDate, isNull);
    });
    test('dos horas, días y duración', () {
      final d = draft('recuérdame la levodopa a las 8 y a las 8 de la noche los lunes y jueves durante 2 semanas');
      expect(d.name, 'Levodopa');
      expect(d.times, [const TimeOfDay(hour: 8, minute: 0), const TimeOfDay(hour: 20, minute: 0)]);
      expect(d.weekdays, [1, 4]);
      expect(d.endDate, DateTime(2026, 11, 25));
    });
    test('cada 8 horas desde las 6', () {
      final d = draft('recordatorio de amoxicilina cada 8 horas desde las 6 a las 6 am durante 7 días');
      expect(d.times.map((t) => t.hour).toList(), [6, 14, 22]);
      expect(d.endDate, DateTime(2026, 11, 18));
    });
    test('entre semana', () => expect(draft('alarma de losartán a las 7 entre semana').weekdays, [1, 2, 3, 4, 5]));
    test('"ahorita a las 4:55" dicho a las 4 p. m. -> 16:55 (frase real)', () {
      final d = draft('Quiero poner un recordatorio de que me tengo que tomar un dolex ahorita a las 4:55');
      expect(d.name, 'Dolex');
      expect(d.times, [const TimeOfDay(hour: 16, minute: 55)]);
    });
    test('sin "ahorita", "a las 6" sigue siendo de la mañana',
        () => expect(draft('recordatorio de amoxicilina a las 6').times, [const TimeOfDay(hour: 6, minute: 0)]));
    test('sin datos: editor vacío', () {
      final d = draft('programa una alarma para mis pastillas');
      expect(d.name, '');
      expect(d.times, isEmpty);
      expect(VoiceAssistantService.reminderReply(d), contains('Completa el medicamento y las horas'));
    });
    test('respuesta hablada con todo', () {
      final d = draft('recuérdame la levodopa a las 8 todos los días');
      expect(VoiceAssistantService.reminderReply(d),
          'Te abro el recordatorio de Levodopa, a las 8:00 a. m.. Revisa los datos y toca Guardar.'
              .replaceAll('a. m..', 'a. m.'));
    });
  });

  group('perfil por voz: extractor local', () {
    Map<String, Object> ex(String p) => VoiceAssistantService.extractProfileUpdates(p);

    test('doctor neurólogo y hospital', () {
      final u = ex('Mi neurólogo se llama Juan Pérez y me atienden en el Hospital San Ignacio');
      expect(u['specialistName'], 'Juan Pérez');
      expect(u['specialistType'], 'Neurología');
      expect(u['hospital'], 'Hospital San Ignacio');
    });
    test('doctora con título', () => expect(ex('mi doctora es la doctora Ana Ruiz')['specialistName'], 'Ana Ruiz'));
    test('celular', () => expect(ex('mi celular es 300 123 4567')['cellPhone'], '3001234567'));
    test('año de diagnóstico', () => expect(ex('me diagnosticaron en 2019')['diagnosisYear'], 2019));
    test('horario de consulta',
        () => expect(ex('mi consulta es los martes a las 3 de la tarde')['consultationTime'], 'Los martes a las 3 de la tarde'));
    test('nombre y apellidos', () {
      final u = ex('me llamo Ana María Gómez');
      expect(u['name'], 'Ana');
      expect(u['lastName'], 'María Gómez');
    });
    test('"mi doctor me dijo que tomara levodopa" NO cambia el doctor',
        () => expect(ex('mi doctor me dijo que tomara levodopa'), isEmpty));
    test('año futuro se descarta', () => expect(ex('me diagnosticaron en 2099'), isEmpty));
  });

  group('escucha continua: tramos dentro de la misma sesión', () {
    bool isNew(String a, String b) => VoiceAssistantService.isNewSegment(a, b);
    test('parcial que reinicia con otra frase = tramo nuevo',
        () => expect(isNew('Hoy desayuné huevos con arepa', 'a las 8 de la mañana'), isTrue));
    test('continuación normal', () => expect(isNew('Hoy desayuné', 'Hoy desayuné huevos'), isFalse));
    test('revisión del reconocedor', () => expect(isNew('Oy desayune huevos', 'Hoy desayuné huevos'), isFalse));
    test('misma primera palabra corregida', () => expect(isNew('me tomé la levo', 'me tomé la levodopa'), isFalse));
  });

  group('perfil por voz: etiqueta de Gemini', () {
    test('varios campos y normalización', () {
      final u = VoiceAssistantService.parseProfileTag(
          'doctor=juan pérez|especialidad=neurólogo|hospital=hospital san ignacio|celular=+57 300 123 4567|anio_diagnostico=2019');
      expect(u['specialistName'], 'Juan Pérez');
      expect(u['specialistType'], 'Neurología');
      expect(u['hospital'], 'Hospital San Ignacio');
      expect(u['cellPhone'], '+573001234567');
      expect(u['diagnosisYear'], 2019);
    });
    test('clave desconocida y valores vacíos se ignoran',
        () => expect(VoiceAssistantService.parseProfileTag('mascota=Firulais|doctor='), isEmpty));
  });
}
