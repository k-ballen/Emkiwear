import 'dart:async';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/ble_device_data.dart';
import '../models/tremor_summary.dart';
import '../models/raw_imu_sample.dart';

class TremorRepository {
  static const String serviceUuid = "7A9B0001-2D4E-4E6F-8A1B-0C2D3E4F5061";
  static const String sampleCharUuid = "7A9B0002-2D4E-4E6F-8A1B-0C2D3E4F5061";
  static const String statusCharUuid = "7A9B0003-2D4E-4E6F-8A1B-0C2D3E4F5061";
  static const String cmdCharUuid = "7A9B0004-2D4E-4E6F-8A1B-0C2D3E4F5061";
  static const String extCharUuid = "7A9B0005-2D4E-4E6F-8A1B-0C2D3E4F5061";
  static const String summaryCharUuid = "7A9B0006-2D4E-4E6F-8A1B-0C2D3E4F5061";
  static const String rawCharUuid = "7A9B0007-2D4E-4E6F-8A1B-0C2D3E4F5061";
  static const String rawFifoCharUuid = "7A9B0008-2D4E-4E6F-8A1B-0C2D3E4F5061";
  // Batería: READ + NOTIFY, 1 byte. 0xFE = nivel no disponible, 0xFF = entrando en modo carga.
  static const String batteryCharUuid = "7A9B0009-2D4E-4E6F-8A1B-0C2D3E4F5061";
  // Firmware anterior usaba 7A9B0009 para DIAG (16 bytes). Se distingue por longitud del paquete.
  static const String diagCharUuid = batteryCharUuid;
  static const String sevCharUuid = "7A9B000A-2D4E-4E6F-8A1B-0C2D3E4F5061";

  static const int batteryNotAvailable = 0xFE;
  static const int batteryEnteringCharge = 0xFF;
  static const int cmdChargeMode = 0xC0;

  final StreamController<TremorSample> _sampleController = StreamController<TremorSample>.broadcast();
  final StreamController<TremorStatus> _statusController = StreamController<TremorStatus>.broadcast();
  final StreamController<TremorExt> _extController = StreamController<TremorExt>.broadcast();
  final StreamController<TremorSev> _sevController = StreamController<TremorSev>.broadcast();
  final StreamController<TremorDiag> _diagController = StreamController<TremorDiag>.broadcast();
  final StreamController<TremorSummary> _summaryController = StreamController<TremorSummary>.broadcast();
  final StreamController<RawImuSample> _rawController = StreamController<RawImuSample>.broadcast();
  final StreamController<RawAxisData> _rawAxisController = StreamController<RawAxisData>.broadcast();
  final StreamController<RawFifoPacket> _rawFifoController = StreamController<RawFifoPacket>.broadcast();
  final StreamController<int> _batteryController = StreamController<int>.broadcast();

  Stream<TremorSample> get sampleStream => _sampleController.stream;
  Stream<TremorStatus> get statusStream => _statusController.stream;
  Stream<TremorExt> get extStream => _extController.stream;
  Stream<TremorSev> get sevStream => _sevController.stream;
  Stream<TremorDiag> get diagStream => _diagController.stream;
  Stream<TremorSummary> get summaryStream => _summaryController.stream;
  Stream<RawImuSample> get rawStream => _rawController.stream;
  Stream<RawAxisData> get rawAxisStream => _rawAxisController.stream;
  Stream<RawFifoPacket> get rawFifoStream => _rawFifoController.stream;
  /// Byte crudo de batería (0-100 = %, 0xFE = no disponible, 0xFF = entrando en modo carga).
  Stream<int> get batteryStream => _batteryController.stream;

  BluetoothCharacteristic? _cmdChar;

  void decodeSample(List<int> value) {
    if (value.length < 14) return;
    
    final data = ByteData.sublistView(Uint8List.fromList(value));
    
    final sample = TremorSample(
      tMs: data.getUint32(0, Endian.little),
      roll: data.getInt16(4, Endian.little) / 100.0,
      pitch: data.getInt16(6, Endian.little) / 100.0,
      linAcc: data.getInt16(8, Endian.little) / 1000.0,
      gyroMag: data.getInt16(10, Endian.little) / 10.0,
      tremorAmp: data.getInt16(12, Endian.little) / 10.0,
    );
    
    _sampleController.add(sample);
  }

  TremorStatus? decodeStatus(List<int> value) {
    if (value.length != 14) return null;

    final data = ByteData.sublistView(Uint8List.fromList(value));
    final flags = data.getUint8(4);
    
    final status = TremorStatus(
      tMs: data.getUint32(0, Endian.little),
      tremorPresent: (flags & 0x01) != 0,
      freqStable: (flags & 0x02) != 0,
      detected: (flags & 0x04) != 0,
      isAnalyzing: (flags & 0x40) != 0,
      tremorClass: TremorClassExtension.fromInt((flags >> 3) & 0x07),
      domFreq: data.getUint8(5) / 10.0,
      tremorAmp: data.getInt16(6, Endian.little) / 10.0,
      movement: data.getInt16(8, Endian.little) / 10.0,
      bandFrac: data.getUint8(10),
      duty: data.getUint8(11),
      episode: data.getUint16(12, Endian.little),
    );
    
    _statusController.add(status);
    return status;
  }

  TremorExt? decodeExt(List<int> value) {
    if (value.length != 12) return null;

    final data = ByteData.sublistView(Uint8List.fromList(value));
    final flags2 = data.getUint8(10);
    final categoryInt = data.getUint8(11);

    final ext = TremorExt(
      tMs: data.getUint32(0, Endian.little),
      accelAmpMg: data.getUint16(4, Endian.little),
      ratio: data.getUint16(6, Endian.little) / 100.0,
      angDeg: data.getUint16(8, Endian.little) / 100.0,
      flags2: flags2,
      isRotational: (flags2 & 0x01) != 0,
      tremorClass: TremorClassExtension.fromInt(categoryInt),
    );

    _extController.add(ext);
    return ext;
  }

  TremorSev? decodeSev(List<int> value) {
    if (value.length != 8) return null;

    final data = ByteData.sublistView(Uint8List.fromList(value));

    final sev = TremorSev(
      tMs: data.getUint32(0, Endian.little),
      thetaDeg: data.getUint16(4, Endian.little) / 100.0,
      desplazCm: data.getUint16(6, Endian.little) / 10.0,
    );

    _sevController.add(sev);
    return sev;
  }

  TremorDiag? decodeDiag(List<int> value) {
    if (value.length != 16) return null;

    final data = ByteData.sublistView(Uint8List.fromList(value));
    final flags = data.getUint8(7);

    final diag = TremorDiag(
      tMs: data.getUint32(0, Endian.little),
      ruta: data.getUint8(4),
      votos: data.getUint8(5),
      ejesActivos: data.getUint8(6),
      flags: flags,
      detectado: (flags & 0x01) != 0,
      rotacional: (flags & 0x02) != 0,
      compuerta: (flags & 0x04) != 0,
      lin: data.getUint16(8, Endian.little) / 1000.0,
      prel3Pct: data.getUint8(10),
      vol110Pct: data.getUint8(11),
      sigmaMin: data.getUint16(12, Endian.little) / 100.0,
      rmsPc: data.getUint16(14, Endian.little) / 10.0,
    );

    _diagController.add(diag);
    return diag;
  }

  void decodeBattery(List<int> value) {
    if (value.length != 1) return;
    _batteryController.add(value[0] & 0xFF);
  }

  /// Característica 7A9B0009: 1 byte = batería, 16 bytes = DIAG (firmware anterior).
  void decodeBatteryOrDiag(List<int> value) {
    if (value.length == 1) {
      decodeBattery(value);
    } else {
      decodeDiag(value);
    }
  }

  void decodeSummary(List<int> value, String userId) {
    if (value.length < 34) return;
    final data = ByteData.sublistView(Uint8List.fromList(value));
    
    final int seq = data.getUint16(0, Endian.little);
    final int startT = data.getUint32(2, Endian.little);
    final int endT = data.getUint32(6, Endian.little);
    
    final startTime = DateTime.fromMillisecondsSinceEpoch(startT * 1000);
    final dateStr = DateFormat('yyyy-MM-dd').format(startTime);
    final hour = startTime.hour;
    final minute = (startTime.minute ~/ 5) * 5;

    final summary = TremorSummary(
      id: "${userId}_${dateStr}_${hour}_${minute}",
      startTime: startTime,
      endTime: DateTime.fromMillisecondsSinceEpoch(endT * 1000),
      avgIntensity: data.getInt16(10, Endian.little) / 10.0,
      maxIntensity: data.getInt16(12, Endian.little) / 10.0,
      totalSamples: data.getUint32(14, Endian.little),
      tremorSamples: data.getUint32(18, Endian.little),
      avgDomFreq: data.getUint8(22) / 10.0,
      severityCounts: {
        "SIN_TEMBLOR": data.getUint16(23, Endian.little),
        "LEVE": data.getUint16(25, Endian.little),
        "MODERADO": data.getUint16(27, Endian.little),
        "GRAVE": data.getUint16(29, Endian.little),
        "VOLUNTARIO": data.getUint16(31, Endian.little),
      },
      date: dateStr,
      hour: hour,
      minute: minute,
      taxonomyVersion: 2,
    );
    
    _summaryController.add(summary);
  }

  void decodeRawImu(List<int> value) {
    if (value.length < 16) return;
    final b = ByteData.sublistView(Uint8List.fromList(value));

    final rawAxis = RawAxisData(
      tMs: b.getUint32(0, Endian.little),
      axG: b.getInt16(4, Endian.little) / 1000.0,
      ayG: b.getInt16(6, Endian.little) / 1000.0,
      azG: b.getInt16(8, Endian.little) / 1000.0,
      gxDps: b.getInt16(10, Endian.little) / 10.0,
      gyDps: b.getInt16(12, Endian.little) / 10.0,
      gzDps: b.getInt16(14, Endian.little) / 10.0,
    );

    _rawAxisController.add(rawAxis);

    final sample = RawImuSample(
      tMs: rawAxis.tMs,
      epochMs: DateTime.now().millisecondsSinceEpoch,
      ax: rawAxis.axG,
      ay: rawAxis.ayG,
      az: rawAxis.azG,
      gx: rawAxis.gxDps,
      gy: rawAxis.gyDps,
      gz: rawAxis.gzDps,
    );
    
    _rawController.add(sample);
  }

  void decodeRawFifo(List<int> value) {
    if (value.length < 7) {
      print("RAWFIFO: Paquete muy corto (${value.length} bytes)");
      return;
    }

    final b = ByteData.sublistView(Uint8List.fromList(value));
    final seq = b.getUint16(0, Endian.little);
    final t0 = b.getUint32(2, Endian.little);
    final n = b.getUint8(6);

    final expectedSize = 7 + n * 12;
    if (value.length != expectedSize) {
      print("RAWFIFO ERROR: Tamaño inconsistente. Esperado: $expectedSize, Recibido: ${value.length}");
      return;
    }

    final samples = <RawSample>[];
    var off = 7;

    for (var i = 0; i < n; i++) {
      samples.add(RawSample(
        b.getInt16(off, Endian.little),
        b.getInt16(off + 2, Endian.little),
        b.getInt16(off + 4, Endian.little),
        b.getInt16(off + 6, Endian.little),
        b.getInt16(off + 8, Endian.little),
        b.getInt16(off + 10, Endian.little),
      ));
      off += 12;
    }

    _rawFifoController.add(RawFifoPacket(seq, t0, n, samples));
  }

  Future<void> sendInfoRequest() async {
    if (_cmdChar == null) return;
    await _cmdChar!.write([0x30]);
  }

  Future<void> sendTimeSync() async {
    if (_cmdChar == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final data = Uint8List(5);
    data[0] = 0x10; // Prefijo SYNC
    final bdata = ByteData.view(data.buffer);
    bdata.setUint32(1, now, Endian.little);
    await _cmdChar!.write(data.toList());
  }

  Future<void> sendSummaryAck(int seq) async {
    if (_cmdChar == null) return;
    final data = Uint8List(3);
    data[0] = 0x20; // Prefijo ACK
    final bdata = ByteData.view(data.buffer);
    bdata.setUint16(1, seq, Endian.little);
    await _cmdChar!.write(data.toList());
  }

  Future<void> sendCommand(bool start) async {
    if (_cmdChar == null) return;
    await _cmdChar!.write([start ? 0x01 : 0x00]);
  }

  Future<void> sendRawControl(bool enable) async {
    if (_cmdChar == null) return;
    await _cmdChar!.write([enable ? 0x03 : 0x02]);
  }

  /// Envía 0xC0: el reloj deja de transmitir y se apaga para cargar.
  /// Devuelve false si no hay característica de control o la escritura falla
  /// (puede fallar si el reloj se apaga antes de confirmar).
  Future<bool> sendChargeModeCommand() async {
    if (_cmdChar == null) return false;
    try {
      await _cmdChar!.write([cmdChargeMode]);
      return true;
    } catch (e) {
      print("BLE: Escritura 0xC0 falló o el reloj se apagó antes de confirmar: $e");
      return false;
    }
  }

  void setCmdCharacteristic(BluetoothCharacteristic char) {
    _cmdChar = char;
  }

  void dispose() {
    _sampleController.close();
    _statusController.close();
    _extController.close();
    _sevController.close();
    _diagController.close();
    _summaryController.close();
    _rawController.close();
    _rawAxisController.close();
    _rawFifoController.close();
    _batteryController.close();
  }
}
