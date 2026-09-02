import 'package:cloud_firestore/cloud_firestore.dart';

class MedicationTask {
  final String id;
  final String name;
  final DateTime scheduledDateTime;
  final bool isTaken;
  final DateTime? takenDateTime;
  final String userId;

  MedicationTask({
    required this.id,
    required this.name,
    required this.scheduledDateTime,
    this.isTaken = false,
    this.takenDateTime,
    required this.userId,
  });

  factory MedicationTask.fromFirestore(String id, Map<String, dynamic> data) {
    return MedicationTask(
      id: id,
      name: data['name'] ?? '',
      scheduledDateTime: (data['scheduledDateTime'] as Timestamp).toDate(),
      isTaken: data['isTaken'] ?? false,
      takenDateTime: data['takenDateTime'] != null
          ? (data['takenDateTime'] as Timestamp).toDate()
          : null,
      userId: data['userId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'scheduledDateTime': Timestamp.fromDate(scheduledDateTime),
      'isTaken': isTaken,
      'takenDateTime': takenDateTime != null ? Timestamp.fromDate(takenDateTime!) : null,
      'userId': userId,
    };
  }
}
