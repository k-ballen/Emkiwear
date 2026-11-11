import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/services/voice_assistant_service.dart';

/// Frases reales de las pruebas con voluntarios (hoja Asistente_Voz).
/// Hora de referencia fija: 10 nov 2026, 10:00 a. m.
void main() {
  final now = DateTime(2026, 11, 10, 10, 0);
  DateTime? time(String p) => VoiceAssistantService.extractEventDateTime(p, now);
  String? item(String p, String c) => VoiceAssistantService.extractItemName(p, c);
  int? duration(String p) => VoiceAssistantService.extractDurationMinutes(p);
  String? mealKw(String p) => VoiceAssistantService.mealTypeKeyword(p);
  String intensity(String p) => VoiceAssistantService.extractIntensity(p);

  group('"Desayuné huevos con arepa hace media hora"', () {
    const p = 'Desayuné huevos con arepa hace media hora';
    test('hora = ahora - 30 min', () => expect(time(p), DateTime(2026, 11, 10, 9, 30)));
    test('nombre sin verbo ni tiempo', () => expect(item(p, 'food'), 'Huevos con arepa'));
    test('tipo Desayuno (bug: quedaba Almuerzo)', () => expect(mealKw(p), 'Desayuno'));
    test('"media hora" relativa NO es duración', () => expect(duration(p), isNull));
  });

  group('"Desayuné huevos con arepa a las 9 de la mañana"', () {
    const p = 'Desayuné huevos con arepa a las 9 de la mañana';
    test('hora 9:00', () => expect(time(p), DateTime(2026, 11, 10, 9, 0)));
    test('nombre', () => expect(item(p, 'food'), 'Huevos con arepa'));
    test('tipo Desayuno', () => expect(mealKw(p), 'Desayuno'));
  });

  group('"poner que me tomé la levodopa a las 8 de la"', () {
    const p = 'poner que me tomé la levodopa a las 8 de la';
    test('nombre Levodopa (bug: quedaba la frase entera)', () => expect(item(p, 'medication'), 'Levodopa'));
    test('hora 8:00 (la más reciente no futura a las 10:00)',
        () => expect(time(p), DateTime(2026, 11, 10, 8, 0)));
  });

  group('"Caminé treinta minutos a intensidad media"', () {
    const p = 'Caminé treinta minutos a intensidad media';
    test('actividad Caminata', () => expect(item(p, 'activity'), 'Caminata'));
    test('duración 30 en palabras', () => expect(duration(p), 30));
    test('intensidad Media', () => expect(intensity(p), 'Media'));
    test('sin hora -> preguntar', () => expect(time(p), isNull));
  });

  group('"camine 30 minutos en la mañana"', () {
    const p = 'camine 30 minutos en la mañana';
    test('actividad Caminata', () => expect(item(p, 'activity'), 'Caminata'));
    test('duración 30', () => expect(duration(p), 30));
    test('"en la mañana" sin hora -> null (bug: 30 -> 23:00)', () => expect(time(p), isNull));
  });

  group('"comí ensalada de tomate a las 12"', () {
    const p = 'comí ensalada de tomate a las 12';
    test('nombre', () => expect(item(p, 'food'), 'Ensalada de tomate'));
    test('hora 12:00 -> ayer (hoy aún no son las 12)', () => expect(time(p), DateTime(2026, 11, 9, 12, 0)));
    test('sin palabra de comida -> se deduce por la hora',
        () => expect(VoiceAssistantService.normalizeMealType(p, at: DateTime(2026, 11, 9, 12, 0)), 'Almuerzo'));
  });

  group('"hoy hice ejercicio quiero registrarlo"', () {
    const p = 'hoy hice ejercicio quiero registrarlo';
    test('nombre genérico -> null (preguntar qué actividad)', () => expect(item(p, 'activity'), isNull));
    test('sin hora', () => expect(time(p), isNull));
    test('sin duración', () => expect(duration(p), isNull));
  });

  group('duración', () {
    test('media hora', () => expect(duration('caminé media hora'), 30));
    test('una hora', () => expect(duration('hice yoga una hora'), 60));
    test('hora y media', () => expect(duration('troté hora y media'), 90));
    test('una hora y media', () => expect(duration('nadé una hora y media'), 90));
    test('2 horas', () => expect(duration('bicicleta 2 horas'), 120));
    test('"hace 20 minutos" no es duración', () => expect(duration('caminé hace 20 minutos'), isNull));
  });

  group('tipo de comida', () {
    test('almorcé', () => expect(mealKw('almorcé arroz'), 'Almuerzo'));
    test('cené', () => expect(mealKw('cené sopa'), 'Cena'));
    test('onces', () => expect(mealKw('tomé onces'), 'Merienda'));
    test('"fui al centro" no es cena', () => expect(mealKw('comí algo en el centro'), isNull));
    test('por hora: 8 -> Desayuno, 13 -> Almuerzo, 20 -> Cena', () {
      expect(VoiceAssistantService.mealTypeForHour(DateTime(2026, 1, 1, 8)), 'Desayuno');
      expect(VoiceAssistantService.mealTypeForHour(DateTime(2026, 1, 1, 13)), 'Almuerzo');
      expect(VoiceAssistantService.mealTypeForHour(DateTime(2026, 1, 1, 20)), 'Cena');
    });
  });

  group('intensidad y nombres', () {
    test('alta', () => expect(intensity('troté a intensidad alta'), 'Alta'));
    test('suave -> Leve', () => expect(intensity('caminé suave'), 'Leve'));
    test('por defecto Media', () => expect(intensity('caminé'), 'Media'));
    test('respuesta corta al pedir el nombre',
        () => expect(VoiceAssistantService.extractItemName('la levodopa', 'medication', wholeIfNoMarker: true), 'Levodopa'));
    test('"me tomé el medicamento" -> null (preguntar cuál)',
        () => expect(item('me tomé el medicamento', 'medication'), isNull));
    test('pastilla de losartán', () => expect(item('me tomé la pastilla de losartán ahorita', 'medication'), 'Losartán'));
  });
}
