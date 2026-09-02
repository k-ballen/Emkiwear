import 'package:cloud_firestore/cloud_firestore.dart';

class TremorData {
  final double intensity;
  final DateTime timestamp;

  TremorData({required this.intensity, required this.timestamp});

  factory TremorData.fromFirestore(Map<String, dynamic> data) {
    return TremorData(
      intensity: (data['intensity'] ?? 0.0).toDouble(),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'intensity': intensity,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
