# CONTEXT HANDOFF: Ensemble - audio_service Migration

## Current State

- **Branch:** `feature/audio-service-migration`
- **Build in progress:** 19806903746 (triggered 00:05:54)
- **Previous branch** `feature/background-playback-just-audio-debug` was merged to master and deleted

## What Was Done Tonight

### 1. Background playback working with just_audio_background - merged to master
### 2. Known issues with that implementation:
   - Notification shows previous track on local IP (race condition - play_media arrives before player_updated with metadata)
   - White square stop button icon on Android 13+
   - `updateNotificationWhilePlaying()` didn't actually update the visible notification

### 3. Migrated to audio_service for full control:
   - Replaced `just_audio_background` with `audio_service: ^0.18.12` and `rxdart: ^0.27.7` in pubspec.yaml
   - Created `lib/services/audio/massiv_audio_handler.dart` - custom AudioHandler
   - Updated `lib/main.dart` to initialize AudioService with global audioHandler
   - Updated `lib/services/local_player_service.dart` to use global audioHandler
   - Notification buttons: Skip Prev, Play/Pause, Skip Next (removed stop to fix white square)

### 4. Fixed build errors:
   - `AudioServiceConfig` assertion: `androidNotificationOngoing` must be false when `androidStopForegroundOnPause` is false
   - `updateMediaItem` override: changed return type from `void` to `Future<void>`

### 5. Wired up skip buttons:
   - Added `onSkipToNext` / `onSkipToPrevious` callbacks to `MassivAudioHandler`
   - Wired callbacks in `MusicAssistantProvider` to call `nextTrackSelectedPlayer()` / `previousTrackSelectedPlayer()`

### 6. Rebranded app from Massiv → Ensemble:
   - New grey logo at `assets/images/ensemble_logo.png` (works for light/dark modes)
   - Updated logo references in `login_screen.dart` and `new_home_screen.dart`
   - Updated app name in `AndroidManifest.xml`, `pubspec.yaml`, `main.dart`
   - Updated `README.md` with new branding and repo URLs
   - Default local player name now "Ensemble"
   - Notification channel name now "Ensemble Audio"

## Key Files Changed

- `pubspec.yaml` - swapped `just_audio_background` for `audio_service` + `rxdart`, renamed to `ensemble`
- `lib/main.dart` - `AudioService.init()` with MassivAudioHandler, app title "Ensemble"
- `lib/services/audio/massiv_audio_handler.dart` - custom handler with skip callbacks
- `lib/services/local_player_service.dart` - wraps global audioHandler
- `lib/providers/music_assistant_provider.dart` - wires skip callbacks, added debug logging for players
- `lib/screens/login_screen.dart` - Ensemble logo
- `lib/screens/new_home_screen.dart` - Ensemble logo
- `android/app/src/main/AndroidManifest.xml` - app label "Ensemble"
- `assets/images/ensemble_logo.png` - NEW FILE
- `README.md` - updated branding

## What's Working (Confirmed by User)

- ✅ Local IP connection works
- ✅ Correct track metadata shows in notification
- ✅ Background playback works
- ✅ No white square icon (stop button removed)

## What Needs Testing (Current Build)

1. Skip next/previous buttons in notification
2. New Ensemble branding (logo on login/home screens)
3. App name shows as "Ensemble"

## Outstanding Issues / Next Features

### 1. Remote Player Notification (HIGH PRIORITY)
**Problem:** Notification ONLY shows when playing locally on the phone. When controlling a remote player (e.g., Dining Room), there's NO notification at all.

**Why:** `audio_service` creates notifications for local audio playback only. When a remote player is active, the phone is just a remote control with no local audio.

**Solution needed:**
- Create a "remote control" notification using a foreground service
- Show notification for ALL playback (local or remote)
- Skip/play/pause buttons control the selected player
- Could add player switcher button to notification
- This is how the official KMP client works

### 2. Player Switcher in Notification (AFTER #1)
Once remote notifications work, add a speaker icon button that opens player selection.

### 3. App Icon
- Currently using old Massiv icon (`massiv_icon.png`)
- User doesn't have new Ensemble icon yet
- Keep current icon for now, notification uses music note

## MusicAssistantProvider Context

The provider at `lib/providers/music_assistant_provider.dart` handles:
- `_pendingTrackMetadata` - metadata captured from player_updated events
- `_currentNotificationMetadata` - what's actually showing in notification
- `_handlePlayerUpdatedEvent()` - captures metadata, detects stale notification
- `_handleLocalPlayerEvent()` - handles play_media, stop, etc from server
- Race condition on local IP: play_media arrives before player_updated with correct metadata

## KMP Client Reference

Looked at https://github.com/music-assistant/kmp-client-app for patterns:
- They use MediaSession directly (Kotlin)
- No stop button in their notification
- Have player switch button
- `MediaNotificationManager.kt` and `MediaSessionHelper.kt` are good references
- They show notification for ANY active player, not just local

## Commands

```bash
# Check build status
gh run list --workflow="Build Android APK" --limit 2

# Watch build
gh run watch <run_id>

# Trigger new build
gh workflow run "Build Android APK" --ref feature/audio-service-migration
```

## Debug Logging Added

Player list debugging in `_loadAndSelectPlayers()`:
```
🎛️ getPlayers returned X players:
   - PlayerName (playerId) available=true/false powered=true/false
🎛️ After filtering: X players available
```
