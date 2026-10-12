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
  });
}
