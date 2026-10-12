import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models.dart';

enum Obd2ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class Obd2BluetoothDevice {
  final String name;
  final String address;
  final bool isBonded;

  const Obd2BluetoothDevice({
    required this.name,
    required this.address,
    required this.isBonded,
  });
}

class Obd2Service extends ChangeNotifier {
  Obd2ConnectionState _connectionState = Obd2ConnectionState.disconnected;
  String? _connectedDeviceName;
  String? _connectedDeviceAddress;
  String _statusMessage = 'Disconnected';
  bool _isDemoMode = false;
  bool _isScanningDtc = false;

  // Active DTC trouble codes
  List<String> _currentDtcCodes = [];

  // Current Live Telemetry
  Obd2Telemetry _currentTelemetry = Obd2Telemetry(timestamp: DateTime.now());

  // Bluetooth Hardware
  final FlutterClassicBluetooth _bluetooth = FlutterClassicBluetooth();
  BtcConnection? _connection;
  StreamSubscription<Uint8List>? _dataSubscription;
  final StringBuffer _receiveBuffer = StringBuffer();
  Completer<String>? _pendingCommandCompleter;
  Timer? _telemetryPollingTimer;

  // Demo mode simulation timer & state
  Timer? _demoTimer;
  double _simRpm = 850.0;
  double _simSpeedMph = 0.0;
  double _simCoolantTempF = 185.0;
  double _simIatF = 82.0;
  double _simEngineLoad = 18.0;
  double _simThrottle = 12.0;
  double _simVoltage = 14.2;
  double _simMaf = 4.5;
  int _simGear = 1;
  bool _simAccelerating = true;

  // Data Logger
  bool _isLogging = false;
  Obd2LogSession? _activeLogSession;
  final List<Obd2Telemetry> _loggedDataPoints = [];
  Timer? _loggingStatsTimer;

  // Getters
  Obd2ConnectionState get connectionState => _connectionState;
  bool get isConnected =>
      _connectionState == Obd2ConnectionState.connected || _isDemoMode;
  bool get isDemoMode => _isDemoMode;
  bool get isScanningDtc => _isScanningDtc;
  bool get isLogging => _isLogging;
  String? get connectedDeviceName =>
      _isDemoMode ? 'Simulated OBD2 (ELM327 v1.5)' : _connectedDeviceName;
  String? get connectedDeviceAddress =>
      _isDemoMode ? 'SIM:00:11:22:33:44' : _connectedDeviceAddress;
  String get statusMessage => _statusMessage;
  List<String> get currentDtcCodes => List.unmodifiable(_currentDtcCodes);
  Obd2Telemetry get currentTelemetry => _currentTelemetry;
  Obd2LogSession? get activeLogSession => _activeLogSession;
  int get loggedSampleCount => _loggedDataPoints.length;

  // -------------------------------------------------------------
  // PERMISSIONS & DEVICE SCANNING
  // -------------------------------------------------------------

  Future<bool> requestPermissions() async {
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      final allGranted = statuses.values.every(
        (status) => status.isGranted || status.isLimited,
      );
      return allGranted;
    } catch (_) {
      return true; // Fallback for various Android flavors
    }
  }

  Future<List<Obd2BluetoothDevice>> getPairedDevices() async {
    try {
      await requestPermissions();
      final bonded = await _bluetooth.getPairedDevices();
      return bonded
          .map((d) => Obd2BluetoothDevice(
                name: d.name ?? d.address,
                address: d.address,
                isBonded: true,
              ))
          .toList();
    } catch (e) {
      debugPrint('Error getting bonded devices: $e');
      return [];
    }
  }

  Stream<Obd2BluetoothDevice> scanForDevices() async* {
    await requestPermissions();
    try {
      await _bluetooth.startDiscovery();
      await for (final result in _bluetooth.discoveryResults) {
        yield Obd2BluetoothDevice(
          name: result.name ?? result.address,
          address: result.address,
          isBonded: false,
        );
      }
    } catch (e) {
      debugPrint('Error discovering devices: $e');
    }
  }

  // -------------------------------------------------------------
  // CONNECTION MANAGEMENT
  // -------------------------------------------------------------

  Future<bool> connectToDevice(Obd2BluetoothDevice device) async {
    if (_isDemoMode) {
      stopDemoMode();
    }

    _setConnectionState(
      Obd2ConnectionState.connecting,
      'Connecting to ${device.name}...',
    );
    _connectedDeviceName = device.name;
    _connectedDeviceAddress = device.address;

    try {
      await _cleanupConnection();

      // Standard Serial Port Profile (SPP / RFCOMM) UUID
      const sppUuid = '00001101-0000-1000-8000-00805F9B34FB';
      _connection = await _bluetooth
          .connect(address: device.address, uuid: sppUuid)
          .timeout(const Duration(seconds: 12));

      _dataSubscription = _connection!.input.listen(
        _handleIncomingData,
        onDone: () => _handleDisconnected('Device disconnected'),
        onError: (e) => _handleDisconnected('Connection error: $e'),
      );

      _setConnectionState(
        Obd2ConnectionState.connecting,
        'Initializing ELM327 protocol...',
      );

      final initSuccess = await _initializeElm327();
      if (!initSuccess) {
        _setConnectionState(
          Obd2ConnectionState.error,
          'ELM327 handshake failed. Check car ignition (ON position).',
        );
        return false;
      }

      _setConnectionState(
        Obd2ConnectionState.connected,
        'Connected to ${device.name}',
      );

      // Start continuous telemetry polling
      _startTelemetryPolling();
      return true;
    } catch (e) {
      _setConnectionState(
        Obd2ConnectionState.error,
        'Failed to connect: $e',
      );
      return false;
    }
  }

  Future<void> disconnect() async {
    _stopTelemetryPolling();
    if (_isLogging) {
      stopLogging();
    }
    if (_isDemoMode) {
      stopDemoMode();
    }
    await _cleanupConnection();
    _setConnectionState(Obd2ConnectionState.disconnected, 'Disconnected');
  }

  Future<void> _cleanupConnection() async {
    try {
      await _dataSubscription?.cancel();
      _dataSubscription = null;
      await _connection?.close();
      _connection = null;
    } catch (_) {}
  }

  void _handleDisconnected(String message) {
    _stopTelemetryPolling();
    _cleanupConnection();
    _setConnectionState(Obd2ConnectionState.disconnected, message);
  }

  void _setConnectionState(Obd2ConnectionState state, String message) {
    _connectionState = state;
    _statusMessage = message;
    notifyListeners();
  }

  // -------------------------------------------------------------
  // ELM327 PROTOCOL & SERIAL COMMUNICATION
  // -------------------------------------------------------------

  void _handleIncomingData(Uint8List data) {
    final text = ascii.decode(data, allowInvalid: true);
    _receiveBuffer.write(text);

    // ELM327 indicates response completion with prompt '>'
    if (_receiveBuffer.toString().contains('>')) {
      final fullResponse = _receiveBuffer.toString();
      _receiveBuffer.clear();

      if (_pendingCommandCompleter != null &&
          !_pendingCommandCompleter!.isCompleted) {
        _pendingCommandCompleter!.complete(fullResponse);
      }
    }
  }

  Future<String> sendCommand(String cmd, {Duration timeout = const Duration(seconds: 4)}) async {
    if (_isDemoMode) {
      return _simulateCommandResponse(cmd);
    }

    if (_connection == null || !_connection!.isConnected) {
      throw Exception('OBD2 adapter is not connected');
    }

    // Prepare fresh completer
    _receiveBuffer.clear();
    _pendingCommandCompleter = Completer<String>();

    final formattedCmd = '${cmd.trim()}\r';
    await _connection!.output
        .add(Uint8List.fromList(ascii.encode(formattedCmd)));

    try {
      final response = await _pendingCommandCompleter!.future.timeout(timeout);
      return _cleanResponse(response);
    } catch (e) {
      _receiveBuffer.clear();
      throw TimeoutException('Command $cmd timed out');
    }
  }

  String _cleanResponse(String raw) {
    // Strip echo, newlines, prompt '>' and spaces
    return raw
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('>', '')
        .replaceAll('SEARCHING...', '')
        .replaceAll('BUS INIT: OK', '')
        .replaceAll('STOPPED', '')
        .trim();
  }

  Future<bool> _initializeElm327() async {
    try {
      // 1. Reset ELM327
      await Future.delayed(const Duration(milliseconds: 300));
      await sendCommand('AT Z', timeout: const Duration(seconds: 3));
      await Future.delayed(const Duration(milliseconds: 300));

      // 2. Turn echo off
      await sendCommand('AT E0');

      // 3. Turn linefeeds off
      await sendCommand('AT L0');

      // 4. Turn spaces off (for faster & consistent parsing)
      await sendCommand('AT S0');

      // 5. Turn headers off
      await sendCommand('AT H0');

      // 6. Set protocol to Auto
      await sendCommand('AT SP 0');

      return true;
    } catch (e) {
      debugPrint('ELM327 init error: $e');
      return false;
    }
  }

  // -------------------------------------------------------------
  // TELEMETRY POLLING LOOP
  // -------------------------------------------------------------

  void _startTelemetryPolling() {
    _telemetryPollingTimer?.cancel();
    _telemetryPollingTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _pollTelemetryCycle(),
    );
  }

  void _stopTelemetryPolling() {
    _telemetryPollingTimer?.cancel();
    _telemetryPollingTimer = null;
  }

  Future<void> _pollTelemetryCycle() async {
    if (_connection == null || !_connection!.isConnected) return;

    try {
      // 1. RPM (01 0C)
      double rpm = _currentTelemetry.rpm;
      try {
        final res = await sendCommand('010C');
        rpm = _parseRpm(res) ?? rpm;
      } catch (_) {}

      // 2. Speed (01 0D)
      double speedKmh = _currentTelemetry.speedKmh;
      try {
        final res = await sendCommand('010D');
        speedKmh = _parseSpeed(res) ?? speedKmh;
      } catch (_) {}

      // 3. Coolant (01 05)
      double coolantC = _currentTelemetry.coolantTempC;
      try {
        final res = await sendCommand('0105');
        coolantC = _parseTemperature(res) ?? coolantC;
      } catch (_) {}

      // 4. Engine Load (01 04)
      double load = _currentTelemetry.engineLoad;
      try {
        final res = await sendCommand('0104');
        load = _parsePercentage(res) ?? load;
      } catch (_) {}

      // 5. Throttle (01 11)
      double throttle = _currentTelemetry.throttlePosition;
      try {
        final res = await sendCommand('0111');
        throttle = _parsePercentage(res) ?? throttle;
      } catch (_) {}

      // 6. Voltage (AT RV)
      double voltage = _currentTelemetry.voltage;
      try {
        final res = await sendCommand('ATRV');
        voltage = _parseVoltage(res) ?? voltage;
      } catch (_) {}

      _updateTelemetry(Obd2Telemetry(
        rpm: rpm,
        speedKmh: speedKmh,
        speedMph: speedKmh * 0.621371,
        coolantTempC: coolantC,
        coolantTempF: (coolantC * 9 / 5) + 32,
        iatC: _currentTelemetry.iatC,
        iatF: _currentTelemetry.iatF,
        engineLoad: load,
        throttlePosition: throttle,
        voltage: voltage,
        maf: _currentTelemetry.maf,
        timestamp: DateTime.now(),
      ));
    } catch (_) {}
  }

  double? _parseRpm(String hex) {
    final clean = hex.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410C');
    if (idx != -1 && clean.length >= idx + 8) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      final b = int.tryParse(clean.substring(idx + 6, idx + 8), radix: 16);
      if (a != null && b != null) {
        return ((a * 256.0) + b) / 4.0;
      }
    }
    return null;
  }

  double? _parseSpeed(String hex) {
    final clean = hex.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410D');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) return a.toDouble();
    }
    return null;
  }

  double? _parseTemperature(String hex) {
    final clean = hex.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('4105');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) return (a - 40).toDouble();
    }
    return null;
  }

  double? _parsePercentage(String hex) {
    final clean = hex.replaceAll(' ', '').toUpperCase();
    if (clean.length >= 6) {
      final valStr = clean.substring(clean.length - 2);
      final a = int.tryParse(valStr, radix: 16);
      if (a != null) return (a * 100.0) / 255.0;
    }
    return null;
  }

  double? _parseVoltage(String res) {
    final match = RegExp(r'(\d+\.?\d*)\s*V?', caseSensitive: false).firstMatch(res);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  // -------------------------------------------------------------
  // SIMULATOR / DEMO MODE
  // -------------------------------------------------------------

  void startDemoMode() {
    _cleanupConnection();
    _stopTelemetryPolling();

    _isDemoMode = true;
    _setConnectionState(
      Obd2ConnectionState.connected,
      'Demo Mode: Simulated ECU & Telemetry Active',
    );

    // Populate initial demo DTCs so user can test AI diagnostics immediately
    _currentDtcCodes = ['P0301', 'P0171', 'P0420'];

    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _simulateEnginePhysics(),
    );
  }

  void stopDemoMode() {
    _isDemoMode = false;
    _demoTimer?.cancel();
    _demoTimer = null;
    _setConnectionState(Obd2ConnectionState.disconnected, 'Disconnected');
  }

  void _simulateEnginePhysics() {
    final rand = math.Random();

    // Rev simulation through 4 gears
    if (_simAccelerating) {
      _simThrottle = (_simThrottle + 3.0).clamp(10.0, 85.0);
      _simRpm += 160.0 + (rand.nextDouble() * 50);
      _simSpeedMph += 0.8 + (rand.nextDouble() * 0.4);

      if (_simRpm > 6200) {
        // Shift up
        _simGear++;
        if (_simGear > 4) {
          _simAccelerating = false;
        } else {
          _simRpm = 3400.0;
        }
      }
    } else {
      // Decelerating / coasting
      _simThrottle = (_simThrottle - 4.0).clamp(5.0, 15.0);
      _simRpm -= 180.0 + (rand.nextDouble() * 40);
      _simSpeedMph -= 1.0;

      if (_simSpeedMph <= 12.0 || _simRpm < 1100) {
        _simGear = 1;
        _simRpm = 850.0 + (rand.nextDouble() * 40);
        _simSpeedMph = (rand.nextDouble() * 2.0);
        _simAccelerating = true;
      }
    }

    _simEngineLoad = (_simThrottle * 0.85 + (rand.nextDouble() * 5.0)).clamp(12.0, 95.0);
    _simCoolantTempF = (_simCoolantTempF + 0.05).clamp(180.0, 208.0);
    _simIatF = 84.0 + (_simThrottle * 0.15) + (rand.nextDouble() * 2.0);
    _simVoltage = 14.15 + (rand.nextDouble() * 0.25);
    _simMaf = (4.0 + (_simRpm / 100.0) * (_simThrottle / 40.0)).clamp(3.5, 180.0);

    final coolantC = (_simCoolantTempF - 32.0) * 5.0 / 9.0;
    final iatC = (_simIatF - 32.0) * 5.0 / 9.0;

    _updateTelemetry(Obd2Telemetry(
      rpm: _simRpm,
      speedKmh: _simSpeedMph * 1.60934,
      speedMph: _simSpeedMph,
      coolantTempC: coolantC,
      coolantTempF: _simCoolantTempF,
      iatC: iatC,
      iatF: _simIatF,
      engineLoad: _simEngineLoad,
      throttlePosition: _simThrottle,
      voltage: _simVoltage,
      maf: _simMaf,
      fuelLevel: 68.0,
      timestamp: DateTime.now(),
    ));
  }

  String _simulateCommandResponse(String cmd) {
    final clean = cmd.trim().toUpperCase();
    if (clean.startsWith('AT')) return 'OK';
    if (clean == '010C') return '410C1A80'; // ~1700 RPM
    if (clean == '010D') return '410D3C'; // 60 kmh
    if (clean == '0105') return '41057B'; // 83 C
    if (clean == '0104') return '410450';
    if (clean == '0111') return '411130';
    if (clean == '03') return '43013001710420'; // P0130, P0171, P0420
    if (clean == '04') return '44';
    return 'NO DATA';
  }

  void _updateTelemetry(Obd2Telemetry telemetry) {
    _currentTelemetry = telemetry;

    if (_isLogging) {
      _loggedDataPoints.add(telemetry);
    }

    notifyListeners();
  }

  // -------------------------------------------------------------
  // DTC TROUBLE CODES SCANNING & CLEARING
  // -------------------------------------------------------------

  Future<List<String>> scanDtcCodes() async {
    _isScanningDtc = true;
    notifyListeners();

    try {
      if (_isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 1400));
        _currentDtcCodes = ['P0301', 'P0171', 'P0420'];
        _isScanningDtc = false;
        notifyListeners();
        return _currentDtcCodes;
      }

      final foundCodes = <String>{};

      // 1. Read Confirmed DTCs (Mode 03)
      try {
        final res03 = await sendCommand('03', timeout: const Duration(seconds: 5));
        final codes03 = _decodeDtcResponse(res03);
        foundCodes.addAll(codes03);
      } catch (e) {
        debugPrint('Mode 03 error: $e');
      }

      // 2. Read Pending DTCs (Mode 07)
      try {
        final res07 = await sendCommand('07', timeout: const Duration(seconds: 5));
        final codes07 = _decodeDtcResponse(res07);
        foundCodes.addAll(codes07);
      } catch (e) {
        debugPrint('Mode 07 error: $e');
      }

      _currentDtcCodes = foundCodes.toList();
      _isScanningDtc = false;
      notifyListeners();
      return _currentDtcCodes;
    } catch (e) {
      _isScanningDtc = false;
      notifyListeners();
      return _currentDtcCodes;
    }
  }

  List<String> _decodeDtcResponse(String response) {
    final clean = response.replaceAll(' ', '').toUpperCase();
    if (clean.contains('NODATA') || clean.contains('0000')) {
      return [];
    }

    final codes = <String>[];
    // Find service echo (43 for 03, 47 for 07)
    int startIndex = clean.indexOf('43');
    if (startIndex == -1) startIndex = clean.indexOf('47');
    if (startIndex == -1) return [];

    final payload = clean.substring(startIndex + 2);
    // Each DTC is encoded in 2 bytes (4 hex characters)
    for (int i = 0; i + 4 <= payload.length; i += 4) {
      final chunk = payload.substring(i, i + 4);
      if (chunk == '0000') continue;

      final byte1 = int.tryParse(chunk.substring(0, 2), radix: 16);
      final byte2 = int.tryParse(chunk.substring(2, 4), radix: 16);
      if (byte1 == null || byte2 == null) continue;

      // Extract DTC system letter (upper 2 bits of byte 1)
      final sysCode = (byte1 >> 6) & 0x03;
      String letter;
      switch (sysCode) {
        case 0:
          letter = 'P';
          break; // Powertrain
        case 1:
          letter = 'C';
          break; // Chassis
        case 2:
          letter = 'B';
          break; // Body
        case 3:
          letter = 'U';
          break; // Network
        default:
          letter = 'P';
      }

      final digit1 = ((byte1 >> 4) & 0x03).toString();
      final digit2 = (byte1 & 0x0F).toRadixString(16).toUpperCase();
      final digit34 = byte2.toRadixString(16).padLeft(2, '0').toUpperCase();

      final fullCode = '$letter$digit1$digit2$digit34';
      if (!codes.contains(fullCode)) {
        codes.add(fullCode);
      }
    }
    return codes;
  }

  Future<bool> clearDtcCodes() async {
    try {
      if (_isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 800));
        _currentDtcCodes.clear();
        notifyListeners();
        return true;
      }

      await sendCommand('04');
      _currentDtcCodes.clear();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void addManualDtcCode(String code) {
    final clean = code.trim().toUpperCase();
    if (clean.isNotEmpty && !_currentDtcCodes.contains(clean)) {
      _currentDtcCodes.add(clean);
      notifyListeners();
    }
  }

  void removeDtcCode(String code) {
    _currentDtcCodes.remove(code);
    notifyListeners();
  }

  // -------------------------------------------------------------
  // REAL-TIME DATA LOGGING
  // -------------------------------------------------------------

  void startLogging({required String title, required Vehicle vehicle}) {
    if (_isLogging) return;

    _loggedDataPoints.clear();
    _activeLogSession = Obd2LogSession(
      title: title.isEmpty ? 'Run Log ${DateTime.now().toLocal()}' : title,
      vehicleId: vehicle.id,
      vehicleName: vehicle.displayName,
      startTime: DateTime.now(),
      dataPoints: _loggedDataPoints,
    );
    _isLogging = true;

    _loggingStatsTimer?.cancel();
    _loggingStatsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );

    notifyListeners();
  }

  Obd2LogSession? stopLogging() {
    if (!_isLogging || _activeLogSession == null) return null;

    _isLogging = false;
    _loggingStatsTimer?.cancel();
    _loggingStatsTimer = null;

    final session = Obd2LogSession(
      id: _activeLogSession!.id,
      title: _activeLogSession!.title,
      vehicleId: _activeLogSession!.vehicleId,
      vehicleName: _activeLogSession!.vehicleName,
      startTime: _activeLogSession!.startTime,
      endTime: DateTime.now(),
      dataPoints: List.from(_loggedDataPoints),
    );

    _activeLogSession = null;
    _loggedDataPoints.clear();
    notifyListeners();
    return session;
  }

  @override
  void dispose() {
    _telemetryPollingTimer?.cancel();
    _demoTimer?.cancel();
    _loggingStatsTimer?.cancel();
    _cleanupConnection();
    super.dispose();
  }
}
