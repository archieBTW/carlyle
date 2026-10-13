import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import '../models.dart';
import '../gemini_service.dart';
import '../widgets/vehicle_specs_dialog.dart';
import '../widgets/blurred_modal.dart';

class GaragePage extends StatefulWidget {
  final AppState appState;
  final GeminiService? geminiService;
  final VoidCallback onSaved;

  const GaragePage({
    super.key,
    required this.appState,
    this.geminiService,
    required this.onSaved,
  });

  @override
  State<GaragePage> createState() => _GaragePageState();
}

class _GaragePageState extends State<GaragePage> {
  String _filter = 'All'; // 'All', 'Car', 'Motorcycle'
  late PageController _pageController;
  late final ValueNotifier<int> _currentPageNotifier;

  @override
  void initState() {
    super.initState();
    int initialPage = 0;
    final filtered = _getFilteredVehicles();
    final idx = filtered.indexWhere((v) => v.id == widget.appState.selectedVehicleId);
    if (idx != -1) initialPage = idx;
    _currentPageNotifier = ValueNotifier<int>(initialPage);
    _pageController = PageController(viewportFraction: 0.86, initialPage: initialPage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheVehicleImages();
  }

  void _precacheVehicleImages() {
    for (final v in widget.appState.vehicles) {
      for (final bytes in v.imageBytesList) {
        try {
          precacheImage(MemoryImage(bytes), context);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  List<Vehicle> _getFilteredVehicles() {
    return widget.appState.vehicles.where((v) {
      if (_filter == 'Car') return !v.isMotorcycle;
      if (_filter == 'Motorcycle') return v.isMotorcycle;
      return true;
    }).toList();
  }

  void _onFilterChanged(String newFilter) {
    setState(() {
      _filter = newFilter;
      _currentPageNotifier.value = 0;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  void _showAddEditVehicleModal({Vehicle? vehicleToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (ctx) => BlurredModalSheet(
        isDraggable: true,
        child: _VehicleFormModal(
          vehicleToEdit: vehicleToEdit,
          onSave: (savedVehicle) async {
            if (vehicleToEdit == null) {
              await widget.appState.addVehicle(savedVehicle);
              _precacheVehicleImages();
              final filtered = _getFilteredVehicles();
              final newIdx = filtered.indexWhere((v) => v.id == savedVehicle.id);
              if (newIdx != -1 && _pageController.hasClients) {
                _pageController.animateToPage(
                  newIdx,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            } else {
              await widget.appState.updateVehicle(savedVehicle);
              _precacheVehicleImages();
            }
            widget.onSaved();
            setState(() {});
          },
        ),
      ),
    );
  }

  void _confirmDeleteVehicle(Vehicle vehicle) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => BlurredDialog(
        child: AlertDialog(
          title: const Text('Delete Vehicle'),
          content: Text('Are you sure you want to remove "${vehicle.displayName}" from your garage?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.appState.deleteVehicle(vehicle.id);
              widget.onSaved();
              setState(() {
                if (_currentPageNotifier.value > 0) {
                  _currentPageNotifier.value--;
                }
              });
              if (_pageController.hasClients && _currentPageNotifier.value >= 0) {
                _pageController.jumpToPage(_currentPageNotifier.value);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.appState.accentColor;
    final vehicles = _getFilteredVehicles();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // Filter Tabs Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildFilterChip('All (${widget.appState.vehicles.length})', 'All'),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Cars (${widget.appState.vehicles.where((v) => !v.isMotorcycle).length})',
                      'Car',
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Bikes (${widget.appState.vehicles.where((v) => v.isMotorcycle).length})',
                      'Motorcycle',
                    ),
                  ],
                ),
              ),
            ),

            // Vehicle Carousel (Swipable with peeking adjacent cards)
            Expanded(
              child: vehicles.isEmpty
                  ? _buildEmptyState(theme, accent)
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: vehicles.length,
                      padEnds: true,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (idx) => _currentPageNotifier.value = idx,
                      itemBuilder: (context, index) {
                        final vehicle = vehicles[index];
                        final isSelected = widget.appState.selectedVehicleId == vehicle.id;

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: _VehicleCarouselCard(
                            key: ValueKey(vehicle.id),
                            vehicle: vehicle,
                            isSelected: isSelected,
                            accent: accent,
                            onSelectForAi: () async {
                              await widget.appState.selectVehicle(vehicle.id);
                              widget.onSaved();
                              setState(() {});
                            },
                            onSpecs: () {
                              VehicleSpecsDialog.show(
                                context,
                                vehicle: vehicle,
                                geminiService: widget.geminiService,
                                onVehicleUpdated: (v) {
                                  widget.appState.updateVehicle(v);
                                  setState(() {});
                                },
                              );
                            },
                            onEdit: () => _showAddEditVehicleModal(vehicleToEdit: vehicle),
                            onDelete: () => _confirmDeleteVehicle(vehicle),
                          ),
                        );
                      },
                    ),
            ),

            // Below the vehicle cards: Page Dots Indicator & "Add Ride" Button
            if (vehicles.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (vehicles.length > 1)
                _buildPageIndicatorDots(vehicles.length, accent),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    label: const Text('Add Ride to Garage'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: accent.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                    onPressed: () => _showAddEditVehicleModal(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, Color accent) {
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.garage_outlined, size: 64, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 16),
            Text(
              'No vehicles in this category',
              style: theme.textTheme.titleLarge?.copyWith(
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Ride to Garage'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: accent.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _showAddEditVehicleModal(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterKey) {
    final isSelected = _filter == filterKey;
    final accent = widget.appState.accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedBg = isDark
        ? accent.withValues(alpha: 0.22)
        : accent;
    final selectedText = isDark
        ? accent
        : (accent.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white);
    final unselectedBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.04);
    final unselectedText = isDark
        ? Colors.white.withValues(alpha: 0.75)
        : const Color(0xFF334155);
    final borderColor = isSelected
        ? accent
        : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.12));

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _onFilterChanged(filterKey),
      selectedColor: selectedBg,
      backgroundColor: unselectedBg,
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        color: isSelected ? selectedText : unselectedText,
      ),
      side: BorderSide(color: borderColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildPageIndicatorDots(int count, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<int>(
      valueListenable: _currentPageNotifier,
      builder: (context, currentPage, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(count, (index) {
            final isCur = index == currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isCur ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: isCur ? accent : (isDark ? Colors.white24 : Colors.black26),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  if (isCur)
                    BoxShadow(
                      color: accent.withValues(alpha: isDark ? 0.5 : 0.35),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

class _VehicleCarouselCard extends StatefulWidget {
  final Vehicle vehicle;
  final bool isSelected;
  final Color accent;
  final VoidCallback onSelectForAi;
  final VoidCallback onSpecs;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VehicleCarouselCard({
    super.key,
    required this.vehicle,
    required this.isSelected,
    required this.accent,
    required this.onSelectForAi,
    required this.onSpecs,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_VehicleCarouselCard> createState() => _VehicleCarouselCardState();
}

class _VehicleCarouselCardState extends State<_VehicleCarouselCard>
    with AutomaticKeepAliveClientMixin {
  late PageController _photoPageController;
  int _currentPhotoIndex = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _photoPageController = PageController(initialPage: 0);
  }

  @override
  void didUpdateWidget(covariant _VehicleCarouselCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicle.id != widget.vehicle.id) {
      _currentPhotoIndex = 0;
      if (_photoPageController.hasClients) {
        _photoPageController.jumpToPage(0);
      }
    } else {
      final imgCount = widget.vehicle.imageBytesList.length;
      if (_currentPhotoIndex >= imgCount && imgCount > 0) {
        _currentPhotoIndex = 0;
        if (_photoPageController.hasClients) {
          _photoPageController.jumpToPage(0);
        }
      }
    }
  }

  @override
  void dispose() {
    _photoPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final vehicle = widget.vehicle;
    final theme = Theme.of(context);
    final accent = widget.accent;
    final isDark = theme.brightness == Brightness.dark;
    final images = vehicle.imageBytesList;

    if (_currentPhotoIndex >= images.length && images.isNotEmpty) {
      _currentPhotoIndex = 0;
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.isSelected
              ? accent
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
          width: widget.isSelected ? 2 : 1,
        ),
        boxShadow: [
          if (widget.isSelected)
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 20,
              spreadRadius: 1,
            )
          else if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header / Category & Selection Status
              Row(
                children: [
                  Icon(
                    vehicle.icon,
                    color: widget.isSelected
                        ? (isDark ? accent : (accent.computeLuminance() > 0.45 ? const Color(0xFF0F172A) : accent))
                        : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      vehicle.type.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold,
                        color: widget.isSelected
                            ? (isDark ? accent : (accent.computeLuminance() > 0.45 ? const Color(0xFF0F172A) : accent))
                            : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  if (widget.isSelected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? accent.withValues(alpha: 0.15) : accent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accent, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 12,
                            color: isDark
                                ? accent
                                : (accent.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Selected',
                            style: TextStyle(
                              color: isDark
                                  ? accent
                                  : (accent.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                        foregroundColor: isDark ? Colors.white70 : const Color(0xFF334155),
                      ),
                      icon: const Icon(Icons.radio_button_unchecked, size: 14),
                      label: const Text('Select for AI', style: TextStyle(fontSize: 12)),
                      onPressed: widget.onSelectForAi,
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Vehicle Photo Display
              if (images.isNotEmpty)
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: images.length == 1
                            ? Image.memory(
                                images.first,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                              )
                            : PageView.builder(
                                controller: _photoPageController,
                                itemCount: images.length,
                                physics: const BouncingScrollPhysics(),
                                onPageChanged: (pIdx) {
                                  setState(() => _currentPhotoIndex = pIdx);
                                },
                                itemBuilder: (context, pIdx) {
                                  return Image.memory(
                                    images[pIdx],
                                    height: 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.medium,
                                  );
                                },
                              ),
                      ),
                    ),
                    if (images.length > 1) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(images.length, (pIdx) {
                          final isCur = pIdx == _currentPhotoIndex;
                          return GestureDetector(
                            onTap: () {
                              _currentPhotoIndex = pIdx;
                              if (_photoPageController.hasClients) {
                                _photoPageController.animateToPage(
                                  pIdx,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                );
                              } else {
                                setState(() {});
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isCur
                                    ? accent
                                    : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isCur
                                      ? accent
                                      : (isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.08)),
                                ),
                              ),
                              child: Text(
                                'Photo ${pIdx + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isCur
                                      ? (accent.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white)
                                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ],
                )
              else
                Container(
                  height: 130,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08)),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, size: 28, color: isDark ? Colors.white38 : Colors.black38),
                        const SizedBox(height: 6),
                        Text(
                          'No photos added yet',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : const Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 14),
              // Vehicle Title & Details
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vehicle.displayName,
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 19),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (vehicle.color.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        vehicle.color,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (vehicle.nickname.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${vehicle.ymm}${vehicle.trim.isNotEmpty ? " • ${vehicle.trim}" : ""}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else if (vehicle.trim.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Trim: ${vehicle.trim}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12.5,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ),

              if (vehicle.mods.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.tune,
                        size: 14,
                        color: isDark ? accent : (accent.computeLuminance() > 0.45 ? const Color(0xFF0F172A) : accent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vehicle.mods,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              // Action Buttons Row: Specs / Info, Edit, Delete
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(
                        Icons.speed,
                        size: 16,
                        color: isDark ? accent : (accent.computeLuminance() > 0.45 ? const Color(0xFF0F172A) : accent),
                      ),
                      label: Text(
                        'Specs & Dyno',
                        style: TextStyle(
                          color: isDark ? accent : (accent.computeLuminance() > 0.45 ? const Color(0xFF0F172A) : accent),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isDark ? accent : (accent.computeLuminance() > 0.45 ? const Color(0xFF0F172A) : accent),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: widget.onSpecs,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 19,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                    tooltip: 'Edit Vehicle',
                    onPressed: widget.onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
                    tooltip: 'Delete Vehicle',
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleFormModal extends StatefulWidget {
  final Vehicle? vehicleToEdit;
  final Function(Vehicle) onSave;

  const _VehicleFormModal({
    this.vehicleToEdit,
    required this.onSave,
  });

  @override
  State<_VehicleFormModal> createState() => _VehicleFormModalState();
}

class _VehicleFormModalState extends State<_VehicleFormModal> {
  late String _type;
  late TextEditingController _nicknameController;
  late TextEditingController _yearController;
  late TextEditingController _makeController;
  late TextEditingController _modelController;
  late TextEditingController _colorController;
  late TextEditingController _trimController;
  late TextEditingController _modsController;
  late List<String> _imagesBase64;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicleToEdit;
    _type = v?.type ?? 'Car';
    _nicknameController = TextEditingController(text: v?.nickname ?? '');
    _yearController = TextEditingController(text: v?.year ?? '');
    _makeController = TextEditingController(text: v?.make ?? '');
    _modelController = TextEditingController(text: v?.model ?? '');
    _colorController = TextEditingController(text: v?.color ?? '');
    _trimController = TextEditingController(text: v?.trim ?? '');
    _modsController = TextEditingController(text: v?.mods ?? '');
    _imagesBase64 = List<String>.from(v?.imagesBase64 ?? []);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _yearController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _trimController.dispose();
    _modsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_imagesBase64.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 3 photos allowed per vehicle.')),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _imagesBase64.add(base64Encode(bytes));
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imagesBase64.removeAt(index);
    });
  }

  void _submit() {
    final vehicle = Vehicle(
      id: widget.vehicleToEdit?.id,
      type: _type,
      nickname: _nicknameController.text.trim(),
      year: _yearController.text.trim(),
      make: _makeController.text.trim(),
      model: _modelController.text.trim(),
      color: _colorController.text.trim(),
      trim: _trimController.text.trim(),
      mods: _modsController.text.trim(),
      imagesBase64: _imagesBase64,
      cachedSpecs: widget.vehicleToEdit?.cachedSpecs,
    );

    widget.onSave(vehicle);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEdit = widget.vehicleToEdit != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Column(
            children: [
              if (!isKeyboardOpen)
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) > 200) {
                            Navigator.pop(context);
                          }
                        },
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 12, bottom: 8),
                              width: 48,
                              height: 5,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white24 : Colors.black26,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isEdit ? 'Edit Vehicle Profile' : 'Add New Ride',
                                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          children: [
                    // Vehicle Type Selector (Car or Motorcycle)
                    Text('Vehicle Category', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTypeSegment('Car', Icons.directions_car),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTypeSegment('Motorcycle', Icons.two_wheeler),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Pictures upload (up to 3 photos)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Vehicle Photos (${_imagesBase64.length}/3)',
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_imagesBase64.length < 3)
                          TextButton.icon(
                            icon: const Icon(Icons.add_photo_alternate, size: 18),
                            label: const Text('Add Photo'),
                            onPressed: _pickImage,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildImageThumbnailsRow(),

                    const SizedBox(height: 24),
                    Text('Specifications', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(_yearController, 'Year (e.g. 2022)')),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTextField(_makeController, 'Make (e.g. Ford / Yamaha)')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(_modelController, 'Model (e.g. Mustang GT / R1)')),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTextField(_colorController, 'Color (e.g. Oxford White)')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildTextField(_trimController, 'Trim / Package (e.g. Premium / Performance / Track)'),
                    const SizedBox(height: 14),
                    _buildTextField(
                      _nicknameController,
                      'Vehicle Nickname (optional - e.g. "The Beast", "Daily Driver")',
                      prefixIcon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 14),
                    _buildTextField(
                      _modsController,
                      'Installed Modifications (e.g. turbocharger, cat-back exhaust, coil-overs, ECU tune)',
                      maxLines: 3,
                    ),

                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _submit,
                      child: Text(isEdit ? 'Update Vehicle' : 'Save Vehicle to Garage'),
                    ),
                    const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSegment(String typeName, IconData icon) {
    final isSelected = _type == typeName;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => setState(() => _type = typeName),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? accent.withValues(alpha: 0.15) : accent.withValues(alpha: 0.12))
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? accent
                : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.1)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? (isDark ? accent : (accent.computeLuminance() > 0.45 ? const Color(0xFF0F172A) : accent))
                  : (isDark ? Colors.white60 : const Color(0xFF64748B)),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              typeName,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? (isDark ? accent : (accent.computeLuminance() > 0.45 ? const Color(0xFF0F172A) : accent))
                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnailsRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: List.generate(3, (index) {
        final hasImage = index < _imagesBase64.length;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index < 2 ? 10 : 0),
            height: 90,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.1)),
            ),
            child: hasImage
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          base64Decode(_imagesBase64[index]),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeImage(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                      if (index == 0)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Primary', style: TextStyle(fontSize: 9, color: Colors.white)),
                          ),
                        ),
                    ],
                  )
                : InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _pickImage,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 22, color: isDark ? Colors.white30 : Colors.black38),
                        const SizedBox(height: 4),
                        Text('Slot ${index + 1}', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black45)),
                      ],
                    ),
                  ),
          ),
        );
      }),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    IconData? prefixIcon,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      scrollPadding: const EdgeInsets.only(bottom: 90, top: 20),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 18, color: Colors.white60)
            : null,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
      ),
    );
  }
}
