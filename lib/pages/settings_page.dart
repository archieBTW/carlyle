import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import '../theme.dart';
import '../gemini_service.dart';
import '../widgets/blurred_modal.dart';

class SettingsPage extends StatefulWidget {
  final AppState appState;

  const SettingsPage({super.key, required this.appState});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _apiKeyController;
  bool _obscureKey = true;
  bool _isTestingKey = false;
  String? _testKeyStatus;
  bool _testKeySuccess = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.appState.apiKey);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testApiKey() async {
    final keyToTest = _apiKeyController.text.trim();
    if (keyToTest.isEmpty) {
      setState(() {
        _testKeyStatus = 'Please enter an API key first.';
        _testKeySuccess = false;
      });
      return;
    }

    setState(() {
      _isTestingKey = true;
      _testKeyStatus = null;
    });

    final success = await GeminiService.testApiKey(keyToTest);
    setState(() {
      _isTestingKey = false;
      _testKeySuccess = success;
      _testKeyStatus = success
          ? 'API Key is valid and connected!'
          : 'Failed to verify API Key. Please check the key.';
    });
  }

  void _saveApiKey() {
    final key = _apiKeyController.text.trim();
    widget.appState.saveApiKey(key);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('API key saved successfully!'),
        backgroundColor: widget.appState.accentColor,
      ),
    );
  }

  Future<void> _exportSaveToFile(BuildContext ctx, String jsonText) async {
    final accent = widget.appState.accentColor;
    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonText));
      final dateStr = DateTime.now().toIso8601String().split('T').first;
      final defaultFileName = 'ai_tuner_backup_$dateStr.json';

      final saveUri = await FilePickerPlatform.instance.saveFile(
        dialogTitle: 'Save Backup JSON File',
        fileName: defaultFileName,
        mimeType: 'application/json',
        bytes: bytes,
      );

      if (saveUri != null && mounted) {
        if (ctx.mounted) {
          Navigator.pop(ctx);
        }
        final displayName = saveUri.pathSegments.isNotEmpty
            ? saveUri.pathSegments.last
            : defaultFileName;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved successfully: $displayName'),
            backgroundColor: accent,
          ),
        );
      }
    } catch (e) {
      // If direct save is unsupported or threw an error on this platform, fallback to sharing the file
      try {
        if (ctx.mounted) {
          await _shareBackupFile(ctx, jsonText);
        }
      } catch (shareErr) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not save file: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _shareBackupFile(BuildContext ctx, String jsonText) async {
    final accent = widget.appState.accentColor;
    try {
      final dateStr = DateTime.now().toIso8601String().split('T').first;
      final fileName = 'ai_tuner_backup_$dateStr.json';
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(jsonText, flush: true);

      final box = ctx.mounted ? ctx.findRenderObject() as RenderBox? : null;
      final sharePositionOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      final result = await SharePlus.instance.share(
        ShareParams(
          text: 'AI Tuner vehicle and preferences backup JSON file',
          subject: 'AI Tuner Backup ($dateStr)',
          files: [XFile(file.path, mimeType: 'application/json', name: fileName)],
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      if (result.status == ShareResultStatus.success && mounted) {
        if (ctx.mounted) {
          Navigator.pop(ctx);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Backup shared successfully!'),
            backgroundColor: accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share backup file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildInfoBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }

  void _showExportModal(BuildContext context) {
    final jsonText = widget.appState.exportToJson();
    final accent = widget.appState.accentColor;
    final bytes = utf8.encode(jsonText);
    final sizeKb = (bytes.length / 1024).toStringAsFixed(1);
    final vehiclesCount = widget.appState.vehicles.length;
    final photosCount = widget.appState.vehicles.fold<int>(0, (sum, v) => sum + v.imagesBase64.length);
    final chatsCount = widget.appState.chatSessions.length;
    final mockupsCount = widget.appState.mockupHistory.length;

    final previewSnippet = jsonText.length > 500
        ? '${jsonText.substring(0, 500)}\n\n... [${jsonText.length - 500} characters omitted for preview]'
        : jsonText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return BlurredModalSheet(
          isDraggable: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.file_upload_outlined, color: accent, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                'Export Backup',
                                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontSize: 18),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: accent.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.inventory_2_outlined, color: accent, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Backup Archive ($sizeKb KB)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: accent,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _buildInfoBadge(Icons.directions_car, '$vehiclesCount rides ($photosCount photos)'),
                                      _buildInfoBadge(Icons.chat_bubble_outline, '$chatsCount chats'),
                                      _buildInfoBadge(Icons.brush_outlined, '$mockupsCount renders'),
                                      _buildInfoBadge(Icons.vpn_key_outlined, widget.appState.apiKey.isNotEmpty ? 'API Key included' : 'No API Key'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.save_alt, size: 20),
                              label: const Text('Save Backup File (.json)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: accent.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => _exportSaveToFile(ctx, jsonText),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('Share Backup File'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: accent),
                                foregroundColor: accent,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => _shareBackupFile(ctx, jsonText),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy JSON to Clipboard'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Theme.of(ctx).dividerColor.withValues(alpha: 0.3)),
                                foregroundColor: Colors.white70,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: jsonText));
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: const Text('Backup JSON copied to clipboard!'),
                                      backgroundColor: accent,
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'JSON Structure Preview',
                              style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                previewSnippet,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  color: Colors.white70,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showImportModal(BuildContext context) {
    final textController = TextEditingController();
    String? importError;
    String? loadedFileName;
    final accent = widget.appState.accentColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return BlurredModalSheet(
          isDraggable: false,
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.88,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.file_download_outlined, color: accent, size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Import Backup',
                                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontSize: 18),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.folder_open, size: 20),
                                  label: const Text('Select Backup File (.json)'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: accent.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 15),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () async {
                                    try {
                                      final files = await FilePickerPlatform.instance.pickFiles(
                                        type: FileType.custom,
                                        allowedExtensions: ['json'],
                                      );
                                      if (files.isNotEmpty) {
                                        final file = files.first;
                                        String? content;
                                        if (file.path != null) {
                                          content = await File(file.path!).readAsString();
                                        } else {
                                          final bytes = await file.readAsBytes();
                                          content = utf8.decode(bytes);
                                        }
                                        if (content.isNotEmpty) {
                                          setModalState(() {
                                            textController.text = content!;
                                            loadedFileName = file.name;
                                            importError = null;
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      setModalState(() {
                                        importError = 'Failed to read file: $e';
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.paste, size: 18),
                                  label: const Text('Paste from Clipboard'),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: accent),
                                    foregroundColor: accent,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () async {
                                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                                    if (data?.text != null && data!.text!.isNotEmpty) {
                                      setModalState(() {
                                        textController.text = data.text!;
                                        loadedFileName = 'Clipboard Text';
                                        importError = null;
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                if (loadedFileName != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: accent.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle, color: accent, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Loaded: $loadedFileName (${(textController.text.length / 1024).toStringAsFixed(1)} KB)',
                                            style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                TextField(
                                  controller: textController,
                                  maxLines: 5,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white),
                                  scrollPadding: const EdgeInsets.only(bottom: 90, top: 20),
                                  decoration: InputDecoration(
                                    labelText: 'Backup JSON content',
                                    hintText: '{\n  "app": "AI_TUNER",\n  ...\n}',
                                    alignLabelWithHint: true,
                                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
                                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                                  ),
                                ),
                                if (importError != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      importError!,
                                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.file_download, size: 18),
                                  label: const Text('Restore Profile & Data'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: accent.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () async {
                                    final text = textController.text.trim();
                                    if (text.isEmpty) {
                                      setModalState(() {
                                        importError = 'Please select a backup file or paste JSON first.';
                                      });
                                      return;
                                    }

                                    final messenger = ScaffoldMessenger.of(context);
                                    try {
                                      await widget.appState.importFromJson(text);
                                      if (mounted) {
                                        setState(() {
                                          _apiKeyController.text = widget.appState.apiKey;
                                        });
                                      }
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                              'Full backup restored successfully! Everything has been updated.'),
                                          backgroundColor: widget.appState.accentColor,
                                        ),
                                      );
                                    } catch (e) {
                                      setModalState(() {
                                        importError = 'Failed to parse and import JSON: $e';
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Preferences'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _buildSectionHeader('Appearance & Theme', Icons.palette_outlined),
          const SizedBox(height: 12),
          _buildThemeModeSelector(context),
          const SizedBox(height: 20),
          _buildAccentColorPicker(context),
          const SizedBox(height: 16),
          // _buildThemePreviewCard(context),

          const SizedBox(height: 12),
          _buildApiKeySection(context),

          const SizedBox(height: 32),
          _buildBackupRestoreSection(context),

          const SizedBox(height: 32),
          _buildDataManagementSection(context),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'AI Tuner v2.0 • Powered by Gemini 3.5 & 3.1 Flash Image',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final accent = widget.appState.accentColor;
    return Row(
      children: [
        Icon(icon, color: accent, size: 22),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildThemeModeSelector(BuildContext context) {
    final themeMode = widget.appState.themeMode;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildThemeSegment(
              context,
              title: 'Dark',
              icon: Icons.dark_mode_outlined,
              isSelected: themeMode == ThemeMode.dark,
              onTap: () => widget.appState.setThemeMode(ThemeMode.dark),
            ),
          ),
          Expanded(
            child: _buildThemeSegment(
              context,
              title: 'Light',
              icon: Icons.light_mode_outlined,
              isSelected: themeMode == ThemeMode.light,
              onTap: () => widget.appState.setThemeMode(ThemeMode.light),
            ),
          ),
          Expanded(
            child: _buildThemeSegment(
              context,
              title: 'System',
              icon: Icons.brightness_auto_outlined,
              isSelected: themeMode == ThemeMode.system,
              onTap: () => widget.appState.setThemeMode(ThemeMode.system),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSegment(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final accent = widget.appState.accentColor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: accent, width: 1.5)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? accent
                  : Theme.of(context).textTheme.bodyMedium?.color,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? accent
                    : Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccentColorPicker(BuildContext context) {
    final currentAccent = widget.appState.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Accent Color',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: AppTheme.accentPresets.map((preset) {
            final isSelected = currentAccent.toARGB32() == preset.color.toARGB32();
            return GestureDetector(
              onTap: () => widget.appState.setAccentColor(preset.color),
              child: Tooltip(
                message: preset.name,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: preset.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: isSelected ? 3.5 : 0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: preset.color.withValues(alpha: isSelected ? 0.6 : 0.2),
                        blurRadius: isSelected ? 12 : 4,
                        spreadRadius: isSelected ? 2 : 0,
                      )
                    ],
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 22)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildApiKeySection(BuildContext context) {
    final accent = widget.appState.accentColor;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Google Gemini API Key',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Gemini API Key',
              hintText: 'AIzaSy...',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white54,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          if (_testKeyStatus != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _testKeySuccess ? Icons.check_circle : Icons.error,
                  color: _testKeySuccess ? Colors.greenAccent : Colors.redAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _testKeyStatus!,
                    style: TextStyle(
                      color: _testKeySuccess ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _isTestingKey
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.speed, size: 18),
                  label: const Text('Test Connection'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: accent),
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isTestingKey ? null : _testApiKey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save Key'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saveApiKey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackupRestoreSection(BuildContext context) {
    final accent = widget.appState.accentColor;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.swap_vert, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Import / Export',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Export JSON'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: accent),
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showExportModal(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Import JSON'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showImportModal(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataManagementSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          _buildDataRow(
            icon: Icons.chat_bubble_outline,
            title: 'Chat History',
            subtitle: '${widget.appState.chatSessions.length} conversations saved',
            actionText: 'Clear',
            onAction: () => _confirmClear(
              title: 'Clear Chat History',
              content: 'Are you sure you want to delete all saved conversations?',
              onConfirm: () async {
                widget.appState.chatSessions.clear();
                await widget.appState.saveChatSessions();
                setState(() {});
              },
            ),
          ),
          const Divider(height: 24),
          _buildDataRow(
            icon: Icons.brush_outlined,
            title: 'Mockup Renders',
            subtitle: '${widget.appState.mockupHistory.length} mockups saved',
            actionText: 'Clear',
            onAction: () => _confirmClear(
              title: 'Clear Mockup History',
              content: 'Are you sure you want to delete all saved mockup renders?',
              onConfirm: () async {
                await widget.appState.clearMockupHistory();
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionText,
    required VoidCallback onAction,
  }) {
    return Row(
      children: [
        Icon(icon, size: 24, color: Colors.white70),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
            ],
          ),
        ),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          child: Text(actionText),
        ),
      ],
    );
  }

  Future<void> _confirmClear({
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => BlurredDialog(
        child: AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      onConfirm();
    }
  }
}
