import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _uniqueIdCounter = 0;
String _generateUniqueId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${_uniqueIdCounter++}';

class Vehicle {
  String id;
  String type; // 'Car' or 'Motorcycle'
  String year;
  String make;
  String model;
  String color;
  String trim;
  String mods;
  List<String> imagesBase64;
  Map<String, dynamic>? cachedSpecs;

  List<Uint8List>? _cachedImageBytes;
  int? _cachedImagesHash;

  Vehicle({
    String? id,
    this.type = 'Car',
    this.year = '',
    this.make = '',
    this.model = '',
    this.color = '',
    this.trim = '',
    this.mods = '',
    List<String>? imagesBase64,
    this.cachedSpecs,
  })  : id = id ?? _generateUniqueId(),
        imagesBase64 = imagesBase64 ?? [];

  bool get isMotorcycle => type.toLowerCase() == 'motorcycle';

  IconData get icon => isMotorcycle ? Icons.two_wheeler : Icons.directions_car;

  List<Uint8List> get imageBytesList {
    final currentHash = Object.hashAll(imagesBase64);
    if (_cachedImageBytes != null && _cachedImagesHash == currentHash) {
      return _cachedImageBytes!;
    }
    final list = <Uint8List>[];
    for (final b64 in imagesBase64) {
      if (b64.isNotEmpty) {
        try {
          list.add(base64Decode(b64));
        } catch (_) {}
      }
    }
    _cachedImageBytes = list;
    _cachedImagesHash = currentHash;
    return list;
  }

  void clearImageCache() {
    _cachedImageBytes = null;
    _cachedImagesHash = null;
  }

  Uint8List? get primaryImageBytes {
    final bytes = imageBytesList;
    return bytes.isNotEmpty ? bytes.first : null;
  }

  String get displayName {
    final name = '$year $make $model'.trim();
    if (name.isEmpty) {
      return isMotorcycle ? 'My Motorcycle' : 'My Awesome Ride';
    }
    return name;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'year': year,
      'make': make,
      'model': model,
      'color': color,
      'trim': trim,
      'mods': mods,
      'imagesBase64': imagesBase64,
      'cachedSpecs': cachedSpecs,
    };
  }

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    List<String> imgs = [];
    if (map['imagesBase64'] is List) {
      imgs = List<String>.from(map['imagesBase64']);
    } else if (map['imageBase64'] is String && (map['imageBase64'] as String).isNotEmpty) {
      imgs = [map['imageBase64'] as String];
    }

    return Vehicle(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: map['type'] ?? 'Car',
      year: map['year'] ?? '',
      make: map['make'] ?? '',
      model: map['model'] ?? '',
      color: map['color'] ?? '',
      trim: map['trim'] ?? '',
      mods: map['mods'] ?? '',
      imagesBase64: imgs,
      cachedSpecs: map['cachedSpecs'] != null ? Map<String, dynamic>.from(map['cachedSpecs']) : null,
    );
  }
}

// Backward compatibility typedef
typedef Car = Vehicle;

class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  String text;
  final String? imageBase64;
  final DateTime timestamp;

  ChatMessage({
    String? id,
    required this.role,
    required this.text,
    this.imageBase64,
    DateTime? timestamp,
  })  : id = id ?? _generateUniqueId(),
        timestamp = timestamp ?? DateTime.now();

  Uint8List? get imageBytes {
    if (imageBase64 == null || imageBase64!.isEmpty) return null;
    try {
      return base64Decode(imageBase64!);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'role': role,
      'text': text,
      'imageBase64': imageBase64,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      role: map['role'] ?? 'user',
      text: map['text'] ?? '',
      imageBase64: map['imageBase64'],
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class ChatSession {
  final String id;
  String title;
  String? vehicleId;
  final DateTime createdAt;
  DateTime updatedAt;
  List<ChatMessage> messages;

  ChatSession({
    String? id,
    required this.title,
    this.vehicleId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  })  : id = id ?? _generateUniqueId(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'vehicleId': vehicleId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages.map((m) => m.toMap()).toList(),
    };
  }

  factory ChatSession.fromMap(Map<String, dynamic> map) {
    return ChatSession(
      id: map['id'],
      title: map['title'] ?? 'Chat',
      vehicleId: map['vehicleId'],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt']) ?? DateTime.now()
          : DateTime.now(),
      messages: (map['messages'] as List? ?? [])
          .map((m) => ChatMessage.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }
}

class MockupItem {
  final String id;
  final String? vehicleId;
  final String vehicleName;
  final String prompt;
  final String imageBase64;
  final bool isFollowup;
  final String? parentMockupId;
  final DateTime timestamp;

  MockupItem({
    String? id,
    this.vehicleId,
    required this.vehicleName,
    required this.prompt,
    required this.imageBase64,
    this.isFollowup = false,
    this.parentMockupId,
    DateTime? timestamp,
  })  : id = id ?? _generateUniqueId(),
        timestamp = timestamp ?? DateTime.now();

  Uint8List? _cachedBytes;

  Uint8List? get imageBytes {
    if (_cachedBytes != null) return _cachedBytes;
    try {
      return _cachedBytes = base64Decode(imageBase64);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vehicleId': vehicleId,
      'vehicleName': vehicleName,
      'prompt': prompt,
      'imageBase64': imageBase64,
      'isFollowup': isFollowup,
      'parentMockupId': parentMockupId,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MockupItem.fromMap(Map<String, dynamic> map) {
    return MockupItem(
      id: map['id'],
      vehicleId: map['vehicleId'],
      vehicleName: map['vehicleName'] ?? '',
      prompt: map['prompt'] ?? '',
      imageBase64: map['imageBase64'] ?? '',
      isFollowup: map['isFollowup'] ?? false,
      parentMockupId: map['parentMockupId'],
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class Obd2Telemetry {
  final double rpm;
  final double speedKmh;
  final double speedMph;
  final double coolantTempC;
  final double coolantTempF;
  final double iatC;
  final double iatF;
  final double engineLoad; // 0 - 100 %
  final double throttlePosition; // 0 - 100 %
  final double voltage; // volts
  final double maf; // g/s
  final double fuelLevel; // 0 - 100 %
  final DateTime timestamp;

  const Obd2Telemetry({
    this.rpm = 0.0,
    this.speedKmh = 0.0,
    this.speedMph = 0.0,
    this.coolantTempC = 0.0,
    this.coolantTempF = 32.0,
    this.iatC = 0.0,
    this.iatF = 32.0,
    this.engineLoad = 0.0,
    this.throttlePosition = 0.0,
    this.voltage = 12.0,
    this.maf = 0.0,
    this.fuelLevel = -1.0,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'rpm': rpm,
    'speedKmh': speedKmh,
    'speedMph': speedMph,
    'coolantTempC': coolantTempC,
    'coolantTempF': coolantTempF,
    'iatC': iatC,
    'iatF': iatF,
    'engineLoad': engineLoad,
    'throttlePosition': throttlePosition,
    'voltage': voltage,
    'maf': maf,
    'fuelLevel': fuelLevel,
    'timestamp': timestamp.toIso8601String(),
  };

  factory Obd2Telemetry.fromMap(Map<String, dynamic> map) {
    return Obd2Telemetry(
      rpm: (map['rpm'] as num?)?.toDouble() ?? 0.0,
      speedKmh: (map['speedKmh'] as num?)?.toDouble() ?? 0.0,
      speedMph: (map['speedMph'] as num?)?.toDouble() ?? 0.0,
      coolantTempC: (map['coolantTempC'] as num?)?.toDouble() ?? 0.0,
      coolantTempF: (map['coolantTempF'] as num?)?.toDouble() ?? 32.0,
      iatC: (map['iatC'] as num?)?.toDouble() ?? 0.0,
      iatF: (map['iatF'] as num?)?.toDouble() ?? 32.0,
      engineLoad: (map['engineLoad'] as num?)?.toDouble() ?? 0.0,
      throttlePosition: (map['throttlePosition'] as num?)?.toDouble() ?? 0.0,
      voltage: (map['voltage'] as num?)?.toDouble() ?? 12.0,
      maf: (map['maf'] as num?)?.toDouble() ?? 0.0,
      fuelLevel: (map['fuelLevel'] as num?)?.toDouble() ?? -1.0,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class Obd2LogSession {
  final String id;
  String title;
  final String? vehicleId;
  final String vehicleName;
  final DateTime startTime;
  DateTime endTime;
  final List<Obd2Telemetry> dataPoints;

  Obd2LogSession({
    String? id,
    required this.title,
    this.vehicleId,
    required this.vehicleName,
    DateTime? startTime,
    DateTime? endTime,
    List<Obd2Telemetry>? dataPoints,
  })  : id = id ?? _generateUniqueId(),
        startTime = startTime ?? DateTime.now(),
        endTime = endTime ?? DateTime.now(),
        dataPoints = dataPoints ?? [];

  int get durationSeconds =>
      endTime.difference(startTime).inSeconds.clamp(0, 864000);

  int get sampleCount => dataPoints.length;

  double get maxRpm => dataPoints.isEmpty
      ? 0.0
      : dataPoints.map((e) => e.rpm).reduce((a, b) => a > b ? a : b);

  double get maxSpeedMph => dataPoints.isEmpty
      ? 0.0
      : dataPoints.map((e) => e.speedMph).reduce((a, b) => a > b ? a : b);

  double get avgEngineLoad => dataPoints.isEmpty
      ? 0.0
      : dataPoints.map((e) => e.engineLoad).reduce((a, b) => a + b) /
          dataPoints.length;

  String toCsv() {
    final sb = StringBuffer();
    sb.writeln(
        'Timestamp,TimeSec,RPM,Speed_MPH,Speed_KMH,Coolant_F,Coolant_C,IAT_F,EngineLoad_Pct,Throttle_Pct,Voltage_V,MAF_gs');
    for (int i = 0; i < dataPoints.length; i++) {
      final p = dataPoints[i];
      final timeSec =
          p.timestamp.difference(startTime).inMilliseconds / 1000.0;
      sb.writeln(
          '${p.timestamp.toIso8601String()},${timeSec.toStringAsFixed(2)},${p.rpm.toStringAsFixed(0)},${p.speedMph.toStringAsFixed(1)},${p.speedKmh.toStringAsFixed(1)},${p.coolantTempF.toStringAsFixed(1)},${p.coolantTempC.toStringAsFixed(1)},${p.iatF.toStringAsFixed(1)},${p.engineLoad.toStringAsFixed(1)},${p.throttlePosition.toStringAsFixed(1)},${p.voltage.toStringAsFixed(2)},${p.maf.toStringAsFixed(2)}');
    }
    return sb.toString();
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'vehicleId': vehicleId,
    'vehicleName': vehicleName,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'dataPoints': dataPoints.map((p) => p.toMap()).toList(),
  };

  factory Obd2LogSession.fromMap(Map<String, dynamic> map) {
    return Obd2LogSession(
      id: map['id'],
      title: map['title'] ?? 'OBD2 Log',
      vehicleId: map['vehicleId'],
      vehicleName: map['vehicleName'] ?? '',
      startTime: map['startTime'] != null
          ? DateTime.tryParse(map['startTime']) ?? DateTime.now()
          : DateTime.now(),
      endTime: map['endTime'] != null
          ? DateTime.tryParse(map['endTime']) ?? DateTime.now()
          : DateTime.now(),
      dataPoints: (map['dataPoints'] as List? ?? [])
          .map((p) => Obd2Telemetry.fromMap(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }
}

class DtcDiagnosisItem {
  final String code;
  final String title;
  final String carSpecificAnalysis;
  final List<String> commonCauses;

  DtcDiagnosisItem({
    required this.code,
    required this.title,
    required this.carSpecificAnalysis,
    required this.commonCauses,
  });

  Map<String, dynamic> toMap() => {
    'code': code,
    'title': title,
    'carSpecificAnalysis': carSpecificAnalysis,
    'commonCauses': commonCauses,
  };

  factory DtcDiagnosisItem.fromMap(Map<String, dynamic> map) => DtcDiagnosisItem(
    code: map['code'] ?? '',
    title: map['title'] ?? '',
    carSpecificAnalysis: map['carSpecificAnalysis'] ?? '',
    commonCauses: List<String>.from(map['commonCauses'] ?? []),
  );
}

class DiagnosticPartItem {
  final String partName;
  final String description;
  final String estimatedCost;
  final String priority; // 'Immediate', 'Recommended', 'Optional'

  DiagnosticPartItem({
    required this.partName,
    required this.description,
    required this.estimatedCost,
    this.priority = 'Recommended',
  });

  Map<String, dynamic> toMap() => {
    'partName': partName,
    'description': description,
    'estimatedCost': estimatedCost,
    'priority': priority,
  };

  factory DiagnosticPartItem.fromMap(Map<String, dynamic> map) =>
      DiagnosticPartItem(
        partName: map['partName'] ?? '',
        description: map['description'] ?? '',
        estimatedCost: map['estimatedCost'] ?? '',
        priority: map['priority'] ?? 'Recommended',
      );
}

class TroubleshootingStepItem {
  final int stepNumber;
  final String title;
  final String action;
  final List<String> toolsNeeded;
  final String difficulty; // 'Beginner', 'Intermediate', 'Advanced'

  TroubleshootingStepItem({
    required this.stepNumber,
    required this.title,
    required this.action,
    required this.toolsNeeded,
    this.difficulty = 'Intermediate',
  });

  Map<String, dynamic> toMap() => {
    'stepNumber': stepNumber,
    'title': title,
    'action': action,
    'toolsNeeded': toolsNeeded,
    'difficulty': difficulty,
  };

  factory TroubleshootingStepItem.fromMap(Map<String, dynamic> map) =>
      TroubleshootingStepItem(
        stepNumber: (map['stepNumber'] as num?)?.toInt() ?? 1,
        title: map['title'] ?? '',
        action: map['action'] ?? '',
        toolsNeeded: List<String>.from(map['toolsNeeded'] ?? []),
        difficulty: map['difficulty'] ?? 'Intermediate',
      );
}

class DiagnosticCostEstimate {
  final String diyCost;
  final String independentShopCost;
  final String dealershipCost;
  final String estimatedLaborHours;
  final String summaryNotes;

  DiagnosticCostEstimate({
    required this.diyCost,
    required this.independentShopCost,
    required this.dealershipCost,
    required this.estimatedLaborHours,
    required this.summaryNotes,
  });

  Map<String, dynamic> toMap() => {
    'diyCost': diyCost,
    'independentShopCost': independentShopCost,
    'dealershipCost': dealershipCost,
    'estimatedLaborHours': estimatedLaborHours,
    'summaryNotes': summaryNotes,
  };

  factory DiagnosticCostEstimate.fromMap(Map<String, dynamic> map) =>
      DiagnosticCostEstimate(
        diyCost: map['diyCost'] ?? 'N/A',
        independentShopCost: map['independentShopCost'] ?? 'N/A',
        dealershipCost: map['dealershipCost'] ?? 'N/A',
        estimatedLaborHours: map['estimatedLaborHours'] ?? 'N/A',
        summaryNotes: map['summaryNotes'] ?? '',
      );
}

class Obd2DiagnosticReport {
  final String id;
  final String? vehicleId;
  final String vehicleName;
  final List<String> dtcCodes;
  final String overallSeverity; // 'Critical', 'Moderate', 'Minor'
  final bool canDrive;
  final String summary;
  final List<DtcDiagnosisItem> diagnoses;
  final List<DiagnosticPartItem> recommendedParts;
  final List<TroubleshootingStepItem> troubleshootingSteps;
  final DiagnosticCostEstimate costEstimate;
  final List<String> preventativeTips;
  final DateTime timestamp;

  Obd2DiagnosticReport({
    String? id,
    this.vehicleId,
    required this.vehicleName,
    required this.dtcCodes,
    required this.overallSeverity,
    required this.canDrive,
    required this.summary,
    required this.diagnoses,
    required this.recommendedParts,
    required this.troubleshootingSteps,
    required this.costEstimate,
    required this.preventativeTips,
    DateTime? timestamp,
  })  : id = id ?? _generateUniqueId(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'vehicleId': vehicleId,
    'vehicleName': vehicleName,
    'dtcCodes': dtcCodes,
    'overallSeverity': overallSeverity,
    'canDrive': canDrive,
    'summary': summary,
    'diagnoses': diagnoses.map((d) => d.toMap()).toList(),
    'recommendedParts': recommendedParts.map((p) => p.toMap()).toList(),
    'troubleshootingSteps': troubleshootingSteps.map((s) => s.toMap()).toList(),
    'costEstimate': costEstimate.toMap(),
    'preventativeTips': preventativeTips,
    'timestamp': timestamp.toIso8601String(),
  };

  factory Obd2DiagnosticReport.fromMap(Map<String, dynamic> map) {
    return Obd2DiagnosticReport(
      id: map['id'],
      vehicleId: map['vehicleId'],
      vehicleName: map['vehicleName'] ?? '',
      dtcCodes: List<String>.from(map['dtcCodes'] ?? []),
      overallSeverity: map['overallSeverity'] ?? 'Moderate',
      canDrive: map['canDrive'] ?? true,
      summary: map['summary'] ?? '',
      diagnoses: (map['diagnoses'] as List? ?? [])
          .map((d) => DtcDiagnosisItem.fromMap(Map<String, dynamic>.from(d)))
          .toList(),
      recommendedParts: (map['recommendedParts'] as List? ?? [])
          .map((p) => DiagnosticPartItem.fromMap(Map<String, dynamic>.from(p)))
          .toList(),
      troubleshootingSteps: (map['troubleshootingSteps'] as List? ?? [])
          .map((s) => TroubleshootingStepItem.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      costEstimate: DiagnosticCostEstimate.fromMap(
          Map<String, dynamic>.from(map['costEstimate'] ?? {})),
      preventativeTips: List<String>.from(map['preventativeTips'] ?? []),
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class AppState extends ChangeNotifier {
  static const String _vehiclesKey = 'saved_vehicles';
  static const String _legacyCarKey = 'saved_car';
  static const String _selectedVehicleIdKey = 'selected_vehicle_id';
  static const String _apiKeyKey = 'gemini_api_key';
  static const String _themeModeKey = 'app_theme_mode';
  static const String _accentColorKey = 'app_accent_color';
  static const String _primaryColorKey = 'app_primary_color';
  static const String _chatSessionsKey = 'saved_chat_sessions';
  static const String _mockupHistoryKey = 'saved_mockup_history';
  static const String _obd2LogsKey = 'saved_obd2_logs';
  static const String _diagnosticReportsKey = 'saved_diagnostic_reports';

  List<Vehicle> vehicles = [];
  String? selectedVehicleId;
  String apiKey = '';
  ThemeMode themeMode = ThemeMode.dark;
  Color accentColor = const Color(0xFF00E5FF); // Neon cyan default
  Color primaryColor = const Color(0xFF00E5FF);

  List<ChatSession> chatSessions = [];
  String? activeChatSessionId;

  List<MockupItem> mockupHistory = [];
  List<Obd2LogSession> savedObd2Logs = [];
  List<Obd2DiagnosticReport> diagnosticReports = [];

  Vehicle get selectedVehicle {
    if (vehicles.isEmpty) {
      final defaultVehicle = Vehicle(
        year: '2020',
        make: 'Ford',
        model: 'Mustang GT',
        color: 'Oxford White',
        trim: 'Premium',
        mods: 'Cold air intake, Corsa cat-back exhaust, Steeda springs',
      );
      vehicles.add(defaultVehicle);
      selectedVehicleId = defaultVehicle.id;
      return defaultVehicle;
    }
    if (selectedVehicleId != null) {
      final found = vehicles.where((v) => v.id == selectedVehicleId);
      if (found.isNotEmpty) return found.first;
    }
    selectedVehicleId = vehicles.first.id;
    return vehicles.first;
  }

  // Compatibility getter
  Vehicle get car => selectedVehicle;

  ChatSession get activeChatSession {
    if (chatSessions.isEmpty) {
      final newSession = ChatSession(
        title: 'Tuner Assistant',
        vehicleId: selectedVehicle.id,
        messages: [
          ChatMessage(
            role: 'assistant',
            text:
                'Hey there! I am your AI Tuner. How can I help you with your ${selectedVehicle.displayName} today? You can ask for mod recommendations, upload pictures for diagnostics, or switch to voice mode!',
          ),
        ],
      );
      chatSessions.add(newSession);
      activeChatSessionId = newSession.id;
      return newSession;
    }
    if (activeChatSessionId != null) {
      final found = chatSessions.where((s) => s.id == activeChatSessionId);
      if (found.isNotEmpty) return found.first;
    }
    activeChatSessionId = chatSessions.first.id;
    return chatSessions.first;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    apiKey = prefs.getString(_apiKeyKey) ?? '';

    // Load Theme Mode
    final modeStr = prefs.getString(_themeModeKey) ?? 'dark';
    if (modeStr == 'light') {
      themeMode = ThemeMode.light;
    } else if (modeStr == 'system') {
      themeMode = ThemeMode.system;
    } else {
      themeMode = ThemeMode.dark;
    }

    // Load Accent & Primary Color
    final accentVal = prefs.getInt(_accentColorKey);
    if (accentVal != null) {
      accentColor = Color(accentVal);
    }
    final primaryVal = prefs.getInt(_primaryColorKey);
    if (primaryVal != null) {
      primaryColor = Color(primaryVal);
    } else {
      primaryColor = accentColor;
    }

    // Load Vehicles
    final vehiclesJson = prefs.getString(_vehiclesKey);
    if (vehiclesJson != null) {
      try {
        final List list = jsonDecode(vehiclesJson);
        vehicles = list.map((item) => Vehicle.fromMap(Map<String, dynamic>.from(item))).toList();
      } catch (_) {}
    }

    // Migration from legacy single car if vehicles is empty
    if (vehicles.isEmpty) {
      final legacyCarJson = prefs.getString(_legacyCarKey);
      if (legacyCarJson != null) {
        try {
          final map = jsonDecode(legacyCarJson);
          final legacyVehicle = Vehicle.fromMap(map);
          vehicles.add(legacyVehicle);
          await saveVehicles();
        } catch (_) {}
      }
    }

    // Ensure at least one default vehicle exists
    if (vehicles.isEmpty) {
      vehicles.add(Vehicle(
        year: '2020',
        make: 'Ford',
        model: 'Mustang GT',
        color: 'Oxford White',
        trim: 'Premium',
        mods: 'Cold air intake, Corsa cat-back exhaust, Steeda springs',
      ));
      await saveVehicles();
    }

    selectedVehicleId = prefs.getString(_selectedVehicleIdKey);
    if (selectedVehicleId == null || !vehicles.any((v) => v.id == selectedVehicleId)) {
      selectedVehicleId = vehicles.first.id;
    }

    // Load Chat Sessions
    final sessionsJson = prefs.getString(_chatSessionsKey);
    if (sessionsJson != null) {
      try {
        final List list = jsonDecode(sessionsJson);
        chatSessions = list.map((item) => ChatSession.fromMap(Map<String, dynamic>.from(item))).toList();
      } catch (_) {}
    }

    // Load Mockup History
    final mockupJson = prefs.getString(_mockupHistoryKey);
    if (mockupJson != null) {
      try {
        final List list = jsonDecode(mockupJson);
        mockupHistory = list.map((item) => MockupItem.fromMap(Map<String, dynamic>.from(item))).toList();
      } catch (_) {}
    }

    // Load OBD2 Logs
    final logsJson = prefs.getString(_obd2LogsKey);
    if (logsJson != null) {
      try {
        final List list = jsonDecode(logsJson);
        savedObd2Logs = list.map((item) => Obd2LogSession.fromMap(Map<String, dynamic>.from(item))).toList();
      } catch (_) {}
    }

    // Load Diagnostic Reports
    final reportsJson = prefs.getString(_diagnosticReportsKey);
    if (reportsJson != null) {
      try {
        final List list = jsonDecode(reportsJson);
        diagnosticReports = list.map((item) => Obd2DiagnosticReport.fromMap(Map<String, dynamic>.from(item))).toList();
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> saveVehicles() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(vehicles.map((v) => v.toMap()).toList());
    await prefs.setString(_vehiclesKey, jsonStr);
    if (selectedVehicleId != null) {
      await prefs.setString(_selectedVehicleIdKey, selectedVehicleId!);
    }
    notifyListeners();
  }

  Future<void> addVehicle(Vehicle vehicle) async {
    vehicles.add(vehicle);
    selectedVehicleId = vehicle.id;
    await saveVehicles();
  }

  Future<void> updateVehicle(Vehicle updated) async {
    final index = vehicles.indexWhere((v) => v.id == updated.id);
    if (index != -1) {
      vehicles[index] = updated;
      await saveVehicles();
    }
  }

  Future<void> deleteVehicle(String id) async {
    if (vehicles.length <= 1) {
      // Don't delete last vehicle, or re-initialize a default one
      vehicles.clear();
      vehicles.add(Vehicle(
        year: '',
        make: '',
        model: '',
        color: '',
      ));
      selectedVehicleId = vehicles.first.id;
    } else {
      vehicles.removeWhere((v) => v.id == id);
      if (selectedVehicleId == id) {
        selectedVehicleId = vehicles.first.id;
      }
    }
    await saveVehicles();
  }

  Future<void> selectVehicle(String id) async {
    selectedVehicleId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedVehicleIdKey, id);
    notifyListeners();
  }

  Future<void> saveApiKey(String key) async {
    apiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    final str = mode == ThemeMode.light
        ? 'light'
        : (mode == ThemeMode.system ? 'system' : 'dark');
    await prefs.setString(_themeModeKey, str);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    accentColor = color;
    primaryColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentColorKey, color.toARGB32());
    await prefs.setInt(_primaryColorKey, color.toARGB32());
    notifyListeners();
  }

  Future<void> saveChatSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(chatSessions.map((s) => s.toMap()).toList());
    await prefs.setString(_chatSessionsKey, jsonStr);
    notifyListeners();
  }

  Future<ChatSession> createNewChatSession({String? title}) async {
    final newSession = ChatSession(
      title: title ?? 'Chat ${chatSessions.length + 1} (${selectedVehicle.displayName})',
      vehicleId: selectedVehicle.id,
      messages: [
        ChatMessage(
          role: 'assistant',
          text:
              'Started a new session for your ${selectedVehicle.displayName}. How can I assist you with performance, mods, or troubleshooting?',
        ),
      ],
    );
    chatSessions.insert(0, newSession);
    activeChatSessionId = newSession.id;
    await saveChatSessions();
    return newSession;
  }

  Future<void> selectChatSession(String id) async {
    activeChatSessionId = id;
    notifyListeners();
  }

  Future<void> deleteChatSession(String id) async {
    chatSessions.removeWhere((s) => s.id == id);
    if (activeChatSessionId == id) {
      activeChatSessionId = chatSessions.isNotEmpty ? chatSessions.first.id : null;
    }
    await saveChatSessions();
  }

  Future<void> addMessageToActiveSession(ChatMessage message) async {
    final session = activeChatSession;
    session.messages.add(message);
    session.updatedAt = DateTime.now();
    // Auto-update session title if it's the first user message
    if (message.role == 'user' && session.title.startsWith('Chat ')) {
      session.title = message.text.length > 28
          ? '${message.text.substring(0, 25)}...'
          : message.text;
    }
    await saveChatSessions();
  }

  Future<void> saveMockupHistory() async {
    final prefs = await SharedPreferences.getInstance();
    // Cap history at 40 items to prevent local storage bloat
    if (mockupHistory.length > 40) {
      mockupHistory = mockupHistory.sublist(0, 40);
    }
    final jsonStr = jsonEncode(mockupHistory.map((m) => m.toMap()).toList());
    await prefs.setString(_mockupHistoryKey, jsonStr);
    notifyListeners();
  }

  Future<void> addMockup(MockupItem item) async {
    mockupHistory.insert(0, item);
    await saveMockupHistory();
  }

  Future<void> deleteMockup(String id) async {
    mockupHistory.removeWhere((m) => m.id == id);
    await saveMockupHistory();
  }

  Future<void> clearMockupHistory() async {
    mockupHistory.clear();
    await saveMockupHistory();
  }

  Future<void> saveObd2Logs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(savedObd2Logs.map((l) => l.toMap()).toList());
    await prefs.setString(_obd2LogsKey, jsonStr);
    notifyListeners();
  }

  Future<void> addObd2Log(Obd2LogSession session) async {
    savedObd2Logs.insert(0, session);
    await saveObd2Logs();
  }

  Future<void> deleteObd2Log(String id) async {
    savedObd2Logs.removeWhere((l) => l.id == id);
    await saveObd2Logs();
  }

  Future<void> clearObd2Logs() async {
    savedObd2Logs.clear();
    await saveObd2Logs();
  }

  Future<void> saveDiagnosticReports() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr =
        jsonEncode(diagnosticReports.map((r) => r.toMap()).toList());
    await prefs.setString(_diagnosticReportsKey, jsonStr);
    notifyListeners();
  }

  Future<void> addDiagnosticReport(Obd2DiagnosticReport report) async {
    diagnosticReports.insert(0, report);
    await saveDiagnosticReports();
  }

  Future<void> deleteDiagnosticReport(String id) async {
    diagnosticReports.removeWhere((r) => r.id == id);
    await saveDiagnosticReports();
  }

  Future<void> clearDiagnosticReports() async {
    diagnosticReports.clear();
    await saveDiagnosticReports();
  }

  String exportToJson() {
    final data = {
      'app': 'AI_TUNER',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'apiKey': apiKey,
      'themeMode': themeMode == ThemeMode.light
          ? 'light'
          : (themeMode == ThemeMode.system ? 'system' : 'dark'),
      'accentColor': accentColor.toARGB32(),
      'primaryColor': primaryColor.toARGB32(),
      'selectedVehicleId': selectedVehicleId,
      'vehicles': vehicles.map((v) => v.toMap()).toList(),
      'chatSessions': chatSessions.map((s) => s.toMap()).toList(),
      'mockupHistory': mockupHistory.map((m) => m.toMap()).toList(),
      'savedObd2Logs': savedObd2Logs.map((l) => l.toMap()).toList(),
      'diagnosticReports': diagnosticReports.map((r) => r.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> importFromJson(String jsonStr) async {
    final Map<String, dynamic> data = jsonDecode(jsonStr);

    if (data['apiKey'] is String) {
      apiKey = data['apiKey'] as String;
    }

    if (data['themeMode'] is String) {
      final modeStr = data['themeMode'] as String;
      if (modeStr == 'light') {
        themeMode = ThemeMode.light;
      } else if (modeStr == 'system') {
        themeMode = ThemeMode.system;
      } else {
        themeMode = ThemeMode.dark;
      }
    }

    if (data['accentColor'] is int) {
      accentColor = Color(data['accentColor'] as int);
      primaryColor = accentColor;
    }

    if (data['vehicles'] is List) {
      vehicles = (data['vehicles'] as List)
          .map((v) => Vehicle.fromMap(Map<String, dynamic>.from(v)))
          .toList();
    }

    if (data['selectedVehicleId'] is String) {
      selectedVehicleId = data['selectedVehicleId'] as String;
    } else if (vehicles.isNotEmpty) {
      selectedVehicleId = vehicles.first.id;
    }

    if (data['chatSessions'] is List) {
      chatSessions = (data['chatSessions'] as List)
          .map((s) => ChatSession.fromMap(Map<String, dynamic>.from(s)))
          .toList();
      activeChatSessionId = chatSessions.isNotEmpty ? chatSessions.first.id : null;
    }

    if (data['mockupHistory'] is List) {
      mockupHistory = (data['mockupHistory'] as List)
          .map((m) => MockupItem.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }

    if (data['savedObd2Logs'] is List) {
      savedObd2Logs = (data['savedObd2Logs'] as List)
          .map((l) => Obd2LogSession.fromMap(Map<String, dynamic>.from(l)))
          .toList();
    }

    if (data['diagnosticReports'] is List) {
      diagnosticReports = (data['diagnosticReports'] as List)
          .map((r) => Obd2DiagnosticReport.fromMap(Map<String, dynamic>.from(r)))
          .toList();
    }

    // Persist all imported data to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, apiKey);
    await prefs.setString(
      _themeModeKey,
      themeMode == ThemeMode.light
          ? 'light'
          : (themeMode == ThemeMode.system ? 'system' : 'dark'),
    );
    await prefs.setInt(_accentColorKey, accentColor.toARGB32());
    await prefs.setInt(_primaryColorKey, primaryColor.toARGB32());
    if (selectedVehicleId != null) {
      await prefs.setString(_selectedVehicleIdKey, selectedVehicleId!);
    }
    await prefs.setString(
      _vehiclesKey,
      jsonEncode(vehicles.map((v) => v.toMap()).toList()),
    );
    await prefs.setString(
      _chatSessionsKey,
      jsonEncode(chatSessions.map((s) => s.toMap()).toList()),
    );
    await prefs.setString(
      _mockupHistoryKey,
      jsonEncode(mockupHistory.map((m) => m.toMap()).toList()),
    );
    await prefs.setString(
      _obd2LogsKey,
      jsonEncode(savedObd2Logs.map((l) => l.toMap()).toList()),
    );
    await prefs.setString(
      _diagnosticReportsKey,
      jsonEncode(diagnosticReports.map((r) => r.toMap()).toList()),
    );

    notifyListeners();
  }
}

