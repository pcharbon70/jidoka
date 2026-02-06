# Phase 6.5: File System Integration

**Date:** 2026-02-04
**Branch:** `feature/file-system-integration`
**Status:** Completed
**Phase:** 6.5 from Phase 6 (Codebase Semantic Model)

---

## Problem Statement

The CodeIndexer (Phase 6.2) can index Elixir source code into the `:elixir_codebase` named graph, but it requires manual triggering. During development, files change frequently and the index becomes stale unless manually refreshed. This causes:
- Stale query results when code has changed
- Manual re-indexing required after edits
- Poor developer experience for interactive coding
- Missed opportunities for real-time code analysis

**Current State:**
- `index_file/2` - Indexes a single file (manual)
- `index_project/2` - Indexes entire projects (manual)
- `reindex_file/2` - Re-indexes a single file (manual)
- No automatic watching or update mechanism

**Desired State:**
- Automatic indexing when files change
- Efficient debouncing for rapid file changes
- Selective watching of project directories
- Graceful error handling for parse errors

---

## Solution Overview

Implemented a file system watcher that:
1. Uses polling-based approach to check for file modifications (no external dependencies)
2. Filters events to only process `.ex` and `.exs` files
3. Debounces rapid file changes to avoid excessive indexing
4. Triggers `reindex_file/2` for changed files
5. Handles errors gracefully without crashing the watcher

**Key Design Decisions:**

1. **Polling-Based Approach**: Instead of using OS-specific file system events, the watcher polls at regular intervals. This is cross-platform and doesn't require additional dependencies.
2. **GenServer-Based Watcher**: Separate GenServer from CodeIndexer for separation of concerns
3. **Debounce Timer**: Accumulate changes and process in batches
4. **Configurable Directories**: Allow specifying which directories to watch
5. **Error Isolation**: Parse errors don't stop the watcher

---

## Technical Details

### Polling-Based File System Events

The watcher polls at regular intervals to:
- Check file modification times (mtime)
- Detect new files
- Detect modified files
- Clean up removed files

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    CodeIndexer                              │
│  - index_project/2                                          │
│  - index_file/2                                             │
│  - reindex_file/2                                           │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │ triggers reindex
                            │
┌─────────────────────────────────────────────────────────────┐
│              FileSystemWatcher (GenServer)                  │
│  - watch_directory/1                                        │
│  - unwatch_directory/1                                      │
│  - watched_directories/0                                    │
│  - poll timer (default: 1000ms)                             │
│  - debounce timer (default: 100ms)                          │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │ polls for changes
                            │
┌─────────────────────────────────────────────────────────────┐
│                    File System                              │
│  - File modification times                                  │
│  - Directory scanning                                       │
└─────────────────────────────────────────────────────────────┘
```

### File Location

- Module: `Jidoka.Indexing.FileSystemWatcher`
- File: `lib/jidoka/indexing/file_system_watcher.ex`
- Tests: `test/jidoka/indexing/file_system_watcher_test.exs`

### Dependencies

- Depends on: CodeIndexer (for triggering reindex)
- Uses: Built-in Elixir `File` module for polling
- Error handling: Logger for errors, telemetry for metrics

---

## Implementation

### Step 1: Create FileSystemWatcher GenServer

**File:** `lib/jidoka/indexing/file_system_watcher.ex`

- [x] 1.1 Create module with GenServer
- [x] 1.2 Define state struct (watched_dirs, file_mtimes, debounce_timer, indexer_name, poll_interval, debounce_ms)
- [x] 1.3 Implement `start_link/1`
- [x] 1.4 Implement `init/1` - setup initial state and poll timer
- [x] 1.5 Implement `watch_directory/1` - scan and track directory
- [x] 1.6 Implement `unwatch_directory/0` - stop tracking directory
- [x] 1.7 Implement `watched_directories/0` - list watched directories
- [x] 1.8 Implement `handle_info/2` for :poll and :process_pending

### Step 2: Implement Event Filtering

**File:** `lib/jidoka/indexing/file_system_watcher.ex`

- [x] 2.1 Add `should_watch_file?/1` - filter by extension (.ex, .exs)
- [x] 2.2 Add `should_ignore_dir?/1` - filter by path
- [x] 2.3 Handle `.ex` and `.exs` files
- [x] 2.4 Filter out common ignore patterns (`.git`, `_build`, `deps`, etc.)

### Step 3: Implement Debouncing

**File:** `lib/jidoka/indexing/file_system_watcher.ex`

- [x] 3.1 Added debounce state (pending_files, debounce_timer)
- [x] 3.2 Implemented `handle_changed_files/2` - add to pending and schedule debounce
- [x] 3.3 Implemented `process_pending/0` - batch process changes
- [x] 3.4 Cancel existing timer when new events arrive
- [x] 3.5 Made debounce timeout configurable (default: 100ms)

### Step 4: Integrate with CodeIndexer

**File:** `lib/jidoka/indexing/file_system_watcher.ex`

- [x] 4.1 Call `CodeIndexer.reindex_file/2` for changed files
- [x] 4.2 Handle successful reindex
- [x] 4.3 Handle errors gracefully (log, don't crash)
- [x] 4.4 Added telemetry for tracking operations

### Step 5: Write Tests

**File:** `test/jidoka/indexing/file_system_watcher_test.exs`

- [x] 5.1 Test watcher starts successfully
- [x] 5.2 Test watch_directory works
- [x] 5.3 Test filtering works correctly (.ex, .exs only)
- [x] 5.4 Test debouncing prevents excessive calls
- [x] 5.5 Test errors don't crash the watcher
- [x] 5.6 Test unwatch_directory works
- [x] 5.7 Test subdirectory handling (including ignored dirs)

---

## Success Criteria

- [x] 6.5.1 Subscribe to file system change events
- [x] 6.5.2 Filter for .ex and .exs files
- [x] 6.5.3 Trigger indexing on file changes
- [x] 6.5.4 Debounce rapid file changes
- [x] 6.5.5 Handle indexing errors gracefully
- [x] All tests passing (22/22)

---

## Progress Tracking

| Step | Description | Status | Date Completed |
|------|-------------|--------|----------------|
| 1 | Create FileSystemWatcher GenServer | Completed | 2026-02-04 |
| 2 | Implement Event Filtering | Completed | 2026-02-04 |
| 3 | Implement Debouncing | Completed | 2026-02-04 |
| 4 | Integrate with CodeIndexer | Completed | 2026-02-04 |
| 5 | Write Tests | Completed | 2026-02-04 |

---

## Current Status

**What Works:**
- FileSystemWatcher polls watched directories for changes
- Detects new and modified files
- Filters by extension (.ex, .exs)
- Ignores common directories (_build, deps, .git, etc.)
- Debounces rapid changes
- Triggers CodeIndexer.reindex_file for changed files
- Graceful error handling
- Telemetry events for batch completion

**Test Results:**
- 22 tests passing
- 0 failures
- All test groups passing

**How to Test:**
```bash
mix test test/jidoka/indexing/file_system_watcher_test.exs
```

---

## Files Modified

1. **lib/jidoka/indexing/file_system_watcher.ex** - New file
2. **test/jidoka/indexing/file_system_watcher_test.exs** - New file

---

## API Documentation

### Starting the Watcher

```elixir
# Start with default settings
{:ok, watcher} = FileSystemWatcher.start_link()

# Start with custom settings
{:ok, watcher} = FileSystemWatcher.start_link(
  name: :my_watcher,
  poll_interval: 500,    # Poll every 500ms
  debounce_ms: 50        # Batch changes within 50ms
)
```

### Watching Directories

```elixir
# Watch a single directory
:ok = FileSystemWatcher.watch_directory("lib")

# Watch multiple directories
:ok = FileSystemWatcher.watch_directory("test")
:ok = FileSystemWatcher.watch_directory("config")
```

### Managing Watched Directories

```elixir
# List watched directories
{:ok, dirs} = FileSystemWatcher.watched_directories()

# Stop watching a directory
:ok = FileSystemWatcher.unwatch_directory("test")

# Get watcher state
{:ok, state} = FileSystemWatcher.get_state()
```

---

## Notes/Considerations

### Polling Strategy

- Default poll interval: 1000ms (1 second)
- Default debounce: 100ms
- File modification times are tracked and compared
- Recursive directory scanning

### Error Handling

- Parse errors are logged but don't stop the watcher
- Invalid files are skipped
- Indexer errors are caught and logged
- Watcher continues running after errors

### Ignored Directories

By default, the following directories are ignored:
- `_build` - Build artifacts
- `deps` - Dependencies
- `.git` - Git metadata
- `cover` - Test coverage
- `doc` - Documentation
- `node_modules` - Node.js dependencies
- Any directory starting with `.`

### Future Improvements

- File deletion detection
- Per-directory debounce settings
- Metrics on indexing frequency
- Configuration file support
- Recursive/unrecursive watch options
