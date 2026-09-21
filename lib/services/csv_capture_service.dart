import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/device_info.dart';
import '../models/ble_device_data.dart';
import 'tremor_repository.dart';

class CsvCaptureService {
  IOSink? _csvSink;
  IOSink? _gapSink;
  File? _csvFile;
  File? _gapFile;

  int? _lastSeq;
  int? _deviceT0;
  DateTime? _wallT0;
  int _wraps = 0;
  int? _lastRawT;

  int _receivedCount = 0;
  int _lostCount = 0;

  DeviceInfo? _deviceInfo;

  final _statusController = StreamController<CaptureStatus>.broadcast();
  Stream<CaptureStatus> get statusStream => _statusController.stream;

  bool get isCapturing => _csvSink != null;

  Future<void> startCapture(DeviceInfo info) async {
    if (isCapturing) return;

    _deviceInfo = info;
    _receivedCount = 0;
    _lostCount = 0;
    _lastSeq = null;
    _deviceT0 = null;
    _wallT0 = null;
    _wraps = 0;
    _lastRawT = null;

    final now = DateTime.now().toUtc();
    final epoch = now.millisecondsSinceEpoch ~/ 1000;
    
    final directory = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${directory.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    _csvFile = File('${exportDir.path}/imu_raw_$epoch.csv');
    _gapFile = File('${exportDir.path}/imu_raw_${epoch}_gaps.csv');

    _csvSink = _csvFile!.openWrite();
    _gapSink = _gapFile!.openWrite();

    // Headers
    _csvSink!.writeln("seq,t_device_us,t_seconds,t_wall_iso,ax_lsb,ay_lsb,az_lsb,gx_lsb,gy_lsb,gz_lsb,ax_ms2,ay_ms2,az_ms2,gx_dps,gy_dps,gz_dps");
    _gapSink!.writeln("seq_inicio,n_perdidas,t_wall_iso");

    _notifyStatus();
  }

  Future<void> stopCapture() async {
    if (!isCapturing) return;

    await _csvSink?.flush();
    await _csvSink?.close();
    await _gapSink?.flush();
    await _gapSink?.close();

    _csvSink = null;
    _gapSink = null;
    
    _notifyStatus();
  }

  void processPacket(RawFifoPacket packet) {
    if (!isCapturing || _deviceInfo == null) return;

    // 1. Detectar Gaps (Secuencia)
    if (_lastSeq != null) {
      final expected = (_lastSeq! + 1) & 0xFFFF;
      if (packet.seqPrimera != expected) {
        final lost = (packet.seqPrimera - expected) & 0xFFFF;
        _handleGap(expected, lost);
      }
    }

    // 2. Corregir Reloj y Correlacionar
    int rawT = packet.t0Us;
    if (_lastRawT != null && rawT < _lastRawT!) {
      _wraps++;
    }
    _lastRawT = rawT;

    int correctedUs = rawT + (_wraps * 4294967296);

    if (_deviceT0 == null) {
      _deviceT0 = correctedUs;
      _wallT0 = DateTime.now().toUtc();
    }

    // 3. Procesar Muestras
    for (var i = 0; i < packet.samples.length; i++) {
      final currentSeq = (packet.seqPrimera + i) & 0xFFFF;
      final currentDeviceUs = correctedUs + (i * 20000);
      final sample = packet.samples[i];
      
      _writeSample(currentSeq, currentDeviceUs, sample);
      _receivedCount++;
      _lastSeq = currentSeq;
    }

    // Flush periódico
    if (_receivedCount % 250 < packet.samples.length) {
      _csvSink?.flush();
      _gapSink?.flush();
    }

    _notifyStatus();
  }

  void _handleGap(int startSeq, int count) {
    _lostCount += count;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    _gapSink?.writeln("$startSeq,$count,$nowIso");

    for (var i = 0; i < count; i++) {
      final seq = (startSeq + i) & 0xFFFF;
      _writeNan(seq);
    }
  }

  void _writeSample(int seq, int deviceUs, RawSample s) {
    final wall = _wallClock(deviceUs);
    final wallIso = wall.toIso8601String();
    final tSeconds = (deviceUs - _deviceT0!) / 1000000.0;

    final axMs2 = s.ax * _deviceInfo!.lsb2ms2;
    final ayMs2 = s.ay * _deviceInfo!.lsb2ms2;
    final azMs2 = s.az * _deviceInfo!.lsb2ms2;
    final gxDps = s.gx * _deviceInfo!.lsb2dps;
    final gyDps = s.gy * _deviceInfo!.lsb2dps;
    final gzDps = s.gz * _deviceInfo!.lsb2dps;

    _csvSink?.writeln("$seq,$deviceUs,${tSeconds.toStringAsFixed(6)},$wallIso,${s.ax},${s.ay},${s.az},${s.gx},${s.gy},${s.gz},${axMs2.toStringAsFixed(6)},${ayMs2.toStringAsFixed(6)},${azMs2.toStringAsFixed(6)},${gxDps.toStringAsFixed(6)},${gyDps.toStringAsFixed(6)},${gzDps.toStringAsFixed(6)}");
  }

  void _writeNan(int seq) {
    _csvSink?.writeln("$seq,,,,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN");
  }

  DateTime _wallClock(int correctedUs) {
    return _wallT0!.add(Duration(microseconds: correctedUs - _deviceT0!));
  }

  void _notifyStatus() {
    _statusController.add(CaptureStatus(
      isCapturing: isCapturing,
      received: _receivedCount,
      lost: _lostCount,
      csvPath: _csvFile?.path,
      gapPath: _gapFile?.path,
    ));
  }

  void dispose() {
    stopCapture();
    _statusController.close();
  }
}

class CaptureStatus {
  final bool isCapturing;
  final int received;
  final int lost;
  final String? csvPath;
  final String? gapPath;

  CaptureStatus({
    required this.isCapturing,
    required this.received,
    required this.lost,
    this.csvPath,
    this.gapPath,
  });
}
