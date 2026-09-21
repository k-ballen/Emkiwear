import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/ble_device_data.dart';
import '../models/tremor_summary.dart';
import 'ble_service.dart';
import 'tremor_repository.dart';
import 'firebase_service.dart';
import 'firestore_raw_service.dart';
import 'csv_capture_service.dart';
import '../models/device_info.dart';

class HourAccumulator {
// ... (mismo contenido de HourAccumulator)
  double sumIntensity = 0.0;
  double maxIntensity = 0.0;
  int totalSamples = 0;
  int tremorSamples = 0;
  double sumDomFreq = 0.0;
  int domFreqCount = 0;
  Map<String, int> severityCounts = {"LEVE": 0, "MODERADO": 0, "GRAVE": 0, "VOLUNTARIO": 0};
  DateTime startTime;

  HourAccumulator(this.startTime);

  Map<String, dynamic> toJson() => {
    'sumIntensity': sumIntensity,
    'maxIntensity': maxIntensity,
    'totalSamples': totalSamples,
    'tremorSamples': tremorSamples,
    'sumDomFreq': sumDomFreq,
    'domFreqCount': domFreqCount,
    'severityCounts': severityCounts,
    'startTime': startTime.millisecondsSinceEpoch,
  };

  static HourAccumulator fromJson(Map<String, dynamic> json) {
    var acc = HourAccumulator(DateTime.fromMillisecondsSinceEpoch(json['startTime']));
    acc.sumIntensity = json['sumIntensity'];
    acc.maxIntensity = json['maxIntensity'];
    acc.totalSamples = json['totalSamples'];
    acc.tremorSamples = json['tremorSamples'];
    acc.sumDomFreq = json['sumDomFreq'];
    acc.domFreqCount = json['domFreqCount'];
    acc.severityCounts = Map<String, int>.from(json['severityCounts']);
    return acc;
  }
}

class TremorProvider with ChangeNotifier {
  final TremorRepository _repository = TremorRepository();
  final FirebaseService _firebaseService = FirebaseService();
  final FirestoreRawService _rawFirestoreService = FirestoreRawService();
  final CsvCaptureService _csvCaptureService = CsvCaptureService();
  late final BleService _bleService;
  
  TremorSample? _lastSample;
  TremorStatus? _lastStatus;
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  bool _isStreaming = true;
  bool _isRawUploadEnabled = true;
  
  final List<TremorSample> _history = [];
  static const int maxHistory = 50;

  Map<String, HourAccumulator> _buckets = {};
  DateTime? _lastSampleProcessed;

  CaptureStatus? _captureStatus;

  TremorSample? get lastSample => _lastSample;
  TremorStatus? get lastStatus => _lastStatus;
  BluetoothConnectionState get connectionState => _connectionState;
  bool get isStreaming => _isStreaming;
  bool get isRawUploadEnabled => _isRawUploadEnabled;
  List<TremorSample> get history => _history;
  CaptureStatus? get captureStatus => _captureStatus;
  DeviceInfo? get deviceInfo => _bleService.deviceInfo;

  TremorProvider() {
    _bleService = BleService(_repository);
    _loadBuckets();
    
    // Escuchar datos del repositorio
    _repository.sampleStream.listen((sample) {
      _lastSample = sample;
      if (_isStreaming) {
        _history.add(sample);
        if (_history.length > maxHistory) _history.removeAt(0);
        _processSampleForBucket(sample);
        _checkAutoUpload();
      }
      notifyListeners();
    });

    _repository.statusStream.listen((status) {
      if (!_isStreaming) return;
      _lastStatus = status;
      notifyListeners();
    });

    _repository.summaryStream.listen((summary) {
      _firebaseService.addTremorSummary(summary);
      notifyListeners();
    });

    _repository.rawStream.listen((sample) {
      _rawFirestoreService.addSample(sample);
    });

    // RAWFIFO para CSV
    _repository.rawFifoStream.listen((packet) {
      _csvCaptureService.processPacket(packet);
    });

    _csvCaptureService.statusStream.listen((status) {
      _captureStatus = status;
      notifyListeners();
    });

    FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
      if (event.device.platformName == "ParkinsonWatch") {
        _connectionState = event.connectionState;
        if (_connectionState == BluetoothConnectionState.disconnected) {
          _isStreaming = false;
        }
        notifyListeners();
      }
    });

    _bleService.startScanAndConnect();
  }

  String _getBucketId(DateTime dt) {
    final userId = _firebaseService.currentUserId ?? "anon";
    final dateStr = DateFormat('yyyy-MM-dd').format(dt);
    final minute = (dt.minute ~/ 5) * 5; // Cambiado de 15 a 5
    return "${userId}_${dateStr}_${dt.hour}_$minute";
  }

  void _processSampleForBucket(TremorSample sample) {
    final now = DateTime.now();
    if (_lastSampleProcessed != null && now.difference(_lastSampleProcessed!).inSeconds < 10) return;
    _lastSampleProcessed = now;

    final bucketId = _getBucketId(now);
    _buckets.putIfAbsent(bucketId, () => HourAccumulator(now));
    
    final acc = _buckets[bucketId]!;
    acc.totalSamples++;
    acc.sumIntensity += sample.tremorAmp;
    if (sample.tremorAmp > acc.maxIntensity) acc.maxIntensity = sample.tremorAmp;
    
    if (_lastStatus?.tremorPresent == true) acc.tremorSamples++;
    if (_lastStatus?.domFreq != null && _lastStatus!.domFreq > 0) {
      acc.sumDomFreq += _lastStatus!.domFreq;
      acc.domFreqCount++;
    }
    
    final classification = getClassification(sample.tremorAmp, _lastStatus);
    acc.severityCounts[classification.severity] = (acc.severityCounts[classification.severity] ?? 0) + 1;
    
    _saveBuckets();
  }

  void _checkAutoUpload() {
    final now = DateTime.now();
    final currentBucketId = _getBucketId(now);
    
    // Si hay buckets en memoria que no son el actual, significa que ya terminaron
    bool hasFinishedBuckets = _buckets.keys.any((id) => id != currentBucketId);
    
    if (hasFinishedBuckets) {
      print("TremorProvider: Detectados bloques terminados. Iniciando subida automática...");
      uploadSummary();
    }
  }

  Future<void> _loadBuckets() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('tremor_buckets');
    if (data != null) {
      final Map<String, dynamic> decoded = json.decode(data);
      _buckets = decoded.map((key, value) => MapEntry(key, HourAccumulator.fromJson(value)));
    }
  }

  Future<void> _saveBuckets() async {
    final prefs = await SharedPreferences.getInstance();
    final data = json.encode(_buckets.map((key, value) => MapEntry(key, value.toJson())));
    await prefs.setString('tremor_buckets', data);
  }

  Future<void> uploadSummary() async {
    final bucketIds = _buckets.keys.toList();
    for (var id in bucketIds) {
      final acc = _buckets[id]!;
      if (acc.totalSamples == 0) continue;

      // Partes del ID: userId_date_hour_minute
      final parts = id.split('_');
      final date = parts.length > 1 ? parts[1] : DateFormat('yyyy-MM-dd').format(acc.startTime);
      final hour = parts.length > 2 ? int.tryParse(parts[2]) ?? acc.startTime.hour : acc.startTime.hour;
      final minute = parts.length > 3 ? int.tryParse(parts[3]) ?? ((acc.startTime.minute ~/ 5) * 5) : ((acc.startTime.minute ~/ 5) * 5);

      final summary = TremorSummary(
        id: id,
        startTime: acc.startTime,
        endTime: DateTime.now(),
        avgIntensity: acc.sumIntensity / acc.totalSamples,
        maxIntensity: acc.maxIntensity,
        totalSamples: acc.totalSamples,
        tremorSamples: acc.tremorSamples,
        avgDomFreq: acc.domFreqCount > 0 ? acc.sumDomFreq / acc.domFreqCount : 0,
        severityCounts: acc.severityCounts,
        date: date,
        hour: hour,
        minute: minute,
      );

      await _firebaseService.addTremorSummary(summary);
      
      // Solo removemos si el bucket ya no es el actual
      if (id != _getBucketId(DateTime.now())) {
        _buckets.remove(id);
      }
    }
    await _saveBuckets();
    notifyListeners();
  }

  ({String severity, String type, Color color, IconData icon, int level}) getClassification(double dps, TremorStatus? status) {
    final bool isPD = status?.tremorPresent ?? false;
    final double freq = status?.domFreq ?? 0.0;
    if (dps > 100 || (freq < 2.0 && dps > 100 && !isPD)) {
       return (severity: "VOLUNTARIO", type: "Movimiento Detectado", color: Colors.blue, icon: Icons.directions_run, level: 3);
    }
    if (isPD) {
      if (dps >= 50) return (severity: "GRAVE", type: "Temblor Parkinsoniano", color: Colors.red, icon: Icons.error_outline, level: 2);
      else if (dps >= 10) return (severity: "MODERADO", type: "Temblor Parkinsoniano", color: Colors.orange, icon: Icons.warning_amber_rounded, level: 1);
    }
    return (severity: "LEVE", type: "Reposo / Ruido", color: Colors.green, icon: Icons.check_circle_outline, level: 0);
  }

  Future<void> retryConnection() async {
    await _bleService.startScanAndConnect();
  }

  Future<void> toggleStreaming() async {
    _isStreaming = !_isStreaming;
    await _repository.sendCommand(_isStreaming);
    if (!_isStreaming) {
      _lastSample = null;
      _lastStatus = null;
    }
    notifyListeners();
  }

  Future<void> sendCommand(bool start) async {
    _isStreaming = start;
    await _repository.sendCommand(start);
    notifyListeners();
  }

  Future<void> toggleRawUpload() async {
    _isRawUploadEnabled = !_isRawUploadEnabled;
    _rawFirestoreService.uploadEnabled = _isRawUploadEnabled;
    await _repository.sendRawControl(_isRawUploadEnabled);
    notifyListeners();
  }

  Future<void> startCsvCapture() async {
    if (deviceInfo == null) {
      print("CSV ERROR: Esperando INFO del dispositivo...");
      return;
    }
    await _csvCaptureService.startCapture(deviceInfo!);
  }

  Future<void> stopCsvCapture() async {
    await _csvCaptureService.stopCapture();
  }

  @override
  void dispose() {
    _repository.dispose();
    _rawFirestoreService.dispose();
    _csvCaptureService.dispose();
    super.dispose();
  }
}
