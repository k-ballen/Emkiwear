import 'dart:async';
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
import 'tremor_filter.dart';
import '../models/device_info.dart';

class HourAccumulator {
  double sumIntensity = 0.0;
  double maxIntensity = 0.0;
  double sumAngleDeg = 0.0;
  double maxAngleDeg = 0.0;
  int angleCount = 0;
  int totalSamples = 0;
  int tremorSamples = 0;
  double sumDomFreq = 0.0;
  int domFreqCount = 0;
  Map<String, int> severityCounts = {
    "SIN_TEMBLOR": 0,
    "LEVE": 0,
    "MODERADO": 0,
    "GRAVE": 0,
    "VOLUNTARIO": 0
  };
  DateTime startTime;

  HourAccumulator(this.startTime);

  Map<String, dynamic> toJson() => {
        'sumIntensity': sumIntensity,
        'maxIntensity': maxIntensity,
        'sumAngleDeg': sumAngleDeg,
        'maxAngleDeg': maxAngleDeg,
        'angleCount': angleCount,
        'totalSamples': totalSamples,
        'tremorSamples': tremorSamples,
        'sumDomFreq': sumDomFreq,
        'domFreqCount': domFreqCount,
        'severityCounts': severityCounts,
        'startTime': startTime.millisecondsSinceEpoch,
      };

  static HourAccumulator fromJson(Map<String, dynamic> json) {
    var acc = HourAccumulator(
        DateTime.fromMillisecondsSinceEpoch(json['startTime']));
    acc.sumIntensity = (json['sumIntensity'] ?? 0.0).toDouble();
    acc.maxIntensity = (json['maxIntensity'] ?? 0.0).toDouble();
    acc.sumAngleDeg = (json['sumAngleDeg'] ?? 0.0).toDouble();
    acc.maxAngleDeg = (json['maxAngleDeg'] ?? 0.0).toDouble();
    acc.angleCount = json['angleCount'] ?? 0;
    acc.totalSamples = json['totalSamples'] ?? 0;
    acc.tremorSamples = json['tremorSamples'] ?? 0;
    acc.sumDomFreq = (json['sumDomFreq'] ?? 0.0).toDouble();
    acc.domFreqCount = json['domFreqCount'] ?? 0;
    acc.severityCounts = Map<String, int>.from(json['severityCounts'] ?? {});
    return acc;
  }
}

class DebugPacketRecord {
  final int tMs;
  final String tremorClass;
  final bool confirmed;
  final bool detected;
  final double fHz;
  final double ampDps;
  final double movDps;
  final int bandPct;
  final int dutyPct;
  final int episodioS;
  final int? accelMg;
  final double? ratio;
  final double? angDeg;
  final bool? rotacional;
  final int? ruta;
  final int? votos;
  final int? activos;
  final bool? compuerta;
  final double? lin;
  final int? prel3;
  final int? vol110;
  final double? sigmaMin;
  final double? rmsPc;
  final bool isIncoherent;
  final DateTime receivedAt;

  DebugPacketRecord({
    required this.tMs,
    required this.tremorClass,
    required this.confirmed,
    required this.detected,
    required this.fHz,
    required this.ampDps,
    required this.movDps,
    required this.bandPct,
    required this.dutyPct,
    required this.episodioS,
    this.accelMg,
    this.ratio,
    this.angDeg,
    this.rotacional,
    this.ruta,
    this.votos,
    this.activos,
    this.compuerta,
    this.lin,
    this.prel3,
    this.vol110,
    this.sigmaMin,
    this.rmsPc,
    required this.isIncoherent,
    required this.receivedAt,
  });

  String toCsvLine() {
    return '$tMs,$tremorClass,$confirmed,$detected,${fHz.toStringAsFixed(1)},${ampDps.toStringAsFixed(1)},${movDps.toStringAsFixed(1)},$bandPct,$dutyPct,$episodioS,${accelMg ?? ''},${ratio != null ? ratio!.toStringAsFixed(2) : ''},${angDeg != null ? angDeg!.toStringAsFixed(2) : ''},${rotacional ?? ''},${ruta ?? ''},${votos ?? ''},${activos ?? ''},${compuerta ?? ''},${lin != null ? lin!.toStringAsFixed(3) : ''},${prel3 ?? ''},${vol110 ?? ''},${sigmaMin != null ? sigmaMin!.toStringAsFixed(2) : ''},${rmsPc != null ? rmsPc!.toStringAsFixed(1) : ''},$isIncoherent';
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
  TremorExt? _lastExt;
  TremorSev? _lastSev;
  TremorDiag? _lastDiag;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  bool _isStreaming = true;
  bool _isRawUploadEnabled = true;

  // Timeout de datos y tiempo de análisis (bit6)
  DateTime? _lastStatusTime;
  DateTime? _analyzingStartTime;
  bool _isDataTimeout = false;
  bool _yaHayResultado = false;
  Timer? _timeoutCheckTimer;
  int? _lastProcessedTMs;

  // Últimos valores válidos de la sesión
  TremorClass? _ultimaClase;
  double? _ultimaFrecuencia;
  double? _ultimoAngulo;
  double? _ultimoDesplazamiento;
  bool? _ultimoConfirmado;
  DateTime? _ultimaActualizacion;

  double? _lastValidDomFreq;
  DateTime? _lastValidDomFreqTime;
  double? _lastValidAngDeg;
  DateTime? _lastValidAngDegTime;
  double? _lastValidDesplazCm;
  DateTime? _lastValidDesplazCmTime;

  // Batería (byte crudo de 7A9B0009). 0xFE/0xFF NUNCA se muestran como % ni se suben a Firestore.
  int? _batteryRaw;

  // Modo carga
  static const String _prefsChargeMode = 'charge_mode';
  static const String _prefsChargeModeStart = 'charge_mode_start_ms';
  static const String _prefsChargeDevice = 'charge_mode_device_id';
  static const String _prefsPreferredWatch = 'preferred_watch_id';

  /// Reloj que se puso a cargar (el sondeo de 60 s solo busca ese).
  String? _chargeDeviceId;

  // ================= SELECTOR DE RELOJ =================

  String? get preferredWatchId => _bleService.preferredDeviceId;
  String? get connectedWatchId => _bleService.connectedDevice?.remoteId.str;

  /// Busca todos los relojes cercanos (unos 6 s).
  Future<List<WatchCandidate>> scanWatches() => _bleService.scanWatches();

  /// Guarda el reloj elegido y se conecta a él (desconecta el actual).
  Future<void> selectWatch(String id) async {
    if (_chargeMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsPreferredWatch, id);
    } catch (_) {}
    _logBleEvent("Reloj elegido por el usuario: $id");
    // Nueva sesión de monitoreo con el otro reloj.
    if (connectedWatchId != null && connectedWatchId != id) {
      await closeMonitoringSession();
    }
    await _bleService.switchToDevice(id);
    notifyListeners();
  }
  bool _chargeMode = false;
  DateTime? _chargeModeStart;
  bool _enteringChargeMode = false;
  Timer? _chargeProbeTimer;
  Timer? _chargeTickTimer;
  bool _probeInProgress = false;

  bool get chargeMode => _chargeMode;
  DateTime? get chargeModeStart => _chargeModeStart;
  bool get enteringChargeMode => _enteringChargeMode;
  Duration get chargeModeElapsed => _chargeModeStart == null
      ? Duration.zero
      : DateTime.now().difference(_chargeModeStart!);

  /// Porcentaje válido (0-100) o null si no está disponible (0xFE, 0xFF o sin dato).
  int? get batteryPercent {
    final v = _batteryRaw;
    if (v == null || v > 100) return null;
    return v;
  }

  String get batteryDisplay {
    final p = batteryPercent;
    return p == null ? "Batería: no disponible" : "Batería: $p %";
  }

  // Registro/Log de eventos BLE con fecha y hora
  final List<String> _bleLogs = [];

  // Getters para el último estado válido
  TremorClass? get ultimaClase => _ultimaClase;
  double? get ultimaFrecuencia => _ultimaFrecuencia;
  double? get ultimoAngulo => _ultimoAngulo;
  double? get ultimoDesplazamiento => _ultimoDesplazamiento;
  bool? get ultimoConfirmado => _ultimoConfirmado;
  DateTime? get ultimaActualizacion => _ultimaActualizacion;
  List<String> get bleLogs => List.unmodifiable(_bleLogs);

  void _logBleEvent(String msg) {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final entry = "$timestamp - $msg";
    print("BLE_LOG: $entry");
    _bleLogs.add(entry);
    if (_bleLogs.length > 200) _bleLogs.removeAt(0);
  }

  // Historial de muestras de velocidad para gráfica (50 muestras)
  final List<TremorSample> _history = [];
  static const int maxHistory = 50;

  // Línea de tiempo de los últimos 2 minutos (240 paquetes STATUS a ~2Hz)
  final List<TremorStatus> _timeline = [];
  static const int maxTimeline = 240;

  // Contadores de Sesión acumulados (0.5 s por STATUS)
  int _sessionSinTemblorCount = 0;
  int _sessionLeveCount = 0;
  int _sessionModeradoCount = 0;
  int _sessionGraveCount = 0;
  int _sessionVoluntarioCount = 0;

  // Contador de incoherencias (bit2 == 1 && clase == 4)
  int _incoherenceCount = 0;

  // Definición de Episodios (Flanco ascendente del bit0 de confirmado)
  int _episodeCount = 0;
  bool _prevConfirmed = false;

  // Filtros de Señal por Eje y Búfers (10 s a 50 Hz = 500 puntos)
  final Tremor3AxisFilter _gyroFilter = Tremor3AxisFilter();
  final Tremor3AxisFilter _accelFilter = Tremor3AxisFilter();
  int? _lastRawTMs;

  final List<RawAxisData> _rawAxisBuffer = [];
  final List<({double x, double y, double z})> _filteredGyroBuffer = [];
  final List<({double x, double y, double z})> _filteredAccelBuffer = [];
  static const int maxRawPoints = 500;

  // Búfer de 60 s para exportación de señal RAW (3000 puntos)
  final List<RawAxisData> _raw60sBuffer = [];
  static const int maxRaw60s = 3000;

  // Control de refresco de UI para RAW (10-15 fps max = ~66 ms)
  DateTime _lastRawNotify = DateTime.now();
  bool _isRawCardVisible = false;

  // Registro de paquetes para pantalla de depuración y exportación CSV
  final List<DebugPacketRecord> _debugRecords = [];
  static const int maxDebugRecords = 500;

  Map<String, HourAccumulator> _buckets = {};
  CaptureStatus? _captureStatus;

  TremorSample? get lastSample => _lastSample;
  TremorStatus? get lastStatus => _lastStatus;
  TremorExt? get lastExt => _lastExt;
  TremorSev? get lastSev => _lastSev;
  TremorDiag? get lastDiag => _lastDiag;
  BluetoothConnectionState get connectionState => _connectionState;
  bool get isStreaming => _isStreaming;
  bool get isRawUploadEnabled => _isRawUploadEnabled;
  bool get isDataTimeout => _isDataTimeout;
  bool get yaHayResultado => _yaHayResultado;
  List<TremorSample> get history => _history;
  List<TremorStatus> get timeline => List.unmodifiable(_timeline);
  List<DebugPacketRecord> get debugRecords => List.unmodifiable(_debugRecords);
  CaptureStatus? get captureStatus => _captureStatus;
  DeviceInfo? get deviceInfo => _bleService.deviceInfo;

  // Acceso a datos RAW
  List<RawAxisData> get rawAxisBuffer => List.unmodifiable(_rawAxisBuffer);
  List<({double x, double y, double z})> get filteredGyroBuffer => List.unmodifiable(_filteredGyroBuffer);
  List<({double x, double y, double z})> get filteredAccelBuffer => List.unmodifiable(_filteredAccelBuffer);
  bool get isRawCardVisible => _isRawCardVisible;

  // Verificación de Firmware < 2.0.0
  bool get isFirmwareOutdated {
    if (deviceInfo == null || deviceInfo!.firmware.isEmpty) return false;
    final parts = deviceInfo!.firmware.split('.');
    final major = int.tryParse(parts[0]) ?? 2;
    return major < 2;
  }

  // Progreso de análisis (0.0 a 1.0 durante ~11s, o -1.0 si es indeterminado tras 11s)
  double get analyzingProgress {
    if (_ultimaClase == null && (_lastStatus == null || _lastStatus!.isAnalyzing)) {
      if (_analyzingStartTime == null) return 0.0;
      final elapsedMs = DateTime.now().difference(_analyzingStartTime!).inMilliseconds;
      if (elapsedMs >= 11000) return -1.0;
      return (elapsedMs / 11000.0).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  // Getters para métricas con el último valor válido de la sesión
  String get validDomFreqDisplay {
    if (_ultimaFrecuencia != null && _ultimaFrecuencia! > 0) {
      return "${_ultimaFrecuencia!.toStringAsFixed(1)} Hz";
    }
    if (_lastStatus != null && _lastStatus!.domFreq > 0) {
      return "${_lastStatus!.domFreq.toStringAsFixed(1)} Hz";
    }
    return "—";
  }

  String get validAngDegDisplay {
    if (_ultimoAngulo != null && _ultimoAngulo! > 0) {
      return "${_ultimoAngulo!.toStringAsFixed(2)}°";
    }
    if (_lastExt != null && _lastExt!.angDeg > 0) {
      return "${_lastExt!.angDeg.toStringAsFixed(2)}°";
    }
    if (_lastSev != null && _lastSev!.thetaDeg > 0) {
      return "${_lastSev!.thetaDeg.toStringAsFixed(2)}°";
    }
    return "—";
  }

  String get validDesplazDisplay {
    if (_ultimoDesplazamiento != null && _ultimoDesplazamiento! > 0) {
      return "${_ultimoDesplazamiento!.toStringAsFixed(1)} cm";
    }
    if (_lastSev != null && _lastSev!.desplazCm > 0) {
      return "${_lastSev!.desplazCm.toStringAsFixed(1)} cm";
    }
    if (_lastExt != null && _lastExt!.angDeg > 0) {
      return "${(_lastExt!.angDeg * 0.2618).toStringAsFixed(1)} cm";
    }
    return "—";
  }

  // Contadores de sesión
  int get sessionSinTemblorCount => _sessionSinTemblorCount;
  int get sessionLeveCount => _sessionLeveCount;
  int get sessionModeradoCount => _sessionModeradoCount;
  int get sessionGraveCount => _sessionGraveCount;
  int get sessionVoluntarioCount => _sessionVoluntarioCount;
  int get incoherenceCount => _incoherenceCount;
  int get episodeCount => _episodeCount;

  // Período de estabilización (t_ms < 12000 ms)
  bool get isStabilizing => _lastStatus != null && _lastStatus!.tMs < 12000;

  TremorProvider() {
    _bleService = BleService(_repository);
    _loadBuckets();

    _timeoutCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_ultimaActualizacion != null &&
          DateTime.now().difference(_ultimaActualizacion!).inSeconds >= 3) {
        if (!_isDataTimeout) {
          _isDataTimeout = true;
          notifyListeners();
        }
      } else {
        if (_isDataTimeout) {
          _isDataTimeout = false;
          notifyListeners();
        }
      }
    });

    _repository.sampleStream.listen((sample) {
      _lastSample = sample;
      if (_isStreaming) {
        _history.add(sample);
        if (_history.length > maxHistory) _history.removeAt(0);
      }
      notifyListeners();
    });

    _repository.statusStream.listen((status) {
      if (!_isStreaming) return;

      if (!_yaHayResultado) {
        if (!status.isAnalyzing) {
          _yaHayResultado = true;
          _analyzingStartTime = null;
        } else {
          _analyzingStartTime ??= DateTime.now();
        }
      } else {
        // Ignora paquetes con bit6 = 1 (isAnalyzing) cuando ya hubo un resultado en esta sesión
        if (status.isAnalyzing) {
          return;
        }
      }

      _lastStatus = status;
      _lastStatusTime = DateTime.now();
      _isDataTimeout = false;

      // Actualizar el ÚLTIMO ESTADO VÁLIDO (bit6 == 0 y clase entre 0 y 4)
      if (!status.isAnalyzing) {
        _ultimaClase = status.tremorClass;
        _ultimoConfirmado = status.tremorPresent;
        _ultimaActualizacion = DateTime.now();

        if (status.tremorClass == TremorClass.leve ||
            status.tremorClass == TremorClass.moderado ||
            status.tremorClass == TremorClass.grave) {
          if (status.domFreq > 0) {
            _ultimaFrecuencia = status.domFreq;
            _lastValidDomFreq = status.domFreq;
            _lastValidDomFreqTime = DateTime.now();
          }
        } else if (status.tremorClass == TremorClass.sinTemblor ||
                   status.tremorClass == TremorClass.voluntario) {
          _ultimaFrecuencia = 0.0;
          _ultimoAngulo = 0.0;
          _ultimoDesplazamiento = 0.0;
        }
      }

      // Deduplicación t_ms: si tMs es idéntico al último ya procesado,
      // la conexión está viva (_ultimaActualizacion ya se actualizó), pero NO duplicamos en la línea de tiempo.
      if (_lastProcessedTMs != null && status.tMs == _lastProcessedTMs) {
        notifyListeners();
        return;
      }
      _lastProcessedTMs = status.tMs;

      _timeline.add(status);
      if (_timeline.length > maxTimeline) _timeline.removeAt(0);

      if (!status.isAnalyzing) {
        switch (status.tremorClass) {
          case TremorClass.sinTemblor:
            _sessionSinTemblorCount++;
            break;
          case TremorClass.leve:
            _sessionLeveCount++;
            break;
          case TremorClass.moderado:
            _sessionModeradoCount++;
            break;
          case TremorClass.grave:
            _sessionGraveCount++;
            break;
          case TremorClass.voluntario:
            _sessionVoluntarioCount++;
            break;
        }

        if (status.detected && status.tremorClass == TremorClass.voluntario) {
          _incoherenceCount++;
        }

        final bool isTremorActive = status.tremorPresent &&
            (status.tremorClass == TremorClass.leve ||
             status.tremorClass == TremorClass.moderado ||
             status.tremorClass == TremorClass.grave);

        if (isTremorActive && !_prevConfirmed) {
          _episodeCount++;
        }
        _prevConfirmed = isTremorActive;
      }

      _recordDebugStatus(status);
      _processStatusForBucket(status);
      _checkAutoUpload();

      notifyListeners();
    });

    _repository.extStream.listen((ext) {
      if (!_isStreaming) return;
      _lastExt = ext;
      _recordDebugExt(ext);

      if (_ultimaClase == TremorClass.leve ||
          _ultimaClase == TremorClass.moderado ||
          _ultimaClase == TremorClass.grave) {
        if (ext.angDeg > 0) {
          _ultimoAngulo = ext.angDeg;
          _lastValidAngDeg = ext.angDeg;
          _lastValidAngDegTime = DateTime.now();
        }
      }

      if (_lastStatus != null && !_lastStatus!.isAnalyzing) {
        _processExtForBucket(ext);
      }

      notifyListeners();
    });

    _repository.sevStream.listen((sev) {
      if (!_isStreaming) return;
      _lastSev = sev;
      if (_ultimaClase == TremorClass.leve ||
          _ultimaClase == TremorClass.moderado ||
          _ultimaClase == TremorClass.grave) {
        if (sev.desplazCm > 0) {
          _ultimoDesplazamiento = sev.desplazCm;
          _lastValidDesplazCm = sev.desplazCm;
          _lastValidDesplazCmTime = DateTime.now();
        }
        if (sev.thetaDeg > 0 && (_ultimoAngulo == null || _ultimoAngulo == 0)) {
          _ultimoAngulo = sev.thetaDeg;
        }
      }
      notifyListeners();
    });

    _repository.diagStream.listen((diag) {
      if (!_isStreaming) return;
      _lastDiag = diag;
      _recordDebugDiag(diag);
      notifyListeners();
    });

    _repository.rawAxisStream.listen((raw) {
      if (!_isStreaming) return;

      if (_lastRawTMs != null && (raw.tMs - _lastRawTMs!).abs() > 100) {
        _gyroFilter.reset();
        _accelFilter.reset();
      }
      _lastRawTMs = raw.tMs;

      final filteredG = _gyroFilter.process(x: raw.gxDps, y: raw.gyDps, z: raw.gzDps);
      final filteredA = _accelFilter.process(x: raw.axG, y: raw.ayG, z: raw.azG);

      _rawAxisBuffer.add(raw);
      if (_rawAxisBuffer.length > maxRawPoints) _rawAxisBuffer.removeAt(0);

      _filteredGyroBuffer.add(filteredG);
      if (_filteredGyroBuffer.length > maxRawPoints) _filteredGyroBuffer.removeAt(0);

      _filteredAccelBuffer.add(filteredA);
      if (_filteredAccelBuffer.length > maxRawPoints) _filteredAccelBuffer.removeAt(0);

      _raw60sBuffer.add(raw);
      if (_raw60sBuffer.length > maxRaw60s) _raw60sBuffer.removeAt(0);

      final now = DateTime.now();
      if (now.difference(_lastRawNotify).inMilliseconds >= 66) {
        _lastRawNotify = now;
        notifyListeners();
      }
    });

    _repository.summaryStream.listen((summary) {
      _firebaseService.addTremorSummary(summary);
      notifyListeners();
    });

    _repository.rawStream.listen((sample) {
      _rawFirestoreService.addSample(sample);
    });

    _repository.rawFifoStream.listen((packet) {
      _csvCaptureService.processPacket(packet);
    });

    _csvCaptureService.statusStream.listen((status) {
      _captureStatus = status;
      notifyListeners();
    });

    _repository.batteryStream.listen((raw) {
      _batteryRaw = raw;
      if (raw == TremorRepository.batteryEnteringCharge) {
        _logBleEvent("Reloj notificó 0xFF: entrando en modo carga");
      }
      notifyListeners();
    });

    FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
      if (BleService.isWatchName(event.device.platformName)) {
        _connectionState = event.connectionState;
        if (_connectionState == BluetoothConnectionState.disconnected) {
          _batteryRaw = null;
          if (_chargeMode || _enteringChargeMode) {
            _logBleEvent("Reloj apagado para modo carga (sin alerta de desconexión)");
          } else {
            _logBleEvent("Desconectado del reloj (ParkinsonWatch)");
          }
          _isStreaming = false;
          _lastStatus = null;
          _lastExt = null;
          _lastSev = null;
          _lastDiag = null;
          _analyzingStartTime = null;
          // NO se borran _ultimaClase, _ultimaFrecuencia, _ultimoAngulo, _ultimoConfirmado o _ultimaActualizacion
          // para mantener el último estado válido visible atenuado al 60%.
          _gyroFilter.reset();
          _accelFilter.reset();
        } else if (_connectionState == BluetoothConnectionState.connected) {
          _logBleEvent("Reconectado exitosamente al reloj (ParkinsonWatch)");
          _isStreaming = true;
          _lastStatus = null;
          _lastExt = null;
          _lastSev = null;
          _lastDiag = null;
          _analyzingStartTime = DateTime.now();
          resetSessionCounters();
        }
        notifyListeners();
      }
    });

    _initConnection();
  }

  Future<void> _initConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _bleService.preferredDeviceId = prefs.getString(_prefsPreferredWatch);
      _chargeDeviceId = prefs.getString(_prefsChargeDevice);
      if (_bleService.preferredDeviceId != null) {
        _logBleEvent("Reloj elegido: ${_bleService.preferredDeviceId}");
      }
      if (prefs.getBool(_prefsChargeMode) ?? false) {
        final startMs = prefs.getInt(_prefsChargeModeStart);
        _chargeMode = true;
        _chargeModeStart = startMs != null
            ? DateTime.fromMillisecondsSinceEpoch(startMs)
            : DateTime.now();
        _bleService.chargeMode = true;
        _isStreaming = false;
        _logBleEvent("Modo carga restaurado al iniciar la app");
        _startChargeModeTimers();
        notifyListeners();
        return;
      }
    } catch (e) {
      print("TremorProvider: Error leyendo modo carga: $e");
    }
    _bleService.startScanAndConnect();
  }

  // ================= MODO CARGA =================

  /// Cierra la sesión de monitoreo: guarda y sincroniza lo pendiente para que el
  /// tiempo de carga no cuente como monitoreado ni genere ventanas vacías.
  /// Guarda los bloques en el teléfono al instante y los sube a Firestore SIN
  /// bloquear (antes el modo carga esperaba a Firestore y, si tardaba, nunca
  /// llegaba a enviar 0xC0 mientras la reconexión seguía activa).
  Future<void> closeMonitoringSession() async {
    _isStreaming = false;
    _analyzingStartTime = null;
    try {
      await _saveBuckets();
    } catch (e) {
      print("TremorProvider: Error al guardar bloques: $e");
    }
    unawaited(uploadSummary().catchError((e) {
      print("TremorProvider: Error al subir bloques al cerrar sesión: $e");
    }));
    _logBleEvent("Sesión de monitoreo cerrada (bloques guardados; subida en segundo plano)");
  }

  /// true cuando el reloj está conectado Y la conexión terminó de armarse
  /// (se le pueden enviar órdenes como 0xC0).
  bool get watchReady =>
      _connectionState == BluetoothConnectionState.connected && _bleService.isReady;

  /// Devuelve null si entró en modo carga, o un mensaje de error para mostrar.
  Future<String?> enterChargeMode() async {
    if (_chargeMode || _enteringChargeMode) return null;
    if (!watchReady) {
      return 'El reloj todavía se está conectando. Espera unos segundos e inténtalo de nuevo.';
    }
    _enteringChargeMode = true;
    notifyListeners();
    final watchId = _bleService.connectedDevice?.remoteId.str;

    try {
      // 1. Bloquear la reconexión automática LO PRIMERO, antes de cualquier
      //    espera, para que una desconexión no dispare reconexiones.
      _bleService.chargeMode = true;

      // 2. Cerrar sesión de monitoreo (guarda local; sube en segundo plano)
      await closeMonitoringSession();

      // 3. Escuchar 0xFF antes de escribir para no perder la notificación
      final ackFuture = _repository.batteryStream
          .firstWhere((v) => v == TremorRepository.batteryEnteringCharge)
          .timeout(const Duration(seconds: 3));

      // 4. Escribir 0xC0 en la característica de control (7A9B0004)
      final sent = await _repository.sendChargeModeCommand();
      if (!sent) {
        // La orden no llegó al reloj: NO se entra en modo carga (el reloj
        // seguiría encendido y la app lo "encontraría" al minuto).
        ackFuture.ignore();
        _bleService.chargeMode = false;
        _isStreaming = true;
        _logBleEvent("No se pudo enviar 0xC0; no se entra en modo carga");
        if (_bleService.connectedDevice == null) {
          unawaited(_bleService.resumeNormalConnection());
        }
        return 'No se pudo enviar la orden al reloj. Verifica que esté cerca y conectado, e inténtalo de nuevo.';
      }

      // 5. Esperar 0xFF (timeout 3 s). Si llega o hay timeout, continuar igual.
      try {
        await ackFuture;
        _logBleEvent("Confirmación 0xFF recibida");
      } catch (_) {
        _logBleEvent("Sin confirmación 0xFF en 3 s; se continúa");
      }

      // 6. Persistir modo carga (y QUÉ reloj se puso a cargar)
      _chargeMode = true;
      _chargeModeStart = DateTime.now();
      _chargeDeviceId = watchId; // capturado antes: al apagarse ya no hay connectedDevice
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsChargeMode, true);
      await prefs.setInt(_prefsChargeModeStart, _chargeModeStart!.millisecondsSinceEpoch);
      if (_chargeDeviceId != null) {
        await prefs.setString(_prefsChargeDevice, _chargeDeviceId!);
      }

      // 7. Liberar la conexión sin disparar reconexión
      await _bleService.disconnectForChargeMode();
      _startChargeModeTimers();
      return null;
    } finally {
      _enteringChargeMode = false;
      notifyListeners();
    }
  }

  /// "Terminé de cargar": sale del modo carga y reactiva la conexión normal.
  Future<void> finishCharging() async {
    await _exitChargeMode();
    await _bleService.resumeNormalConnection();
  }

  Future<void> _exitChargeMode() async {
    _chargeProbeTimer?.cancel();
    _chargeTickTimer?.cancel();
    _chargeProbeTimer = null;
    _chargeTickTimer = null;
    _chargeMode = false;
    _chargeModeStart = null;
    _bleService.chargeMode = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsChargeMode);
      await prefs.remove(_prefsChargeModeStart);
      await prefs.remove(_prefsChargeDevice);
    } catch (_) {}
    _chargeDeviceId = null;
    _logBleEvent("Modo carga finalizado");
    notifyListeners();
  }

  void _startChargeModeTimers() {
    _chargeTickTimer?.cancel();
    _chargeTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_chargeMode) notifyListeners();
    });
    _chargeProbeTimer?.cancel();
    _chargeProbeTimer = Timer.periodic(const Duration(seconds: 60), (_) => _probeForWatch());
  }

  /// Escaneo corto (5 s). Si el reloj aparece, sale del modo carga y se reconecta;
  /// la reconexión reinicia los contadores e inicia una sesión nueva.
  Future<void> _probeForWatch() async {
    if (!_chargeMode || _probeInProgress) return;
    _probeInProgress = true;
    try {
      // Solo el reloj que se puso a cargar: otro reloj encendido cerca no
      // debe sacar a este del modo carga.
      final device = await _bleService.probeScanForWatch(
        timeout: const Duration(seconds: 5),
        onlyId: _chargeDeviceId ?? _bleService.preferredDeviceId,
      );
      if (device != null && _chargeMode) {
        _logBleEvent("Reloj detectado durante modo carga; reconectando");
        await _exitChargeMode();
        await _bleService.connectToDevice(device);
        if (_bleService.connectedDevice == null) {
          await _bleService.resumeNormalConnection();
        }
      }
    } finally {
      _probeInProgress = false;
    }
  }

  void resetSessionCounters() {
    _sessionSinTemblorCount = 0;
    _sessionLeveCount = 0;
    _sessionModeradoCount = 0;
    _sessionGraveCount = 0;
    _sessionVoluntarioCount = 0;
    _incoherenceCount = 0;
    _episodeCount = 0;
    _prevConfirmed = false;
  }

  /* 
   * LÓGICA ANTERIOR DE RECLASIFICACIÓN POR AMPLITUD (DESACTIVADA)
   * // reemplazado: la clase viene del reloj
   */

  Future<void> setRawCardVisibility(bool visible) async {
    _isRawCardVisible = visible;
    await _repository.sendRawControl(visible);
    notifyListeners();
  }

  void _recordDebugStatus(TremorStatus status) {
    // // reemplazado: la clase viene del reloj
    final record = DebugPacketRecord(
      tMs: status.tMs,
      tremorClass: status.isAnalyzing ? "ANALIZANDO" : status.tremorClass.nameEs,
      confirmed: status.tremorPresent,
      detected: status.detected,
      fHz: status.domFreq,
      ampDps: status.tremorAmp,
      movDps: status.movement,
      bandPct: status.bandFrac,
      dutyPct: status.duty,
      episodioS: status.episode,
      accelMg: _lastExt?.accelAmpMg,
      ratio: _lastExt?.ratio,
      angDeg: _lastExt?.angDeg,
      rotacional: _lastExt?.isRotational,
      ruta: _lastDiag?.ruta,
      votos: _lastDiag?.votos,
      activos: _lastDiag?.ejesActivos,
      compuerta: _lastDiag?.compuerta,
      lin: _lastDiag?.lin,
      prel3: _lastDiag?.prel3Pct,
      vol110: _lastDiag?.vol110Pct,
      sigmaMin: _lastDiag?.sigmaMin,
      rmsPc: _lastDiag?.rmsPc,
      isIncoherent: status.detected && status.tremorClass == TremorClass.voluntario,
      receivedAt: DateTime.now(),
    );

    _debugRecords.add(record);
    if (_debugRecords.length > maxDebugRecords) {
      _debugRecords.removeAt(0);
    }
  }

  void _recordDebugExt(TremorExt ext) {
    if (_debugRecords.isNotEmpty) {
      final last = _debugRecords.last;
      if (last.tMs == ext.tMs) {
        _debugRecords[_debugRecords.length - 1] = DebugPacketRecord(
          tMs: last.tMs,
          tremorClass: last.tremorClass,
          confirmed: last.confirmed,
          detected: last.detected,
          fHz: last.fHz,
          ampDps: last.ampDps,
          movDps: last.movDps,
          bandPct: last.bandPct,
          dutyPct: last.dutyPct,
          episodioS: last.episodioS,
          accelMg: ext.accelAmpMg,
          ratio: ext.ratio,
          angDeg: ext.angDeg,
          rotacional: ext.isRotational,
          ruta: last.ruta,
          votos: last.votos,
          activos: last.activos,
          compuerta: last.compuerta,
          lin: last.lin,
          prel3: last.prel3,
          vol110: last.vol110,
          sigmaMin: last.sigmaMin,
          rmsPc: last.rmsPc,
          isIncoherent: last.isIncoherent,
          receivedAt: last.receivedAt,
        );
      }
    }
  }

  void _recordDebugDiag(TremorDiag diag) {
    if (_debugRecords.isNotEmpty) {
      final last = _debugRecords.last;
      if (last.tMs == diag.tMs) {
        _debugRecords[_debugRecords.length - 1] = DebugPacketRecord(
          tMs: last.tMs,
          tremorClass: last.tremorClass,
          confirmed: last.confirmed,
          detected: last.detected,
          fHz: last.fHz,
          ampDps: last.ampDps,
          movDps: last.movDps,
          bandPct: last.bandPct,
          dutyPct: last.dutyPct,
          episodioS: last.episodioS,
          accelMg: last.accelMg,
          ratio: last.ratio,
          angDeg: last.angDeg,
          rotacional: diag.rotacional,
          ruta: diag.ruta,
          votos: diag.votos,
          activos: diag.ejesActivos,
          compuerta: diag.compuerta,
          lin: diag.lin,
          prel3: diag.prel3Pct,
          vol110: diag.vol110Pct,
          sigmaMin: diag.sigmaMin,
          rmsPc: diag.rmsPc,
          isIncoherent: last.isIncoherent,
          receivedAt: last.receivedAt,
        );
      }
    }
  }

  String exportDebugCsv() {
    final buffer = StringBuffer();
    buffer.writeln(
        't_ms,clase,confirmado,detectado,f_hz,amp_dps,mov_dps,band_pct,duty_pct,episodio_s,accel_mg,ratio,ang_deg,rotacional,ruta,votos,activos,compuerta,lin,prel3,vol110,sigma_min,rms_pc,incoherente');
    for (var r in _debugRecords) {
      buffer.writeln(r.toCsvLine());
    }
    return buffer.toString();
  }

  String exportRaw60sCsv() {
    final buffer = StringBuffer();
    buffer.writeln('t_ms,ax,ay,az,gx,gy,gz');
    for (var r in _raw60sBuffer) {
      buffer.writeln(
          '${r.tMs},${r.axG.toStringAsFixed(3)},${r.ayG.toStringAsFixed(3)},${r.azG.toStringAsFixed(3)},${r.gxDps.toStringAsFixed(1)},${r.gyDps.toStringAsFixed(1)},${r.gzDps.toStringAsFixed(1)}');
    }
    return buffer.toString();
  }

  String _getBucketId(DateTime dt) {
    final userId = _firebaseService.currentUserId ?? "anon";
    final dateStr = DateFormat('yyyy-MM-dd').format(dt);
    final minute = (dt.minute ~/ 5) * 5;
    return "${userId}_${dateStr}_${dt.hour}_$minute";
  }

  void _processStatusForBucket(TremorStatus status) {
    if (status.isAnalyzing) return; // NO guardar las ventanas ANALIZANDO como sin temblor
    final now = DateTime.now();
    final bucketId = _getBucketId(now);
    _buckets.putIfAbsent(bucketId, () => HourAccumulator(now));

    final acc = _buckets[bucketId]!;

    acc.totalSamples++;

    // // reemplazado: la clase viene del reloj
    final int classVal = status.tremorClass.index;
    if (classVal >= 1 && classVal <= 3) {
      acc.tremorSamples++;
      acc.sumIntensity += status.tremorAmp;
      if (status.tremorAmp > acc.maxIntensity) {
        acc.maxIntensity = status.tremorAmp;
      }
      if (status.domFreq > 0) {
        acc.sumDomFreq += status.domFreq;
        acc.domFreqCount++;
      }
    }

    final className = status.tremorClass.nameEs;
    acc.severityCounts[className] = (acc.severityCounts[className] ?? 0) + 1;

    _saveBuckets();
  }

  void _processExtForBucket(TremorExt ext) {
    final now = DateTime.now();
    final bucketId = _getBucketId(now);
    if (_buckets.containsKey(bucketId)) {
      final acc = _buckets[bucketId]!;
      // // reemplazado: la clase viene del reloj
      if (ext.tremorClass.index >= 1 && ext.tremorClass.index <= 3) {
        acc.sumAngleDeg += ext.angDeg;
        acc.angleCount++;
        if (ext.angDeg > acc.maxAngleDeg) {
          acc.maxAngleDeg = ext.angDeg;
        }
      }
    }
  }

  void _checkAutoUpload() {
    final now = DateTime.now();
    final currentBucketId = _getBucketId(now);

    bool hasFinishedBuckets = _buckets.keys.any((id) => id != currentBucketId);

    // Una sola subida a la vez: antes se lanzaba otra con cada STATUS (0,5 s)
    // mientras la anterior seguía esperando a Firestore.
    if (hasFinishedBuckets && !_uploadingSummary) {
      print("TremorProvider: Bloques terminados detectados. Subida automática...");
      uploadSummary();
    }
  }

  bool _uploadingSummary = false;

  Future<void> _loadBuckets() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('tremor_buckets');
    if (data != null) {
      final Map<String, dynamic> decoded = json.decode(data);
      _buckets = decoded.map(
          (key, value) => MapEntry(key, HourAccumulator.fromJson(value)));
    }
  }

  Future<void> _saveBuckets() async {
    final prefs = await SharedPreferences.getInstance();
    final data =
        json.encode(_buckets.map((key, value) => MapEntry(key, value.toJson())));
    await prefs.setString('tremor_buckets', data);
  }

  Future<void> uploadSummary() async {
    if (_uploadingSummary) return;
    _uploadingSummary = true;
    try {
      await _uploadSummaryInner();
    } finally {
      _uploadingSummary = false;
    }
  }

  Future<void> _uploadSummaryInner() async {
    final bucketIds = _buckets.keys.toList();
    for (var id in bucketIds) {
      final acc = _buckets[id]!;
      if (acc.totalSamples == 0) continue;

      final parts = id.split('_');
      final date = parts.length > 1
          ? parts[1]
          : DateFormat('yyyy-MM-dd').format(acc.startTime);
      final hour = parts.length > 2
          ? int.tryParse(parts[2]) ?? acc.startTime.hour
          : acc.startTime.hour;
      final minute = parts.length > 3
          ? int.tryParse(parts[3]) ?? ((acc.startTime.minute ~/ 5) * 5)
          : ((acc.startTime.minute ~/ 5) * 5);

      final summary = TremorSummary(
        id: id,
        startTime: acc.startTime,
        endTime: DateTime.now(),
        avgIntensity: acc.tremorSamples > 0 ? acc.sumIntensity / acc.tremorSamples : 0.0,
        maxIntensity: acc.maxIntensity,
        avgAngleDeg: acc.angleCount > 0 ? acc.sumAngleDeg / acc.angleCount : 0.0,
        maxAngleDeg: acc.maxAngleDeg,
        totalSamples: acc.totalSamples,
        tremorSamples: acc.tremorSamples,
        avgDomFreq: acc.domFreqCount > 0 ? acc.sumDomFreq / acc.domFreqCount : 0.0,
        severityCounts: acc.severityCounts,
        date: date,
        hour: hour,
        minute: minute,
        taxonomyVersion: 2,
      );

      // Firestore deja la escritura en su cola local aunque el servidor tarde en
      // confirmar; no se espera indefinidamente.
      try {
        await _firebaseService.addTremorSummary(summary).timeout(const Duration(seconds: 8));
      } on TimeoutException {
        print("TremorProvider: Firestore sin confirmación del bloque $id; queda en cola local.");
      }

      if (id != _getBucketId(DateTime.now())) {
        _buckets.remove(id);
      }
    }
    await _saveBuckets();
    notifyListeners();
  }

  Future<void> retryConnection() async {
    if (_chargeMode) return;
    await _bleService.startScanAndConnect();
  }

  Future<void> toggleStreaming() async {
    _isStreaming = !_isStreaming;
    await _repository.sendCommand(_isStreaming);
    if (!_isStreaming) {
      _lastSample = null;
      _lastStatus = null;
      _lastExt = null;
      _lastSev = null;
      _lastDiag = null;
      _analyzingStartTime = null;
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
    _timeoutCheckTimer?.cancel();
    _chargeProbeTimer?.cancel();
    _chargeTickTimer?.cancel();
    _repository.dispose();
    _rawFirestoreService.dispose();
    _csvCaptureService.dispose();
    super.dispose();
  }
}
