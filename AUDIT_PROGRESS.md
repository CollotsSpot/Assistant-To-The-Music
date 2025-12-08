# Ensemble App - Audit Progress Tracker

**Audit Date:** 2025-12-08
**Branch:** `refactor/audit-cleanup`
**Overall Health Score:** 6.5/10 (before fixes)

---

## Phase 1: Quick Wins (1-2 days)
*Low effort, immediate impact*

- [x] Remove unused `cupertino_icons` dependency from `pubspec.yaml`
- [x] Remove 12 debug `print()` statements from `main.dart` (replaced with `_logger.log()`)
- [x] Fix empty `setState(() {})` in progress timer (`expandable_player.dart`) - converted to `ValueNotifier`
- [x] Fix empty `setState(() {})` on text input (`search_screen.dart`) - removed unnecessary setState
- [x] Complete or remove TODO comments:
  - [x] `queue_screen.dart` - enhanced comment with API requirements
  - [x] `library_screen.dart` - **IMPLEMENTED** play track functionality
  - [x] `expandable_player.dart` - enhanced comment with API limitations

---

## Phase 2: Performance Fixes (2-3 days)
*Medium effort, significant performance gains*

- [x] Fix slider setState spam - use ValueNotifier pattern (`expandable_player.dart`)
- [x] Replace volume polling with events (`volume_control.dart`) - removed polling loop
- [x] Cache `Theme.of(context)` lookups - removed unused lookup in `search_screen.dart`
- [x] Move `SystemChrome` out of build() (`main.dart`) - created SystemUIWrapper widget
- [x] Replace `Image.network` with `CachedNetworkImage` (`expandable_player.dart`)
- [x] Use `ListView.builder` instead of spread operators (`search_screen.dart`)

---

## Phase 3: Dead Code Cleanup (1 day)
*Consolidate and remove unused files*

- [x] Delete unused `library_screen.dart` (old version, `new_library_screen.dart` is active)
- [x] Remove unused `PlayerStateService` (`player_state_service.dart`)
- [x] Remove unused `Player` import from `debug_log_screen.dart`

Note: `new_home_screen.dart` and `new_library_screen.dart` are NOT dead code - they are
the active screens used in `home_screen.dart`. The naming suggests they replaced older
versions during a refactor.

---

## Phase 4: State Management Refactor (3-4 days)
*Split monolithic provider (2,106 lines)*

- [x] Extract cache logic → `CacheService` (lib/services/cache_service.dart)
- [x] Update `MusicAssistantProvider` to delegate caching to `CacheService`
- [x] Delete unused `library_service.dart`
- [ ] Extract connection logic → `ConnectionProvider` (skeleton created)
- [ ] Extract library data → `LibraryProvider` (skeleton created)
- [ ] Extract player state → `PlayerProvider` (skeleton created)
- [ ] Remove global singleton (`navigation_provider.dart:40`)
- [ ] Add stream filtering (`.distinct()`, `.where()`)

**Note:** Phase 4 partial completion - extracted CacheService and reduced
`music_assistant_provider.dart` from 2,106 to ~1,650 lines. Full provider
split deferred as lower priority.

---

## Phase 5: Widget Decomposition (3-4 days)
*Split mega-widgets into focused components*

### expandable_player.dart (1,365 → 1,150 lines) - DONE
- [x] Extract `DeviceSelectorBar` → `lib/widgets/player/device_selector_bar.dart`
- [x] Extract `QueuePanel` → `lib/widgets/player/queue_panel.dart`
- [x] Create `PlayerControls` → `lib/widgets/player/player_controls.dart` (available for future use)

### login_screen.dart (968 → 843 lines) - DONE
- [x] Extract `DebugConsole` → `lib/widgets/debug/debug_console.dart`
- [x] Extract `DebugToggleButton` → included in debug_console.dart

### album_details_screen.dart (818 lines)
- [ ] Extract `TrackListSection`
- [ ] Extract `PlayOnBottomSheet` (shared)

### search_screen.dart (516 lines)
- [ ] Extract `MediaItemTile`
- [ ] Extract `SearchFilters`

---

## Phase 6: Code Deduplication (2-3 days)
*Extract reusable widgets*

- [ ] Create `MediaItemTile` (consolidate 3 list tile builders)
- [ ] Create `PlayOnBottomSheet` (consolidate 4 implementations)
- [x] Create `EmptyState` (consolidate 6+ implementations) → `lib/widgets/common/empty_state.dart`
- [ ] Create `FilterChipRow` (consolidate 3 implementations)
- [x] Create `DisconnectedState` (consolidate 3 implementations) → `lib/widgets/common/disconnected_state.dart`

**Note:** Phase 6 partial completion - extracted EmptyState (8 usages, ~227 lines removed)
and DisconnectedState (3 usages, ~140 lines removed). Total ~367 lines of duplicate code removed.

---

## Phase 7: Design System (2 days)
*Centralize hardcoded values*

- [x] Create `lib/theme/design_tokens.dart`:
  - [x] Spacing constants (Spacing class with xxs-xxxl scale)
  - [x] Border radius constants (Radii class)
  - [x] Icon size constants (IconSizes class)
  - [x] Dimension constants (Dimensions class)
  - [x] Animation duration constants (Durations class)
- [x] Apply tokens to extracted widgets:
  - [x] `empty_state.dart` - Spacing tokens
  - [x] `disconnected_state.dart` - Spacing, IconSizes, Radii tokens
  - [x] `queue_panel.dart` - Spacing, Radii, IconSizes tokens
  - [x] `player_controls.dart` - Spacing tokens
  - [x] `device_selector_bar.dart` - Spacing, IconSizes tokens
  - [x] `debug_console.dart` - Spacing, Radii, IconSizes tokens
- [ ] Continue replacing remaining hardcoded values (~223 remaining)
- [ ] Create `lib/constants/strings.dart` (40+ strings)

---

## Phase 8: Polish (Backlog)
*Nice-to-have improvements*

- [ ] Add Semantics labels for accessibility
- [ ] Implement localization (i18n)
- [ ] Add test coverage
- [ ] Implement WebSocket heartbeat
- [ ] Add responsive grid layouts for tablets
- [ ] Add completer guards to prevent double-completion

---

## Completed Summary

| Phase | Status | Completed Date |
|-------|--------|----------------|
| Phase 1 | **COMPLETED** | 2025-12-08 |
| Phase 2 | **COMPLETED** | 2025-12-08 |
| Phase 3 | **COMPLETED** | 2025-12-08 |
| Phase 4 | **PARTIAL** | 2025-12-08 |
| Phase 5 | **PARTIAL** | 2025-12-08 |
| Phase 6 | **PARTIAL** | 2025-12-08 |
| Phase 7 | **PARTIAL** | 2025-12-08 |
| Phase 8 | Not Started | - |

---

## Notes

- Original audit performed by 7 parallel sub-agents analyzing different aspects
- Total LOC: 17,454 across 57 Dart files
- Largest files: `music_assistant_provider.dart` (2,106), `music_assistant_api.dart` (1,948), `expandable_player.dart` (1,335)
