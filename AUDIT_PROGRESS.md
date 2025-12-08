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

- [ ] Fix slider setState spam - debounce/throttle (`expandable_player.dart:879-880`)
- [ ] Replace volume polling with events (`volume_control.dart:154-163`)
- [ ] Cache `Theme.of(context)` lookups (99 occurrences across files)
- [ ] Move `SystemChrome` out of build() (`main.dart:132`)
- [ ] Replace `Image.network` with `CachedNetworkImage` (`expandable_player.dart:1195-1207`)
- [ ] Use `ListView.builder` instead of spread operators (`search_screen.dart:301-311`)

---

## Phase 3: Dead Code Cleanup (1 day)
*Consolidate and remove unused files*

- [ ] Delete or consolidate `new_home_screen.dart` and `new_library_screen.dart`
- [ ] Remove unused `PlayerStateService` (`player_state_service.dart`)
- [ ] Verify and remove unused imports (`debug_log_screen.dart:5-6`)

---

## Phase 4: State Management Refactor (3-4 days)
*Split monolithic provider (2,106 lines)*

- [ ] Extract connection logic → `ConnectionProvider`
- [ ] Extract library data → `LibraryProvider`
- [ ] Extract player state → `PlayerProvider`
- [ ] Extract cache logic → `CacheProvider`
- [ ] Remove global singleton (`navigation_provider.dart:40`)
- [ ] Add stream filtering (`.distinct()`, `.where()`)

---

## Phase 5: Widget Decomposition (3-4 days)
*Split mega-widgets into focused components*

### expandable_player.dart (1,335 lines)
- [ ] Extract `MorphingPlayerContent`
- [ ] Extract `DeviceSelectorBar`
- [ ] Extract `QueuePanel`
- [ ] Extract `PlayerControls`

### login_screen.dart (968 lines)
- [ ] Extract `LoginFormSection`
- [ ] Extract `AuthDebugConsole`

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
- [ ] Create `EmptyState` (consolidate 6+ implementations)
- [ ] Create `FilterChipRow` (consolidate 3 implementations)
- [ ] Create `DisconnectedState` (consolidate 3 implementations)

---

## Phase 7: Design System (2 days)
*Centralize hardcoded values*

- [ ] Create `lib/theme/design_tokens.dart`:
  - [ ] Spacing constants (205 instances)
  - [ ] Color constants (~10 hardcoded)
  - [ ] Dimension constants
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
| Phase 2 | Not Started | - |
| Phase 3 | Not Started | - |
| Phase 4 | Not Started | - |
| Phase 5 | Not Started | - |
| Phase 6 | Not Started | - |
| Phase 7 | Not Started | - |
| Phase 8 | Not Started | - |

---

## Notes

- Original audit performed by 7 parallel sub-agents analyzing different aspects
- Total LOC: 17,454 across 57 Dart files
- Largest files: `music_assistant_provider.dart` (2,106), `music_assistant_api.dart` (1,948), `expandable_player.dart` (1,335)
