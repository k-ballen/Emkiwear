import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityHabit {
  final String id;
  final String activityType; // Caminar, Estiramiento, etc.
  final int duration; // en minutos
  final String intensity; // Leve, Media, Alta
  final DateTime timestamp;
  final String userId;

  ActivityHabit({
    required this.id,
    required this.activityType,
    required this.duration,
    required this.intensity,
    required this.timestamp,
    required this.userId,
  });

  factory ActivityHabit.fromFirestore(String id, Map<String, dynamic> data) {
    return ActivityHabit(
      id: id,
      activityType: data['activityType'] ?? '',
      duration: data['duration'] ?? 0,
      intensity: data['intensity'] ?? 'Media',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      userId: data['userId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'activityType': activityType,
      'duration': duration,
      'intensity': intensity,
      'timestamp': Timestamp.fromDate(timestamp),
      'userId': userId,
    };
  }
}
