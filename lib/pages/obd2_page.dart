import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';
import '../gemini_service.dart';
import '../services/obd2_service.dart';
import '../widgets/obd2_gauge.dart';
import '../widgets/obd2_device_dialog.dart';
import '../widgets/diagnostic_report_dialog.dart';
import '../widgets/obd2_log_viewer_dialog.dart';

class Obd2Page extends StatefulWidget {
  final AppState appState;
  final GeminiService? geminiService;
  final Obd2Service obd2service;
  final VoidCallback? onSwitchToAssistant;

  const Obd2Page({
    super.key,
    required this.appState,
    required this.geminiService,
    required this.obd2service,
    this.onSwitchToAssistant,
  });

  @override
  State<Obd2Page> createState() => _Obd2PageState();
}

class _Obd2PageState extends State<Obd2Page>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<double> _rpmHistory = [];
  final List<double> _speedHistory = [];
  bool _speedInMph = true;
  bool _isAnalyzingDtc = false;
  final TextEditingController _manualDtcController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.obd2service.addListener(_onObd2Update);
  }

  @override
  void dispose() {
    widget.obd2service.removeListener(_onObd2Update);
    _tabController.dispose();
    _manualDtcController.dispose();
    super.dispose();
  }

  void _onObd2Update() {
    if (!mounted) return;
    final tel = widget.obd2service.currentTelemetry;

    setState(() {
      _rpmHistory.add(tel.rpm);
      if (_rpmHistory.length > 50) _rpmHistory.removeAt(0);

      final spd = _speedInMph ? tel.speedMph : tel.speedKmh;
      _speedHistory.add(spd);
      if (_speedHistory.length > 50) _speedHistory.removeAt(0);
    });
  }

  void _openDevicePicker() {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => Obd2DeviceDialog(obd2service: widget.obd2service),
    );
  }

  Future<void> _runDtcScan() async {
    final codes = await widget.obd2service.scanDtcCodes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(codes.isEmpty
              ? 'Scan complete: No trouble codes (DTCs) found!'
              : 'Scan complete: Found ${codes.length} trouble code(s): ${codes.join(", ")}'),
          backgroundColor: codes.isEmpty ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _clearDtcCodes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Clear Trouble Codes (Mode 04)?'),
        content: const Text(
          'This will send OBD2 Command 04 to clear active DTCs and turn off the Check Engine light. Confirm only after repairs are completed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Codes'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await widget.obd2service.clearDtcCodes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Trouble codes cleared successfully.'
                : 'Failed to clear trouble codes from ECU.'),
          ),
        );
      }
    }
  }

  void _addManualDtc() {
    final code = _manualDtcController.text.trim();
    if (code.isNotEmpty) {
      widget.obd2service.addManualDtcCode(code);
      _manualDtcController.clear();
    }
  }

  Future<void> _runAiDiagnosis() async {
    final codes = widget.obd2service.currentDtcCodes;
    if (codes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No DTC codes to diagnose. Scan vehicle or enter codes manually first.'),
        ),
      );
      return;
    }

    if (widget.geminiService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure your Gemini API key in Settings.'),
        ),
      );
      return;
    }

    setState(() => _isAnalyzingDtc = true);

    try {
      final report = await widget.geminiService!.diagnoseTroubleCodes(
        vehicle: widget.appState.selectedVehicle,
        dtcCodes: codes,
      );

      // Save report in AppState
      await widget.appState.addDiagnosticReport(report);

      if (mounted) {
        setState(() => _isAnalyzingDtc = false);
        _showDiagnosticReport(report);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzingDtc = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnosis error: $e')),
        );
      }
    }
  }

  void _showDiagnosticReport(Obd2DiagnosticReport report) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => DiagnosticReportDialog(
        report: report,
        onDiscussWithAi: () {
          // Add context message into active assistant chat session
          final session = widget.appState.activeChatSession;
          session.messages.add(ChatMessage(
            role: 'user',
            text:
                'I just scanned my ${report.vehicleName} and found DTC codes: ${report.dtcCodes.join(", ")}. Can you help me troubleshoot further?',
          ));
          session.messages.add(ChatMessage(
            role: 'assistant',
            text:
                'I have your OBD2 diagnostic report for ${report.dtcCodes.join(", ")} on your ${report.vehicleName}. Overall severity is ${report.overallSeverity}. What questions do you have about the repair steps or parts?',
          ));
          widget.appState.saveChatSessions();
          if (widget.onSwitchToAssistant != null) {
            widget.onSwitchToAssistant!();
          }
        },
      ),
    );
  }

  Future<void> _startRecordingSession() async {
    final titleController = TextEditingController(
      text: 'Pull / Log ${DateTime.now().toLocal().toString().substring(11, 16)}',
    );

    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Start Telemetry Log Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a name for this telemetry log:'),
            const SizedBox(height: 10),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Session Title',
                hintText: 'e.g., 3rd Gear Dyno Pull, Highway Cruise',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, titleController.text.trim()),
            child: const Text('Start Recording'),
          ),
        ],
      ),
    );

    if (title != null) {
      widget.obd2service.startLogging(
        title: title,
        vehicle: widget.appState.selectedVehicle,
      );
    }
  }

  Future<void> _stopRecordingSession() async {
    final session = widget.obd2service.stopLogging();
    if (session != null) {
      await widget.appState.addObd2Log(session);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved "${session.title}" with ${session.sampleCount} data points.',
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _viewSavedLog(session),
            ),
          ),
        );
      }
    }
  }

  void _viewSavedLog(Obd2LogSession session) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => Obd2LogViewerDialog(
        session: session,
        onDelete: () => widget.appState.deleteObd2Log(session.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.appState.accentColor;
    final isConnected = widget.obd2service.isConnected;
    final isDemo = widget.obd2service.isDemoMode;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F15),
      body: Column(
        children: [
          // Bluetooth Status Header Bar
          _buildConnectionHeader(accent, isConnected, isDemo),

          // Tab Bar
          Container(
            color: const Color(0xFF141721),
            child: TabBar(
              controller: _tabController,
              indicatorColor: accent,
              indicatorWeight: 3,
              labelColor: accent,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.speed, size: 20), text: 'Live Telemetry'),
                Tab(icon: Icon(Icons.troubleshoot, size: 20), text: 'AI Diagnostics'),
                Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'Data Logs'),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLiveTelemetryTab(accent),
                _buildAiDiagnosticsTab(accent),
                _buildLogsTab(accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionHeader(Color accent, bool isConnected, bool isDemo) {
    Color statusColor;
    String statusTitle;

    if (isDemo) {
      statusColor = const Color(0xFFFFB300);
      statusTitle = 'SIMULATION ECU ACTIVE';
    } else if (isConnected) {
      statusColor = const Color(0xFF00E676);
      statusTitle = widget.obd2service.connectedDeviceName ?? 'CONNECTED';
    } else if (widget.obd2service.connectionState ==
        Obd2ConnectionState.connecting) {
      statusColor = const Color(0xFF00E5FF);
      statusTitle = 'CONNECTING...';
    } else {
      statusColor = Colors.white38;
      statusTitle = 'DISCONNECTED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141721),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: statusColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.obd2service.statusMessage,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isConnected) ...[
            TextButton.icon(
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('Disconnect', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => widget.obd2service.disconnect(),
            ),
          ] else ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Demo', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFB300),
                side: const BorderSide(color: Color(0xFFFFB300), width: 1),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => widget.obd2service.startDemoMode(),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.bluetooth, size: 16),
              label: const Text('Connect OBD', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _openDevicePicker,
            ),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------
  // TAB 1: LIVE TELEMETRY
  // ----------------------------------------------------------------------

  Widget _buildLiveTelemetryTab(Color accent) {
    final tel = widget.obd2service.currentTelemetry;
    final isLogging = widget.obd2service.isLogging;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            // Prominent Tachometer & Speed Readout Card
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141721),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // RPM Radial Gauge
                      Obd2RadialGauge(
                        value: tel.rpm,
                        minValue: 0,
                        maxValue: 8000,
                        redlineValue: 6500,
                        title: 'ENGINE SPEED',
                        unit: 'RPM',
                        accentColor: accent,
                        size: 190,
                      ),

                      // Speed Digital Display
                      Column(
                        children: [
                          Text(
                            'VEHICLE SPEED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (_speedInMph ? tel.speedMph : tel.speedKmh)
                                .toStringAsFixed(0),
                            style: const TextStyle(
                              fontSize: 54,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _speedInMph = !_speedInMph),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _speedInMph ? 'MPH' : 'KM/H',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Gear & Drive Indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.tune, size: 14, color: accent),
                                const SizedBox(width: 6),
                                Text(
                                  widget.appState.selectedVehicle.displayName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Live Sensor Grid
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.45,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                Obd2SensorCard(
                  label: 'Coolant Temp',
                  value: tel.coolantTempF.toStringAsFixed(0),
                  unit: '°F',
                  icon: Icons.thermostat,
                  ratio: (tel.coolantTempF - 100) / 140,
                  barColor: tel.coolantTempF > 225
                      ? Colors.redAccent
                      : const Color(0xFF00E5FF),
                  subtitle: '${tel.coolantTempC.toStringAsFixed(0)}°C',
                ),
                Obd2SensorCard(
                  label: 'Engine Load',
                  value: tel.engineLoad.toStringAsFixed(0),
                  unit: '%',
                  icon: Icons.fitness_center,
                  ratio: tel.engineLoad / 100,
                  barColor: tel.engineLoad > 80
                      ? const Color(0xFFFF9100)
                      : accent,
                ),
                Obd2SensorCard(
                  label: 'Throttle Position',
                  value: tel.throttlePosition.toStringAsFixed(0),
                  unit: '%',
                  icon: Icons.electric_bolt,
                  ratio: tel.throttlePosition / 100,
                  barColor: accent,
                ),
                Obd2SensorCard(
                  label: 'Battery / ECU',
                  value: tel.voltage.toStringAsFixed(1),
                  unit: 'V',
                  icon: Icons.battery_charging_full,
                  ratio: (tel.voltage - 11.0) / 4.0,
                  barColor: tel.voltage < 12.0
                      ? Colors.redAccent
                      : const Color(0xFF00E676),
                ),
                Obd2SensorCard(
                  label: 'Intake Air Temp',
                  value: tel.iatF.toStringAsFixed(0),
                  unit: '°F',
                  icon: Icons.air,
                  ratio: (tel.iatF - 40) / 120,
                  barColor: const Color(0xFF00E5FF),
                  subtitle: '${tel.iatC.toStringAsFixed(0)}°C',
                ),
                Obd2SensorCard(
                  label: 'Mass Air Flow',
                  value: tel.maf.toStringAsFixed(1),
                  unit: 'g/s',
                  icon: Icons.compress,
                  ratio: tel.maf / 200,
                  barColor: const Color(0xFFFFB300),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Real-Time Sparkline History Graphs
            Obd2TelemetryGraph(
              values: _rpmHistory,
              label: 'LIVE RPM TRACE',
              color: accent,
              minVal: 0,
              maxVal: 8000,
            ),
            const SizedBox(height: 8),
            Obd2TelemetryGraph(
              values: _speedHistory,
              label: 'LIVE SPEED TRACE (${_speedInMph ? "MPH" : "KM/H"})',
              color: const Color(0xFFFFB300),
              minVal: 0,
              maxVal: 120,
            ),
          ],
        ),

        // Floating Recording Controller
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF191D28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLogging
                    ? Colors.redAccent.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.1),
                width: isLogging ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isLogging
                      ? Colors.redAccent.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                if (isLogging) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'RECORDING TELEMETRY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: Colors.redAccent,
                          ),
                        ),
                        Text(
                          '${widget.obd2service.loggedSampleCount} samples • ${widget.obd2service.activeLogSession?.durationSeconds ?? 0}s elapsed',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Stop & Save'),
                    onPressed: _stopRecordingSession,
                  ),
                ] else ...[
                  Icon(Icons.fiber_manual_record,
                      color: Colors.white.withValues(alpha: 0.4), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ready to log dyno/track runs',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start Run Log'),
                    onPressed: _startRecordingSession,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------------
  // TAB 2: AI DIAGNOSTICS & TROUBLE CODES
  // ----------------------------------------------------------------------

  Widget _buildAiDiagnosticsTab(Color accent) {
    final vehicle = widget.appState.selectedVehicle;
    final dtcCodes = widget.obd2service.currentDtcCodes;
    final isScanning = widget.obd2service.isScanningDtc;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Target Vehicle Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF141721),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(vehicle.icon, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TARGET VEHICLE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: accent,
                      ),
                    ),
                    Text(
                      vehicle.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      vehicle.mods.isEmpty
                          ? 'Stock baseline configuration'
                          : 'Mods: ${vehicle.mods}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Action Buttons Row (Scan / Clear)
        Row(
          children: [
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.document_scanner),
                label: Text(
                  isScanning ? 'Querying ECU...' : 'Scan DTC Codes',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: isScanning ? null : _runDtcScan,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Clear ECU'),
                onPressed: _clearDtcCodes,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Active Trouble Codes Container
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141721),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: dtcCodes.isNotEmpty
                  ? const Color(0xFFFF9100).withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        dtcCodes.isNotEmpty
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        color: dtcCodes.isNotEmpty
                            ? const Color(0xFFFF9100)
                            : Colors.greenAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'DETECTED TROUBLE CODES (${dtcCodes.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: dtcCodes.isNotEmpty
                              ? const Color(0xFFFF9100)
                              : Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                  if (dtcCodes.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => widget.obd2service.clearDtcCodes(),
                      child: const Text('Remove All', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (dtcCodes.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.verified,
                          size: 36,
                          color: Colors.greenAccent.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No Active Fault Codes',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ECU is reporting clear emissions and powertrain status.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: dtcCodes.map((code) {
                    return Chip(
                      backgroundColor:
                          const Color(0xFFFF9100).withValues(alpha: 0.15),
                      side: BorderSide(
                        color: const Color(0xFFFF9100).withValues(alpha: 0.4),
                      ),
                      label: Text(
                        code,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => widget.obd2service.removeDtcCode(code),
                    );
                  }).toList(),
                ),
              ],

              const Divider(height: 24, color: Colors.white10),

              // Manual Code Input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualDtcController,
                      style: const TextStyle(fontSize: 13),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Add DTC Code Manually',
                        hintText: 'e.g. P0300, P0420, P0171',
                        isDense: true,
                        prefixIcon: const Icon(Icons.add, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onSubmitted: (_) => _addManualDtc(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.check, size: 18),
                    onPressed: _addManualDtc,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Deep AI Diagnosis Trigger Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6200EE),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
            icon: _isAnalyzingDtc
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _isAnalyzingDtc
                  ? 'AI Tuning Engine Diagnosing...'
                  : 'Run AI Diagnostic Engine (${dtcCodes.length} Codes)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            onPressed: (_isAnalyzingDtc || dtcCodes.isEmpty)
                ? null
                : _runAiDiagnosis,
          ),
        ),

        const SizedBox(height: 24),

        // Diagnostic History Section
        if (widget.appState.diagnosticReports.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DIAGNOSTIC HISTORY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: accent,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => widget.appState.clearDiagnosticReports(),
                child: const Text('Clear All', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...widget.appState.diagnosticReports.map((report) {
            final sevColor = report.overallSeverity.toLowerCase() == 'critical'
                ? const Color(0xFFFF3366)
                : const Color(0xFFFF9100);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF141721),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: sevColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.troubleshoot, color: sevColor, size: 20),
                ),
                title: Text(
                  report.dtcCodes.join(', '),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                subtitle: Text(
                  '${report.vehicleName} • ${report.timestamp.toLocal().toString().substring(0, 16)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.white38),
                      onPressed: () =>
                          widget.appState.deleteDiagnosticReport(report.id),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
                onTap: () => _showDiagnosticReport(report),
              ),
            );
          }),
        ],
      ],
    );
  }

  // ----------------------------------------------------------------------
  // TAB 3: DATA LOGS (SAVED RECORDINGS)
  // ----------------------------------------------------------------------

  Widget _buildLogsTab(Color accent) {
    final logs = widget.appState.savedObd2Logs;

    if (logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.folder_open,
                size: 56,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 12),
              const Text(
                'No Telemetry Logs Yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Switch to the Live Telemetry tab and tap "Start Run Log" during acceleration runs to capture CSV telemetry.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SAVED RUN LOGS (${logs.length})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: accent,
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => widget.appState.clearObd2Logs(),
              child: const Text('Clear All', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...logs.map((session) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF141721),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: InkWell(
              onTap: () => _viewSavedLog(session),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.show_chart, color: accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${session.vehicleName} • ${session.startTime.toLocal().toString().substring(0, 16)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.white38),
                        onPressed: () =>
                            widget.appState.deleteObd2Log(session.id),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 20, color: Colors.white38),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMiniMetric(
                          'DURATION', '${session.durationSeconds}s'),
                      _buildMiniMetric(
                          'SAMPLES', '${session.sampleCount}'),
                      _buildMiniMetric('PEAK RPM',
                          session.maxRpm.toStringAsFixed(0)),
                      _buildMiniMetric('TOP SPEED',
                          '${session.maxSpeedMph.toStringAsFixed(0)} mph'),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMiniMetric(String label, String val) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
