import 'package:flutter/material.dart';
import 'models.dart';
import 'theme.dart';
import 'gemini_service.dart';
import 'pages/garage_page.dart';
import 'pages/obd2_page.dart';
import 'pages/assistant_page.dart';
import 'pages/mockup_page.dart';
import 'pages/settings_page.dart';
import 'services/obd2_service.dart';
import 'widgets/blurred_modal.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.load();
  runApp(AITunerApp(appState: appState));
}

class AITunerApp extends StatelessWidget {
  final AppState appState;

  const AITunerApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'AI Tuner',
          theme: AppTheme.buildLightTheme(accentColor: appState.accentColor),
          darkTheme: AppTheme.buildDarkTheme(accentColor: appState.accentColor),
          themeMode: appState.themeMode,
          home: MainScreen(appState: appState),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  final AppState appState;

  const MainScreen({super.key, required this.appState});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  GeminiService? _geminiService;
  final Obd2Service _obd2service = Obd2Service();

  @override
  void initState() {
    super.initState();
    _checkApiKey();
  }

  @override
  void dispose() {
    _obd2service.dispose();
    super.dispose();
  }

  void _checkApiKey() {
    if (widget.appState.apiKey.isNotEmpty) {
      setState(() {
        _geminiService = GeminiService(widget.appState.apiKey);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showApiKeyDialog();
      });
    }
  }

  Future<void> _showApiKeyDialog() async {
    String tempKey = '';
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (context) {
        return BlurredDialog(
          dismissible: false,
          child: AlertDialog(
            title: const Text('Welcome to AI Tuner'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter your Google Gemini API Key (BYOK) to activate real-time tuning, AI dyno analysis, and photorealistic mockups:'),
                const SizedBox(height: 14),
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Gemini API Key',
                    hintText: 'AIzaSy...',
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  obscureText: true,
                  onChanged: (val) => tempKey = val,
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  if (tempKey.trim().isNotEmpty) {
                    widget.appState.saveApiKey(tempKey.trim());
                    setState(() {
                      _geminiService = GeminiService(tempKey.trim());
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('Save & Continue'),
              )
            ],
          ),
        );
      },
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(appState: widget.appState),
      ),
    ).then((_) {
      // Re-initialize geminiService if key changed
      if (widget.appState.apiKey.isNotEmpty) {
        setState(() {
          _geminiService = GeminiService(widget.appState.apiKey);
        });
      }
    });
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.appState.accentColor;

    if (_geminiService == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: accent),
              const SizedBox(height: 16),
              const Text('Connecting to AI Tuner...'),
            ],
          ),
        ),
      );
    }

    final pages = [
      GaragePage(
        appState: widget.appState,
        geminiService: _geminiService,
        onSaved: () => setState(() {}),
      ),
      Obd2Page(
        appState: widget.appState,
        geminiService: _geminiService,
        obd2service: _obd2service,
        onSwitchToAssistant: () => _onTabTapped(2),
      ),
      AssistantPage(
        appState: widget.appState,
        geminiService: _geminiService!,
      ),
      MockupPage(
        appState: widget.appState,
        geminiService: _geminiService!,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          [
            'My Garage',
            'OBD-II Live & AI Diagnostics',
            'AI Tuner Assistant',
            'Mockup Studio'
          ][_currentIndex],
          style: TextStyle(
            color: _currentIndex == 0 ? null : accent,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings & Preferences',
            onPressed: _openSettings,
          )
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: pages[_currentIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).cardTheme.color,
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          selectedItemColor: accent,
          unselectedItemColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white38
              : const Color(0xFF64748B),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.garage_outlined),
              activeIcon: Icon(Icons.garage),
              label: 'Garage',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.speed_outlined),
              activeIcon: Icon(Icons.speed),
              label: 'OBD-II',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'AI Assistant',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.brush_outlined),
              activeIcon: Icon(Icons.brush),
              label: 'Mockups',
            ),
          ],
        ),
      ),
    );
  }
}
