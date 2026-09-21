import 'package:cloud_firestore/cloud_firestore.dart';

class TremorData {
  final double intensity;
  final double? domFreq;
  final bool? tremorPresent;
  final String? severity;
  final String? classification;
  final DateTime timestamp;

  TremorData({
    required this.intensity,
    this.domFreq,
    this.tremorPresent,
    this.severity,
    this.classification,
    required this.timestamp,
  });

  factory TremorData.fromFirestore(Map<String, dynamic> data) {
    return TremorData(
      intensity: (data['intensity'] ?? 0.0).toDouble(),
      domFreq: (data['domFreq'] ?? 0.0).toDouble(),
      tremorPresent: data['tremorPresent'] ?? false,
      severity: data['severity'],
      classification: data['classification'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'intensity': intensity,
      'domFreq': domFreq,
      'tremorPresent': tremorPresent,
      'severity': severity,
      'classification': classification,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
