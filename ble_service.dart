// lib/services/ble_service.dart
//
// Handles BOTH roles:
//   PERIPHERAL  — one device advertises as BChat GATT server
//   CENTRAL     — the other scans and connects to the peripheral
//
// The app lets the user choose role on the connect screen.
// Protocol: newline-delimited JSON packets over BLE notify/write.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

// ─── UUIDs ────────────────────────────────────────────────────────────────
const kServiceUUID        = 'FFE0';
const kCharUUID           = 'FFE1';
const kServiceUUIDFull    = '0000FFE0-0000-1000-8000-00805F9B34FB';
const kCharUUIDFull       = '0000FFE1-0000-1000-8000-00805F9B34FB';

// ─── MTU chunk size (safe BLE minimum) ───────────────────────────────────
const kMTU = 20;

enum BleRole { none, peripheral, central }

class BleService {
  // Public state
  BleRole role = BleRole.none;
  bool get isConnected => _isConnected;
  Stream<String> get dataStream => _dataController.stream;
  Stream<String> get statusStream => _statusController.stream;

  // Internals
  bool _isConnected = false;
  String _rxBuffer = '';
  BluetoothDevice? _device;
  BluetoothCharacteristic? _char;

  final _dataController   = StreamController<String>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  // ── Permissions ─────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  PERIPHERAL ROLE  — this phone advertises a GATT server
  // ════════════════════════════════════════════════════════════════════════

  Future<void> startPeripheral() async {
    role = BleRole.peripheral;
    _status('Starting BLE peripheral…');

    await BlePeripheral.initialize();

    // Add service + characteristic
    await BlePeripheral.addService(
      BleService2(
        uuid: kServiceUUIDFull,
        primary: true,
        characteristics: [
          BleCharacteristic(
            uuid: kCharUUIDFull,
            properties: [
              CharacteristicProperties.notify,
              CharacteristicProperties.write,
              CharacteristicProperties.writeWithoutResponse,
            ],
            permissions: [
              AttributePermissions.readable,
              AttributePermissions.writeable,
            ],
            descriptors: [],
          ),
        ],
      ),
    );

    // Listen for writes from Central
    BlePeripheral.setDataReceivedCallback((deviceId, charUUID, value) {
      _isConnected = true;
      _onRawData(value);
    });

    // Listen for subscriptions (central subscribing to notify)
    BlePeripheral.setNotifySubscriptionCallback((deviceId, charUUID, status) {
      if (status) {
        _isConnected = true;
        _status('Central connected: $deviceId');
      } else {
        _isConnected = false;
        _status('Central disconnected.');
      }
    });

    // Start advertising
    await BlePeripheral.startAdvertising(
      services: [kServiceUUIDFull],
      localName: 'BChat',
    );

    _status('Advertising as "BChat"… waiting for peer.');
  }

  Future<void> stopPeripheral() async {
    await BlePeripheral.stopAdvertising();
    role = BleRole.none;
    _isConnected = false;
    _status('Peripheral stopped.');
  }

  /// Send data as Peripheral (notify the connected Central)
  Future<void> peripheralSend(String json) async {
    final bytes = Uint8List.fromList(utf8.encode('$json\n'));
    for (int i = 0; i < bytes.length; i += kMTU) {
      final chunk = bytes.sublist(i, (i + kMTU).clamp(0, bytes.length));
      await BlePeripheral.updateCharacteristic(
        serviceId: kServiceUUIDFull,
        characteristicId: kCharUUIDFull,
        value: chunk,
      );
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  CENTRAL ROLE  — this phone scans and connects
  // ════════════════════════════════════════════════════════════════════════

  Future<void> startScan() async {
    role = BleRole.central;
    _status('Scanning for BChat devices…');

    // Turn on Bluetooth if off
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }

    await FlutterBluePlus.startScan(
      withServices: [Guid(kServiceUUID)],
      timeout: const Duration(seconds: 15),
    );

    FlutterBluePlus.onScanResults.listen((results) async {
      if (results.isNotEmpty) {
        await FlutterBluePlus.stopScan();
        final result = results.first;
        _status('Found: ${result.device.platformName}. Connecting…');
        await _connectTo(result.device);
      }
    }, onError: (e) => _status('Scan error: $e'));
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false);

    device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _isConnected = false;
        _status('Disconnected from peer.');
      }
    });

    final services = await device.discoverServices();
    for (final svc in services) {
      if (svc.uuid.toString().toUpperCase().contains('FFE0')) {
        for (final chr in svc.characteristics) {
          if (chr.uuid.toString().toUpperCase().contains('FFE1')) {
            _char = chr;
            await chr.setNotifyValue(true);
            chr.onValueReceived.listen((bytes) => _onRawData(bytes));
            _isConnected = true;
            _status('Connected to ${device.platformName}!');
            return;
          }
        }
      }
    }
    _status('Connected but BChat service not found.');
  }

  /// Send data as Central (write to Peripheral's characteristic)
  Future<void> centralSend(String json) async {
    if (_char == null) return;
    final bytes = Uint8List.fromList(utf8.encode('$json\n'));
    for (int i = 0; i < bytes.length; i += kMTU) {
      final chunk = bytes.sublist(i, (i + kMTU).clamp(0, bytes.length));
      await _char!.write(chunk, withoutResponse: true);
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  // ── Unified send ────────────────────────────────────────────────────────

  Future<void> send(String json) async {
    if (role == BleRole.peripheral) {
      await peripheralSend(json);
    } else if (role == BleRole.central) {
      await centralSend(json);
    }
  }

  // ── RX handler ──────────────────────────────────────────────────────────

  void _onRawData(List<int> bytes) {
    _rxBuffer += utf8.decode(bytes, allowMalformed: true);
    final lines = _rxBuffer.split('\n');
    _rxBuffer = lines.removeLast(); // keep incomplete tail
    for (final line in lines) {
      final t = line.trim();
      if (t.isNotEmpty) _dataController.add(t);
    }
  }

  // ── Disconnect ──────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    if (role == BleRole.peripheral) {
      await stopPeripheral();
    } else {
      await _device?.disconnect();
    }
    role = BleRole.none;
    _isConnected = false;
    _char = null;
    _device = null;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  void _status(String msg) => _statusController.add(msg);

  void dispose() {
    _dataController.close();
    _statusController.close();
  }
}
