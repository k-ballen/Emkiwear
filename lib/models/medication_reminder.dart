import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Plan de recordatorios de un medicamento (colección medication_reminders).
///
/// - [times]: horas del día de cada toma (p. ej. 08:00, 14:00, 20:00).
/// - [weekdays]: días de la semana (1 = lunes ... 7 = domingo). Vacío = todos.
/// - [endDate]: último día del tratamiento (inclusive). null = sin fin.
class MedicationReminder {
  final String id;
  final String name;
  final String? dose;
  final List<TimeOfDay> times;
  final List<int> weekdays;
  final DateTime startDate;
  final DateTime? endDate;
  final bool active;

  const MedicationReminder({
    required this.id,
    required this.name,
    this.dose,
    required this.times,
    this.weekdays = const [],
    required this.startDate,
    this.endDate,
    this.active = true,
  });

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// ¿Hay tomas este día? (activo, dentro de fechas y en un día elegido)
  bool occursOn(DateTime day) {
    if (!active) return false;
    final d = _day(day);
    if (d.isBefore(_day(startDate))) return false;
    if (endDate != null && d.isAfter(_day(endDate!))) return false;
    return weekdays.isEmpty || weekdays.contains(d.weekday);
  }

  /// Fechas y horas de las tomas entre [from] y [from] + [days] días.
  List<DateTime> dosesBetween(DateTime from, int days) {
    final result = <DateTime>[];
    final start = _day(from);
    for (var i = 0; i < days; i++) {
      final day = start.add(Duration(days: i));
      if (!occursOn(day)) continue;
      for (final t in times) {
        result.add(DateTime(day.year, day.month, day.day, t.hour, t.minute));
      }
    }
    result.sort();
    return result;
  }

  /// Id determinístico del documento de la toma en medication_tasks, para no
  /// duplicar tomas y poder marcarla desde la notificación.
  String doseTaskId(DateTime dose) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'rem_${id}_${dose.year}${two(dose.month)}${two(dose.day)}_${two(dose.hour)}${two(dose.minute)}';
  }

  static const _dayNames = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  /// "Todos los días" o "L, X, V".
  String get weekdaysLabel {
    if (weekdays.isEmpty || weekdays.length == 7) return 'Todos los días';
    final sorted = [...weekdays]..sort();
    return sorted.map((d) => _dayNames[d - 1]).join(', ');
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parseHhmm(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  Map<String, dynamic> toFirestore(String userId) => {
        'userId': userId,
        'name': name,
        'dose': dose,
        'times': times.map(_hhmm).toList(),
        'weekdays': weekdays,
        'startDate': Timestamp.fromDate(_day(startDate)),
        'endDate': endDate != null ? Timestamp.fromDate(_day(endDate!)) : null,
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory MedicationReminder.fromFirestore(String id, Map<String, dynamic> data) {
    final times = ((data['times'] as List?) ?? const [])
        .map((e) => _parseHhmm(e.toString()))
        .toList()
      ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    return MedicationReminder(
      id: id,
      name: (data['name'] ?? '').toString(),
      dose: (data['dose'] as String?)?.trim().isEmpty == true ? null : data['dose'] as String?,
      times: times,
      weekdays: ((data['weekdays'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      active: data['active'] ?? true,
    );
  }

  MedicationReminder copyWith({bool? active}) => MedicationReminder(
        id: id,
        name: name,
        dose: dose,
        times: times,
        weekdays: weekdays,
        startDate: startDate,
        endDate: endDate,
        active: active ?? this.active,
      );
}
