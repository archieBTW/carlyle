import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_tuner/models.dart';
import 'package:ai_tuner/theme.dart';
import 'package:ai_tuner/gemini_service.dart';

import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Requirement 1 & 2: Multi-Vehicle & Up to 3 Photos', () {
    test('Vehicle supports Car and Motorcycle types with up to 3 photos', () {
      final car = Vehicle(
        type: 'Car',
        year: '2021',
        make: 'Toyota',
        model: 'Supra GR',
        color: 'Turbulence Gray',
        trim: '3.0 Premium',
        mods: 'Downpipe, bootmod3 Stage 2 tune',
        imagesBase64: [
          base64Encode([1, 2, 3]),
          base64Encode([4, 5, 6]),
          base64Encode([7, 8, 9]),
        ],
      );

      expect(car.isMotorcycle, isFalse);
      expect(car.displayName, '2021 Toyota Supra GR');
      expect(car.imagesBase64.length, 3);
      expect(car.imageBytesList.length, 3);
      expect(car.primaryImageBytes, isNotNull);

      final bike = Vehicle(
        type: 'Motorcycle',
        year: '2023',
        make: 'Yamaha',
        model: 'YZF-R1',
        color: 'Team Yamaha Blue',
        mods: 'Akrapovic full titanium exhaust',
      );

      expect(bike.isMotorcycle, isTrue);
      expect(bike.icon, Icons.two_wheeler);
      expect(bike.displayName, '2023 Yamaha YZF-R1');
    });

    test('Serialization and deserialization maintains all properties and images', () {
      final v = Vehicle(
        type: 'Motorcycle',
        nickname: 'Red Bullet',
        year: '2022',
        make: 'Ducati',
        model: 'Panigale V4',
        imagesBase64: [base64Encode([10, 20, 30])],
      );

      final map = v.toMap();
      final restored = Vehicle.fromMap(map);

      expect(restored.id, v.id);
      expect(restored.type, 'Motorcycle');
      expect(restored.nickname, 'Red Bullet');
      expect(restored.displayName, 'Red Bullet');
      expect(restored.ymm, '2022 Ducati Panigale V4');
      expect(restored.imagesBase64.length, 1);
    });

    test('Vehicle displayName falls back to year make model when nickname is empty', () {
      final vWithoutNick = Vehicle(
        year: '2020',
        make: 'Ford',
        model: 'Mustang GT',
      );
      expect(vWithoutNick.nickname, isEmpty);
      expect(vWithoutNick.displayName, '2020 Ford Mustang GT');
      expect(vWithoutNick.ymm, '2020 Ford Mustang GT');

      vWithoutNick.nickname = 'The Beast';
      expect(vWithoutNick.displayName, 'The Beast');
      expect(vWithoutNick.ymm, '2020 Ford Mustang GT');
    });

    test('Vehicle caches decoded image bytes for stable reference equality and flicker-free swiping', () {
      final v = Vehicle(
        imagesBase64: [
          base64Encode([10, 20, 30]),
          base64Encode([40, 50, 60]),
        ],
      );

      final firstAccess = v.imageBytesList;
      final secondAccess = v.imageBytesList;

      expect(identical(firstAccess, secondAccess), isTrue);
      expect(identical(firstAccess[0], secondAccess[0]), isTrue);
      expect(identical(firstAccess[1], secondAccess[1]), isTrue);
    });
  });

  group('Requirement 3: Setting Selected Vehicle for AI', () {
    test('Can add multiple vehicles and switch selected vehicle', () async {
      final state = AppState();
      await state.load();

      final v1 = Vehicle(year: '2018', make: 'Ford', model: 'Mustang');
      final v2 = Vehicle(type: 'Motorcycle', year: '2020', make: 'Kawasaki', model: 'Ninja ZX-6R');

      await state.addVehicle(v1);
      await state.addVehicle(v2);

      expect(state.vehicles.length, greaterThanOrEqualTo(2));
      expect(state.selectedVehicle.id, v2.id);

      // Switch selection
      await state.selectVehicle(v1.id);
      expect(state.selectedVehicle.id, v1.id);
      expect(state.selectedVehicle.displayName, '2018 Ford Mustang');
    });
  });

  group('Requirement 4: Settings & UI Customization', () {
    test('Allows changing theme mode and custom accent colors', () async {
      final state = AppState();
      await state.load();

      expect(state.themeMode, ThemeMode.dark);

      await state.setThemeMode(ThemeMode.light);
      expect(state.themeMode, ThemeMode.light);

      const customColor = Color(0xFFFF007F); // Cyber Pink
      await state.setAccentColor(customColor);
      expect(state.accentColor.toARGB32(), customColor.toARGB32());

      final darkTheme = AppTheme.buildDarkTheme(accentColor: state.accentColor);
      expect(darkTheme.colorScheme.primary.toARGB32(), customColor.toARGB32());

      final lightTheme = AppTheme.buildLightTheme(accentColor: state.accentColor);
      expect(lightTheme.colorScheme.primary.toARGB32(), customColor.toARGB32());
    });
  });

  group('Requirement 5: Vehicle Specs & Dyno Heuristics', () {
    test('Generates stock and modded specs with performance gains', () async {
      final gemini = GeminiService('fake-key');
      final car = Vehicle(
        year: '2020',
        make: 'Ford',
        model: 'Mustang GT',
        mods: 'Turbo, ECU tune, cat-back exhaust',
      );

      // Using the offline heuristic fallback
      final specs = await gemini.fetchVehicleSpecs(car);
      expect(specs.containsKey('stock'), isTrue);
      expect(specs.containsKey('modded'), isTrue);
      expect(specs.containsKey('breakdown'), isTrue);

      final stock = specs['stock'] as Map<String, dynamic>;
      final modded = specs['modded'] as Map<String, dynamic>;

      expect(stock['horsepower'], isNotNull);
      expect(modded['horsepower'], isNotNull);
      expect(modded['hpGain'], isNotNull);
    });
  });

  group('Requirement 6 & 7: Mockup References, Follow-up & History', () {
    test('Mockup history stores items and supports deletion', () async {
      final state = AppState();
      await state.load();

      final item1 = MockupItem(
        vehicleName: '2020 Ford Mustang GT',
        prompt: 'Lowered on bronze wheels',
        imageBase64: base64Encode([1, 2, 3]),
        isFollowup: false,
      );

      await state.addMockup(item1);
      expect(state.mockupHistory.length, 1);
      expect(state.mockupHistory.first.isFollowup, isFalse);

      final item2 = MockupItem(
        vehicleName: '2020 Ford Mustang GT',
        prompt: 'Add carbon fiber GT wing',
        imageBase64: base64Encode([4, 5, 6]),
        isFollowup: true,
        parentMockupId: item1.id,
      );

      await state.addMockup(item2);
      expect(state.mockupHistory.length, 2);
      expect(state.mockupHistory.first.isFollowup, isTrue);

      await state.deleteMockup(item1.id);
      expect(state.mockupHistory.length, 1);
      expect(state.mockupHistory.first.id, item2.id);
    });
  });

  group('Requirement 7: Chat History & Sessions', () {
    test('Chat sessions are created and managed', () async {
      final state = AppState();
      await state.load();

      final session1 = await state.createNewChatSession(title: 'Mod Discussion');
      expect(state.chatSessions.first.id, session1.id);

      await state.addMessageToActiveSession(ChatMessage(
        role: 'user',
        text: 'What exhaust should I get?',
      ));

      expect(state.activeChatSession.messages.length, greaterThanOrEqualTo(2));

      final session2 = await state.createNewChatSession(title: 'Track Setup');
      expect(state.activeChatSessionId, session2.id);
      expect(state.chatSessions.length, 2);

      await state.selectChatSession(session1.id);
      expect(state.activeChatSessionId, session1.id);
    });
  });

  group('Import / Export Full Profile (including API Key)', () {
    test('Exports all state including API key to JSON and imports it back accurately', () async {
      final state1 = AppState();
      await state1.load();

      const testKey = 'AIzaSyTestApiKey123456789';
      await state1.saveApiKey(testKey);
      await state1.setThemeMode(ThemeMode.light);
      const testColor = Color(0xFFFF6D00); // Electric Orange
      await state1.setAccentColor(testColor);

      final car = Vehicle(
        type: 'Car',
        year: '2024',
        make: 'Chevrolet',
        model: 'Corvette Z06',
        color: 'Torch Red',
        mods: 'Corsa valved exhaust',
        imagesBase64: [base64Encode([100, 101, 102])],
      );
      await state1.addVehicle(car);
      await state1.selectVehicle(car.id);

      await state1.createNewChatSession(title: 'Z06 Mod Session');
      await state1.addMessageToActiveSession(ChatMessage(
        role: 'user',
        text: 'Should I do aero or headers first?',
      ));

      final mockup = MockupItem(
        vehicleId: car.id,
        vehicleName: car.displayName,
        prompt: 'Lowered on carbon fiber wheels in neon track paddock',
        imageBase64: base64Encode([200, 201, 202]),
        isFollowup: false,
      );
      await state1.addMockup(mockup);

      // Export JSON
      final exportedJson = state1.exportToJson();

      // Verify JSON contains everything including the API key
      expect(exportedJson.contains(testKey), isTrue);
      expect(exportedJson.contains('Corvette Z06'), isTrue);
      expect(exportedJson.contains('Z06 Mod Session'), isTrue);
      expect(exportedJson.contains('neon track paddock'), isTrue);
      expect(exportedJson.contains('light'), isTrue);

      // Import into a fresh AppState
      final state2 = AppState();
      await state2.load();
      await state2.importFromJson(exportedJson);

      // Verify all imported state
      expect(state2.apiKey, testKey);
      expect(state2.themeMode, ThemeMode.light);
      expect(state2.accentColor.toARGB32(), testColor.toARGB32());
      expect(state2.selectedVehicle.displayName, '2024 Chevrolet Corvette Z06');
      expect(state2.selectedVehicle.imagesBase64.length, 1);
      expect(state2.chatSessions.any((s) => s.title == 'Z06 Mod Session'), isTrue);
      expect(state2.mockupHistory.length, 1);
      expect(state2.mockupHistory.first.prompt, contains('carbon fiber wheels'));
    });
  });
}

