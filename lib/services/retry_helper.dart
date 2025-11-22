import 'dart:async';
import 'debug_logger.dart';

class RetryHelper {
  static final _logger = DebugLogger();

  /// Retry a function with exponential backoff
  ///
  /// [operation] - The async function to retry
  /// [maxAttempts] - Maximum number of attempts (default: 3)
  /// [initialDelay] - Initial delay in seconds (default: 2)
  /// [maxDelay] - Maximum delay in seconds (default: 16)
  /// [shouldRetry] - Optional function to determine if we should retry based on error
  static Future<T> retry<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    int initialDelaySeconds = 2,
    int maxDelaySeconds = 16,
    bool Function(dynamic error)? shouldRetry,
  }) async {
    int attempt = 0;
    int delaySeconds = initialDelaySeconds;

    while (true) {
      attempt++;

      try {
        return await operation();
      } catch (error) {
        // Check if we should retry this error
        final canRetry = shouldRetry?.call(error) ?? true;

        // If this was the last attempt or we shouldn't retry, rethrow
        if (attempt >= maxAttempts || !canRetry) {
          _logger.log('❌ Operation failed after $attempt attempts: $error');
          rethrow;
        }

        // Log the retry attempt
        _logger.log(
          '⚠️ Attempt $attempt/$maxAttempts failed: $error. Retrying in ${delaySeconds}s...'
        );

        // Wait before retrying (exponential backoff)
        await Future.delayed(Duration(seconds: delaySeconds));

        // Double the delay for next attempt, but cap at maxDelay
        delaySeconds = (delaySeconds * 2).clamp(initialDelaySeconds, maxDelaySeconds);
      }
    }
  }

  /// Retry specifically for network operations
  /// Uses default settings optimized for network calls
  static Future<T> retryNetwork<T>({
    required Future<T> Function() operation,
    int maxAttempts = 4, // More attempts for network
  }) {
    return retry(
      operation: operation,
      maxAttempts: maxAttempts,
      initialDelaySeconds: 2,
      maxDelaySeconds: 16,
      shouldRetry: (error) {
        // Retry on network-related errors
        final errorString = error.toString().toLowerCase();
        return errorString.contains('socket') ||
            errorString.contains('network') ||
            errorString.contains('timeout') ||
            errorString.contains('connection');
      },
    );
  }

  /// Retry for critical operations that should almost never fail
  /// Uses more aggressive retry strategy
  static Future<T> retryCritical<T>({
    required Future<T> Function() operation,
  }) {
    return retry(
      operation: operation,
      maxAttempts: 5,
      initialDelaySeconds: 1,
      maxDelaySeconds: 10,
    );
  }
}
