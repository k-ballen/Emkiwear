class Medication {
  final String id;
  final String name;
  final String dosage;
  final List<String> schedule; // e.g., ["08:00", "20:00"]
  final List<MedicationLog> logs;

  Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.schedule,
    this.logs = const [],
  });

  factory Medication.fromFirestore(String id, Map<String, dynamic> data) {
    return Medication(
      id: id,
      name: data['name'] ?? '',
      dosage: data['dosage'] ?? '',
      schedule: List<String>.from(data['schedule'] ?? []),
      logs: (data['logs'] as List? ?? [])
          .map((log) => MedicationLog.fromMap(log))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'dosage': dosage,
      'schedule': schedule,
      'logs': logs.map((log) => log.toMap()).toList(),
    };
  }
}

class MedicationLog {
  final DateTime timestamp;
  final String perception; // "¿mejoró?", "¿empeoró?"

  MedicationLog({required this.timestamp, required this.perception});

  factory MedicationLog.fromMap(Map<String, dynamic> map) {
    return MedicationLog(
      timestamp: DateTime.parse(map['timestamp']),
      perception: map['perception'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'perception': perception,
    };
  }
}
