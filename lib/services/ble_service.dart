import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'tremor_repository.dart';
import '../models/device_info.dart';

/// Reloj encontrado en un escaneo (para el selector de reloj).
class WatchCandidate {
  final String id; // remoteId (MAC en Android)
  final String name;
  final int rssi;
  final bool isConnected;

  const WatchCandidate({
    required this.id,
    required this.name,
    required this.rssi,
    this.isConnected = false,
  });

  /// Últimos 5 caracteres de la MAC (p. ej. "C7:EE") para distinguir relojes.
  String get shortId => id.length >= 5 ? id.substring(id.length - 5) : id;
}

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
  StreamSubscription? _lastSummarySub;
  StreamSubscription? _lastCmdSub;

  /// true cuando la conexión terminó de armarse (servicios descubiertos y
  /// característica de control lista). Antes de eso no se pueden enviar órdenes.
  bool _setupComplete = false;
  bool get isReady => _connectedDevice != null && _setupComplete;

  bool _isConnecting = false;
  bool _isReconnecting = false;
  bool _userDisconnected = false;
  // Mientras sea true: sin reconexión automática ni escaneo normal.
  bool _chargeMode = false;
  bool _isProbeScanning = false;
  DeviceInfo? deviceInfo;

  BleService(this.repository);

  /// Reloj elegido por el usuario (remoteId). Si es null, se conecta al primer
  /// "ParkinsonWatch" que encuentre (comportamiento anterior).
  String? preferredDeviceId;

  /// Acepta "ParkinsonWatch" y variantes con sufijo (p. ej. "ParkinsonWatch-A").
  static bool isWatchName(String name) => name.startsWith('ParkinsonWatch');

  static String _nameOf(ScanResult r) {
    final name = r.device.platformName;
    return name.isNotEmpty ? name : r.advertisementData.localName;
  }

  /// ¿Este resultado es el reloj al que debemos conectarnos?
  bool _isTargetWatch(ScanResult r, {String? onlyId}) {
    if (!isWatchName(_nameOf(r))) return false;
    final id = onlyId ?? preferredDeviceId;
    return id == null || r.device.remoteId.str == id;
  }

  /// Escanea y devuelve TODOS los relojes cercanos (sin conectarse).
  Future<List<WatchCandidate>> scanWatches({Duration timeout = const Duration(seconds: 6)}) async {
    final found = <String, WatchCandidate>{};
    final connected = _connectedDevice;
    if (connected != null) {
      found[connected.remoteId.str] = WatchCandidate(
        id: connected.remoteId.str,
        name: connected.platformName.isNotEmpty ? connected.platformName : 'ParkinsonWatch',
        rssi: 0,
        isConnected: true,
      );
    }
    if (_isConnecting || _isProbeScanning) return found.values.toList();

    try {
      final adapter = await FlutterBluePlus.adapterState.first;
      if (adapter != BluetoothAdapterState.on) return found.values.toList();
    } catch (_) {}

    _isProbeScanning = true;
    StreamSubscription? sub;
    try {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final name = _nameOf(r);
          final id = r.device.remoteId.str;
          if (!isWatchName(name) || found[id]?.isConnected == true) continue;
          found[id] = WatchCandidate(id: id, name: name, rssi: r.rssi);
        }
      }, onError: (e) => print("BLE Scan (selector) Error: $e"));
      await FlutterBluePlus.startScan(timeout: timeout, androidUsesFineLocation: true);
      await FlutterBluePlus.isScanning.where((s) => s == false).first
          .timeout(timeout + const Duration(seconds: 2), onTimeout: () => false);
    } catch (e) {
      print("BLE: Error en escaneo del selector: $e");
    } finally {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await sub?.cancel();
      _isProbeScanning = false;
    }

    final list = found.values.toList()
      ..sort((a, b) {
        if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });
    print("BLE: Relojes encontrados: ${list.map((w) => '${w.name} ${w.shortId} (${w.rssi} dBm)').join(', ')}");
    return list;
  }

  /// Cambia al reloj [id]: desconecta el actual (sin reconexión automática) y
  /// se conecta al nuevo.
  Future<void> switchToDevice(String id) async {
    preferredDeviceId = id;
    final current = _connectedDevice;
    if (current != null && current.remoteId.str == id) return;
    if (current != null) {
      _userDisconnected = true; // evita que la reconexión vuelva al reloj viejo
      _isReconnecting = false;
      try {
        await current.disconnect();
      } catch (_) {}
      _cleanupConnection();
      await Future.delayed(const Duration(milliseconds: 600));
    }
    _userDisconnected = false;
    _lastDevice = null;
    _lastDeviceId = id;
    print("BLE: Cambiando al reloj $id...");
    await connectToDevice(BluetoothDevice.fromId(id));
    if (_connectedDevice == null) {
      // No respondió de inmediato: queda la reconexión automática a ESTE reloj.
      _startAutoReconnect();
    }
  }

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
  /// Con [onlyId] solo acepta ESE reloj (el que se puso a cargar), para no
  /// confundirlo con otro reloj encendido cerca.
  Future<BluetoothDevice?> probeScanForWatch({
    Duration timeout = const Duration(seconds: 5),
    String? onlyId,
  }) async {
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
          if (_isTargetWatch(r, onlyId: onlyId) && !completer.isCompleted) {
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

    var handled = false;
    var subscription = FlutterBluePlus.onScanResults.listen((results) async {
      for (ScanResult r in results) {
        // Con reloj elegido, solo ese; si no, el primer "ParkinsonWatch".
        if (!handled && _isTargetWatch(r)) {
          handled = true;
          print("BLE: ¡Dispositivo encontrado! (${_nameOf(r)} ${r.device.remoteId.str})");
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
      // mtu: null -> flutter_blue_plus NO pide su MTU automático de 512 al
      // conectar. Esa negociación extra (además de la de 247) hacía que el
      // ESP32-C6 dejara de responder y la conexión cayera a los ~5 s
      // (GATT_CONN_TIMEOUT, status 8).
      await device.connect(autoConnect: false, mtu: null);
      _connectedDevice = device;
      _isConnecting = false;

      // Suscripción a eventos de desconexión ANTES de negociar: si el reloj se
      // cae durante el MTU, se limpia y se reintenta (antes quedaba "conectado").
      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("BLE: Desconectado de ${device.platformName}.");
          _cleanupConnection();
          if (!_userDisconnected && !_chargeMode) {
            _startAutoReconnect();
          }
        }
      });

      // Pequeña pausa para que el enlace se estabilice antes de negociar.
      await Future.delayed(const Duration(milliseconds: 400));

      // 1. En Android pedir prioridad de conexión alta (antes del MTU)
      try {
        await device.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
        print("BLE: Connection Priority High solicitada.");
      } catch (e) {
        print("BLE: Error Connection Priority: $e");
      }

      // 2. Una sola negociación de MTU (247). Si falla, se sigue con el MTU
      //    por defecto: no debe tumbar la conexión.
      try {
        final mtu = await device.requestMtu(247, timeout: 5);
        print("BLE: MTU negociado: $mtu");
      } catch (e) {
        print("BLE: Error MTU (se continúa con el MTU por defecto): $e");
      }
      if (_connectedDevice == null || !device.isConnected) {
        throw StateError('El reloj se desconectó durante la negociación inicial');
      }

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
              // Se guarda para cancelarlo al desconectar: flutter_blue_plus
              // entrega los valores por UUID, así que un oyente viejo seguía
              // recibiendo (y respondiendo ACK) en cada reconexión.
              await _lastSummarySub?.cancel();
              _lastSummarySub = char.onValueReceived.listen((value) async {
                repository.decodeSummary(value, "actual_user");
                if (value.length >= 2) {
                  int seq = value[0] | (value[1] << 8);
                  try {
                    await repository.sendSummaryAck(seq);
                  } catch (e) {
                    print("BLE: ACK de resumen no enviado: $e");
                  }
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
        await _lastCmdSub?.cancel();
        _lastCmdSub = cmdChar.onValueReceived.listen((value) {
          final text = utf8.decode(value, allowMalformed: true);
          if (text.startsWith("FW=")) {
            deviceInfo = DeviceInfo.parse(text);
            print("BLE: INFO Recibida: $deviceInfo");
            if (rawFifoChar != null) {
              _subscribeToRawFifo(rawFifoChar);
            }
          }
        });

        final connectedAt = _connectedDevice;
        Future.delayed(const Duration(seconds: 1), () async {
          // Si en ese segundo se desconectó, no se escribe (evita GATT_ERROR).
          if (_connectedDevice == null || _connectedDevice != connectedAt) return;
          try {
            await repository.sendTimeSync();
            await repository.sendInfoRequest();
          } catch (e) {
            print("BLE: Sincronización de hora/INFO no enviada: $e");
          }
        });
      }
      
      print("BLE: Suscripciones iniciales completadas.");
      _setupComplete = _connectedDevice != null && repository.hasCmdCharacteristic;
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
    await _lastRawFifoSub?.cancel(); // un solo oyente aunque llegue INFO varias veces
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
    _lastSummarySub?.cancel();
    _lastCmdSub?.cancel();
    _lastSummarySub = null;
    _lastCmdSub = null;
    _lastRawFifoSub = null;
    _setupComplete = false;
    repository.clearCmdCharacteristic();
    _statusChar = null;
    _connectedDevice = null;
    _isConnecting = false;
  }

  void dispose() {
    _cleanupConnection();
  }
}
