import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/models/medication_reminder.dart';
import 'package:mi_primer_app/services/reminder_service.dart';

MedicationReminder rem({
  List<TimeOfDay> times = const [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)],
  List<int> weekdays = const [],
  DateTime? start,
  DateTime? end,
  bool active = true,
}) =>
    MedicationReminder(
      id: 'abc',
      name: 'Levodopa',
      times: times,
      weekdays: weekdays,
      startDate: start ?? DateTime(2026, 11, 10),
      endDate: end,
      active: active,
    );

void main() {
  // 12 nov 2026 es jueves (weekday 4).
  final thursday = DateTime(2026, 11, 12, 9, 30);

  test('todos los días: 2 tomas diarias durante 3 días = 6', () {
    expect(rem().dosesBetween(thursday, 3).length, 6);
  });

  test('días específicos: solo lunes y jueves', () {
    final r = rem(weekdays: [1, 4]);
    final doses = r.dosesBetween(thursday, 7);
    expect(doses.map((d) => d.weekday).toSet(), {1, 4});
    expect(doses.length, 4); // jueves y lunes, 2 tomas cada uno
  });

  test('fecha de fin inclusiva: termina el sábado', () {
    final r = rem(end: DateTime(2026, 11, 14));
    final doses = r.dosesBetween(thursday, 7);
    expect(doses.last, DateTime(2026, 11, 14, 20, 0));
    expect(doses.length, 6); // jue, vie, sáb
  });

  test('antes de la fecha de inicio no hay tomas', () {
    final r = rem(start: DateTime(2026, 11, 20));
    expect(r.occursOn(thursday), isFalse);
    expect(r.occursOn(DateTime(2026, 11, 20)), isTrue);
  });

  test('desactivado no tiene tomas', () {
    expect(rem(active: false).dosesBetween(thursday, 7), isEmpty);
  });

  test('id de la toma es determinístico', () {
    expect(rem().doseTaskId(DateTime(2026, 11, 12, 8, 0)), 'rem_abc_20261112_0800');
  });

  test('etiqueta de días', () {
    expect(rem().weekdaysLabel, 'Todos los días');
    expect(rem(weekdays: [5, 1, 3]).weekdaysLabel, 'L, X, V');
  });

  test('ids de notificación: estables, positivos y distintos para cada reaviso', () {
    const id = 'rem_abc_20261112_0800';
    expect(notificationIdFor(id), notificationIdFor(id));
    expect(notificationIdFor(id), isNonNegative);
    final ids = {for (var k = 0; k <= 3; k++) notificationIdFor(id, followUp: k)};
    expect(ids.length, 4); // aviso + 3 reavisos, todos distintos
    expect(notificationIdFor(id), isNot(notificationIdFor('rem_abc_20261112_2000')));
  });
}
