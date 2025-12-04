# Multi-Client Player Discovery Issue

## Issue Summary

When multiple Ensemble app instances connect to Music Assistant simultaneously, player discovery becomes unreliable. One phone connecting/playing can cause the other to lose visibility of players.

**Date Identified**: 2025-12-04
**MA Version**: 2.7.0b18 (schema 28)
**Branch**: `fix/player-discovery-auth`

---

## Symptoms

1. **Player Discovery Failure**: After one phone plays music, the other phone shows no players available
2. **Stream Delivery Failure**: Server shows `playback_state: "playing"` but audio doesn't reach the app
3. **Config Not Found Errors**: `'No config found for player id ensemble_xxx'`
4. **Player Not Available Errors**: `Player ensemble_xxx is not available`
5. **Unhandled Stream Requests**: `Received unhandled GET request to /builtin_player/flow/ensemble_xxx.mp3`

---

## Root Cause Analysis

### The Core Problem

Music Assistant's builtin_player provider appears to have issues handling multiple simultaneous clients:

1. **Runtime vs Persisted State Mismatch**: Players register in runtime but `config/players/save` fails, so they don't persist to `settings.json`

2. **Race Condition**: App calls `config/players/save` before registration fully completes, causing "Player not available" errors

3. **Stream Endpoint Issues**: When player config doesn't exist, the stream URL (`/builtin_player/flow/{player_id}.mp3`) returns "unhandled"

4. **Ghost Player Cleanup Side Effects**: Cleaning corrupted entries can accidentally remove active player configs

### Evidence from Logs

```
# Phone A connects and registers successfully
[15:41:51.794] Player registered: ensemble_dbdaec94.../Kat's Phone

# Phone B connects, tries to save config - FAILS
[15:42:07.387] ERROR: config/players/save: 'No config found for player id ensemble_f8c905cf...'

# Phone A's config save also fails
[15:42:07.947] ERROR: config/players/save: Player ensemble_dbdaec94... is not available

# Phone B tries to play - FAILS
[15:43:07.282] ERROR: player_queues/play_media: 'No config found for player id ensemble_f8c905cf...'
```

---

## Current State (as of 2025-12-04 15:45)

### settings.json Players
```json
{
  "ensemble_4be5077a-2a21-42c3-9d06-2eaf48ae8ca7": {
    "provider": "builtin_player",
    "default_name": "Kat's Phone"
  },
  "ma_okk8ykm4er": {
    "provider": "builtin_player",
    "default_name": "This Device"
  }
}
```

### Phone States
| Phone | Owner | Stored Player ID | Config Exists | Status |
|-------|-------|------------------|---------------|--------|
| Chris' Phone | collotsspot | ensemble_f8c905cf-b43e-4378-beba-5e802f3645d2 | NO | Cannot play |
| Kat's Phone | kat | ensemble_dbdaec94-0de7-4cb8-b612-ac320687c6cd | NO | Cannot play |

### Orphaned Config
- `ensemble_4be5077a...` exists in config but no phone is using it

---

## The Registration Flow Problem

### Current App Flow (Problematic)
```
1. WebSocket connects
2. Authentication succeeds
3. fetchState() - loads providers
4. _fetchAndSetUserProfileName() - gets display name
5. _tryAdoptGhostPlayer() - looks for existing player to adopt
6. _registerLocalPlayer() - registers with MA
7. config/players/save - FAILS if registration not complete
8. _loadAndSelectPlayers() - may return empty if config missing
```

### What MA Expects
```
1. WebSocket connects
2. Authentication succeeds
3. builtin_player/register - creates runtime player
4. Player appears in players/all
5. config/players/save - should work AFTER registration completes
6. Player persisted to settings.json
```

### The Gap
- App calls `config/players/save` immediately after `builtin_player/register`
- MA may not have fully processed registration yet
- Race condition causes "Player not available" error
- Config never gets saved
- On reconnect, player ID doesn't exist in config

---

## Why Ghost Cleanup Made It Worse

When cleaning up ghost players from settings.json:
1. Removed entries that appeared to be ghosts
2. Accidentally removed `ensemble_f8c905cf...` (Chris' active player)
3. Chris' app still has this ID stored locally
4. App tries to use non-existent player → all operations fail

---

## Proposed Solutions

### Solution 1: Retry config/players/save with Delay

Add retry logic with exponential backoff after registration:

```dart
Future<void> _registerLocalPlayer() async {
  // ... registration code ...

  // Wait for MA to process registration
  await Future.delayed(Duration(milliseconds: 1000));

  // Retry save with backoff
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      await _api.savePlayerConfig(playerId);
      break;
    } catch (e) {
      if (attempt < 2) {
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }
}
```

### Solution 2: Verify Registration Before Proceeding

```dart
Future<bool> _verifyPlayerRegistration(String playerId) async {
  for (int attempt = 0; attempt < 5; attempt++) {
    final players = await _api.getPlayers();
    if (players.any((p) => p.playerId == playerId)) {
      return true;
    }
    await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
  }
  return false;
}
```

### Solution 3: Handle Missing Config Gracefully

If `config/players/save` fails:
1. Log warning but don't block
2. Player still works in runtime
3. On next connect, detect missing config and re-register
4. Implement "self-healing" player registration

### Solution 4: Remove config/players/save Entirely

The MA web UI doesn't call `config/players/save` for builtin players. Maybe the app shouldn't either:

1. Just call `builtin_player/register`
2. Let MA handle persistence automatically
3. Remove explicit save calls

**Needs testing**: Does MA auto-persist builtin player configs?

### Solution 5: Unique Player IDs Per User Account

Instead of device-based IDs, use MA user account + device:
```
ensemble_{ma_user_id}_{device_hash}
```

This ensures:
- Each MA user has their own player per device
- No collision between users on same device
- Easier to identify orphaned players

---

## Immediate Recovery Steps

### For Current Broken State

1. **Stop MA**:
   ```bash
   docker stop musicassistant
   ```

2. **Add missing player configs**:
   ```bash
   # Get current settings
   docker cp musicassistant:/data/settings.json /tmp/settings.json

   # Add Chris' player config (using jq)
   cat /tmp/settings.json | jq '.players["ensemble_f8c905cf-b43e-4378-beba-5e802f3645d2"] = {
     "values": {},
     "provider": "builtin_player",
     "player_id": "ensemble_f8c905cf-b43e-4378-beba-5e802f3645d2",
     "enabled": true,
     "name": null,
     "available": true,
     "default_name": "Chris'\'' Phone"
   }' > /tmp/settings_fixed.json

   # Copy back and restart
   docker cp /tmp/settings_fixed.json musicassistant:/data/settings.json
   docker start musicassistant
   ```

3. **Or clear app data on both phones** and let them re-register fresh

---

## Testing Checklist for Multi-Client

### Basic Multi-Client Test
- [ ] Phone A connects → players visible
- [ ] Phone B connects → players visible on both
- [ ] Phone A plays music → audio works
- [ ] Phone B still sees players
- [ ] Phone B plays music → audio works
- [ ] Phone A still sees players
- [ ] Both can play to different external players simultaneously

### Reconnection Test
- [ ] Phone A disconnects (kill app)
- [ ] Phone B still works
- [ ] Phone A reconnects → players visible, can play
- [ ] Phone B still works

### Fresh Install Test
- [ ] Phone A: fresh install → connects → gets player ID
- [ ] Phone B: fresh install → connects → gets different player ID
- [ ] Both can play simultaneously

### Ghost Adoption Test
- [ ] Phone A disconnects, player becomes "ghost"
- [ ] Phone A reinstalls → should adopt same player ID
- [ ] Phone B unaffected

---

## Files Involved

| File | Relevance |
|------|-----------|
| `lib/providers/music_assistant_provider.dart` | Connection flow, player registration |
| `lib/services/music_assistant_api.dart` | API calls including `config/players/save` |
| `lib/services/device_id_service.dart` | Player ID generation |
| `lib/services/settings_service.dart` | Local storage of player ID |
| `GHOST_PLAYERS_ANALYSIS.md` | Related ghost player issues |

---

## Related Issues

- **Ghost Players**: Players accumulate when app reinstalled (see GHOST_PLAYERS_ANALYSIS.md)
- **MA Auth Integration**: Player discovery fails until `fetchState()` called (fixed in this branch)
- **Corrupted Configs**: Missing `provider` field crashes MA (manual cleanup required)

---

## Questions for MA Developers

1. Is `config/players/save` required for builtin players, or does MA auto-persist?
2. What's the expected timing between `builtin_player/register` and player being queryable?
3. Can multiple builtin player clients share the same MA instance reliably?
4. Is there an event to know when registration is complete?

---

## Next Steps

1. **Short term**: Fix immediate broken state by adding configs manually
2. **Medium term**: Add retry/verification logic to registration flow
3. **Long term**: Consider if `config/players/save` should be removed entirely
4. **Testing**: Need reliable multi-device test setup

---

## Appendix: Relevant Log Snippets

### Successful Registration (What We Want)
```
[timestamp] Player registered: ensemble_xxx/Chris' Phone
[timestamp] config/players/save: success
[timestamp] Player appears in players/all
```

### Failed Registration (Current Problem)
```
[15:41:51.794] Player registered: ensemble_dbdaec94.../Kat's Phone
[15:42:07.947] ERROR: config/players/save: Player ensemble_dbdaec94... is not available
```

### Stream Failure
```
[15:40:04.467] WARNING: Received unhandled GET request to /builtin_player/flow/ensemble_efb81a54...mp3
```

### Config Not Found
```
[15:43:07.282] ERROR: player_queues/play_media: 'No config found for player id ensemble_f8c905cf...'
```
