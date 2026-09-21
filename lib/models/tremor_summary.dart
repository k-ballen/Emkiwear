import 'package:cloud_firestore/cloud_firestore.dart';

class TremorSummary {
  final String id; // userId_YYYY-MM-DD_HH
  final DateTime startTime;
  final DateTime endTime;
  final double avgIntensity;
  final double maxIntensity;
  final int totalSamples;
  final int tremorSamples;
  final double avgDomFreq;
  final Map<String, int> severityCounts;
  final String date; // YYYY-MM-DD
  final int hour;   // 0-23
  final int minute; // 0, 5, 10, ..., 55

  TremorSummary({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.avgIntensity,
    required this.maxIntensity,
    required this.totalSamples,
    required this.tremorSamples,
    required this.avgDomFreq,
    required this.severityCounts,
    required this.date,
    required this.hour,
    required this.minute,
  });

  factory TremorSummary.fromFirestore(String id, Map<String, dynamic> data) {
    return TremorSummary(
      id: id,
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      avgIntensity: (data['avgIntensity'] ?? 0.0).toDouble(),
      maxIntensity: (data['maxIntensity'] ?? 0.0).toDouble(),
      totalSamples: data['totalSamples'] ?? 0,
      tremorSamples: data['tremorSamples'] ?? 0,
      avgDomFreq: (data['avgDomFreq'] ?? 0.0).toDouble(),
      severityCounts: Map<String, int>.from(data['severityCounts'] ?? {}),
      date: data['date'] ?? '',
      hour: data['hour'] ?? 0,
      minute: data['minute'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'avgIntensity': avgIntensity,
      'maxIntensity': maxIntensity,
      'totalSamples': totalSamples,
      'tremorSamples': tremorSamples,
      'avgDomFreq': avgDomFreq,
      'severityCounts': severityCounts,
      'date': date,
      'hour': hour,
      'minute': minute,
      'lastSync': FieldValue.serverTimestamp(),
    };
  }
}
