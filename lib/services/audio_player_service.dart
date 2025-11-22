import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import '../models/audio_track.dart';
import 'debug_logger.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final _logger = DebugLogger();

  AudioPlayer get audioPlayer => _audioPlayer;

  List<AudioTrack> _playlist = [];
  int _currentIndex = 0;

  List<AudioTrack> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  AudioTrack? get currentTrack =>
      _playlist.isNotEmpty && _currentIndex < _playlist.length
          ? _playlist[_currentIndex]
          : null;

  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;
  Stream<double> get volumeStream => _audioPlayer.volumeStream;

  bool get isPlaying => _audioPlayer.playing;
  Duration get position => _audioPlayer.position;
  Duration? get duration => _audioPlayer.duration;

  Future<void> setPlaylist(List<AudioTrack> tracks, {int initialIndex = 0}) async {
    _playlist = tracks;
    _currentIndex = initialIndex;

    if (_playlist.isNotEmpty) {
      await loadTrack(_currentIndex);
    }
  }

  Future<void> _testStreamUrl(String url) async {
    try {
      _logger.log('🔍 Testing stream URL accessibility...');
      final response = await http.head(
        Uri.parse(url),
        headers: {'User-Agent': 'MusicAssistantMobile/1.0'},
      ).timeout(const Duration(seconds: 5));

      _logger.log('HTTP Response: ${response.statusCode}');
      _logger.log('Content-Type: ${response.headers['content-type'] ?? 'none'}');
      _logger.log('Content-Length: ${response.headers['content-length'] ?? 'unknown'}');

      if (response.statusCode != 200) {
        _logger.log('⚠️ Stream returned non-200 status: ${response.statusCode}');
        _logger.log('Response headers: ${response.headers}');
      } else {
        _logger.log('✓ Stream URL is accessible');
      }
    } catch (e) {
      _logger.log('⚠️ Stream test failed: $e');
    }
  }

  Future<void> loadTrack(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _currentIndex = index;
      final track = _playlist[index];

      try {
        _logger.log('Loading track: ${track.title}');
        _logger.log('Stream URL: ${track.filePath}');

        // Use different audio source based on URL type
        if (track.filePath.startsWith('http://') ||
            track.filePath.startsWith('https://')) {
          // Test the stream URL first
          await _testStreamUrl(track.filePath);

          _logger.log('Creating progressive audio source for HTTP stream...');

          // Use ProgressiveAudioSource for HTTP/HTTPS streams
          // This is specifically designed for progressive streaming
          final audioSource = ProgressiveAudioSource(
            Uri.parse(track.filePath),
            headers: {
              'User-Agent': 'MusicAssistantMobile/1.0',
            },
          );

          _logger.log('Setting audio source...');
          await _audioPlayer.setAudioSource(audioSource);
          _logger.log('✓ Track loaded successfully');
        } else {
          _logger.log('Loading from local file path...');
          await _audioPlayer.setFilePath(track.filePath);
          _logger.log('✓ Track loaded from file path');
        }
      } catch (e) {
        _logger.log('✗ Error loading track: $e');
        if (e is PlayerException) {
          _logger.log('PlayerException - code: ${e.code}, message: ${e.message}');
        }
        if (e is PlayerInterruptedException) {
          _logger.log('PlayerInterruptedException - message: ${e.message}');
        }
        rethrow;
      }
    }
  }

  Future<void> play() async {
    await _audioPlayer.play();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (_currentIndex < _playlist.length - 1) {
      await loadTrack(_currentIndex + 1);
      await play();
    }
  }

  Future<void> previous() async {
    if (position.inSeconds > 3) {
      await seek(Duration.zero);
    } else if (_currentIndex > 0) {
      await loadTrack(_currentIndex - 1);
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<void> addToPlaylist(AudioTrack track) async {
    _playlist.add(track);
  }

  Future<void> removeFromPlaylist(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _playlist.removeAt(index);

      if (index == _currentIndex && _playlist.isNotEmpty) {
        await loadTrack(_currentIndex.clamp(0, _playlist.length - 1));
      } else if (index < _currentIndex) {
        _currentIndex--;
      }
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
