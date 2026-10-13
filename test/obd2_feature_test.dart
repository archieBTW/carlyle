import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tuner/models.dart';
import 'package:ai_tuner/services/obd2_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OBD2 Telemetry & Data Logging Tests', () {
    test('Obd2Telemetry serialization and deserialization', () {
      final now = DateTime.now();
      final tel = Obd2Telemetry(
        rpm: 3450.0,
        speedKmh: 80.0,
        speedMph: 49.7,
        coolantTempC: 88.0,
        coolantTempF: 190.4,
        iatC: 28.0,
        iatF: 82.4,
        engineLoad: 42.5,
        throttlePosition: 35.0,
        voltage: 14.2,
        maf: 28.5,
        fuelLevel: 65.0,
        timestamp: now,
      );

      final map = tel.toMap();
      final fromMap = Obd2Telemetry.fromMap(map);

      expect(fromMap.rpm, 3450.0);
      expect(fromMap.speedMph, 49.7);
      expect(fromMap.coolantTempF, 190.4);
      expect(fromMap.engineLoad, 42.5);
      expect(fromMap.voltage, 14.2);
      expect(fromMap.maf, 28.5);
    });

    test('Obd2LogSession calculates statistics and generates CSV correctly', () {
      final t0 = DateTime.now();
      final t1 = t0.add(const Duration(seconds: 1));
      final t2 = t0.add(const Duration(seconds: 2));

      final session = Obd2LogSession(
        title: '3rd Gear Pull',
        vehicleName: '2020 Ford Mustang GT',
        startTime: t0,
        endTime: t2,
        dataPoints: [
          Obd2Telemetry(
            rpm: 2500.0,
            speedMph: 40.0,
            coolantTempF: 195.0,
            engineLoad: 50.0,
            voltage: 14.2,
            timestamp: t0,
          ),
          Obd2Telemetry(
            rpm: 6500.0,
            speedMph: 85.0,
            coolantTempF: 198.0,
            engineLoad: 95.0,
            voltage: 14.3,
            timestamp: t1,
          ),
          Obd2Telemetry(
            rpm: 4200.0,
            speedMph: 88.0,
            coolantTempF: 199.0,
            engineLoad: 30.0,
            voltage: 14.1,
            timestamp: t2,
          ),
        ],
      );

      expect(session.sampleCount, 3);
      expect(session.maxRpm, 6500.0);
      expect(session.maxSpeedMph, 88.0);
      expect(session.avgEngineLoad, closeTo(58.33, 0.1));
      expect(session.durationSeconds, 2);

      final csv = session.toCsv();
      expect(csv.contains('Timestamp,TimeSec,RPM,Speed_MPH'), isTrue);
      expect(csv.contains('6500,85.0'), isTrue);
    });
  });

  group('OBD2 DTC & Diagnostic Report Tests', () {
    test('Obd2DiagnosticReport models parts list and repair cost estimates', () {
      final report = Obd2DiagnosticReport(
        vehicleName: '2020 Ford Mustang GT',
        dtcCodes: ['P0301', 'P0171'],
        overallSeverity: 'Critical',
        canDrive: false,
        summary: 'Cylinder 1 misfire accompanied by lean AFR condition.',
        diagnoses: [
          DtcDiagnosisItem(
            code: 'P0301',
            title: 'Cylinder 1 Misfire Detected',
            carSpecificAnalysis:
                'On Coyote 5.0L with cold air intake, check coil 1 and plug gap.',
            commonCauses: ['Fouled spark plug', 'Failed ignition coil'],
          ),
        ],
        recommendedParts: [
          DiagnosticPartItem(
            partName: 'Motorcraft SP-548 Spark Plugs',
            description: 'Iridium plugs for 5.0L Coyote',
            estimatedCost: '\$50 - \$70',
            priority: 'Immediate',
          ),
        ],
        troubleshootingSteps: [
          TroubleshootingStepItem(
            stepNumber: 1,
            title: 'Coil Pack Swap',
            action: 'Swap coil 1 with cylinder 2 to check if code moves to P0302.',
            toolsNeeded: ['8mm socket', 'Ratchet'],
            difficulty: 'Beginner',
          ),
        ],
        costEstimate: DiagnosticCostEstimate(
          diyCost: '\$50 - \$80',
          independentShopCost: '\$160 - \$240',
          dealershipCost: '\$320 - \$450',
          estimatedLaborHours: '1.0 - 1.5 hrs',
          summaryNotes: 'Very accessible DIY repair.',
        ),
        preventativeTips: ['Inspect intake silicone couplers for leaks.'],
      );

      expect(report.dtcCodes, contains('P0301'));
      expect(report.canDrive, isFalse);
      expect(report.recommendedParts.first.partName, contains('Spark Plugs'));
      expect(report.costEstimate.diyCost, '\$50 - \$80');

      // Test map roundtrip
      final map = report.toMap();
      final roundtrip = Obd2DiagnosticReport.fromMap(map);
      expect(roundtrip.dtcCodes, contains('P0301'));
      expect(roundtrip.costEstimate.dealershipCost, '\$320 - \$450');
    });

    test('Obd2Service Simulation Mode triggers telemetry and demo codes', () async {
      final service = Obd2Service();
      expect(service.isConnected, isFalse);

      service.startDemoMode();
      expect(service.isDemoMode, isTrue);
      expect(service.isConnected, isTrue);
      expect(service.connectedDeviceName, contains('Simulated OBD2'));
      expect(service.currentDtcCodes, contains('P0301'));

      // Scan codes in demo mode
      final scanned = await service.scanDtcCodes();
      expect(scanned, contains('P0171'));

      // Clear codes
      final cleared = await service.clearDtcCodes();
      expect(cleared, isTrue);
      expect(service.currentDtcCodes, isEmpty);

      // Add manual code
      service.addManualDtcCode('P0420');
      expect(service.currentDtcCodes, contains('P0420'));

      // Logging in demo mode
      final dummyVehicle = Vehicle(
        year: '2020',
        make: 'Ford',
        model: 'Mustang GT',
      );
      service.startLogging(title: 'Demo Test Run', vehicle: dummyVehicle);
      expect(service.isLogging, isTrue);

      final session = service.stopLogging();
      expect(service.isLogging, isFalse);
      expect(session, isNotNull);
      expect(session!.title, 'Demo Test Run');

      service.stopDemoMode();
      expect(service.isDemoMode, isFalse);
      expect(service.isConnected, isFalse);
      service.dispose();
    });

    test('Real-World ELM327 DTC Decoding correctly handles CAN frames, padding, and multi-line responses', () {
      final service = Obd2Service();

      // Real CAN single-frame response with 1 DTC (P0171) and 00 00 padding
      final singleCan = service.decodeDtcResponseForTesting('43 01 01 71 00 00 00 00');
      expect(singleCan, equals(['P0171']));

      // Compact response without spaces
      final compactCan = service.decodeDtcResponseForTesting('4301017100000000');
      expect(compactCan, equals(['P0171']));

      // Real CAN single-frame with 2 DTCs (P0171, P0301)
      final twoCodes = service.decodeDtcResponseForTesting('43 02 01 71 03 01 00 00');
      expect(twoCodes, equals(['P0171', 'P0301']));

      // Multi-line CAN frame (ISO 15765-2) with frame index prefixes
      const multiFrame = '0: 43 03 01 71 03 01\r\n1: 04 20 00 00 00 00';
      final multiResult = service.decodeDtcResponseForTesting(multiFrame);
      expect(multiResult, equals(['P0171', 'P0301', 'P0420']));

      // Response with CAN ECU ID prefix (e.g. 7E8)
      final ecuHeader = service.decodeDtcResponseForTesting('7E8 06 43 01 01 71 00 00');
      expect(ecuHeader, equals(['P0171']));

      // Mode 07 Pending Code
      final mode07 = service.decodeDtcResponseForTesting('47 01 04 20 00 00');
      expect(mode07, equals(['P0420']));

      // Mode 0A Permanent Code
      final mode0A = service.decodeDtcResponseForTesting('4A 01 01 71 00 00');
      expect(mode0A, equals(['P0171']));

      // Non-powertrain codes (Chassis C0035, Network U0100)
      final chassisAndNetwork = service.decodeDtcResponseForTesting('43 02 40 35 C1 00 00 00');
      expect(chassisAndNetwork, equals(['C0035', 'U0100']));

      // No DTCs reported
      expect(service.decodeDtcResponseForTesting('43 00'), isEmpty);
      expect(service.decodeDtcResponseForTesting('43 00 00 00 00 00 00 00'), isEmpty);
      expect(service.decodeDtcResponseForTesting('NO DATA'), isEmpty);
      expect(service.decodeDtcResponseForTesting('UNABLE TO CONNECT'), isEmpty);

      service.dispose();
    });

    test('Telemetry PID parsers extract values accurately from CAN-padded strings', () {
      final service = Obd2Service();

      // RPM: 41 0C 1A 80 -> ((0x1A * 256) + 0x80) / 4 = 1696.0 RPM
      expect(service.parseRpmForTesting('41 0C 1A 80'), closeTo(1696.0, 0.1));
      expect(service.parseRpmForTesting('410C1A8000000000'), closeTo(1696.0, 0.1));

      // Speed: 41 0D 3C -> 60 km/h
      expect(service.parseSpeedForTesting('41 0D 3C'), 60.0);
      expect(service.parseSpeedForTesting('410D3C00000000'), 60.0);

      // Coolant: 41 05 7B -> 123 - 40 = 83 C
      expect(service.parseTemperatureForTesting('41 05 7B', '4105'), 83.0);

      // Engine Load: 41 04 80 -> 128 * 100 / 255 = ~50.2%
      expect(service.parseLoadForTesting('41 04 80 00 00 00'), closeTo(50.2, 0.2));

      // Battery Voltage: AT RV -> 14.2V
      expect(service.parseVoltageForTesting('14.2V'), 14.2);
      expect(service.parseVoltageForTesting('AT RV 13.8V'), 13.8);

      service.dispose();
    });
  });
}
