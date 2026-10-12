import 'package:flutter/material.dart';
import '../models.dart';
import '../gemini_service.dart';
import 'blurred_modal.dart';

class VehicleSpecsDialog extends StatefulWidget {
  final Vehicle vehicle;
  final GeminiService? geminiService;
  final Function(Vehicle) onVehicleUpdated;

  const VehicleSpecsDialog({
    super.key,
    required this.vehicle,
    this.geminiService,
    required this.onVehicleUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required Vehicle vehicle,
    GeminiService? geminiService,
    required Function(Vehicle) onVehicleUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (ctx) => BlurredModalSheet(
        isDraggable: true,
        child: VehicleSpecsDialog(
          vehicle: vehicle,
          geminiService: geminiService,
          onVehicleUpdated: onVehicleUpdated,
        ),
      ),
    );
  }

  @override
  State<VehicleSpecsDialog> createState() => _VehicleSpecsDialogState();
}

class _VehicleSpecsDialogState extends State<VehicleSpecsDialog> {
  bool _isLoading = false;
  Map<String, dynamic>? _specs;

  @override
  void initState() {
    super.initState();
    if (widget.vehicle.cachedSpecs != null) {
      _specs = widget.vehicle.cachedSpecs;
    } else {
      _loadSpecs();
    }
  }

  Future<void> _loadSpecs({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);

    Map<String, dynamic> results;
    if (widget.geminiService != null) {
      results = await widget.geminiService!.fetchVehicleSpecs(widget.vehicle);
    } else {
      // Offline fallback heuristic
      results = {
        "stock": {
          "horsepower": widget.vehicle.isMotorcycle ? "115 HP" : "310 HP",
          "torque": widget.vehicle.isMotorcycle ? "75 lb-ft" : "290 lb-ft",
          "zeroToSixty": widget.vehicle.isMotorcycle ? "3.4s" : "5.4s",
          "engine": widget.vehicle.isMotorcycle ? "Inline Twin / 4-Cyl" : "Turbocharged Inline-4",
          "drivetrain": widget.vehicle.isMotorcycle ? "Chain Drive" : "RWD / AWD",
          "transmission": widget.vehicle.isMotorcycle ? "6-Speed Manual" : "6-Speed Manual / Auto",
          "curbWeight": widget.vehicle.isMotorcycle ? "425 lbs" : "3,500 lbs",
          "topSpeed": widget.vehicle.isMotorcycle ? "155 mph" : "155 mph",
        },
        "modded": {
          "horsepower": widget.vehicle.isMotorcycle ? "130 HP" : "355 HP",
          "torque": widget.vehicle.isMotorcycle ? "85 lb-ft" : "335 lb-ft",
          "zeroToSixty": widget.vehicle.isMotorcycle ? "3.1s" : "4.8s",
          "hpGain": widget.vehicle.mods.isNotEmpty ? "+45 HP" : "Stock",
          "torqueGain": widget.vehicle.mods.isNotEmpty ? "+45 lb-ft" : "Stock",
          "zeroToSixtyDiff": widget.vehicle.mods.isNotEmpty ? "-0.6s" : "0.0s",
        },
        "breakdown": [
          {
            "mod": widget.vehicle.mods.isEmpty ? "OEM Factory Spec" : widget.vehicle.mods,
            "impact": "Estimated performance gain based on installed parts"
          }
        ],
        "dynoNotes":
            "Baseline dyno projection. Add more detailed mods in vehicle profile to see itemized power impacts."
      };
    }

    widget.vehicle.cachedSpecs = results;
    widget.onVehicleUpdated(widget.vehicle);

    if (mounted) {
      setState(() {
        _specs = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final primaryImg = widget.vehicle.primaryImageBytes;

    final stock = _specs?['stock'] as Map<String, dynamic>? ?? {};
    final modded = _specs?['modded'] as Map<String, dynamic>? ?? {};
    final breakdown = (_specs?['breakdown'] as List?) ?? [];
    final dynoNotes = _specs?['dynoNotes'] as String? ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 25,
                spreadRadius: 5,
              )
            ],
          ),
          child: Column(
            children: [
              // Grab handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Title bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.vehicle.icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.vehicle.displayName,
                            style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Stock vs. Modded Performance Specs',
                            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.refresh, color: accent),
                      tooltip: 'Re-analyze with AI Dyno',
                      onPressed: _isLoading ? null : () => _loadSpecs(forceRefresh: true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Body content
              Expanded(
                child: _isLoading && _specs == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: accent),
                            const SizedBox(height: 16),
                            const Text('Running AI Dyno Simulation...'),
                          ],
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20),
                        children: [
                          // Vehicle Banner Image
                          if (primaryImg != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                primaryImg,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                          if (primaryImg != null) const SizedBox(height: 20),

                          // Top Key Comparison Cards (HP, Torque, 0-60)
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatComparisonCard(
                                  context: context,
                                  title: 'HORSEPOWER',
                                  icon: Icons.bolt,
                                  stockVal: stock['horsepower']?.toString() ?? '---',
                                  moddedVal: modded['horsepower']?.toString() ?? '---',
                                  deltaText: modded['hpGain']?.toString() ?? '',
                                  deltaColor: Colors.greenAccent,
                                  accent: accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildStatComparisonCard(
                                  context: context,
                                  title: 'TORQUE',
                                  icon: Icons.rotate_right,
                                  stockVal: stock['torque']?.toString() ?? '---',
                                  moddedVal: modded['torque']?.toString() ?? '---',
                                  deltaText: modded['torqueGain']?.toString() ?? '',
                                  deltaColor: Colors.orangeAccent,
                                  accent: accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildStatComparisonCard(
                                  context: context,
                                  title: '0-60 MPH',
                                  icon: Icons.timer_outlined,
                                  stockVal: stock['zeroToSixty']?.toString() ?? '---',
                                  moddedVal: modded['zeroToSixty']?.toString() ?? '---',
                                  deltaText: modded['zeroToSixtyDiff']?.toString() ?? '',
                                  deltaColor: Colors.lightBlueAccent,
                                  accent: accent,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),
                          _buildSectionTitle('Factory OEM Specifications', Icons.factory_outlined),
                          const SizedBox(height: 12),
                          _buildStockSpecsGrid(stock),

                          const SizedBox(height: 24),
                          _buildSectionTitle('Modifications & Dyno Impact', Icons.tune),
                          const SizedBox(height: 12),
                          if (breakdown.isNotEmpty)
                            ...breakdown.map((item) {
                              final modMap = item is Map ? item : {};
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: theme.cardTheme.color,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.check_circle, color: accent, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            modMap['mod']?.toString() ?? 'Mod',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (modMap['impact'] != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4.0),
                                              child: Text(
                                                modMap['impact'].toString(),
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  color: Colors.greenAccent.withValues(alpha: 0.9),
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                            ),
                                          if (modMap['notes'] != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2.0),
                                              child: Text(
                                                modMap['notes'].toString(),
                                                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            })
                          else
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.cardTheme.color,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                widget.vehicle.mods.isEmpty
                                    ? 'No mods listed yet. Edit vehicle in garage to add your modifications!'
                                    : widget.vehicle.mods,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),

                          if (dynoNotes.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildSectionTitle('AI Dyno Engineering Insights', Icons.auto_awesome),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: accent.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                dynoNotes,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildStatComparisonCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required String stockVal,
    required String moddedVal,
    required String deltaText,
    required Color deltaColor,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: isDark ? accent : (accent.computeLuminance() > 0.45 ? const Color(0xFF0F172A) : accent),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            moddedVal,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Stock: $stockVal',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          if (deltaText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: deltaColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                deltaText,
                style: TextStyle(
                  color: deltaColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildStockSpecsGrid(Map<String, dynamic> stock) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      {'label': 'Engine', 'val': stock['engine'] ?? 'OEM Spec'},
      {'label': 'Drivetrain', 'val': stock['drivetrain'] ?? 'OEM Spec'},
      {'label': 'Transmission', 'val': stock['transmission'] ?? 'OEM Spec'},
      {'label': 'Curb Weight', 'val': stock['curbWeight'] ?? 'OEM Spec'},
      {'label': 'Top Speed', 'val': stock['topSpeed'] ?? 'OEM Spec'},
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item['label']!,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
                Text(
                  item['val']!,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
