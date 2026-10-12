import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../gemini_service.dart';
import '../models.dart';
import '../widgets/blurred_modal.dart';

class MockupPage extends StatefulWidget {
  final AppState appState;
  final GeminiService geminiService;

  const MockupPage({
    super.key,
    required this.appState,
    required this.geminiService,
  });

  @override
  State<MockupPage> createState() => _MockupPageState();
}

class _MockupPageState extends State<MockupPage> {
  final TextEditingController _promptController = TextEditingController();
  bool _isLoading = false;
  Uint8List? _currentImageBytes;
  String? _promptUsed;
  String? _errorMessage;
  bool _showHistory = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  // Requirement 6: Initial generation vs Follow-up prompt
  Future<void> _generateMockup({bool isFollowup = false}) async {
    final queryText = _promptController.text.trim();
    if (queryText.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final vehicle = widget.appState.selectedVehicle;
      final vehicleContext =
          '${vehicle.year} ${vehicle.make} ${vehicle.model} ${vehicle.trim}, color ${vehicle.color}';

      List<Uint8List> referenceImagesToSend = [];

      if (isFollowup && _currentImageBytes != null) {
        // Requirement 6: Follow-up prompt includes ONLY the most recently generated vehicle image!
        referenceImagesToSend = [_currentImageBytes!];
      } else {
        // Requirement 6: Initial generation includes selected vehicle's photos (up to 3)
        referenceImagesToSend = vehicle.imageBytesList;
      }

      final optimizedPrompt = await widget.geminiService.generateMockupPrompt(
        vehicleContext,
        queryText,
        hasReferencePhotos: referenceImagesToSend.isNotEmpty,
        isFollowup: isFollowup,
      );

      final generatedBytes = await widget.geminiService.generateMockupImageDirect(
        optimizedPrompt,
        widget.appState.apiKey,
        referenceImages: referenceImagesToSend,
      );

      if (generatedBytes != null) {
        setState(() {
          _currentImageBytes = generatedBytes;
          _promptUsed = optimizedPrompt;
          _promptController.clear();
          _isLoading = false;
        });

        // Save to Mockup History (Requirement 7)
        final historyItem = MockupItem(
          vehicleId: vehicle.id,
          vehicleName: vehicle.displayName,
          prompt: queryText,
          imageBase64: base64Encode(generatedBytes),
          isFollowup: isFollowup,
        );
        await widget.appState.addMockup(historyItem);
      } else {
        setState(() {
          _errorMessage = 'Gemini returned an empty image response. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error generating mockup: $e';
        _isLoading = false;
      });
    }
  }

  void _startFreshMockup() {
    setState(() {
      _currentImageBytes = null;
      _promptUsed = null;
      _promptController.clear();
      _errorMessage = null;
    });
  }

  void _useHistoryMockupAsBase(MockupItem item) {
    final bytes = item.imageBytes;
    if (bytes != null) {
      setState(() {
        _currentImageBytes = bytes;
        _promptUsed = item.prompt;
        _showHistory = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded render from history. You can now send follow-up prompts on this image!'),
          backgroundColor: widget.appState.accentColor,
        ),
      );
    }
  }

  void _showImageLightbox(Uint8List imageBytes, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => BlurredDialog(
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(ctx),
                  )
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.memory(imageBytes, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.appState.accentColor;
    final vehicle = widget.appState.selectedVehicle;
    final hasGeneratedImage = _currentImageBytes != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Top Navigation / Header: Active Vehicle & Mode Switcher
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: theme.cardTheme.color,
            child: Row(
              children: [
                // Vehicle Badge
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(vehicle.icon, size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Active: ',
                            style: TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                          Flexible(
                            child: Text(
                              vehicle.displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        vehicle.imageBytesList.isNotEmpty
                            ? '📎 ${vehicle.imageBytesList.length} photos will be referenced'
                            : '⚠️ No garage photos (text specs only)',
                        style: TextStyle(
                          fontSize: 11,
                          color: vehicle.imageBytesList.isNotEmpty ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle between Generator and Mockup History (Requirement 7)
                IconButton(
                  icon: Icon(
                    _showHistory ? Icons.brush : Icons.history,
                    color: _showHistory ? accent : Colors.white70,
                  ),
                  tooltip: _showHistory ? 'Back to Generator' : 'Mockup History',
                  onPressed: () => setState(() => _showHistory = !_showHistory),
                ),
              ],
            ),
          ),

          // Main View (Generator vs History)
          Expanded(
            child: _showHistory
                ? _buildHistoryView(context)
                : _buildGeneratorView(context, hasGeneratedImage, accent),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratorView(BuildContext context, bool hasGeneratedImage, Color accent) {
    final theme = Theme.of(context);
    final vehicle = widget.appState.selectedVehicle;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Followup vs Initial Status Banner
          if (hasGeneratedImage)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Follow-up Mode: Next prompt applies to the generated render below only.',
                      style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _startFreshMockup,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('New Base', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Render Display
          if (hasGeneratedImage) ...[
            GestureDetector(
              onTap: () => _showImageLightbox(_currentImageBytes!, 'Mockup Render'),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25),
                      blurRadius: 30,
                      spreadRadius: -5,
                    )
                  ],
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.memory(
                        _currentImageBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fullscreen, size: 16, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Tap to Enlarge', style: TextStyle(fontSize: 11, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_promptUsed != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Prompt: $_promptUsed',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ] else ...[
            // Explanatory Card when empty
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                children: [
                  Icon(Icons.auto_awesome, size: 40, color: accent),
                  const SizedBox(height: 12),
                  Text(
                    'AI Visual Mockup Studio',
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your dream visual modifications. When you generate, your garage photos of ${vehicle.displayName} are referenced so the render preserves your exact car lines and color.',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Prompt Input Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasGeneratedImage ? accent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _promptController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: hasGeneratedImage
                        ? 'Follow-up Modification Prompt'
                        : 'Desired Visual Modifications',
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                    hintText: hasGeneratedImage
                        ? 'e.g. Change wheels to bronze TE37, add carbon front splitter, golden hour lighting'
                        : 'e.g. Lowered on coilovers, titanium exhaust tips, carbon fiber hood, Tokyo neon night',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Icon(hasGeneratedImage ? Icons.subdirectory_arrow_right : Icons.brush),
                  label: Text(
                    _isLoading
                        ? 'Generating Render with Gemini...'
                        : (hasGeneratedImage ? 'Apply Follow-up Modification' : 'Generate Initial Mockup'),
                  ),
                  onPressed: _isLoading ? null : () => _generateMockup(isFollowup: hasGeneratedImage),
                ),
              ],
            ),
          ),

          if (_isLoading) ...[
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: accent),
                  const SizedBox(height: 12),
                  Text(
                    hasGeneratedImage
                        ? 'Applying follow-up mods to your latest render...'
                        : 'Synthesizing vehicle photos and mods with Gemini 3.1 Flash Image (~10s)...',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Requirement 7: Mockup History View
  Widget _buildHistoryView(BuildContext context) {
    final theme = Theme.of(context);
    final history = widget.appState.mockupHistory;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history_outlined, size: 60, color: Colors.white24),
            const SizedBox(height: 16),
            Text('No Mockups in History Yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Generated renders will appear here automatically.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _showHistory = false),
              child: const Text('Create Mockup Now'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        final bytes = item.imageBytes;
        final timeStr =
            '${item.timestamp.month}/${item.timestamp.day} ${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (bytes != null)
                GestureDetector(
                  onTap: () => _showImageLightbox(bytes, item.prompt),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Image.memory(
                      bytes,
                      height: 180,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item.vehicleName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Row(
                          children: [
                            if (item.isFollowup)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purpleAccent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Follow-up',
                                  style: TextStyle(fontSize: 10, color: Colors.purpleAccent),
                                ),
                              ),
                            Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.white38)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.prompt,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.fork_right, size: 16),
                            label: const Text('Iterate / Follow-up', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: widget.appState.accentColor),
                              foregroundColor: widget.appState.accentColor,
                            ),
                            onPressed: () => _useHistoryMockupAsBase(item),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          tooltip: 'Delete render',
                          onPressed: () => widget.appState.deleteMockup(item.id),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
