import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import '../gemini_service.dart';
import '../models.dart';
import '../widgets/blurred_modal.dart';

class AssistantPage extends StatefulWidget {
  final AppState appState;
  final GeminiService geminiService;

  const AssistantPage({
    super.key,
    required this.appState,
    required this.geminiService,
  });

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  Uint8List? _selectedImage;

  // Voice chat variables
  late stt.SpeechToText _speech;
  late AudioPlayer _audioPlayer;
  bool _isListening = false;
  bool _voiceMode = false;
  String _recognizedText = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _audioPlayer = AudioPlayer();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  bool _isSpeechInitialized = false;
  bool _isInitializingSpeech = false;

  Future<void> _initSpeech() async {
    if (_isSpeechInitialized || _isInitializingSpeech) return;
    _isInitializingSpeech = true;
    try {
      _isSpeechInitialized = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (_isListening) {
              setState(() => _isListening = false);
              if (_recognizedText.isNotEmpty) {
                _controller.text = _recognizedText;
                _sendMessage();
                _recognizedText = '';
              }
            }
          }
        },
      );
    } finally {
      _isInitializingSpeech = false;
    }
  }

  void _startListening() async {
    if (!_isListening) {
      await _initSpeech();
      if (_isSpeechInitialized) {
        setState(() {
          _isListening = true;
          _recognizedText = '';
        });
        _speech.listen(
          onResult: (val) => setState(() {
            _recognizedText = val.recognizedWords;
          }),
        );
      }
    }
  }

  void _stopListening() async {
    if (_isListening) {
      await _speech.stop();
    }
  }

  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  Future<void> _speakWithGoogleVoices(String text) async {
    if (!_voiceMode) return;

    final cleanText = text.replaceAll(RegExp(r'[*#_`]'), '');
    final sentences = cleanText.split(RegExp(r'(?<=[.!?])\s+'));

    for (var sentence in sentences) {
      if (sentence.trim().isEmpty || !_voiceMode) continue;
      final url =
          'https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en&q=${Uri.encodeComponent(sentence)}';
      await _audioPlayer.play(UrlSource(url));
      await _audioPlayer.onPlayerComplete.first;
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedImage = bytes;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    final image = _selectedImage;
    final b64 = image != null ? base64Encode(image) : null;

    final userMessage = ChatMessage(
      role: 'user',
      text: text,
      imageBase64: b64,
    );

    final assistantMessage = ChatMessage(
      role: 'assistant',
      text: '',
    );

    final currentSession = widget.appState.activeChatSession;
    currentSession.messages.add(userMessage);
    currentSession.messages.add(assistantMessage);

    setState(() {
      _controller.clear();
      _selectedImage = null;
      _isLoading = true;
    });

    _scrollToBottom();

    final vehicle = widget.appState.selectedVehicle;
    final nicknamePart = vehicle.nickname.isNotEmpty ? ' (Nickname: "${vehicle.nickname}")' : '';
    final vehicleContext =
        'Selected Vehicle: ${vehicle.type} - ${vehicle.year} ${vehicle.make} ${vehicle.model} ${vehicle.trim}$nicknamePart, Color: ${vehicle.color}. Installed Mods: ${vehicle.mods.isEmpty ? "Stock" : vehicle.mods}.';
    final prompt = '$vehicleContext\n\nUser Question: $text';

    String fullResponse = '';
    try {
      await for (final chunk in widget.geminiService.askAssistantStream(prompt, imageBytes: image)) {
        setState(() {
          _isLoading = false;
          fullResponse += chunk;
          assistantMessage.text = fullResponse;
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        fullResponse = 'Error generating response: $e';
        assistantMessage.text = fullResponse;
      });
    }

    // Persist to storage
    await widget.appState.saveChatSessions();

    if (fullResponse.isNotEmpty) {
      _speakWithGoogleVoices(fullResponse);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showChatSessionsDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (ctx) => BlurredModalSheet(
        isDraggable: true,
        child: _ChatHistorySheet(
          appState: widget.appState,
          onSessionSelected: () {
            Navigator.pop(ctx);
            setState(() {});
          },
        ),
      ),
    );
  }

  void _showVehicleSwitcherSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (ctx) => BlurredModalSheet(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select Active Vehicle for AI',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 12),
            ...widget.appState.vehicles.map((v) {
              final isSelected = widget.appState.selectedVehicleId == v.id;
              return ListTile(
                leading: Icon(v.icon, color: isSelected ? widget.appState.accentColor : Colors.white60),
                title: Text(v.displayName, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(v.type),
                trailing: isSelected ? Icon(Icons.check_circle, color: widget.appState.accentColor) : null,
                onTap: () async {
                  await widget.appState.selectVehicle(v.id);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    setState(() {});
                  }
                },
              );
            }),
            const SizedBox(height: 16),
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
    final currentSession = widget.appState.activeChatSession;
    final messages = currentSession.messages;

    return Column(
      children: [
        // Top Header Banner: Active Vehicle & Chat History (Requirements 3 & 7)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.cardTheme.color,
          child: Row(
            children: [
              // Vehicle Switcher Pill (Requirement 3)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _showVehicleSwitcherSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(vehicle.icon, size: 14, color: accent),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(
                          vehicle.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: accent,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 16, color: accent),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Chat History Button (Requirement 7)
              IconButton(
                icon: const Icon(Icons.history, size: 20),
                tooltip: 'Chat History',
                onPressed: _showChatSessionsDrawer,
              ),
              // New Chat Button
              IconButton(
                icon: const Icon(Icons.add_comment_outlined, size: 20),
                tooltip: 'New Chat Session',
                onPressed: () async {
                  await widget.appState.createNewChatSession();
                  setState(() {});
                },
              ),
            ],
          ),
        ),

        // Voice Mode Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: theme.cardTheme.color?.withValues(alpha: 0.7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Voice Chat Mode (Google Voice)',
                style: TextStyle(
                  color: _voiceMode ? accent : Colors.white54,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: _voiceMode,
                activeThumbColor: accent,
                onChanged: (val) async {
                  setState(() => _voiceMode = val);
                  if (!val) {
                    await _audioPlayer.stop();
                    if (_isListening) _speech.stop();
                  }
                },
              ),
            ],
          ),
        ),

        // Messages List
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 48, color: Colors.white24),
                      const SizedBox(height: 12),
                      Text('Start a conversation about ${vehicle.displayName}', style: theme.textTheme.bodyMedium),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isUser = msg.role == 'user';
                    return _buildMessageBubble(msg, isUser, accent);
                  },
                ),
        ),

        if (_isLoading) LinearProgressIndicator(color: accent),

        if (_isListening)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Listening: $_recognizedText',
              style: TextStyle(color: accent, fontStyle: FontStyle.italic),
            ),
          ),

        if (_selectedImage != null)
          Container(
            padding: const EdgeInsets.all(8.0),
            color: theme.cardTheme.color,
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_selectedImage!, height: 100, fit: BoxFit.cover),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => setState(() => _selectedImage = null),
                )
              ],
            ),
          ),

        // Input Field Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.cardTheme.color,
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.add_photo_alternate, color: accent),
                  onPressed: _pickImage,
                  tooltip: 'Upload photo for diagnostics',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? 'Listening...'
                          : 'Ask about mods, specs, diagnostics...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Colors.transparent,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                if (_voiceMode)
                  GestureDetector(
                    onTap: _toggleListening,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening ? Colors.redAccent : accent.withValues(alpha: 0.2),
                      ),
                      child: Icon(
                        _isListening ? Icons.stop : Icons.mic,
                        color: _isListening ? Colors.white : accent,
                        size: 20,
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: Icon(Icons.send, color: accent),
                    onPressed: _sendMessage,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isUser, Color accent) {
    final imageBytes = msg.imageBytes;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 16,
          left: isUser ? 40.0 : 0.0,
          right: isUser ? 0.0 : 40.0,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUser ? accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(0),
          ),
          border: Border.all(
            color: isUser ? accent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(imageBytes, height: 180, fit: BoxFit.cover),
              ),
              const SizedBox(height: 10),
            ],
            if (msg.text.isNotEmpty)
              Text(
                msg.text,
                style: const TextStyle(fontSize: 14.5, height: 1.45),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatHistorySheet extends StatelessWidget {
  final AppState appState;
  final VoidCallback onSessionSelected;

  const _ChatHistorySheet({
    required this.appState,
    required this.onSessionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = appState.accentColor;
    final sessions = appState.chatSessions;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
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
                    Text(
                      'Chat History (${sessions.length})',
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New Chat', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await appState.createNewChatSession();
                        onSessionSelected();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: sessions.isEmpty
                    ? Center(
                        child: Text('No previous conversations', style: theme.textTheme.bodyMedium),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          final isActive = appState.activeChatSessionId == session.id;
                          final dateStr =
                              '${session.updatedAt.month}/${session.updatedAt.day} ${session.updatedAt.hour.toString().padLeft(2, '0')}:${session.updatedAt.minute.toString().padLeft(2, '0')}';

                          return ListTile(
                            leading: Icon(
                              Icons.chat_bubble_outline,
                              color: isActive ? accent : Colors.white38,
                            ),
                            title: Text(
                              session.title,
                              style: TextStyle(
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                color: isActive ? accent : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$dateStr • ${session.messages.length} messages',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              onPressed: () async {
                                await appState.deleteChatSession(session.id);
                                if (ctx.mounted && appState.chatSessions.isEmpty) {
                                  Navigator.pop(ctx);
                                }
                              },
                            ),
                            onTap: () async {
                              await appState.selectChatSession(session.id);
                              onSessionSelected();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
