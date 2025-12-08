import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'providers/music_assistant_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/settings_service.dart';
import 'services/audio/massiv_audio_handler.dart';
import 'services/auth/auth_manager.dart';
import 'services/debug_logger.dart';
import 'theme/theme_provider.dart';
import 'theme/app_theme.dart';
import 'theme/system_theme_helper.dart';
import 'widgets/global_player_overlay.dart';

// Global audio handler instance
late MassivAudioHandler audioHandler;

// Global debug logger instance
final _logger = DebugLogger();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create auth manager for streaming headers
  final authManager = AuthManager();

  // Initialize audio_service with our custom handler
  audioHandler = await AudioService.init(
    builder: () => MassivAudioHandler(authManager: authManager),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'io.github.collotsspot.massiv.audio',
      androidNotificationChannelName: 'Ensemble Audio',
      androidNotificationOngoing: false,  // Must be false when androidStopForegroundOnPause is false
      androidNotificationIcon: 'drawable/ic_notification',
      androidShowNotificationBadge: false,
      androidStopForegroundOnPause: false,  // Keep service alive when paused for background playback
    ),
  );
  _logger.log('🎵 AudioService initialized - background playback and media notifications ENABLED');

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF1a1a1a),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MusicAssistantApp());
}

class MusicAssistantApp extends StatefulWidget {
  const MusicAssistantApp({super.key});

  @override
  State<MusicAssistantApp> createState() => _MusicAssistantAppState();
}

class _MusicAssistantAppState extends State<MusicAssistantApp> with WidgetsBindingObserver {
  late MusicAssistantProvider _musicProvider;
  late ThemeProvider _themeProvider;

  @override
  void initState() {
    super.initState();
    _musicProvider = MusicAssistantProvider();
    _themeProvider = ThemeProvider();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App came back to foreground - check connection and reconnect if needed
      _logger.log('📱 App resumed - checking WebSocket connection...');
      _musicProvider.checkAndReconnect();
    } else if (state == AppLifecycleState.paused) {
      _logger.log('📱 App paused (backgrounded)');
    } else if (state == AppLifecycleState.detached) {
      _logger.log('📱 App detached (being destroyed)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _musicProvider),
        ChangeNotifierProvider.value(value: _themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return FutureBuilder<(ColorScheme, ColorScheme)?>(
            future: themeProvider.useMaterialTheme
                ? SystemThemeHelper.getSystemColorSchemes()
                : null,
            builder: (context, snapshot) {
              // Determine which color schemes to use
              ColorScheme? lightColorScheme;
              ColorScheme? darkColorScheme;

              if (themeProvider.useMaterialTheme && snapshot.hasData && snapshot.data != null) {
                // Use system color schemes
                final (light, dark) = snapshot.data!;
                lightColorScheme = light;
                darkColorScheme = dark;
              } else {
                // Use brand color schemes
                lightColorScheme = brandLightColorScheme;
                darkColorScheme = brandDarkColorScheme;
              }

              // Update system UI overlay style based on theme mode
              final isDark = themeProvider.themeMode == ThemeMode.dark ||
                  (themeProvider.themeMode == ThemeMode.system &&
                      MediaQuery.platformBrightnessOf(context) == Brightness.dark);

              SystemChrome.setSystemUIOverlayStyle(
                SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                  systemNavigationBarColor: isDark
                      ? darkColorScheme.background
                      : lightColorScheme.background,
                  systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                ),
              );

              return MaterialApp(
                title: 'Ensemble',
                debugShowCheckedModeBanner: false,
                themeMode: themeProvider.themeMode,
                theme: AppTheme.lightTheme(colorScheme: lightColorScheme),
                darkTheme: AppTheme.darkTheme(colorScheme: darkColorScheme),
                builder: (context, child) {
                  // Wrap entire app with global player overlay
                  return GlobalPlayerOverlay(child: child ?? const SizedBox.shrink());
                },
                home: const AppStartup(),
              );
            },
          );
        },
      ),
    );
  }
}

/// Startup widget that checks if user is logged in and auto-connects
class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  bool _isConnecting = false;
  String? _savedServerUrl;
  bool _connectionAttempted = false;

  @override
  void initState() {
    super.initState();
    _checkAndConnect();
  }

  Future<void> _checkAndConnect() async {
    final serverUrl = await SettingsService.getServerUrl();

    if (!mounted) return;

    setState(() {
      _savedServerUrl = serverUrl;
    });

    // If we have a saved server URL, attempt auto-connection
    if (serverUrl != null && serverUrl.isNotEmpty) {
      setState(() {
        _isConnecting = true;
      });

      final provider = context.read<MusicAssistantProvider>();

      // Only attempt connection if not already connected
      if (!provider.isConnected) {
        _logger.log('🚀 AppStartup: Auto-connecting to saved server: $serverUrl');
        try {
          // Restore auth credentials before connecting (critical for Authelia)
          final savedCredentials = await SettingsService.getAuthCredentials();
          if (savedCredentials != null) {
            _logger.log('🚀 AppStartup: Restoring saved auth credentials');
            provider.authManager.deserializeCredentials(savedCredentials);
          }

          await provider.connectToServer(serverUrl);
          _logger.log('🚀 AppStartup: Auto-connection successful');
        } catch (e) {
          _logger.log('🚀 AppStartup: Auto-connection failed: $e');
          // Connection failed, but still show home screen
          // User can manually reconnect from there
        }
      } else {
        _logger.log('🚀 AppStartup: Already connected');
      }

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionAttempted = true;
        });
      }
    } else {
      setState(() {
        _connectionAttempted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking settings or connecting
    if (!_connectionAttempted || _isConnecting) {
      return Scaffold(
        backgroundColor: const Color(0xFF1a1a1a),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              if (_isConnecting) ...[
                const SizedBox(height: 16),
                Text(
                  'Connecting...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // If server URL is saved, go to home screen
    // Otherwise, show login screen
    final hasServerUrl = _savedServerUrl != null && _savedServerUrl!.isNotEmpty;
    return hasServerUrl ? const HomeScreen() : const LoginScreen();
  }
}
