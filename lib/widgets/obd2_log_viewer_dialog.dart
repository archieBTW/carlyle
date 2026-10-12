import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import 'blurred_modal.dart';

class Obd2LogViewerDialog extends StatelessWidget {
  final Obd2LogSession session;
  final VoidCallback? onDelete;

  const Obd2LogViewerDialog({
    super.key,
    required this.session,
    this.onDelete,
  });

  Future<void> _exportCsv(BuildContext context) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final sanitizedTitle = session.title.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final file = File('${tempDir.path}/obd2_log_${session.id}_$sanitizedTitle.csv');
      await file.writeAsString(session.toCsv());

      await SharePlus.instance.share(
        ShareParams(
          text:
              'OBD2 Telemetry Log - ${session.vehicleName} (${session.title})',
          subject: 'OBD2 Telemetry Log - ${session.title}',
          files: [
            XFile(file.path,
                mimeType: 'text/csv', name: '$sanitizedTitle.csv')
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export CSV: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return BlurredDialog(
      child: Dialog(
        backgroundColor: const Color(0xFF141720),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
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
                      child: Icon(Icons.show_chart, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
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
                  ],
                ),
              ),

              // Metrics Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.white.withValues(alpha: 0.02),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('DURATION', '${session.durationSeconds}s', accent),
                    _buildStatItem('SAMPLES', session.sampleCount.toString(), Colors.white),
                    _buildStatItem('MAX RPM', session.maxRpm.toStringAsFixed(0), const Color(0xFFFF3366)),
                    _buildStatItem('MAX SPEED', '${session.maxSpeedMph.toStringAsFixed(1)} mph', const Color(0xFFFFB300)),
                  ],
                ),
              ),

              const Divider(height: 1, color: Colors.white10),

              // Data Points Table
              Expanded(
                child: session.dataPoints.isEmpty
                    ? Center(
                        child: Text(
                          'No telemetry data points recorded.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: session.dataPoints.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (context, index) {
                          final p = session.dataPoints[index];
                          final timeOffset = p.timestamp
                                  .difference(session.startTime)
                                  .inMilliseconds /
                              1000.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 45,
                                  child: Text(
                                    '+${timeOffset.toStringAsFixed(1)}s',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '${p.rpm.toStringAsFixed(0)} RPM',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            '${p.speedMph.toStringAsFixed(1)} mph',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: accent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${p.engineLoad.toStringAsFixed(0)}% Load',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white.withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Coolant: ${p.coolantTempF.toStringAsFixed(0)}°F • Throttle: ${p.throttlePosition.toStringAsFixed(0)}% • Volt: ${p.voltage.toStringAsFixed(1)}V • MAF: ${p.maf.toStringAsFixed(1)}g/s',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                          color: Colors.white.withValues(alpha: 0.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // Footer Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(20)),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent, size: 20),
                        tooltip: 'Delete Log',
                        onPressed: () {
                          Navigator.pop(context);
                          onDelete!();
                        },
                      ),
                    const Spacer(),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.file_download, size: 16),
                      label: const Text('Export CSV'),
                      onPressed: () => _exportCsv(context),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
      ],
    );
  }
}
