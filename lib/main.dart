import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'providers/music_assistant_provider.dart';
import 'providers/navigation_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/settings_service.dart';
import 'services/audio/massiv_audio_handler.dart';
import 'services/auth/auth_manager.dart';
import 'services/debug_logger.dart';
import 'services/hardware_volume_service.dart';
import 'services/music_assistant_api.dart' show MAConnectionState;
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
  final _hardwareVolumeService = HardwareVolumeService();
  StreamSubscription? _volumeUpSub;
  StreamSubscription? _volumeDownSub;

  // Volume step size (percentage points per button press)
  static const int _volumeStep = 5;

  @override
  void initState() {
    super.initState();
    _musicProvider = MusicAssistantProvider();
    _themeProvider = ThemeProvider();
    WidgetsBinding.instance.addObserver(this);
    _initHardwareVolumeControl();
  }

  Future<void> _initHardwareVolumeControl() async {
    await _hardwareVolumeService.init();

    _volumeUpSub = _hardwareVolumeService.onVolumeUp.listen((_) {
      _adjustVolume(_volumeStep);
    });

    _volumeDownSub = _hardwareVolumeService.onVolumeDown.listen((_) {
      _adjustVolume(-_volumeStep);
    });
  }

  Future<void> _adjustVolume(int delta) async {
    final player = _musicProvider.selectedPlayer;
    if (player == null) {
      _logger.log('🔊 Hardware volume button pressed but no player selected');
      return;
    }

    _logger.log('🔊 Hardware volume: player=${player.displayName}, current=${player.volume}, delta=$delta');

    final newVolume = (player.volume + delta).clamp(0, 100);
    if (newVolume != player.volume) {
      try {
        await _musicProvider.setVolume(player.playerId, newVolume);
        _logger.log('🔊 Hardware volume adjusted: ${player.volume} -> $newVolume for ${player.displayName}');
      } catch (e) {
        _logger.error('Hardware volume adjustment failed', context: 'VolumeControl', error: e);
      }
    } else {
      _logger.log('🔊 Hardware volume: already at limit ($newVolume)');
    }
  }

  @override
  void dispose() {
    _volumeUpSub?.cancel();
    _volumeDownSub?.cancel();
    _hardwareVolumeService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    // Intercept back button at app level - runs BEFORE Navigator processes it
    // If player is expanded, collapse it and consume the back gesture
    if (GlobalPlayerOverlay.isPlayerExpanded) {
      GlobalPlayerOverlay.collapsePlayer();
      return true; // We handled it, don't let Navigator process it
    }
    // Let Navigator handle the back gesture normally
    return super.didPopRoute();
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

              return SystemUIWrapper(
                themeMode: themeProvider.themeMode,
                lightColorScheme: lightColorScheme,
                darkColorScheme: darkColorScheme,
                child: MaterialApp(
                  navigatorKey: navigationProvider.navigatorKey,
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Widget that manages system UI overlay style updates efficiently
/// Only updates when theme properties actually change
class SystemUIWrapper extends StatefulWidget {
  final Widget child;
  final ThemeMode themeMode;
  final ColorScheme lightColorScheme;
  final ColorScheme darkColorScheme;

  const SystemUIWrapper({
    super.key,
    required this.child,
    required this.themeMode,
    required this.lightColorScheme,
    required this.darkColorScheme,
  });

  @override
  State<SystemUIWrapper> createState() => _SystemUIWrapperState();
}

class _SystemUIWrapperState extends State<SystemUIWrapper> {
  ThemeMode? _previousThemeMode;
  Brightness? _previousPlatformBrightness;
  ColorScheme? _previousLightColorScheme;
  ColorScheme? _previousDarkColorScheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSystemUIIfNeeded();
  }

  @override
  void didUpdateWidget(SystemUIWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSystemUIIfNeeded();
  }

  void _updateSystemUIIfNeeded() {
    final platformBrightness = MediaQuery.platformBrightnessOf(context);

    // Check if any relevant properties have changed
    final themeChanged = _previousThemeMode != widget.themeMode;
    final platformBrightnessChanged = _previousPlatformBrightness != platformBrightness;
    final lightColorSchemeChanged = _previousLightColorScheme != widget.lightColorScheme;
    final darkColorSchemeChanged = _previousDarkColorScheme != widget.darkColorScheme;

    if (themeChanged || platformBrightnessChanged || lightColorSchemeChanged || darkColorSchemeChanged) {
      // Determine if we should use dark theme
      final isDark = widget.themeMode == ThemeMode.dark ||
          (widget.themeMode == ThemeMode.system && platformBrightness == Brightness.dark);

      // Update system UI overlay style
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isDark
              ? widget.darkColorScheme.background
              : widget.lightColorScheme.background,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
      );

      // Update cached values
      _previousThemeMode = widget.themeMode;
      _previousPlatformBrightness = platformBrightness;
      _previousLightColorScheme = widget.lightColorScheme;
      _previousDarkColorScheme = widget.darkColorScheme;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
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

      // Connection is handled by MusicAssistantProvider._initialize()
      // Just wait for it to complete or timeout
      _logger.log('🚀 AppStartup: Waiting for provider auto-connection to $serverUrl');

      // Give the provider time to connect (it restores credentials and connects in _initialize)
      // Check connection state periodically
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (provider.isConnected) {
          _logger.log('🚀 AppStartup: Connection established');
          break;
        }
        if (provider.connectionState == MAConnectionState.error) {
          _logger.log('🚀 AppStartup: Connection failed with error');
          break;
        }
      }

      if (!provider.isConnected) {
        _logger.log('🚀 AppStartup: Connection still pending or failed');
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
