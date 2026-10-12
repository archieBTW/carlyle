import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tuner/main.dart';
import 'package:ai_tuner/models.dart';
import 'package:ai_tuner/pages/garage_page.dart';
import 'package:ai_tuner/pages/settings_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('AITunerApp initial pump test', (WidgetTester tester) async {
    final appState = AppState();
    await tester.pumpWidget(AITunerApp(appState: appState));
    expect(find.byType(AITunerApp), findsOneWidget);
  });

  testWidgets('GaragePage layout renders carousel with peeking and Add Ride button below cards', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final appState = AppState();
    await appState.load();

    // Add a second vehicle so carousel has multiple pages to swipe & peek
    await appState.addVehicle(Vehicle(
      type: 'Motorcycle',
      year: '2023',
      make: 'Yamaha',
      model: 'YZF-R1',
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GaragePage(
            appState: appState,
            onSaved: () {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify PageView carousel exists
    expect(find.byType(PageView), findsOneWidget);

    // Verify PageView has viewportFraction set for peeking
    final pageView = tester.widget<PageView>(find.byType(PageView));
    final controller = pageView.controller;
    expect(controller?.viewportFraction, lessThan(1.0));

    // Verify Add Ride button is below the cards
    expect(find.text('Add Ride to Garage'), findsOneWidget);

    // Verify filter chips exist
    expect(find.textContaining('All ('), findsOneWidget);

    // Verify 'Selected' badge text is present instead of 'ACTIVE FOR AI'
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('ACTIVE FOR AI'), findsNothing);

    // Test swiping carousel to next vehicle
    await tester.drag(find.byType(PageView), const Offset(-250, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify second vehicle is now visible
    expect(find.textContaining('Yamaha YZF-R1'), findsOneWidget);
  });

  testWidgets('SettingsPage shows clean Import / Export without verbose info text and clean BYOK header', (WidgetTester tester) async {
    final appState = AppState();
    await appState.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(appState: appState),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify 'Import / Export' is present
    expect(find.text('Import / Export'), findsWidgets);

    // Verify verbose descriptions have been removed
    expect(find.textContaining('Export or restore your full configuration'), findsNothing);
    expect(find.textContaining('Your key is stored securely on your device for BYOK'), findsNothing);
  });

  testWidgets('Modals and Dialogs render BackdropFilter blur behind modal', (WidgetTester tester) async {
    final appState = AppState();
    await appState.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GaragePage(appState: appState, onSaved: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Add Ride to Garage button to open modal
    await tester.tap(find.text('Add Ride to Garage'));
    await tester.pumpAndSettle();

    // Verify modal is open and has BackdropFilter blur
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('Add/Edit Vehicle modal resizes and moves content up when keyboard opens', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetViewInsets();
    });

    final appState = AppState();
    await appState.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GaragePage(appState: appState, onSaved: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Add Ride modal
    await tester.tap(find.text('Add Ride to Garage'));
    await tester.pumpAndSettle();

    expect(find.text('Add New Ride'), findsOneWidget);

    // Simulate keyboard popping up (300px high)
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    // Enter text in fields while keyboard is open
    final yearField = find.widgetWithText(TextField, 'Year (e.g. 2022)');
    expect(yearField, findsOneWidget);
    await tester.enterText(yearField, '2024');
    await tester.pumpAndSettle();

    final makeField = find.widgetWithText(TextField, 'Make (e.g. Ford / Yamaha)');
    expect(makeField, findsOneWidget);
    await tester.enterText(makeField, 'Toyota');
    await tester.pumpAndSettle();

    final modelField = find.widgetWithText(TextField, 'Model (e.g. Mustang GT / R1)');
    expect(modelField, findsOneWidget);
    await tester.enterText(modelField, 'Supra');
    await tester.pumpAndSettle();

    expect(find.text('Supra'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Test clicking Export JSON and Import JSON buttons in SettingsPage', (WidgetTester tester) async {
    final appState = AppState();
    await appState.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(appState: appState),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final exportBtn = find.text('Export JSON');
    expect(exportBtn, findsOneWidget);
    await tester.ensureVisible(exportBtn);
    await tester.tap(exportBtn);
    await tester.pumpAndSettle();

    expect(find.text('Save Backup File (.json)'), findsOneWidget);
    expect(find.text('Share Backup File'), findsOneWidget);
    expect(find.text('Copy JSON to Clipboard'), findsOneWidget);

    // Close export modal
    final closeBtn = find.byIcon(Icons.close);
    await tester.tap(closeBtn);
    await tester.pumpAndSettle();

    // Test import modal
    final importBtn = find.text('Import JSON');
    expect(importBtn, findsOneWidget);
    await tester.ensureVisible(importBtn);
    await tester.tap(importBtn);
    await tester.pumpAndSettle();

    expect(find.text('Select Backup File (.json)'), findsOneWidget);
    expect(find.text('Paste from Clipboard'), findsOneWidget);
  });
}
