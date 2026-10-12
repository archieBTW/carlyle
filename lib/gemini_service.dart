import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class GeminiService {
  final String apiKey;
  late final GenerativeModel _model;
  late final GenerativeModel _visionModel;

  GeminiService(this.apiKey) {
    _model = GenerativeModel(
      model: 'gemini-3.5-flash-lite',
      apiKey: apiKey,
    );
    _visionModel = GenerativeModel(
      model: 'gemini-3.8-flash',
      apiKey: apiKey,
    );
  }

  Stream<String> askAssistantStream(String prompt, {Uint8List? imageBytes}) async* {
    try {
      if (imageBytes != null) {
        final content = [
          Content.multi([
            TextPart(prompt),
            DataPart('image/jpeg', imageBytes),
          ])
        ];
        await for (final chunk in _visionModel.generateContentStream(content)) {
          if (chunk.text != null) yield chunk.text!;
        }
      } else {
        final content = [Content.text(prompt)];
        await for (final chunk in _model.generateContentStream(content)) {
          if (chunk.text != null) yield chunk.text!;
        }
      }
    } catch (e) {
      yield 'Error: $e';
    }
  }

  Future<String> generateMockupPrompt(
    String vehicleInfo,
    String desiredMods, {
    bool hasReferencePhotos = false,
    bool isFollowup = false,
  }) async {
    String systemInstruction;
    if (isFollowup) {
      systemInstruction = '''
You are an expert car/motorcycle renderer prompt engineer.
The user wants to make a FOLLOW-UP modification to an existing vehicle rendering.
Vehicle Base: $vehicleInfo
Requested Changes: $desiredMods

Write an ultra-detailed, cinematic image generation prompt describing these exact modifications applied to the previous image. Keep consistency with the vehicle's perspective, color, and design while integrating the new modifications photorealistically. Output only the final prompt paragraph, no formatting, no conversational filler.
''';
    } else if (hasReferencePhotos) {
      systemInstruction = '''
You are an expert car/motorcycle renderer prompt engineer.
Reference photos of the actual vehicle are provided to the image generation model.
Vehicle: $vehicleInfo
Desired modifications: $desiredMods

Create an ultra-detailed, photorealistic prompt for generating this vehicle with the modifications. Explicitly emphasize matching the exact body lines, angle, color, and trim of the vehicle seen in the attached photo(s) while rendering the specified modifications seamlessly. Single paragraph, photorealistic, 8k, cinematic automotive photography style.
''';
    } else {
      systemInstruction = '''
You are an expert car/motorcycle renderer prompt engineer.
Vehicle: $vehicleInfo
Desired modifications: $desiredMods

Create a highly detailed, photorealistic prompt for an AI image generator to render this exact vehicle with the modifications in a cool, cinematic setting. Output only a single paragraph, no markdown, just the image prompt text focusing on visual details, lighting, angles, and textures.
''';
    }

    try {
      final response = await _model.generateContent([Content.text(systemInstruction)]);
      final text = response.text?.trim();
      if (text != null && text.isNotEmpty) return text;
    } catch (_) {}

    return '$vehicleInfo with $desiredMods, photorealistic, 8k automotive photography, cinematic lighting';
  }

  Future<Uint8List?> generateMockupImageDirect(
    String prompt,
    String keyToUse, {
    List<Uint8List>? referenceImages,
  }) async {
    final effectiveKey = keyToUse.isNotEmpty ? keyToUse : apiKey;
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent?key=$effectiveKey');

    final parts = <Map<String, dynamic>>[];

    // Include reference images if provided (up to 3 for initial, or 1 for followup)
    if (referenceImages != null && referenceImages.isNotEmpty) {
      for (final img in referenceImages) {
        parts.add({
          "inlineData": {
            "mimeType": "image/jpeg",
            "data": base64Encode(img),
          }
        });
      }
    }

    parts.add({"text": prompt});

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "contents": [
          {"parts": parts}
        ],
        "generationConfig": {
          "responseModalities": ["IMAGE"]
        }
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final candidates = json['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        if (content != null) {
          final pList = content['parts'] as List?;
          if (pList != null && pList.isNotEmpty) {
            for (final part in pList) {
              final inlineData = part['inlineData'];
              if (inlineData != null) {
                final b64 = inlineData['data'] as String?;
                if (b64 != null) {
                  return base64Decode(b64);
                }
              }
            }
          }
        }
      }
    } else {
      throw Exception('Gemini API Error ${response.statusCode}: ${response.body}');
    }
    return null;
  }

  Future<Map<String, dynamic>> fetchVehicleSpecs(Vehicle vehicle) async {
    final prompt = '''
You are an expert automotive and motorcycle performance engineer and dyno specialist.
Analyze this vehicle and its installed modifications:
- Type: ${vehicle.type}
- Year/Make/Model: ${vehicle.year} ${vehicle.make} ${vehicle.model}
- Trim: ${vehicle.trim}
- Current Mods: ${vehicle.mods.isEmpty ? 'Stock (No modifications listed)' : vehicle.mods}

Return a valid JSON object strictly matching this schema with realistic factory numbers and estimated gains with the mods:
```json
{
  "stock": {
    "horsepower": "450 HP",
    "torque": "410 lb-ft",
    "zeroToSixty": "4.2s",
    "engine": "5.0L V8",
    "drivetrain": "RWD",
    "transmission": "6-Speed Manual",
    "curbWeight": "3,705 lbs",
    "topSpeed": "155 mph"
  },
  "modded": {
    "horsepower": "485 HP",
    "torque": "435 lb-ft",
    "zeroToSixty": "3.9s",
    "hpGain": "+35 HP",
    "torqueGain": "+25 lb-ft",
    "zeroToSixtyDiff": "-0.3s"
  },
  "breakdown": [
    {
      "mod": "Name of modification",
      "impact": "+15-20 HP, improved airflow",
      "type": "Power"
    }
  ],
  "dynoNotes": "Detailed technical analysis of how the modifications impact power delivery, throttle response, and overall handling."
}
```
Only return raw JSON. No conversational wrapper.
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        final parsed = jsonDecode(jsonMatch.group(0)!);
        if (parsed is Map<String, dynamic>) {
          return parsed;
        }
      }
    } catch (_) {}

    // Return smart fallback heuristic if API call fails
    return _generateFallbackSpecs(vehicle);
  }

  Map<String, dynamic> _generateFallbackSpecs(Vehicle vehicle) {
    final isMoto = vehicle.isMotorcycle;
    final mods = vehicle.mods.toLowerCase();

    int baseHp = isMoto ? 115 : 310;
    int baseTorque = isMoto ? 75 : 290;
    double base060 = isMoto ? 3.4 : 5.4;

    int gainHp = 0;
    int gainTorque = 0;
    double drop060 = 0.0;

    final breakdown = <Map<String, dynamic>>[];

    if (mods.contains('turbo') || mods.contains('supercharger')) {
      gainHp += 80;
      gainTorque += 75;
      drop060 += 0.7;
      breakdown.add({
        "mod": "Forced Induction / Boost",
        "impact": "+80 HP / +75 lb-ft, massive mid & top-end surge",
        "type": "Power"
      });
    }

    if (mods.contains('tune') || mods.contains('ecu')) {
      gainHp += 25;
      gainTorque += 30;
      drop060 += 0.2;
      breakdown.add({
        "mod": "ECU Performance Tune",
        "impact": "+25 HP / +30 lb-ft, sharpened throttle & fuel maps",
        "type": "Tuning"
      });
    }

    if (mods.contains('exhaust') || mods.contains('downpipe') || mods.contains('header')) {
      gainHp += 15;
      gainTorque += 12;
      drop060 += 0.1;
      breakdown.add({
        "mod": "Performance Exhaust",
        "impact": "+15 HP, reduced backpressure and rich tone",
        "type": "Exhaust"
      });
    }

    if (mods.contains('intake') || mods.contains('cai')) {
      gainHp += 10;
      gainTorque += 8;
      drop060 += 0.1;
      breakdown.add({
        "mod": "High-Flow Cold Air Intake",
        "impact": "+10 HP, enhanced induction sound & spool",
        "type": "Intake"
      });
    }

    if (mods.contains('suspension') || mods.contains('coilover') || mods.contains('spring')) {
      breakdown.add({
        "mod": "Sport Suspension / Coilovers",
        "impact": "Lowered center of gravity, reduced body roll",
        "type": "Handling"
      });
    }

    if (breakdown.isEmpty) {
      breakdown.add({
        "mod": vehicle.mods.isEmpty ? "Factory Stock" : vehicle.mods,
        "impact": vehicle.mods.isEmpty ? "Original OEM baseline specs" : "Estimated +10-15% modest gain across band",
        "type": "Baseline"
      });
      if (vehicle.mods.isNotEmpty) {
        gainHp = 15;
        gainTorque = 10;
        drop060 = 0.1;
      }
    }

    final modHp = baseHp + gainHp;
    final modTorque = baseTorque + gainTorque;
    final mod060 = (base060 - drop060).clamp(1.9, 15.0);

    return {
      "stock": {
        "horsepower": "$baseHp HP",
        "torque": "$baseTorque lb-ft",
        "zeroToSixty": "${base060.toStringAsFixed(1)}s",
        "engine": isMoto ? "Inline-4 / Twin Engine" : "Gasoline Performance Engine",
        "drivetrain": isMoto ? "Chain Drive" : "RWD / AWD",
        "transmission": isMoto ? "6-Speed Sequential" : "Manual / Automatic",
        "curbWeight": isMoto ? "420 lbs" : "3,500 lbs",
        "topSpeed": isMoto ? "160 mph" : "155 mph",
      },
      "modded": {
        "horsepower": "$modHp HP",
        "torque": "$modTorque lb-ft",
        "zeroToSixty": "${mod060.toStringAsFixed(1)}s",
        "hpGain": gainHp > 0 ? "+$gainHp HP" : "Stock",
        "torqueGain": gainTorque > 0 ? "+$gainTorque lb-ft" : "Stock",
        "zeroToSixtyDiff": drop060 > 0 ? "-${drop060.toStringAsFixed(1)}s" : "0.0s",
      },
      "breakdown": breakdown,
      "dynoNotes":
          "Dyno projection based on vehicle architecture and listed modifications. Gains reflect realistic wheel output improvements."
    };
  }

  Future<Obd2DiagnosticReport> diagnoseTroubleCodes({
    required Vehicle vehicle,
    required List<String> dtcCodes,
    String? userNotes,
  }) async {
    final vehicleDesc =
        '${vehicle.year} ${vehicle.make} ${vehicle.model} ${vehicle.trim}'
            .trim();
    final modsDesc =
        vehicle.mods.trim().isEmpty ? 'Stock (no modifications)' : vehicle.mods;
    final engineDesc = vehicle.cachedSpecs?['stock']?['engine'] ??
        (vehicle.isMotorcycle ? 'Motorcycle Engine' : 'Performance Engine');

    final prompt = '''
You are a master ASE-certified automotive diagnostic technician, tuner, and powertrain specialist.
Analyze these scanned OBD2 Diagnostic Trouble Codes (DTCs) matched specifically to this exact vehicle and its installed modifications:

Vehicle: $vehicleDesc
Type: ${vehicle.type}
Engine: $engineDesc
Current Modifications: $modsDesc
Scanned Trouble Codes: ${dtcCodes.join(', ')}
${userNotes != null && userNotes.isNotEmpty ? 'Driver Observed Symptoms: $userNotes' : ''}

You MUST match each trouble code to this specific vehicle architecture, taking into account how installed modifications (e.g. cold air intake, downpipe/exhaust, aftermarket tune, boost levels) may be causing or contributing to the issue (e.g. MAF scaling issues, running lean, secondary O2 sensor bypass, misfire under higher cylinder pressure).

Return a valid JSON object strictly adhering to this schema:
```json
{
  "overallSeverity": "Critical | Moderate | Minor",
  "canDrive": true,
  "summary": "Clear, informative 2-3 sentence overview of the diagnosed problem for this specific vehicle and configuration.",
  "diagnoses": [
    {
      "code": "P0301",
      "title": "Cylinder 1 Misfire Detected",
      "carSpecificAnalysis": "Technical breakdown of why this occurs on this specific engine, what to look for with the installed mods, and whether fuel trim/boost played a role.",
      "commonCauses": [
        "Worn or fouled spark plug gap",
        "Failed ignition coil pack",
        "Intake runner air leak"
      ]
    }
  ],
  "recommendedParts": [
    {
      "partName": "OEM / Performance Spark Plug Set",
      "description": "Iridium plugs gapped for current mod level",
      "estimatedCost": "\$40 - \$75",
      "priority": "Immediate"
    }
  ],
  "troubleshootingSteps": [
    {
      "stepNumber": 1,
      "title": "Ignition Coil Swap Test",
      "action": "Swap coil pack from offending cylinder with an adjacent cylinder to verify if fault migrates.",
      "toolsNeeded": ["Socket set", "Torque wrench"],
      "difficulty": "Beginner"
    }
  ],
  "costEstimate": {
    "diyCost": "\$45 - \$80",
    "independentShopCost": "\$150 - \$240",
    "dealershipCost": "\$300 - \$450",
    "estimatedLaborHours": "1.0 - 1.5 hrs",
    "summaryNotes": "Very DIY accessible; dealership rates include diagnostic fee and OEM markup."
  },
  "preventativeTips": [
    "Regularly inspect intake silicone couplers for vacuum leaks after installing aftermarket intakes",
    "Check spark plug gaps when increasing boost or installing ECU tunes"
  ]
}
```
Only return the raw JSON object. No conversational filler or markdown other than the json block.
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        final parsed = jsonDecode(jsonMatch.group(0)!);
        if (parsed is Map<String, dynamic>) {
          return _parseDiagnosticReport(vehicle, dtcCodes, parsed);
        }
      }
    } catch (_) {}

    return _generateFallbackDiagnosticReport(vehicle, dtcCodes);
  }

  Obd2DiagnosticReport _parseDiagnosticReport(
    Vehicle vehicle,
    List<String> codes,
    Map<String, dynamic> json,
  ) {
    final diagnosesList = <DtcDiagnosisItem>[];
    if (json['diagnoses'] is List) {
      for (final item in json['diagnoses']) {
        if (item is Map<String, dynamic>) {
          diagnosesList.add(DtcDiagnosisItem.fromMap(item));
        }
      }
    }

    final partsList = <DiagnosticPartItem>[];
    if (json['recommendedParts'] is List) {
      for (final item in json['recommendedParts']) {
        if (item is Map<String, dynamic>) {
          partsList.add(DiagnosticPartItem.fromMap(item));
        }
      }
    }

    final stepsList = <TroubleshootingStepItem>[];
    if (json['troubleshootingSteps'] is List) {
      for (final item in json['troubleshootingSteps']) {
        if (item is Map<String, dynamic>) {
          stepsList.add(TroubleshootingStepItem.fromMap(item));
        }
      }
    }

    final costMap = json['costEstimate'] is Map<String, dynamic>
        ? json['costEstimate'] as Map<String, dynamic>
        : <String, dynamic>{};

    final costEstimate = DiagnosticCostEstimate(
      diyCost: costMap['diyCost']?.toString() ?? '\$50 - \$100',
      independentShopCost:
          costMap['independentShopCost']?.toString() ?? '\$160 - \$260',
      dealershipCost: costMap['dealershipCost']?.toString() ?? '\$320 - \$480',
      estimatedLaborHours:
          costMap['estimatedLaborHours']?.toString() ?? '1.0 - 2.0 hrs',
      summaryNotes: costMap['summaryNotes']?.toString() ??
          'Estimates based on national averages for this make/model.',
    );

    final prevTips = <String>[];
    if (json['preventativeTips'] is List) {
      for (final tip in json['preventativeTips']) {
        if (tip != null) prevTips.add(tip.toString());
      }
    }

    return Obd2DiagnosticReport(
      vehicleId: vehicle.id,
      vehicleName: vehicle.displayName,
      dtcCodes: codes,
      overallSeverity: json['overallSeverity']?.toString() ?? 'Moderate',
      canDrive: json['canDrive'] is bool ? json['canDrive'] as bool : true,
      summary: json['summary']?.toString() ??
          'Diagnostic evaluation for ${codes.join(", ")} on ${vehicle.displayName}.',
      diagnoses: diagnosesList,
      recommendedParts: partsList,
      troubleshootingSteps: stepsList,
      costEstimate: costEstimate,
      preventativeTips: prevTips,
    );
  }

  Obd2DiagnosticReport _generateFallbackDiagnosticReport(
    Vehicle vehicle,
    List<String> codes,
  ) {
    final vehicleName = vehicle.displayName;
    final isTuned = vehicle.mods.toLowerCase().contains('tune') ||
        vehicle.mods.toLowerCase().contains('intake') ||
        vehicle.mods.toLowerCase().contains('downpipe');

    final diagnoses = <DtcDiagnosisItem>[];
    final parts = <DiagnosticPartItem>[];
    final steps = <TroubleshootingStepItem>[];
    String severity = 'Moderate';
    bool canDrive = true;

    for (final code in codes) {
      final c = code.toUpperCase();
      if (c.startsWith('P030')) {
        severity = 'Critical';
        canDrive = false;
        final cyl = c == 'P0300' ? 'Random / Multiple' : 'Cylinder ${c.replaceAll(RegExp(r'[^0-9]'), '').substring(3)}';
        diagnoses.add(DtcDiagnosisItem(
          code: c,
          title: '$cyl Misfire Detected',
          carSpecificAnalysis:
              'Misfire on $vehicleName ($cyl). With installed mods ($vehicle.mods), check ignition coils and plug gap immediately. High boost or intake flow can blow out the spark.',
          commonCauses: [
            'Fouled or incorrectly gapped spark plug',
            'Degraded ignition coil pack boot or resistor',
            'Clogged or sticky fuel injector',
            'Intake air leak / vacuum leak post-MAF',
          ],
        ));
        parts.add(DiagnosticPartItem(
          partName: 'Performance Spark Plugs (Cold Heat Range)',
          description: 'Matched to $vehicleName engine & tune',
          estimatedCost: '\$45 - \$70',
          priority: 'Immediate',
        ));
        parts.add(DiagnosticPartItem(
          partName: 'Ignition Coil Pack',
          description: 'Direct OEM or high-output performance coil',
          estimatedCost: '\$55 - \$95 each',
          priority: 'Recommended',
        ));
        steps.add(TroubleshootingStepItem(
          stepNumber: 1,
          title: 'Swap Coil Pack to Adjacent Cylinder',
          action: 'Move the coil from the misfiring cylinder to cylinder 2. Clear codes and re-scan. If the code follows, replace that coil.',
          toolsNeeded: ['8mm/10mm socket', 'Ratchet', 'Extension'],
          difficulty: 'Beginner',
        ));
        steps.add(TroubleshootingStepItem(
          stepNumber: 2,
          title: 'Inspect Spark Plug Condition & Gap',
          action: 'Remove spark plug and inspect ceramic insulator for hairline cracks or fuel fouling. Re-gap to OEM spec.',
          toolsNeeded: ['Spark plug socket (5/8")', 'Feeler gauge', 'Torque wrench'],
          difficulty: 'Intermediate',
        ));
      } else if (c == 'P0171' || c == 'P0174') {
        final bank = c == 'P0171' ? 'Bank 1' : 'Bank 2';
        diagnoses.add(DtcDiagnosisItem(
          code: c,
          title: 'System Too Lean ($bank)',
          carSpecificAnalysis:
              'ECU fuel trims on $vehicleName have reached max enrichment limit (+25%). If an aftermarket cold air intake is fitted, unmetered air or altered MAF housing diameter is the most probable cause.',
          commonCauses: [
            'Loose intake coupler clamp / vacuum leak',
            'Dirty or contaminated Mass Air Flow (MAF) sensor wire',
            'Weak fuel pump or clogged fuel filter',
            'Faulty upstream O2 sensor',
          ],
        ));
        parts.add(DiagnosticPartItem(
          partName: 'MAF Sensor Cleaner Spray',
          description: 'Specialized quick-evaporating electronics cleaner',
          estimatedCost: '\$10 - \$15',
          priority: 'Immediate',
        ));
        parts.add(DiagnosticPartItem(
          partName: 'Silicone Intake Coupler / T-Bolt Clamps',
          description: 'Ensure airtight seal on intake tubing',
          estimatedCost: '\$20 - \$35',
          priority: 'Recommended',
        ));
        steps.add(TroubleshootingStepItem(
          stepNumber: 1,
          title: 'Inspect Intake Couplers & Vacuum Hoses',
          action: 'Visually and physically inspect all connections between the air filter and throttle body. Spray soapy water or carb cleaner around joints while idling.',
          toolsNeeded: ['Screwdriver', 'Pliers'],
          difficulty: 'Beginner',
        ));
        steps.add(TroubleshootingStepItem(
          stepNumber: 2,
          title: 'Clean the MAF Sensor',
          action: 'Disconnect battery, remove MAF sensor, spray with MAF cleaner, allow to dry completely, reinstall.',
          toolsNeeded: ['Torx / screwdriver', 'MAF cleaner'],
          difficulty: 'Beginner',
        ));
      } else if (c == 'P0420' || c == 'P0430') {
        final bank = c == 'P0420' ? 'Bank 1' : 'Bank 2';
        severity = 'Minor';
        diagnoses.add(DtcDiagnosisItem(
          code: c,
          title: 'Catalyst System Efficiency Below Threshold ($bank)',
          carSpecificAnalysis:
              'Downstream O2 sensor reading matches upstream sensor, indicating catalytic converter isn\'t scrubbing exhaust gases efficiently. If an aftermarket downpipe or high-flow cat is installed, this is common unless tuned.',
          commonCauses: [
            'Exhaust leak near catalytic converter',
            'High-flow aftermarket catalytic converter or downpipe',
            'Failing downstream Heated O2 Sensor (HO2S)',
            'Degraded catalytic converter substrate',
          ],
        ));
        parts.add(DiagnosticPartItem(
          partName: 'Downstream O2 Sensor (Oxygen Sensor)',
          description: 'OEM wideband/narrowband downstream sensor',
          estimatedCost: '\$65 - \$120',
          priority: 'Recommended',
        ));
        steps.add(TroubleshootingStepItem(
          stepNumber: 1,
          title: 'Check Exhaust for Pre-Cat or Post-Cat Leaks',
          action: 'Listen for exhaust ticking or hissing near headers and mid-pipe flanges while vehicle warms up.',
          toolsNeeded: ['Ramps / Jack stands', 'Flashlight'],
          difficulty: 'Intermediate',
        ));
      } else {
        diagnoses.add(DtcDiagnosisItem(
          code: c,
          title: 'Diagnostic Trouble Code $c',
          carSpecificAnalysis:
              'Identified on $vehicleName. Corresponds to vehicle subsystem malfunction that triggered the Check Engine light.',
          commonCauses: [
            'Wiring harness or connector corrosion',
            'Sensor signal out of calibrated range',
            'Component mechanical wear or failure',
          ],
        ));
        parts.add(DiagnosticPartItem(
          partName: 'Replacement Sensor / Assembly for $c',
          description: 'OEM-grade direct replacement',
          estimatedCost: '\$50 - \$150',
          priority: 'Recommended',
        ));
        steps.add(TroubleshootingStepItem(
          stepNumber: 1,
          title: 'Verify Wiring Harness & Terminal Pins',
          action: 'Inspect corresponding sensor harness for pinched wires, melted loom near exhaust, or moisture.',
          toolsNeeded: ['Flashlight', 'Multimeter'],
          difficulty: 'Beginner',
        ));
      }
    }

    final diyCost = parts.isNotEmpty ? '\$60 - \$120' : '\$30 - \$60';
    final shopCost = '\$180 - \$320';
    final dealerCost = '\$350 - \$550';

    return Obd2DiagnosticReport(
      vehicleId: vehicle.id,
      vehicleName: vehicleName,
      dtcCodes: codes,
      overallSeverity: severity,
      canDrive: canDrive,
      summary:
          'Diagnostics detected ${codes.length} active code(s) on $vehicleName: ${codes.join(", ")}. ${isTuned ? "Installed modifications may impact fuel/air sensor thresholds." : "Recommend inspecting recommended components."}',
      diagnoses: diagnoses,
      recommendedParts: parts,
      troubleshootingSteps: steps,
      costEstimate: DiagnosticCostEstimate(
        diyCost: diyCost,
        independentShopCost: shopCost,
        dealershipCost: dealerCost,
        estimatedLaborHours: '1.0 - 2.0 hrs',
        summaryNotes:
            'Doing the repair yourself saves ~60% in labor and markup. Dealership quotes include comprehensive diagnostics and OEM parts.',
      ),
      preventativeTips: [
        'Always clear DTCs after replacing suspected faulty parts to verify the fix.',
        'Record live OBD2 fuel trims and RPM telemetry during a test drive to ensure ECU has completed drive cycles.',
        'Keep intake air filter clean and avoid over-oiling reusable gauze filters.',
      ],
    );
  }

  static Future<bool> testApiKey(String testKey) async {
    try {
      final testModel = GenerativeModel(
        model: 'gemini-3.5-flash-lite',
        apiKey: testKey,
      );
      final res = await testModel.generateContent([Content.text('Ping')]);
      return res.text != null;
    } catch (_) {
      return false;
    }
  }
}
