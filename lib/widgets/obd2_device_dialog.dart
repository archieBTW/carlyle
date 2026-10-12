import 'dart:async';
import 'package:flutter/material.dart';
import '../services/obd2_service.dart';
import 'blurred_modal.dart';

class Obd2DeviceDialog extends StatefulWidget {
  final Obd2Service obd2service;

  const Obd2DeviceDialog({super.key, required this.obd2service});

  @override
  State<Obd2DeviceDialog> createState() => _Obd2DeviceDialogState();
}

class _Obd2DeviceDialogState extends State<Obd2DeviceDialog> {
  List<Obd2BluetoothDevice> _pairedDevices = [];
  final List<Obd2BluetoothDevice> _discoveredDevices = [];
  bool _isLoadingPaired = true;
  bool _isDiscovering = false;
  StreamSubscription<Obd2BluetoothDevice>? _discoverySubscription;
  String? _connectingDeviceAddress;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
  }

  Future<void> _loadPairedDevices() async {
    setState(() {
      _isLoadingPaired = true;
      _errorMessage = null;
    });

    final devices = await widget.obd2service.getPairedDevices();
    if (mounted) {
      setState(() {
        _pairedDevices = devices;
        _isLoadingPaired = false;
      });
    }
  }

  void _startDiscovery() {
    if (_isDiscovering) return;

    setState(() {
      _isDiscovering = true;
      _discoveredDevices.clear();
      _errorMessage = null;
    });

    _discoverySubscription = widget.obd2service.scanForDevices().listen(
      (device) {
        if (mounted &&
            !_pairedDevices.any((p) => p.address == device.address) &&
            !_discoveredDevices.any((d) => d.address == device.address)) {
          setState(() {
            _discoveredDevices.add(device);
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() => _isDiscovering = false);
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _isDiscovering = false;
            _errorMessage = 'Bluetooth scan error: $err';
          });
        }
      },
    );
  }

  Future<void> _connect(Obd2BluetoothDevice device) async {
    setState(() {
      _connectingDeviceAddress = device.address;
      _errorMessage = null;
    });

    final success = await widget.obd2service.connectToDevice(device);

    if (mounted) {
      if (success) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _connectingDeviceAddress = null;
          _errorMessage = widget.obd2service.statusMessage;
        });
      }
    }
  }

  void _activateDemoMode() {
    widget.obd2service.startDemoMode();
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    super.dispose();
  }

  bool _isProbableObd(String name) {
    final lower = name.toLowerCase();
    return lower.contains('obd') ||
        lower.contains('elm') ||
        lower.contains('vlink') ||
        lower.contains('v-link') ||
        lower.contains('vgate') ||
        lower.contains('viecar') ||
        lower.contains('bafx') ||
        lower.contains('scanner');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return BlurredDialog(
      child: AlertDialog(
        backgroundColor: const Color(0xFF161922),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.all(16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.bluetooth_searching, color: accent, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Connect OBD2 Reader',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select your paired ELM327 or Bluetooth OBD-II adapter. Ensure your car ignition is switched ON.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoadingPaired
                    ? Center(
                        child: CircularProgressIndicator(color: accent),
                      )
                    : ListView(
                        children: [
                          if (_pairedDevices.isNotEmpty) ...[
                            _buildSectionHeader('PAIRED ADAPTERS', accent),
                            ..._pairedDevices.map(
                              (device) => _buildDeviceTile(device, accent),
                            ),
                          ],
                          if (_discoveredDevices.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildSectionHeader(
                                'OTHER DISCOVERED DEVICES', Colors.white54),
                            ..._discoveredDevices.map(
                              (device) => _buildDeviceTile(device, accent),
                            ),
                          ],
                          if (_pairedDevices.isEmpty &&
                              _discoveredDevices.isEmpty &&
                              !_isDiscovering) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.bluetooth_disabled,
                                      size: 40,
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No paired Bluetooth adapters found',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Pair your adapter in Android Bluetooth Settings first',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        fontSize: 11,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('Try Demo Mode'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFB300),
            ),
            onPressed: _activateDemoMode,
          ),
          const Spacer(),
          if (!_isDiscovering)
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Scan Nearby'),
              onPressed: _startDiscovery,
            )
          else
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDeviceTile(Obd2BluetoothDevice device, Color accent) {
    final isConnecting = _connectingDeviceAddress == device.address;
    final isLikelyObd = _isProbableObd(device.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isLikelyObd
            ? accent.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLikelyObd
              ? accent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Icon(
          isLikelyObd ? Icons.speed : Icons.bluetooth,
          color: isLikelyObd ? accent : Colors.white60,
          size: 22,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                device.name,
                style: TextStyle(
                  fontWeight:
                      isLikelyObd ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLikelyObd)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'OBD-II',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          device.address,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        trailing: isConnecting
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent,
                ),
              )
            : Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.white.withValues(alpha: 0.3),
              ),
        onTap: isConnecting ? null : () => _connect(device),
      ),
    );
  }
}
