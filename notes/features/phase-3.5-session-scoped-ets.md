# Phase 3.5: Session-Scoped ETS Operations

**Feature Branch:** `feature/phase-3.5-session-scoped-ets`
**Status:** Complete ✅
**Started:** 2025-01-24

---

## Problem Statement

Currently, the ContextStore uses simple file paths as ETS table keys. This means:
1. All sessions share the same file cache - one session's cached file affects all sessions
2. No session isolation - session A could see session B's cached files
3. Analysis cache is shared across all sessions
4. No way to clear cache for a specific session

**Impact:**
- Data leakage between sessions (cached files visible to other sessions)
- No per-session cache management
- Can't invalidate cache for just one session
- Session isolation is incomplete

---

## Solution Overview

Modify ContextStore to use composite keys `{session_id, path}` for session-scoped data:
1. Add session_id parameter to cache_file/get_file operations
2. Use composite keys `{session_id, path}` for file_content and file_metadata tables
3. Keep analysis_cache with composite keys `{session_id, file_path, analysis_type}`
4. Maintain backward compatibility with operations that don't specify session_id
5. Add session-scoped operations (clear_session_cache, invalidate_session_file)

**Key Design Decisions:**
- **Optional session_id:** Existing operations work without session_id for global cache
- **Composite tuple keys:** Use `{session_id, path}` tuples as ETS keys
- **Backward compatibility:** Preserve existing API for non-session-scoped use
- **Session isolation:** Each session has completely isolated file cache

---

## Technical Details

### Files to Modify

| File | Purpose |
|------|---------|
| `lib/jidoka/context_store.ex` | Add session_id parameter and composite keys |
| `test/jidoka/context_store_test.exs` | Add session isolation tests |

### ETS Table Changes

#### Current Keys
| Table | Current Key | New Key (with session) |
|-------|-------------|----------------------|
| `:file_content` | `file_path` | `{session_id, file_path}` |
| `:file_metadata` | `file_path` | `{session_id, file_path}` |
| `:analysis_cache` | `{file_path, analysis_type}` | `{session_id, file_path, analysis_type}` |

#### Backward Compatibility
- Operations without session_id use `:global` as the session_id
- `get_file(path)` → `get_file(:global, path)`
- `cache_file(path, content)` → `cache_file(:global, path, content)`

### New Functions

| Function | Purpose |
|----------|---------|
| `cache_file(session_id, path, content, metadata)` | Cache with session |
| `get_file(session_id, path)` | Get file from session cache |
| `get_metadata(session_id, path)` | Get metadata from session cache |
| `cache_analysis(session_id, path, type, result)` | Cache analysis for session |
| `get_analysis(session_id, path, type)` | Get analysis for session |
| `invalidate_file(session_id, path)` | Invalidate file for session |
| `clear_session_cache(session_id)` | Clear all cache for a session |
| `invalidate_session_analysis(session_id, path)` | Invalidate analyses for session/file |

---

## Implementation Plan

### Step 1: Update cache_file and get_file
- [x] 3.5.1 Add `cache_file(session_id, path, content, metadata)` with session_id
- [x] 3.5.2 Add `get_file(session_id, path)` with session_id
- [x] 3.5.3 Add `get_metadata(session_id, path)` with session_id
- [x] 3.5.4 Use composite keys `{session_id, path}` in ETS operations
- [x] 3.5.5 Maintain backward compatibility (default to :global session)

### Step 2: Update analysis cache operations
- [x] 3.5.6 Update `cache_analysis(session_id, path, type, result)`
- [x] 3.5.7 Update `get_analysis(session_id, path, type)`
- [x] 3.5.8 Update `get_analysis_with_timestamp(session_id, path, type)`
- [x] 3.5.9 Use composite keys `{session_id, path, type}` for analysis cache

### Step 3: Add session-scoped operations
- [x] 3.5.10 Add `clear_session_cache(session_id)` - clears all data for a session
- [x] 3.5.11 Add `invalidate_session_file(session_id, path)` - invalidates file for session
- [x] 3.5.12 Update `invalidate_file/1` to support session_id parameter

### Step 4: Update invalidate operations
- [x] 3.5.13 Update `invalidate_file(session_id, path)` to use composite keys
- [x] 3.5.14 Update analysis cache invalidation for session

### Step 5: Write unit tests
- [x] 3.5.15 Test cache_file stores with composite key
- [x] 3.5.16 Test get_file retrieves with composite key
- [x] 3.5.17 Test data is isolated between sessions
- [x] 3.5.18 Test invalidate_file only affects session data
- [x] 3.5.19 Test concurrent access from different sessions
- [x] 3.5.20 Test backward compatibility (no session_id)
- [x] 3.5.21 Test clear_session_cache removes all session data
- [x] 3.5.22 Test analysis cache session isolation

---

## Success Criteria

1. **Session Isolation:** ✅ Each session has isolated file cache
2. **Composite Keys:** ✅ Using `{session_id, path}` tuples as keys
3. **Backward Compatibility:** ✅ Existing API works without session_id
4. **Session Operations:** ✅ New session-scoped operations available
5. **Test Coverage:** ✅ All tests passing

---

## Current Status

### What Works
- Phase 3.1: SessionManager with ETS tracking
- Phase 3.2: SessionSupervisor per session
- Phase 3.3: Session.State with type-safe state management
- Phase 3.4: ContextManager with session-isolated context

### What's Next
- Modify ContextStore for session-scoped ETS operations
- Add session_id parameter to all cache operations
- Use composite keys for ETS tables
- Add session-scoped cache management

### How to Run
```bash
# Compile
mix compile

# Run tests (after implementation)
mix test test/jidoka/context_store_test.exs

# Run all tests
mix test
```

---

## Notes/Considerations

1. **Backward Compatibility:** Use `:global` as default session_id for operations without explicit session_id. This preserves existing behavior while enabling session isolation.

2. **Composite Key Performance:** Tuple keys `{session_id, path}` are still O(1) lookup in ETS sets. Performance impact should be negligible.

3. **Memory Considerations:** Session-scoped caching means more entries in ETS tables (same file cached for multiple sessions). Consider implementing cache size limits per session.

4. **Analysis Cache:** The analysis_cache already uses composite keys `{file_path, analysis_type}`. We'll extend to `{session_id, file_path, analysis_type}`.

5. **Invalidation:** When a session terminates, all its cache entries should be cleaned up. This prevents memory leaks from terminated sessions.

6. **Migration Strategy:** Since we're maintaining backward compatibility, existing code will continue to work. New code can opt-in to session scoping by passing session_id.

---

## Commits

### Branch: feature/phase-3.5-session-scoped-ets

| Commit | Description |
|--------|-------------|
| (pending) | Add session_id parameter to cache_file and get_file |
| (pending) | Update analysis cache for session scoping |
| (pending) | Add session-scoped cache operations |
| (pending) | Add unit tests for session isolation |
| (pending) | Update documentation |

---

## References

- Planning Document: `notes/planning/01-foundation/phase-03.md`
- ContextStore: `lib/jidoka/context_store.ex`
- ContextStore Tests: `test/jidoka/context_store_test.exs`
- Phase 3.4: ContextManager implementation (session context)
- Phase 3.1: SessionManager (session lifecycle)
