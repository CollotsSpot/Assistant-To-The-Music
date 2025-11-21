import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/music_player_provider.dart';
import 'providers/music_assistant_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
  late MusicAssistantProvider _musicAssistantProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _musicAssistantProvider = MusicAssistantProvider();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _musicAssistantProvider.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App came back to foreground - reconnect if we have a server URL
      if (_musicAssistantProvider.serverUrl != null &&
          _musicAssistantProvider.serverUrl!.isNotEmpty &&
          !_musicAssistantProvider.isConnected) {
        _musicAssistantProvider.connectToServer(_musicAssistantProvider.serverUrl!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MusicPlayerProvider()),
        ChangeNotifierProvider.value(value: _musicAssistantProvider),
      ],
      child: MaterialApp(
        title: 'Music Assistant',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF1a1a1a),
          scaffoldBackgroundColor: const Color(0xFF1a1a1a),
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            secondary: Colors.white70,
            surface: Color(0xFF2a2a2a),
            background: Color(0xFF1a1a1a),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
          fontFamily: 'Roboto',
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
