import 'dart:async';
import 'package:flutter/services.dart';
import 'debug_logger.dart';

/// Service to intercept hardware volume button presses
/// and route them to the selected Music Assistant player
class HardwareVolumeService {
  static final HardwareVolumeService _instance = HardwareVolumeService._internal();
  factory HardwareVolumeService() => _instance;
  HardwareVolumeService._internal();

  static const _channel = MethodChannel('com.musicassistant.music_assistant/volume_buttons');
  final _logger = DebugLogger();

  final _volumeUpController = StreamController<void>.broadcast();
  final _volumeDownController = StreamController<void>.broadcast();

  Stream<void> get onVolumeUp => _volumeUpController.stream;
  Stream<void> get onVolumeDown => _volumeDownController.stream;

  bool _isListening = false;
  bool get isListening => _isListening;

  /// Initialize the service and start listening for volume button events
  Future<void> init() async {
    if (_isListening) return;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'volumeUp':
          _logger.log('🔊 Hardware VOLUME UP pressed');
          _volumeUpController.add(null);
          break;
        case 'volumeDown':
          _logger.log('🔊 Hardware VOLUME DOWN pressed');
          _volumeDownController.add(null);
          break;
      }
    });

    try {
      await _channel.invokeMethod('startListening');
      _isListening = true;
      _logger.info('Hardware volume button listening started', context: 'VolumeService');
    } catch (e) {
      _logger.error('Failed to start volume button listening', context: 'VolumeService', error: e);
    }
  }

  /// Stop listening for volume button events
  Future<void> dispose() async {
    if (!_isListening) return;

    try {
      await _channel.invokeMethod('stopListening');
      _isListening = false;
      _logger.info('Hardware volume button listening stopped', context: 'VolumeService');
    } catch (e) {
      _logger.error('Failed to stop volume button listening', context: 'VolumeService', error: e);
    }
  }
}
