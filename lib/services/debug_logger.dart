import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Log levels for filtering and display
enum LogLevel {
  perf,   // Performance timing (for FPS diagnosis)
  debug,  // Verbose debugging info (hidden by default)
  info,   // General information
  warning, // Potential issues
  error,  // Errors and failures
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? context;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.context,
  });

  String get formatted {
    final time = timestamp.toIso8601String().substring(11, 23);
    final levelStr = level.name.toUpperCase().padRight(5);
    final contextStr = context != null ? '[$context] ' : '';
    return '[$time] $levelStr $contextStr$message';
  }
}

class DebugLogger {
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal();

  final List<LogEntry> _entries = [];
  final _maxLogs = 1000;

  // Minimum level to display in debug console (debug builds show all)
  LogLevel _minConsoleLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Legacy getter for backward compatibility
  List<String> get logs => _entries.map((e) => e.formatted).toList();

  // Set to true to only log perf entries (for FPS diagnosis)
  // Set to false for normal operation with full logging for user bug reports
  static const bool _perfOnlyMode = false;

  void _addEntry(LogLevel level, String message, {String? context}) {
    // In perf-only mode, skip all non-perf logs
    if (_perfOnlyMode && level != LogLevel.perf) {
      return;
    }

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      context: context,
    );

    // Always store in memory
    _entries.add(entry);
    if (_entries.length > _maxLogs) {
      _entries.removeAt(0);
    }

    // Only print to console if above minimum level
    if (level.index >= _minConsoleLevel.index) {
      debugPrint(entry.formatted);
    }
  }

  /// Debug level - verbose info for development
  void debug(String message, {String? context}) {
    _addEntry(LogLevel.debug, message, context: context);
  }

  /// Info level - general operational info
  void info(String message, {String? context}) {
    _addEntry(LogLevel.info, message, context: context);
  }

  /// Warning level - potential issues
  void warning(String message, {String? context}) {
    _addEntry(LogLevel.warning, message, context: context);
  }

  /// Error level - failures and errors
  void error(String message, {String? context, Object? error, StackTrace? stackTrace}) {
    var fullMessage = message;
    if (error != null) {
      fullMessage += ': $error';
    }
    _addEntry(LogLevel.error, fullMessage, context: context);
    if (stackTrace != null && kDebugMode) {
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Legacy method for backward compatibility
  void log(String message) {
    _addEntry(LogLevel.info, message);
  }

  /// Performance logging - always prints to console for real-time monitoring
  void perf(String message, {String? context}) {
    _addEntry(LogLevel.perf, message, context: context);
  }

  /// Track build time of a widget
  final Map<String, Stopwatch> _buildTimers = {};

  void startBuild(String widgetName) {
    _buildTimers[widgetName] = Stopwatch()..start();
  }

  void endBuild(String widgetName) {
    final sw = _buildTimers.remove(widgetName);
    if (sw != null) {
      sw.stop();
      if (sw.elapsedMilliseconds > 4) { // Only log if > 4ms (slow for 60fps)
        perf('BUILD ${sw.elapsedMilliseconds}ms', context: widgetName);
      }
    }
  }

  /// Track frame times during scroll
  Stopwatch? _frameTimer;
  int _slowFrameCount = 0;
  int _totalFrameCount = 0;

  void startFrame() {
    _frameTimer = Stopwatch()..start();
  }

  void endFrame() {
    if (_frameTimer != null) {
      _frameTimer!.stop();
      _totalFrameCount++;
      final ms = _frameTimer!.elapsedMilliseconds;
      if (ms > 16) { // > 16ms means dropped frame at 60fps
        _slowFrameCount++;
        perf('SLOW FRAME ${ms}ms (${_slowFrameCount}/${_totalFrameCount} slow)', context: 'Scroll');
      }
    }
  }

  void resetFrameStats() {
    _slowFrameCount = 0;
    _totalFrameCount = 0;
  }

  void clear() {
    _entries.clear();
  }

  String getAllLogs() {
    return _entries.map((e) => e.formatted).join('\n');
  }

  /// Get logs filtered by minimum level
  String getLogsFiltered({LogLevel minLevel = LogLevel.info}) {
    return _entries
        .where((e) => e.level.index >= minLevel.index)
        .map((e) => e.formatted)
        .join('\n');
  }

  /// Generate a formatted bug report with device info
  Future<String> generateBugReport() async {
    final buffer = StringBuffer();

    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('ENSEMBLE BUG REPORT');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln();

    // App info
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      buffer.writeln('APP INFO:');
      buffer.writeln('  Version: ${packageInfo.version} (${packageInfo.buildNumber})');
      buffer.writeln('  Package: ${packageInfo.packageName}');
      buffer.writeln();
    } catch (e) {
      buffer.writeln('APP INFO: Unable to retrieve');
      buffer.writeln();
    }

    // Device info
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        buffer.writeln('DEVICE INFO:');
        buffer.writeln('  Model: ${android.manufacturer} ${android.model}');
        buffer.writeln('  Android: ${android.version.release} (SDK ${android.version.sdkInt})');
        buffer.writeln('  Device: ${android.device}');
        buffer.writeln();
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        buffer.writeln('DEVICE INFO:');
        buffer.writeln('  Model: ${ios.model}');
        buffer.writeln('  iOS: ${ios.systemVersion}');
        buffer.writeln('  Name: ${ios.name}');
        buffer.writeln();
      }
    } catch (e) {
      buffer.writeln('DEVICE INFO: Unable to retrieve');
      buffer.writeln();
    }

    // Log statistics
    final errorCount = _entries.where((e) => e.level == LogLevel.error).length;
    final warningCount = _entries.where((e) => e.level == LogLevel.warning).length;
    buffer.writeln('LOG SUMMARY:');
    buffer.writeln('  Total entries: ${_entries.length}');
    buffer.writeln('  Errors: $errorCount');
    buffer.writeln('  Warnings: $warningCount');
    buffer.writeln();

    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('LOGS (newest first):');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln();

    // Add logs in reverse order (newest first) for easier reading
    for (final entry in _entries.reversed) {
      buffer.writeln(entry.formatted);
    }

    return buffer.toString();
  }
}
