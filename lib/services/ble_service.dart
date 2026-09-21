import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'tremor_repository.dart';
import 'firestore_raw_service.dart';
import '../models/device_info.dart';
import '../models/ble_device_data.dart';

class BleService {
  final TremorRepository repository;
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _lastSampleSub;
  StreamSubscription? _lastStatusSub;
  StreamSubscription? _lastRawSub;
  StreamSubscription? _lastRawFifoSub;

  bool _isConnecting = false;
  DeviceInfo? deviceInfo;

  BleService(this.repository);

  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  Future<void> startScanAndConnect() async {
    if (_connectedDevice != null) return;
    
    _isConnecting = true;
    print("BLE: Iniciando escaneo...");
    
    // Detener cualquier escaneo previo
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    // Configurar escaneo
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
    
    // Cleanup scan sub after timeout
    Future.delayed(const Duration(seconds: 16), () {
      subscription.cancel();
      _isConnecting = false;
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      print("BLE: Conectando a ${device.platformName}...");
      await device.connect(autoConnect: false);
      _connectedDevice = device;

      // Solicitar MTU alto inmediatamente
      try {
        await device.requestMtu(512);
      } catch (e) {
        print("BLE: Error MTU: $e");
      }

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("BLE: Desconectado. Intentando reconectar...");
          _cleanupConnection();
          startScanAndConnect();
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
              await char.setNotifyValue(true);
              _lastSampleSub = char.onValueReceived.listen((value) => repository.decodeSample(value));
            } else if (uuid == TremorRepository.statusCharUuid) {
              await char.setNotifyValue(true);
              _lastStatusSub = char.onValueReceived.listen((value) => repository.decodeStatus(value));
            } else if (uuid == TremorRepository.summaryCharUuid) {
              await char.setNotifyValue(true);
              char.onValueReceived.listen((value) async {
                repository.decodeSummary(value, "actual_user");
                if (value.length >= 2) {
                  int seq = value[0] | (value[1] << 8);
                  await repository.sendSummaryAck(seq);
                }
              });
            } else if (uuid == TremorRepository.rawCharUuid) {
              await char.setNotifyValue(true);
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
        await cmdChar.setNotifyValue(true);
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
    } catch (e) {
      print("BLE Connection Error: $e");
      _isConnecting = false;
    }
  }

  Future<void> _subscribeToRawFifo(BluetoothCharacteristic char) async {
    print("BLE: Suscribiendo a RAWFIFO...");
    await char.setNotifyValue(true);
    _lastRawFifoSub = char.onValueReceived.listen((value) {
      repository.decodeRawFifo(value);
    });
  }

  void _cleanupConnection() {
    _connectionSubscription?.cancel();
    _lastSampleSub?.cancel();
    _lastStatusSub?.cancel();
    _lastRawSub?.cancel();
    _lastRawFifoSub?.cancel();
    _connectedDevice = null;
    _isConnecting = false;
  }

  void dispose() {
    _cleanupConnection();
  }
}
