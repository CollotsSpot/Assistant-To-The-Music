package com.musicassistant.music_assistant

import android.util.Log
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extend AudioServiceActivity instead of FlutterActivity to support audio_service package
// while also intercepting volume button events
class MainActivity: AudioServiceActivity() {
    private val TAG = "EnsembleVolume"
    private val CHANNEL = "com.musicassistant.music_assistant/volume_buttons"
    private var methodChannel: MethodChannel? = null
    private var isListening = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Configuring Flutter engine, setting up MethodChannel")

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d(TAG, "Received method call: ${call.method}")
            when (call.method) {
                "startListening" -> {
                    isListening = true
                    Log.d(TAG, "Volume listening ENABLED")
                    result.success(null)
                }
                "stopListening" -> {
                    isListening = false
                    Log.d(TAG, "Volume listening DISABLED")
                    result.success(null)
                }
                else -> {
                    Log.d(TAG, "Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    // Use dispatchKeyEvent instead of onKeyDown - Flutter's engine uses dispatchKeyEvent
    // and may consume events before they reach onKeyDown
    override fun dispatchKeyEvent(event: KeyEvent?): Boolean {
        if (event == null) {
            return super.dispatchKeyEvent(event)
        }

        val keyCode = event.keyCode
        val action = event.action

        Log.d(TAG, "dispatchKeyEvent: keyCode=$keyCode, action=$action, isListening=$isListening")

        // Only handle KEY_DOWN events to avoid double-triggering (down + up)
        if (action != KeyEvent.ACTION_DOWN) {
            // For volume keys when listening, also consume ACTION_UP to fully block system volume
            if (isListening && (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
                Log.d(TAG, "Consuming ACTION_UP for volume key")
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        if (!isListening) {
            Log.d(TAG, "Not listening, passing to super")
            return super.dispatchKeyEvent(event)
        }

        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                Log.d(TAG, "VOLUME UP pressed - sending to Flutter")
                methodChannel?.invokeMethod("volumeUp", null)
                true // Consume the event to prevent system volume change
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                Log.d(TAG, "VOLUME DOWN pressed - sending to Flutter")
                methodChannel?.invokeMethod("volumeDown", null)
                true // Consume the event to prevent system volume change
            }
            else -> {
                Log.d(TAG, "Other key, passing to super")
                super.dispatchKeyEvent(event)
            }
        }
    }
}
