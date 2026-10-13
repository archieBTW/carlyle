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
  bool _isPollingTelemetry = false;
  bool _isMilOn = false;
  int _ecuDtcCount = 0;
  String? _ecuProtocol;

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
  Future<void>? _commandQueue;

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
  String? _lastError;

  // Getters
  Obd2ConnectionState get connectionState => _connectionState;
  bool get isConnected =>
      _connectionState == Obd2ConnectionState.connected || _isDemoMode;
  bool get isDemoMode => _isDemoMode;
  bool get isScanningDtc => _isScanningDtc;
  bool get isMilOn => _isMilOn;
  int get ecuDtcCount => _ecuDtcCount;
  String? get ecuProtocol => _ecuProtocol;
  bool get isLogging => _isLogging;
  String? get connectedDeviceName =>
      _isDemoMode ? 'Simulated OBD2 (ELM327 v1.5)' : _connectedDeviceName;
  String? get connectedDeviceAddress =>
      _isDemoMode ? 'SIM:00:11:22:33:44' : _connectedDeviceAddress;
  String get statusMessage => _statusMessage;
  String? get lastError => _lastError;
  List<String> get currentDtcCodes => List.unmodifiable(_currentDtcCodes);
  Obd2Telemetry get currentTelemetry => _currentTelemetry;
  Obd2LogSession? get activeLogSession => _activeLogSession;
  int get loggedSampleCount => _loggedDataPoints.length;

  // -------------------------------------------------------------
  // PERMISSIONS & DEVICE SCANNING
  // -------------------------------------------------------------

  Future<bool> isBluetoothEnabled() async {
    try {
      return await _bluetooth.isEnabled();
    } catch (_) {
      return true; // Default to true if unable to check
    }
  }

  Future<bool> enableBluetooth() async {
    try {
      return await _bluetooth.enableBluetooth();
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      final opened = await _bluetooth.openAppSettings();
      if (opened) return true;
    } catch (_) {}
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    try {
      final status = await _bluetooth.checkPermissions();
      if (status == BtcPermissionStatus.granted) {
        return true;
      }
      final requested = await _bluetooth.requestPermissions();
      if (requested == BtcPermissionStatus.granted) {
        return true;
      }
    } catch (e) {
      debugPrint('Native bluetooth permission check note: $e');
    }

    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
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
    _lastError = null;
    try {
      final enabled = await isBluetoothEnabled();
      if (!enabled) {
        _lastError = 'Bluetooth is turned off. Please enable Bluetooth.';
        notifyListeners();
        return [];
      }

      await requestPermissions();
      final bonded = await _bluetooth.getPairedDevices();
      return bonded
          .map((d) => Obd2BluetoothDevice(
                name: d.name ?? d.address,
                address: d.address,
                isBonded: true,
              ))
          .toList();
    } on BtcDisabledException {
      _lastError = 'Bluetooth is disabled. Please turn on Bluetooth.';
      notifyListeners();
      return [];
    } on BtcPermissionException {
      _lastError = 'Bluetooth permission denied. Please allow Bluetooth access.';
      notifyListeners();
      return [];
    } catch (e) {
      debugPrint('Error getting bonded devices: $e');
      _lastError = 'Could not load paired devices: $e';
      notifyListeners();
      return [];
    }
  }

  Stream<Obd2BluetoothDevice> scanForDevices() async* {
    _lastError = null;
    try {
      final enabled = await isBluetoothEnabled();
      if (!enabled) {
        _lastError = 'Bluetooth is turned off.';
        notifyListeners();
        return;
      }

      await requestPermissions();
      await _bluetooth.startDiscovery();
      await for (final result in _bluetooth.discoveryResults) {
        yield Obd2BluetoothDevice(
          name: result.name ?? result.address,
          address: result.address,
          isBonded: false,
        );
      }
    } on BtcDisabledException {
      _lastError = 'Bluetooth is disabled. Please turn on Bluetooth.';
      notifyListeners();
    } on BtcPermissionException {
      _lastError = 'Bluetooth permission denied.';
      notifyListeners();
    } catch (e) {
      debugPrint('Error discovering devices: $e');
      _lastError = 'Scan error: $e';
      notifyListeners();
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

      // First attempt standard secure RFCOMM; fallback to insecure RFCOMM if adapter requires it
      try {
        _connection = await _bluetooth
            .connect(address: device.address, uuid: sppUuid, secure: true)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('Secure RFCOMM failed ($e), trying insecure RFCOMM channel...');
        _connection = await _bluetooth
            .connect(address: device.address, uuid: sppUuid, secure: false)
            .timeout(const Duration(seconds: 8));
      }

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
        await _cleanupConnection();
        _setConnectionState(
          Obd2ConnectionState.error,
          'ELM327 handshake failed. Check car ignition (ON position).',
        );
        return false;
      }

      final protoMsg = _ecuProtocol != null ? ' ($_ecuProtocol)' : '';
      _setConnectionState(
        Obd2ConnectionState.connected,
        'Connected to ${device.name}$protoMsg',
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
    _commandQueue = null;
    if (_pendingCommandCompleter != null && !_pendingCommandCompleter!.isCompleted) {
      _pendingCommandCompleter!.completeError(Exception('OBD2 connection closed'));
    }
    _pendingCommandCompleter = null;
    _receiveBuffer.clear();
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

  Future<String> sendCommand(
    String cmd, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_isDemoMode) {
      return _simulateCommandResponse(cmd);
    }

    if (_connection == null || !_connection!.isConnected) {
      throw Exception('OBD2 adapter is not connected');
    }

    // Chain execution sequentially through serial queue to avoid bus collisions
    final previous = _commandQueue;
    final currentCompleter = Completer<void>();
    _commandQueue = currentCompleter.future;

    try {
      if (previous != null) {
        await previous;
      }
      return await _executeCommand(cmd, timeout);
    } finally {
      currentCompleter.complete();
    }
  }

  Future<String> _executeCommand(String cmd, Duration timeout) async {
    if (_connection == null || !_connection!.isConnected) {
      throw Exception('OBD2 adapter is not connected');
    }

    _receiveBuffer.clear();
    _pendingCommandCompleter = Completer<String>();

    final formattedCmd = '${cmd.trim()}\r';
    await _connection!.output
        .add(Uint8List.fromList(ascii.encode(formattedCmd)));

    try {
      final response = await _pendingCommandCompleter!.future.timeout(timeout);
      // Small 25ms settling delay to prevent UART buffer overrun on clone ELM chips
      await Future.delayed(const Duration(milliseconds: 25));
      return _cleanResponse(response);
    } catch (e) {
      _receiveBuffer.clear();
      throw TimeoutException('Command $cmd timed out');
    }
  }

  String _cleanResponse(String raw) {
    // Strip echo, prompt '>' and status tokens while preserving newlines for multi-frame CAN
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
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
      await sendCommand('AT Z', timeout: const Duration(seconds: 4));
      await Future.delayed(const Duration(milliseconds: 400));

      // 2. Turn echo off
      await sendCommand('AT E0');
      await Future.delayed(const Duration(milliseconds: 40));

      // 3. Turn linefeeds off (ELM outputs \r before >)
      await sendCommand('AT L0');
      await Future.delayed(const Duration(milliseconds: 40));

      // 4. Turn spaces off (compact transmission)
      await sendCommand('AT S0');
      await Future.delayed(const Duration(milliseconds: 40));

      // 5. Turn headers off (simplifies single & multi-frame parsing)
      await sendCommand('AT H0');
      await Future.delayed(const Duration(milliseconds: 40));

      // 6. Set protocol to Auto
      await sendCommand('AT SP 0');
      await Future.delayed(const Duration(milliseconds: 80));

      // 7. Handshake with vehicle ECU (Force protocol search and lock)
      _setConnectionState(
        Obd2ConnectionState.connecting,
        'Connecting to vehicle ECU (detecting protocol)...',
      );

      final pid00 = await sendCommand('01 00', timeout: const Duration(seconds: 9));
      final clean00 = pid00.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();

      if (clean00.contains('UNABLETOCONNECT') ||
          clean00.contains('BUSBUSY') ||
          clean00.contains('BUSINIT:ERROR') ||
          clean00.contains('CANERROR') ||
          clean00.contains('NODATA') ||
          !clean00.contains('4100')) {
        debugPrint('ECU Handshake note on SP 0: $pid00. Retrying with ISO 15765-4 CAN (SP 6)...');
        // Fallback retry with standard 11-bit 500k CAN (standard on 2008+ cars)
        try {
          await sendCommand('AT SP 6');
          await Future.delayed(const Duration(milliseconds: 100));
          final retryPid = await sendCommand('01 00', timeout: const Duration(seconds: 6));
          final cleanRetry = retryPid.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();
          if (!cleanRetry.contains('4100')) {
            return false;
          }
        } catch (_) {
          return false;
        }
      }

      // 8. Capture protocol name
      try {
        _ecuProtocol = await sendCommand('AT DP');
        debugPrint('Vehicle OBD Protocol locked: $_ecuProtocol');
      } catch (_) {}

      // 9. Initial MIL status check
      try {
        final milRes = await sendCommand('01 01', timeout: const Duration(seconds: 3));
        _parseMilStatus(milRes);
      } catch (_) {}

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
    if (_isPollingTelemetry) return;
    _isPollingTelemetry = true;
    _runTelemetryLoop();
  }

  void _stopTelemetryPolling() {
    _isPollingTelemetry = false;
    _telemetryPollingTimer?.cancel();
    _telemetryPollingTimer = null;
  }

  Future<void> _runTelemetryLoop() async {
    int cycle = 0;
    while (_isPollingTelemetry && isConnected && !_isDemoMode) {
      if (_isScanningDtc) {
        // Yield serial bus completely while DTC diagnostic scan is running
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      try {
        await _pollTelemetryCycle(cycle++);
      } catch (e) {
        debugPrint('Telemetry cycle error: $e');
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _pollTelemetryCycle(int cycle) async {
    if (_connection == null || !_connection!.isConnected) return;

    try {
      // 1. RPM (01 0C) - High Priority: every cycle
      double rpm = _currentTelemetry.rpm;
      try {
        final res = await sendCommand('01 0C');
        rpm = _parseRpm(res) ?? rpm;
      } catch (_) {}

      // 2. Speed (01 0D) - High Priority: every cycle
      double speedKmh = _currentTelemetry.speedKmh;
      try {
        final res = await sendCommand('01 0D');
        speedKmh = _parseSpeed(res) ?? speedKmh;
      } catch (_) {}

      // 3. Engine Load (01 04) & Throttle (01 11) - Alternating cycles
      double load = _currentTelemetry.engineLoad;
      double throttle = _currentTelemetry.throttlePosition;
      if (cycle % 2 == 0) {
        try {
          final res = await sendCommand('01 04');
          load = _parseLoad(res) ?? load;
        } catch (_) {}

        try {
          final res = await sendCommand('01 11');
          throttle = _parseThrottle(res) ?? throttle;
        } catch (_) {}
      }

      // 4. Coolant Temp (01 05) & IAT (01 0F) - Every 6th cycle
      double coolantC = _currentTelemetry.coolantTempC;
      double iatC = _currentTelemetry.iatC;
      if (cycle % 6 == 1) {
        try {
          final res = await sendCommand('01 05');
          coolantC = _parseTemperature(res, '4105') ?? coolantC;
        } catch (_) {}

        try {
          final res = await sendCommand('01 0F');
          iatC = _parseTemperature(res, '410F') ?? iatC;
        } catch (_) {}
      }

      // 5. Battery Voltage (AT RV) - Every 6th cycle
      double voltage = _currentTelemetry.voltage;
      if (cycle % 6 == 3) {
        try {
          final res = await sendCommand('AT RV');
          voltage = _parseVoltage(res) ?? voltage;
        } catch (_) {}
      }

      _updateTelemetry(Obd2Telemetry(
        rpm: rpm,
        speedKmh: speedKmh,
        speedMph: speedKmh * 0.621371,
        coolantTempC: coolantC,
        coolantTempF: (coolantC * 9 / 5) + 32,
        iatC: iatC,
        iatF: (iatC * 9 / 5) + 32,
        engineLoad: load,
        throttlePosition: throttle,
        voltage: voltage,
        maf: _currentTelemetry.maf,
        fuelLevel: _currentTelemetry.fuelLevel,
        timestamp: DateTime.now(),
      ));
    } catch (_) {}
  }

  double? _parseRpm(String hex) {
    final clean = hex.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();
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
    final clean = hex.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();
    final idx = clean.indexOf('410D');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) return a.toDouble();
    }
    return null;
  }

  double? _parseTemperature(String hex, String pidHeader) {
    final clean = hex.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();
    final idx = clean.indexOf(pidHeader);
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) return (a - 40).toDouble();
    }
    return null;
  }

  double? _parseLoad(String hex) {
    final clean = hex.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();
    final idx = clean.indexOf('4104');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) return (a * 100.0) / 255.0;
    }
    return null;
  }

  double? _parseThrottle(String hex) {
    final clean = hex.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();
    final idx = clean.indexOf('4111');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) return (a * 100.0) / 255.0;
    }
    return null;
  }

  double? _parseVoltage(String res) {
    final match = RegExp(r'(?:AT\s*RV)?\s*(\d{1,2}\.\d+)\s*V?', caseSensitive: false).firstMatch(res);
    if (match != null) {
      final val = double.tryParse(match.group(1)!);
      if (val != null && val >= 5.0 && val <= 20.0) {
        return val;
      }
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
    final clean = cmd.trim().toUpperCase().replaceAll(' ', '');
    if (clean.startsWith('AT')) {
      if (clean == 'ATRV') return '14.2V';
      if (clean == 'ATDP') return 'AUTO, ISO 15765-4 (CAN 11/500)';
      return 'OK';
    }
    if (clean == '0100') return '4100BE1FA813';
    if (clean == '0101') return '41018307E800'; // MIL ON, 3 codes
    if (clean == '010C') return '410C1A80'; // ~1700 RPM
    if (clean == '010D') return '410D3C'; // 60 kmh
    if (clean == '0105') return '41057B'; // 83 C
    if (clean == '010F') return '410F46'; // 30 C
    if (clean == '0104') return '410450';
    if (clean == '0111') return '411130';
    if (clean == '03') return '4303013001710420'; // P0130, P0171, P0420
    if (clean == '07') return '470104200000'; // P0420
    if (clean == '0A') return '4A00';
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
        await Future.delayed(const Duration(milliseconds: 1200));
        _currentDtcCodes = ['P0130', 'P0171', 'P0301', 'P0420'];
        _isMilOn = true;
        _ecuDtcCount = 4;
        _isScanningDtc = false;
        notifyListeners();
        return _currentDtcCodes;
      }

      final foundCodes = <String>{};

      // 1. Check MIL Status & Stored Fault Count (Mode 01 PID 01)
      try {
        final res01 = await sendCommand('01 01', timeout: const Duration(seconds: 4));
        _parseMilStatus(res01);
      } catch (e) {
        debugPrint('Mode 01 PID 01 check error: $e');
      }

      // 2. Read Confirmed DTCs (Mode 03 - active Check Engine Light codes)
      try {
        final res03 = await sendCommand('03', timeout: const Duration(seconds: 6));
        final codes03 = _decodeDtcResponse(res03);
        foundCodes.addAll(codes03);
      } catch (e) {
        debugPrint('Mode 03 error: $e');
      }

      // 3. Read Pending DTCs (Mode 07 - active cycle faults)
      try {
        final res07 = await sendCommand('07', timeout: const Duration(seconds: 5));
        final codes07 = _decodeDtcResponse(res07);
        foundCodes.addAll(codes07);
      } catch (e) {
        debugPrint('Mode 07 error: $e');
      }

      // 4. Read Permanent DTCs (Mode 0A - emission monitors)
      try {
        final res0A = await sendCommand('0A', timeout: const Duration(seconds: 5));
        final codes0A = _decodeDtcResponse(res0A);
        foundCodes.addAll(codes0A);
      } catch (e) {
        debugPrint('Mode 0A error: $e');
      }

      _currentDtcCodes = foundCodes.toList()..sort();
      _isScanningDtc = false;
      notifyListeners();
      return _currentDtcCodes;
    } catch (e) {
      debugPrint('DTC scan error: $e');
      _isScanningDtc = false;
      notifyListeners();
      return _currentDtcCodes;
    }
  }

  void _parseMilStatus(String hex) {
    final clean = hex.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();
    final idx = clean.indexOf('4101');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) {
        _isMilOn = (a & 0x80) != 0;
        _ecuDtcCount = a & 0x7F;
        debugPrint('Vehicle MIL Status: isMilOn=$_isMilOn, ecuDtcCount=$_ecuDtcCount');
      }
    }
  }

  List<String> _decodeDtcResponse(String response) {
    final upper = response.toUpperCase();
    if (upper.contains('NO DATA') ||
        upper.contains('NODATA') ||
        upper.contains('UNABLE TO CONNECT') ||
        upper.contains('ERROR')) {
      return [];
    }

    final codes = <String>{};

    // Split response by newlines to handle multi-line / multi-frame ELM327 responses
    final lines = upper
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) =>
            l.isNotEmpty &&
            !l.startsWith('SEARCHING') &&
            !l.startsWith('BUS INIT') &&
            !l.startsWith('STOPPED'));

    for (final rawLine in lines) {
      var line = rawLine;
      // Strip leading frame prefixes like "0: ", "1: ", "2: "
      line = line.replaceAll(RegExp(r'^[0-9A-F]:\s*'), '');
      // Strip CAN ECU headers like "7E8 06 ", "7E9 02 " if present
      line = line.replaceAll(RegExp(r'^(7E[0-9A-F]|18DA[0-9A-F]{4})\s+([0-9A-F]{2}\s+)?'), '');

      // Extract all 2-char hex bytes from this line
      final byteMatches = RegExp(r'[0-9A-F]{2}').allMatches(line);
      final bytes = byteMatches.map((m) => m.group(0)!).toList();
      if (bytes.isEmpty) continue;

      // Look for response service byte: 43 (Mode 03), 47 (Mode 07), 4A (Mode 0A)
      int serviceIdx = -1;
      for (int i = 0; i < bytes.length; i++) {
        if (bytes[i] == '43' || bytes[i] == '47' || bytes[i] == '4A') {
          serviceIdx = i;
          break;
        }
      }

      List<String> payloadBytes;
      if (serviceIdx != -1) {
        payloadBytes = bytes.sublist(serviceIdx + 1);
      } else {
        // Multi-frame continuation line
        payloadBytes = bytes;
      }

      if (payloadBytes.isEmpty) continue;

      int startOffset = 0;
      if (serviceIdx != -1) {
        final firstByteVal = int.tryParse(payloadBytes[0], radix: 16) ?? 0;
        if (firstByteVal == 0 && payloadBytes.length <= 2) {
          // e.g. "43 00" -> 0 trouble codes
          continue;
        }

        // Standard SAE J1979 has 1-byte count header. If payload is odd length, index 0 is count.
        if (payloadBytes.length % 2 != 0) {
          startOffset = 1;
        }
      }

      // Process 2-byte DTC pairs
      for (int i = startOffset; i + 1 < payloadBytes.length; i += 2) {
        final b1Hex = payloadBytes[i];
        final b2Hex = payloadBytes[i + 1];

        // Skip CAN padding bytes (00 00, FF FF, AA AA)
        if ((b1Hex == '00' && b2Hex == '00') ||
            (b1Hex == 'FF' && b2Hex == 'FF') ||
            (b1Hex == 'AA' && b2Hex == 'AA')) {
          continue;
        }

        final byte1 = int.tryParse(b1Hex, radix: 16);
        final byte2 = int.tryParse(b2Hex, radix: 16);
        if (byte1 == null || byte2 == null) continue;

        // Extract DTC system letter (upper 2 bits of byte 1) per SAE J2012
        final sysCode = (byte1 >> 6) & 0x03;
        final letter = const ['P', 'C', 'B', 'U'][sysCode];

        final digit1 = ((byte1 >> 4) & 0x03).toString();
        final digit2 = (byte1 & 0x0F).toRadixString(16).toUpperCase();
        final digit34 = byte2.toRadixString(16).padLeft(2, '0').toUpperCase();

        final fullCode = '$letter$digit1$digit2$digit34';
        codes.add(fullCode);
      }
    }

    return codes.toList()..sort();
  }

  Future<bool> clearDtcCodes() async {
    _isScanningDtc = true; // Suspend telemetry during ECU clear
    try {
      if (_isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 800));
        _currentDtcCodes.clear();
        _isMilOn = false;
        _ecuDtcCount = 0;
        notifyListeners();
        return true;
      }

      final res = await sendCommand('04', timeout: const Duration(seconds: 6));
      final clean = res.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();
      final success = clean.contains('44') || clean.contains('OK');
      if (success) {
        _currentDtcCodes.clear();
        _isMilOn = false;
        _ecuDtcCount = 0;
        notifyListeners();
      }
      return success;
    } catch (e) {
      debugPrint('clearDtcCodes error: $e');
      return false;
    } finally {
      _isScanningDtc = false;
    }
  }

  @visibleForTesting
  List<String> decodeDtcResponseForTesting(String response) =>
      _decodeDtcResponse(response);

  @visibleForTesting
  double? parseRpmForTesting(String hex) => _parseRpm(hex);

  @visibleForTesting
  double? parseSpeedForTesting(String hex) => _parseSpeed(hex);

  @visibleForTesting
  double? parseTemperatureForTesting(String hex, String pid) =>
      _parseTemperature(hex, pid);

  @visibleForTesting
  double? parseLoadForTesting(String hex) => _parseLoad(hex);

  @visibleForTesting
  double? parseVoltageForTesting(String res) => _parseVoltage(res);

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
