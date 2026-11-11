import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'tremor_repository.dart';
import '../models/device_info.dart';

class BleService {
  final TremorRepository repository;
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? _lastDevice;
  String? _lastDeviceId;

  BluetoothCharacteristic? _statusChar;
  DateTime? _lastStatusPacketTime;
  int _failedReadCount = 0;
  Timer? _fallbackReadTimer;

  StreamSubscription? _connectionSubscription;
  StreamSubscription? _lastSampleSub;
  StreamSubscription? _lastStatusSub;
  StreamSubscription? _lastExtSub;
  StreamSubscription? _lastSevSub;
  StreamSubscription? _lastDiagSub;
  StreamSubscription? _lastRawSub;
  StreamSubscription? _lastRawFifoSub;

  StreamSubscription? _lastBatterySub;

  bool _isConnecting = false;
  bool _isReconnecting = false;
  bool _userDisconnected = false;
  // Mientras sea true: sin reconexión automática ni escaneo normal.
  bool _chargeMode = false;
  bool _isProbeScanning = false;
  DeviceInfo? deviceInfo;

  BleService(this.repository);

  bool get chargeMode => _chargeMode;
  set chargeMode(bool value) {
    _chargeMode = value;
    if (value) _isReconnecting = false;
  }

  /// Corta la conexión al entrar en modo carga sin disparar reconexión.
  Future<void> disconnectForChargeMode() async {
    _chargeMode = true;
    _isReconnecting = false;
    final device = _connectedDevice;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    _cleanupConnection();
  }

  /// Escaneo corto buscando el reloj. Devuelve el dispositivo si lo encuentra.
  Future<BluetoothDevice?> probeScanForWatch({Duration timeout = const Duration(seconds: 5)}) async {
    if (_isProbeScanning || _isConnecting || _connectedDevice != null) return null;
    try {
      final adapter = await FlutterBluePlus.adapterState.first;
      if (adapter != BluetoothAdapterState.on) return null;
    } catch (_) {}

    _isProbeScanning = true;
    final completer = Completer<BluetoothDevice?>();
    StreamSubscription? sub;
    try {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}

      sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          String name = r.device.platformName;
          if (name.isEmpty) name = r.advertisementData.localName;
          if (name == "ParkinsonWatch" && !completer.isCompleted) {
            completer.complete(r.device);
            break;
          }
        }
      }, onError: (e) => print("BLE Probe Scan Error: $e"));

      await FlutterBluePlus.startScan(timeout: timeout, androidUsesFineLocation: true);
      final found = await completer.future.timeout(
        timeout + const Duration(milliseconds: 500),
        onTimeout: () => null,
      );
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      return found;
    } catch (e) {
      print("BLE: Error en escaneo corto: $e");
      return null;
    } finally {
      await sub?.cancel();
      _isProbeScanning = false;
    }
  }

  /// Sale del modo carga y reactiva la conexión normal (reconexión automática si
  /// se conoce el último reloj; si no, escaneo normal).
  Future<void> resumeNormalConnection() async {
    _chargeMode = false;
    _userDisconnected = false;
    if (_connectedDevice != null) return;
    if (_lastDevice != null || (_lastDeviceId != null && _lastDeviceId!.isNotEmpty)) {
      _startAutoReconnect();
    } else {
      await startScanAndConnect();
    }
  }

  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get lastDeviceId => _lastDeviceId;
  bool get userDisconnected => _userDisconnected;
  bool get isReconnecting => _isReconnecting;
  bool get isConnecting => _isConnecting;

  Future<void> disconnectManual() async {
    print("BLE: Desconexión manual iniciada por el usuario.");
    _userDisconnected = true;
    _isReconnecting = false;
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
    }
    _cleanupConnection();
  }

  Future<bool> subscribeWithRetry(BluetoothCharacteristic char, {int maxRetries = 3}) async {
    for (int i = 1; i <= maxRetries; i++) {
      try {
        await char.setNotifyValue(true);
        return true;
      } catch (e) {
        print("BLE: Error al suscribir a ${char.uuid} (intento $i/$maxRetries): $e");
        if (i < maxRetries) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    return false;
  }

  Future<void> startScanAndConnect() async {
    if (_connectedDevice != null || _isConnecting || _chargeMode) return;
    _userDisconnected = false;
    
    _isConnecting = true;
    print("BLE: Iniciando escaneo...");
    
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    var subscription = FlutterBluePlus.onScanResults.listen((results) async {
      for (ScanResult r in results) {
        String name = r.device.platformName;
        if (name.isEmpty) name = r.advertisementData.localName;
        
        if (name == "ParkinsonWatch") {
          print("BLE: ¡Dispositivo encontrado! ($name)");
          await FlutterBluePlus.stopScan();
          await connectToDevice(r.device);
          break;
        }
      }
    }, onError: (e) => print("BLE Scan Error: $e"));

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      print("BLE: Error al iniciar escaneo: $e");
      _isConnecting = false;
    }
    
    Future.delayed(const Duration(seconds: 16), () {
      subscription.cancel();
      _isConnecting = false;
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_connectedDevice != null && _connectedDevice!.remoteId == device.remoteId) return;

    _userDisconnected = false;
    _isConnecting = true;
    _lastDevice = device;
    _lastDeviceId = device.remoteId.str;

    try {
      print("BLE: Conectando a ${device.platformName} (${device.remoteId.str})...");
      await device.connect(autoConnect: false);
      _connectedDevice = device;
      _isConnecting = false;

      // 1. Pedir MTU 247
      try {
        await device.requestMtu(247);
        print("BLE: MTU 247 solicitado.");
      } catch (e) {
        print("BLE: Error MTU: $e");
      }

      // 2. En Android pedir prioridad de conexión alta
      try {
        await device.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
        print("BLE: Connection Priority High solicitada.");
      } catch (e) {
        print("BLE: Error Connection Priority: $e");
      }

      // 3. Suscripción a eventos de desconexión
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("BLE: Desconectado de ${device.platformName}.");
          _cleanupConnection();
          if (!_userDisconnected && !_chargeMode) {
            _startAutoReconnect();
          }
        }
      });

      print("BLE: Descubriendo servicios...");
      List<BluetoothService> services = await device.discoverServices();
      
      BluetoothCharacteristic? cmdChar;
      BluetoothCharacteristic? rawFifoChar;

      for (var service in services) {
        if (service.uuid.toString().toUpperCase() == TremorRepository.serviceUuid) {
          for (var char in service.characteristics) {
            final uuid = char.uuid.toString().toUpperCase();
            if (uuid == TremorRepository.sampleCharUuid) {
              await subscribeWithRetry(char);
              _lastSampleSub = char.onValueReceived.listen((value) => repository.decodeSample(value));
            } else if (uuid == TremorRepository.statusCharUuid) {
              _statusChar = char;
              final ok = await subscribeWithRetry(char);
              if (ok) {
                print("STATUS suscrito");
              }
              _lastStatusSub = char.onValueReceived.listen((value) {
                _onStatusPacketReceived(value);
              });
            } else if (uuid == TremorRepository.extCharUuid) {
              await subscribeWithRetry(char);
              _lastExtSub = char.onValueReceived.listen((value) => repository.decodeExt(value));
            } else if (uuid == TremorRepository.sevCharUuid) {
              try {
                await subscribeWithRetry(char);
                _lastSevSub = char.onValueReceived.listen((value) => repository.decodeSev(value));
              } catch (e) {
                print("BLE: Opcional SEV no disponible: $e");
              }
            } else if (uuid == TremorRepository.batteryCharUuid) {
              // 7A9B0009: batería (1 byte). Si un firmware anterior manda DIAG (16 bytes), se decodifica como DIAG.
              try {
                _lastBatterySub = char.onValueReceived.listen((value) => repository.decodeBatteryOrDiag(value));
                final ok = await subscribeWithRetry(char);
                if (ok) print("BATERIA (7A9B0009) suscrita");
                if (char.properties.read) {
                  final initial = await char.read();
                  repository.decodeBatteryOrDiag(initial);
                }
              } catch (e) {
                print("BLE: Característica de batería no disponible: $e");
              }
            } else if (uuid == TremorRepository.summaryCharUuid) {
              await subscribeWithRetry(char);
              char.onValueReceived.listen((value) async {
                repository.decodeSummary(value, "actual_user");
                if (value.length >= 2) {
                  int seq = value[0] | (value[1] << 8);
                  await repository.sendSummaryAck(seq);
                }
              });
            } else if (uuid == TremorRepository.rawCharUuid) {
              await subscribeWithRetry(char);
              _lastRawSub = char.onValueReceived.listen((value) => repository.decodeRawImu(value));
            } else if (uuid == TremorRepository.rawFifoCharUuid) {
              rawFifoChar = char;
            } else if (uuid == TremorRepository.cmdCharUuid) {
              cmdChar = char;
              repository.setCmdCharacteristic(char);
            }
          }
        }
      }

      if (cmdChar != null) {
        await subscribeWithRetry(cmdChar);
        cmdChar.onValueReceived.listen((value) {
          final text = utf8.decode(value, allowMalformed: true);
          if (text.startsWith("FW=")) {
            deviceInfo = DeviceInfo.parse(text);
            print("BLE: INFO Recibida: $deviceInfo");
            if (rawFifoChar != null) {
              _subscribeToRawFifo(rawFifoChar);
            }
          }
        });

        Future.delayed(const Duration(seconds: 1), () {
          repository.sendTimeSync();
          repository.sendInfoRequest();
        });
      }
      
      print("BLE: Suscripciones iniciales completadas.");
      _startFallbackReadCheck();
    } catch (e) {
      print("BLE Connection Error: $e");
      _isConnecting = false;
    }
  }

  void _onStatusPacketReceived(List<int> value) {
    _lastStatusPacketTime = DateTime.now();
    _failedReadCount = 0; // Exitoso, reseteamos fallos
    repository.decodeStatus(value);
  }

  void _startFallbackReadCheck() {
    _fallbackReadTimer?.cancel();
    _fallbackReadTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_connectedDevice == null || _statusChar == null) return;

      final now = DateTime.now();
      final secondsSinceLastStatus = _lastStatusPacketTime == null
          ? 0
          : now.difference(_lastStatusPacketTime!).inSeconds;

      // Si estando CONECTADO pasan 2 s sin recibir notificación de STATUS, hacer READ cada 2 s
      if (secondsSinceLastStatus >= 2 && now.millisecond % 2000 < 1000) {
        print("BLE: Hace $secondsSinceLastStatus s sin STATUS. Ejecutando READ de respaldo...");
        try {
          final value = await _statusChar!.read();
          if (value.isNotEmpty) {
            _onStatusPacketReceived(value);
          } else {
            _failedReadCount++;
            print("BLE: READ de STATUS devolvió bytes vacíos (fallo $_failedReadCount/3).");
          }
        } catch (e) {
          _failedReadCount++;
          print("BLE: READ de STATUS falló ($e) (fallo $_failedReadCount/3).");
        }

        // Si 3 lecturas seguidas fallan, volver a suscribirse (paso 2)
        if (_failedReadCount >= 3) {
          print("BLE: 3 lecturas seguidas fallaron. Re-suscribiendo a STATUS...");
          _failedReadCount = 0;
          await _resubscribeStatus();
        }
      }
    });
  }

  Future<void> _resubscribeStatus() async {
    if (_statusChar == null) return;
    try {
      await _statusChar!.setNotifyValue(false);
    } catch (_) {}
    final ok = await subscribeWithRetry(_statusChar!);
    if (ok) {
      print("STATUS suscrito");
    }
  }

  Future<void> _startAutoReconnect() async {
    if (_userDisconnected || _chargeMode || _isReconnecting || _connectedDevice != null) return;
    _isReconnecting = true;

    final backoffSteps = [1, 2, 4];
    int stepIndex = 0;

    print("BLE: Iniciando reconexión automática para $_lastDeviceId...");

    while (!_userDisconnected && !_chargeMode && _connectedDevice == null) {
      final delaySec = stepIndex < backoffSteps.length ? backoffSteps[stepIndex] : 5;
      stepIndex++;

      print("BLE: Reintentando conexión en $delaySec s (intento $stepIndex)...");
      await Future.delayed(Duration(seconds: delaySec));

      if (_userDisconnected || _chargeMode || _connectedDevice != null) break;

      try {
        final adapter = await FlutterBluePlus.adapterState.first;
        if (adapter != BluetoothAdapterState.on) {
          print("BLE: Adaptador Bluetooth apagado. Esperando...");
          continue;
        }
      } catch (_) {}

      if (_lastDevice != null) {
        try {
          await connectToDevice(_lastDevice!);
          if (_connectedDevice != null) break;
        } catch (e) {
          print("BLE: Reintento directo falló: $e");
        }
      } else if (_lastDeviceId != null && _lastDeviceId!.isNotEmpty) {
        try {
          final device = BluetoothDevice.fromId(_lastDeviceId!);
          await connectToDevice(device);
          if (_connectedDevice != null) break;
        } catch (e) {
          print("BLE: Reintento por ID falló: $e");
        }
      }
    }

    _isReconnecting = false;
  }

  Future<void> _subscribeToRawFifo(BluetoothCharacteristic char) async {
    print("BLE: Suscribiendo a RAWFIFO...");
    await subscribeWithRetry(char);
    _lastRawFifoSub = char.onValueReceived.listen((value) {
      repository.decodeRawFifo(value);
    });
  }

  void _cleanupConnection() {
    _fallbackReadTimer?.cancel();
    _connectionSubscription?.cancel();
    _lastSampleSub?.cancel();
    _lastStatusSub?.cancel();
    _lastExtSub?.cancel();
    _lastSevSub?.cancel();
    _lastDiagSub?.cancel();
    _lastRawSub?.cancel();
    _lastRawFifoSub?.cancel();
    _lastBatterySub?.cancel();
    _statusChar = null;
    _connectedDevice = null;
    _isConnecting = false;
  }

  void dispose() {
    _cleanupConnection();
  }
}
