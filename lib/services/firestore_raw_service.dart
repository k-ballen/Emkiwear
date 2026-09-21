import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/raw_imu_sample.dart';
import 'firebase_service.dart';

class FirestoreRawService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseService _firebaseService = FirebaseService();
  
  // Buffers de arrays paralelos para optimizar Firestore
  final List<double> _ax = [];
  final List<double> _ay = [];
  final List<double> _az = [];
  final List<double> _gx = [];
  final List<double> _gy = [];
  final List<double> _gz = [];
  final List<int> _tMsOffsets = [];
  
  String? _sessionId;
  int? _lastDeviceT0;
  DateTime? _startMinute;
  bool uploadEnabled = true;

  FirestoreRawService() {
    _sessionId = "${DateTime.now().millisecondsSinceEpoch}";
  }

  void addSample(RawImuSample sample) {
    if (!uploadEnabled) return;

    final now = DateTime.now();
    
    // Si cambiamos de minuto, subimos el bloque anterior
    if (_startMinute != null && _startMinute!.minute != now.minute) {
      _flushBuffer();
    }

    if (_startMinute == null) {
      _startMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      _lastDeviceT0 = sample.tMs;
    }

    _ax.add(double.parse(sample.ax.toStringAsFixed(3)));
    _ay.add(double.parse(sample.ay.toStringAsFixed(3)));
    _az.add(double.parse(sample.az.toStringAsFixed(3)));
    _gx.add(double.parse(sample.gx.toStringAsFixed(2)));
    _gy.add(double.parse(sample.gy.toStringAsFixed(2)));
    _gz.add(double.parse(sample.gz.toStringAsFixed(2)));
    _tMsOffsets.add(sample.tMs - _lastDeviceT0!);
  }

  String _getSummaryId(DateTime dt) {
    final userId = _firebaseService.currentUserId ?? "anon";
    final dateStr = DateFormat('yyyy-MM-dd').format(dt);
    final minute = (dt.minute ~/ 5) * 5; // El bloque de 5 min correspondiente
    return "${userId}_${dateStr}_${dt.hour}_$minute";
  }

  String _getRawBucketId(DateTime dt) {
    final userId = _firebaseService.currentUserId ?? "anon";
    final dateStr = DateFormat('yyyy-MM-dd').format(dt);
    return "${userId}_${dateStr}_${dt.hour}_${dt.minute}";
  }

  Future<void> _flushBuffer() async {
    if (_ax.isEmpty || _startMinute == null) return;

    final uid = _firebaseService.currentUserId ?? "anon";
    final bucketId = _getRawBucketId(_startMinute!);
    final summaryId = _getSummaryId(_startMinute!);

    final Map<String, dynamic> docData = {
      'userId': uid,
      'sessionId': _sessionId,
      'summaryId': summaryId,
      'startTime': Timestamp.fromDate(_startMinute!),
      'device_t0': _lastDeviceT0,
      'sampleCount': _ax.length,
      'ax': _ax.toList(),
      'ay': _ay.toList(),
      'az': _az.toList(),
      'gx': _gx.toList(),
      'gy': _gy.toList(),
      'gz': _gz.toList(),
      't_offsets': _tMsOffsets.toList(),
    };

    // Limpiar buffers antes de la subida asíncrona para no duplicar datos
    _ax.clear(); _ay.clear(); _az.clear();
    _gx.clear(); _gy.clear(); _gz.clear();
    _tMsOffsets.clear();
    final previousStartMinute = _startMinute;
    _startMinute = null;

    try {
      await _db.collection('raw_readings').doc(bucketId).set(docData, SetOptions(merge: true));
      print("FirestoreRaw: Bloque de 1 minuto subido correctamente ($bucketId)");
    } catch (e) {
      print("FirestoreRaw Error: $e");
      // En caso de error, los datos se pierden en este buffer para evitar saturar memoria,
      // pero en una implementación futura se podrían guardar localmente.
    }
  }

  void dispose() {
    _flushBuffer();
  }
}
