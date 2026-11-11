import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_generative_ai/google_generative_ai.dart' hide ChatSession;
import 'package:ai_tuner/gemini_service.dart';
import 'package:ai_tuner/models.dart';

void main() {
  group('AI Assistant Context & Multi-turn Chat Follow-up Tests', () {
    late Vehicle testVehicle;
    late Obd2DiagnosticReport testReport;

    setUp(() {
      testVehicle = Vehicle(
        id: 'veh_123',
        type: 'Car',
        year: '2024',
        make: 'Ford',
        model: 'Mustang',
        trim: 'GT',
        nickname: 'Dark Horse',
        color: 'Vapor Blue',
        mods: 'Cold Air Intake, Corsa Cat-back Exhaust',
        cachedSpecs: {
          'stock': {
            'engine': '5.0L Coyote V8',
            'drivetrain': 'RWD',
            'horsepower': '480 HP',
            'torque': '415 lb-ft',
          },
          'modded': {
            'horsepower': '505 HP',
            'torque': '435 lb-ft',
          }
        },
      );

      testReport = Obd2DiagnosticReport(
        vehicleId: 'veh_123',
        vehicleName: 'Dark Horse',
        dtcCodes: ['P0300', 'P0171'],
        overallSeverity: 'Critical',
        canDrive: false,
        summary: 'Random cylinder misfire combined with System Too Lean Bank 1.',
        diagnoses: [
          DtcDiagnosisItem(
            code: 'P0300',
            title: 'Random/Multiple Cylinder Misfire Detected',
            carSpecificAnalysis:
                'Occurring on 5.0L Coyote V8. High likelihood of spark blowout or unmetered air leak after CAI installation.',
            commonCauses: ['Fouled spark plugs', 'Intake coupler leak', 'Faulty coil pack'],
          ),
          DtcDiagnosisItem(
            code: 'P0171',
            title: 'System Too Lean (Bank 1)',
            carSpecificAnalysis:
                'Aftermarket intake silicone coupler clamp loose near MAF sensor.',
            commonCauses: ['Loose intake clamp', 'Contaminated MAF sensor wire'],
          ),
        ],
        recommendedParts: [
          DiagnosticPartItem(
            partName: 'Iridium Spark Plugs (Cold Heat Range)',
            description: 'OEM/Performance spec gapped for CAI',
            estimatedCost: '\$60 - \$90',
            priority: 'Immediate',
          ),
          DiagnosticPartItem(
            partName: 'Silicone Coupler & T-Bolt Clamps',
            description: 'Airtight intake seal',
            estimatedCost: '\$25 - \$40',
            priority: 'Recommended',
          ),
        ],
        troubleshootingSteps: [
          TroubleshootingStepItem(
            stepNumber: 1,
            title: 'Check Intake Couplers and Vacuum Lines',
            action: 'Inspect all silicone couplers from airbox to throttle body for unmetered air leaks.',
            toolsNeeded: ['Flathead screwdriver', 'Carb cleaner spray'],
            difficulty: 'Beginner',
          ),
          TroubleshootingStepItem(
            stepNumber: 2,
            title: 'Inspect Spark Plug Gaps',
            action: 'Pull cylinder 1 and 2 spark plugs and check electrode color and gap.',
            toolsNeeded: ['5/8" spark plug socket', 'Feeler gauge'],
            difficulty: 'Intermediate',
          ),
        ],
        costEstimate: DiagnosticCostEstimate(
          diyCost: '\$70 - \$120',
          independentShopCost: '\$220 - \$350',
          dealershipCost: '\$450 - \$650',
          estimatedLaborHours: '1.5 - 2.0 hrs',
          summaryNotes: 'DIY fixable with basic hand tools.',
        ),
        preventativeTips: [
          'Ensure intake clamps are torqued properly after mod installations.',
        ],
      );
    });

    test('buildSystemInstruction formats vehicle details, mods, and active OBD2 DTC trouble codes', () {
      final sysText = GeminiService.buildSystemInstruction(
        vehicle: testVehicle,
        diagnosticReports: [testReport],
      );

      // Verify persona and critical context instruction
      expect(sysText, contains('Carlyle'));
      expect(sysText, contains('CRITICAL: You MUST maintain and remember the complete context'));

      // Verify active vehicle details
      expect(sysText, contains('2024 Ford Mustang GT'));
      expect(sysText, contains('Dark Horse'));
      expect(sysText, contains('Cold Air Intake, Corsa Cat-back Exhaust'));
      expect(sysText, contains('5.0L Coyote V8'));
      expect(sysText, contains('505 HP'));

      // Verify active trouble code diagnostics
      expect(sysText, contains('P0300, P0171'));
      expect(sysText, contains('Critical'));
      expect(sysText, contains('NO - Risk of Engine Damage'));
      expect(sysText, contains('Random/Multiple Cylinder Misfire Detected'));
      expect(sysText, contains('System Too Lean (Bank 1)'));
      expect(sysText, contains('Iridium Spark Plugs'));
      expect(sysText, contains('Check Intake Couplers and Vacuum Lines'));
      expect(sysText, contains('DIY \$70 - \$120'));

      // Verify follow-up instructions
      expect(sysText, contains('Never ask the user to repeat the code'));
      expect(sysText, contains('answer immediately referencing the active code(s)'));
    });

    test('formatChatHistory skips leading assistant greetings so first turn is user role', () {
      final messages = [
        ChatMessage(
          role: 'assistant',
          text: 'Hey there! I am Carlyle. How can I help you today?',
        ),
        ChatMessage(
          role: 'user',
          text: 'What does code P0300 mean on my Mustang?',
        ),
      ];

      final contents = GeminiService.formatChatHistory(
        history: messages,
      );

      expect(contents.length, 1);
      expect(contents.first.role, 'user');
      expect((contents.first.parts.first as TextPart).text, 'What does code P0300 mean on my Mustang?');
    });

    test('formatChatHistory preserves multi-turn conversation and strictly alternates roles', () {
      final messages = [
        ChatMessage(
          role: 'assistant',
          text: 'Greeting message',
        ),
        ChatMessage(
          role: 'user',
          text: 'I have trouble code P0300.',
        ),
        ChatMessage(
          role: 'assistant',
          text: 'P0300 indicates a random misfire. Check your spark plugs and coils.',
        ),
        ChatMessage(
          role: 'user',
          text: 'What tools do I need for that?',
        ),
      ];

      final contents = GeminiService.formatChatHistory(
        history: messages,
      );

      // Should have 3 turns: user -> model -> user
      expect(contents.length, 3);
      expect(contents[0].role, 'user');
      expect((contents[0].parts.first as TextPart).text, 'I have trouble code P0300.');

      expect(contents[1].role, 'model');
      expect((contents[1].parts.first as TextPart).text, contains('random misfire'));

      expect(contents[2].role, 'user');
      expect((contents[2].parts.first as TextPart).text, 'What tools do I need for that?');
    });

    test('formatChatHistory drops empty placeholder messages and merges consecutive same-role turns', () {
      final messages = [
        ChatMessage(role: 'user', text: 'First message'),
        ChatMessage(role: 'user', text: 'Second consecutive message from user'),
        ChatMessage(role: 'assistant', text: 'Response from assistant'),
        ChatMessage(role: 'assistant', text: 'Follow-up info from assistant'),
        ChatMessage(role: 'user', text: 'Next prompt'),
        ChatMessage(role: 'assistant', text: ''), // Streaming placeholder
      ];

      final contents = GeminiService.formatChatHistory(
        history: messages,
      );

      // Should be strictly alternating: user -> model -> user
      expect(contents.length, 3);
      expect(contents[0].role, 'user');
      expect(contents[0].parts.length, 2); // merged 2 user parts

      expect(contents[1].role, 'model');
      expect(contents[1].parts.length, 2); // merged 2 assistant parts

      expect(contents[2].role, 'user');
      expect((contents[2].parts.first as TextPart).text, 'Next prompt');
    });

    test('formatChatHistory includes image parts for multimodal diagnostic requests', () {
      final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b64 = base64Encode(dummyBytes);

      final messages = [
        ChatMessage(
          role: 'user',
          text: 'Does this spark plug look fouled?',
          imageBase64: b64,
        ),
      ];

      final contents = GeminiService.formatChatHistory(
        history: messages,
      );

      expect(contents.length, 1);
      expect(contents.first.role, 'user');
      final parts = contents.first.parts;
      expect(parts.any((p) => p is DataPart), isTrue);
      expect(parts.any((p) => p is TextPart), isTrue);
    });

    test('Chat session retains context when user asks a follow-up after OBD2 scan', () {
      final session = ChatSession(
        title: 'OBD2: P0300, P0171',
        messages: [
          ChatMessage(
            role: 'user',
            text: 'I just scanned my Dark Horse and found DTC codes: P0300, P0171. Can you help me troubleshoot further?',
          ),
          ChatMessage(
            role: 'assistant',
            text: 'I reviewed your report for P0300 and P0171. P0300 is misfire and P0171 is running lean. Start by inspecting the intake couplers for unmetered air leaks.',
          ),
          ChatMessage(
            role: 'user',
            text: 'Give me a follow up of that code: how do I inspect the couplers?',
          ),
          ChatMessage(
            role: 'assistant',
            text: '', // Active streaming message
          ),
        ],
      );

      final contents = GeminiService.formatChatHistory(
        history: session.messages,
      );

      // Both the OBD2 code context and the follow-up prompt are preserved in order
      expect(contents.length, 3);
      expect(contents[0].role, 'user');
      expect((contents[0].parts.first as TextPart).text, contains('P0300, P0171'));

      expect(contents[1].role, 'model');
      expect((contents[1].parts.first as TextPart).text, contains('intake couplers'));

      expect(contents[2].role, 'user');
      expect((contents[2].parts.first as TextPart).text, contains('Give me a follow up of that code'));
    });
  });
}
