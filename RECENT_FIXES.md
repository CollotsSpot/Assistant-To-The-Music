# Recent Fixes - December 2025

## Build c02bb92 - Music Assistant Native Auth Support

### New Feature: MA 2.7.0+ Authentication
Music Assistant 2.7.0 BETA 17 introduced mandatory built-in authentication. Ensemble now supports this:

- **Auto-detection**: App detects if MA requires native auth (schema 28+)
- **Login flow**: Username/password login over WebSocket after connection
- **Token storage**: Long-lived tokens saved for automatic reconnection
- **Backward compatible**: Still works with Authelia, Basic Auth, or no auth (for stable MA)

### Auth Detection Logic
1. Probes `/api` endpoint with `info` command
2. 401 response or "Authentication required" → MA auth needed
3. Falls back to Authelia/Basic detection if not MA

### Files Changed
- `lib/services/auth/ma_auth_strategy.dart` (new)
- `lib/services/auth/auth_manager.dart` - MA detection
- `lib/services/music_assistant_api.dart` - Post-connect auth, new states
- `lib/screens/login_screen.dart` - MA auth UI flow
- `lib/providers/music_assistant_provider.dart` - Auto-reconnect with MA auth
- `lib/services/settings_service.dart` - MA token storage

### Connection States
Added `authenticating` and `authenticated` states to track MA auth progress.

---

## Build 495ccce - UI Improvements

### 1. Removed Hero Animations
- Removed Hero widget animations from album and artist cards
- Fixes the "zoom" effect on bottom navigation bar during page transitions
- Cards now use smooth fade+slide transitions instead

### 2. Custom Page Transitions
- Created `FadeSlidePageRoute` for consistent navigation animations
- Uses fade with subtle 5% horizontal slide
- 300ms duration matching player animations
- Located in `lib/utils/page_transitions.dart`

### 3. Contrast Fixes for Adaptive Colors
- Added luminance-based text color selection
- Dark primary colors now get white text, light colors get black text
- Bottom nav icons automatically lighten when too dark for visibility
- Prevents unreadable text on Play buttons with dark album art colors

### 4. Glow Overscroll on Home Screen
- Added glow effect when overscrolling (matching Library behavior)
- Uses primary color for the glow
- Replaced iOS-style bounce with Android-style glow

### 5. Settings Connection Bar
- Connection status now displays as edge-to-edge bar
- Tick icon and "Connected" text on same line
- Server URL displayed below

---

## Build 9114a87 - Play Responsiveness

- Mini player appears instantly when playing (optimistic update)
- Album/artist views no longer auto-close when playing

## Build 19477f9 - Color Flash Fix

- Fixed color flash during navigation with adaptive theme
- Keeps previous adaptive color during rebuilds

## Build d1a8f67 - Animation & Nav Improvements

- Player animation reduced to 300ms (from 400ms)
- Bottom nav bar syncs color with expanded player background
- Smooth color transition during player expand/collapse

## Build 87171dc - Settings & Logo

- Logo inverts properly on light mode
- Simplified settings screen (removed IP/port fields)
- Added transparent logo matching login screen size

## Build f894675 - Auth Reconnection

- Fixed auto-reconnection with Authelia authentication
- Credentials now properly restored on cold start

## Build 10bc407 - Back Gesture Fix

- Added 40px dead zone on right edge for Android back gesture
- Prevents queue panel interference during swipe-back
