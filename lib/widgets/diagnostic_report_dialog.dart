import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import 'blurred_modal.dart';

class DiagnosticReportDialog extends StatelessWidget {
  final Obd2DiagnosticReport report;
  final VoidCallback? onDiscussWithAi;

  const DiagnosticReportDialog({
    super.key,
    required this.report,
    this.onDiscussWithAi,
  });

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFFF3366);
      case 'moderate':
        return const Color(0xFFFF9100);
      case 'minor':
      default:
        return const Color(0xFF00E5FF);
    }
  }

  void _shareReport() {
    final sb = StringBuffer();
    sb.writeln('🚗 AI TUNER DIAGNOSTIC REPORT');
    sb.writeln('Vehicle: ${report.vehicleName}');
    sb.writeln('Date: ${report.timestamp.toLocal()}');
    sb.writeln('DTC Codes: ${report.dtcCodes.join(", ")}');
    sb.writeln('Severity: ${report.overallSeverity}');
    sb.writeln('Driveable: ${report.canDrive ? "Yes (Drive with caution)" : "NO - Risk of Engine Damage"}');
    sb.writeln('\n--- SUMMARY ---');
    sb.writeln(report.summary);
    sb.writeln('\n--- DIAGNOSES ---');
    for (final d in report.diagnoses) {
      sb.writeln('${d.code}: ${d.title}');
      sb.writeln(d.carSpecificAnalysis);
    }
    sb.writeln('\n--- RECOMMENDED PARTS ---');
    for (final p in report.recommendedParts) {
      sb.writeln('• ${p.partName} (${p.estimatedCost}) - Priority: ${p.priority}');
    }
    sb.writeln('\n--- REPAIR COST BREAKDOWN ---');
    sb.writeln('DIY: ${report.costEstimate.diyCost}');
    sb.writeln('Independent Shop: ${report.costEstimate.independentShopCost}');
    sb.writeln('Dealership: ${report.costEstimate.dealershipCost}');
    sb.writeln('Labor Hours: ${report.costEstimate.estimatedLaborHours}');

    SharePlus.instance.share(
      ShareParams(
        text: sb.toString(),
        subject: 'OBD2 Diagnostic Report - ${report.vehicleName}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final sevColor = _severityColor(report.overallSeverity);

    return BlurredDialog(
      child: Dialog(
        backgroundColor: const Color(0xFF13161F),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: sevColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 720),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
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
                        color: sevColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sevColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Icon(Icons.troubleshoot, color: sevColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'AI DIAGNOSTIC REPORT',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: sevColor,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: sevColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  report.overallSeverity.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: sevColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => Navigator.pop(context),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 16, color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            report.vehicleName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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

              // Scrollable Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    // Driveability Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: report.canDrive
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.08)
                            : const Color(0xFFFF3366).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: report.canDrive
                              ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
                              : const Color(0xFFFF3366).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            report.canDrive
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_rounded,
                            color: report.canDrive
                                ? const Color(0xFF00E5FF)
                                : const Color(0xFFFF3366),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  report.canDrive
                                      ? 'VEHICLE IS DRIVABLE'
                                      : 'DO NOT DRIVE - RISK OF SEVERE DAMAGE',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: report.canDrive
                                        ? const Color(0xFF00E5FF)
                                        : const Color(0xFFFF3366),
                                  ),
                                ),
                                Text(
                                  report.canDrive
                                      ? 'Safe to drive short distances for service. Avoid high boost and RPM.'
                                      : 'Misfires or severe AFR lean conditions can destroy catalytic converters or pistons.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Codes List Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: report.dtcCodes.map((code) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: sevColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.code, size: 14, color: sevColor),
                              const SizedBox(width: 6),
                              Text(
                                code,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 14),

                    // Executive Summary
                    _buildSectionHeader('EXECUTIVE SUMMARY', accent),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Text(
                        report.summary,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Vehicle-Matched Diagnoses
                    _buildSectionHeader('CAR-SPECIFIC ANALYSIS', accent),
                    ...report.diagnoses.map((diag) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: sevColor.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      diag.code,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: sevColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      diag.title,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                diag.carSpecificAnalysis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.45,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                              if (diag.commonCauses.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Probable Causes:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...diag.commonCauses.map((cause) => Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('• ',
                                              style: TextStyle(
                                                  color: accent,
                                                  fontWeight: FontWeight.bold)),
                                          Expanded(
                                            child: Text(
                                              cause,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: Colors.white
                                                    .withValues(alpha: 0.75),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                            ],
                          ),
                        )),

                    const SizedBox(height: 12),

                    // Recommended Parts List
                    if (report.recommendedParts.isNotEmpty) ...[
                      _buildSectionHeader('RECOMMENDED PARTS', accent),
                      ...report.recommendedParts.map((part) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.build_circle,
                                      color: accent, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        part.partName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        part.description,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      part.estimatedCost,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        color: accent,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    Text(
                                      part.priority,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: part.priority.toLowerCase() ==
                                                'immediate'
                                            ? const Color(0xFFFF3366)
                                            : Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 12),
                    ],

                    // Step-by-Step Troubleshooting Guide
                    if (report.troubleshootingSteps.isNotEmpty) ...[
                      _buildSectionHeader('STEP-BY-STEP REPAIR GUIDE', accent),
                      ...report.troubleshootingSteps.map((step) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 11,
                                      backgroundColor: accent,
                                      child: Text(
                                        '${step.stepNumber}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        step.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        step.difficulty,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  step.action,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color:
                                        Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                                if (step.toolsNeeded.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tools: ${step.toolsNeeded.join(", ")}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontStyle: FontStyle.italic,
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )),
                      const SizedBox(height: 12),
                    ],

                    // Cost Breakdown Table
                    _buildSectionHeader('EXPECTED REPAIR COST BREAKDOWN', accent),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildCostRow('DIY (Parts Only)',
                              report.costEstimate.diyCost, accent, true),
                          const Divider(height: 16, color: Colors.white10),
                          _buildCostRow('Independent Repair Shop',
                              report.costEstimate.independentShopCost, Colors.white70, false),
                          const Divider(height: 16, color: Colors.white10),
                          _buildCostRow('Authorized Dealership',
                              report.costEstimate.dealershipCost, const Color(0xFFFF9100), false),
                          const Divider(height: 16, color: Colors.white10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Estimated Labor Time:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                              Text(
                                report.costEstimate.estimatedLaborHours,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (report.costEstimate.summaryNotes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              report.costEstimate.summaryNotes,
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (report.preventativeTips.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildSectionHeader('PREVENTATIVE & TUNING TIPS', accent),
                      ...report.preventativeTips.map((tip) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.lightbulb_outline,
                                    size: 14, color: accent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tip,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color:
                                          Colors.white.withValues(alpha: 0.75),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
              ),

              // Actions Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(22)),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Share Report',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        foregroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        padding: const EdgeInsets.all(10),
                      ),
                      icon: const Icon(Icons.share_outlined, size: 18),
                      onPressed: _shareReport,
                    ),
                    const SizedBox(width: 8),
                    if (onDiscussWithAi != null)
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Discuss with AI',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            onDiscussWithAi!();
                          },
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
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

  Widget _buildSectionHeader(String title, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: accent,
        ),
      ),
    );
  }

  Widget _buildCostRow(String title, String cost, Color color, bool isBold) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: Colors.white,
          ),
        ),
        Text(
          cost,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
      ],
    );
  }
}
