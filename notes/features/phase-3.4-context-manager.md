# Phase 3.4: ContextManager Per Session

**Feature Branch:** `feature/phase-3.4-context-manager`
**Status:** In Progress
**Started:** 2025-01-24

---

## Problem Statement

Currently, the SessionSupervisor uses a placeholder for ContextManager. Each session needs its own ContextManager that manages context for that specific session, ensuring:

- Session-isolated conversation history (messages are not shared between sessions)
- Session-isolated active files list (each session tracks its own files)
- Session-isolated file index (each session maintains its own file context)
- LLM context assembly for session-specific conversations

**Impact:**
- No session-specific context management
- Shared context between sessions would cause data leakage
- No way to build LLM context per session
- Placeholder in SessionSupervisor needs to be replaced

---

## Solution Overview

Implement a `Jidoka.Agents.ContextManager` GenServer that:

1. Starts with a session_id for isolation
2. Registers in Registry with `"context_#{session_id}"` key for lookup
3. Maintains session-isolated conversation history (list of messages)
4. Maintains session-isolated active files list (files currently in context)
5. Maintains session-isolated file index (metadata about tracked files)
6. Implements `build_context/3` for assembling LLM context
7. Publishes events to session-specific PubSub topics
8. Integrates with SessionSupervisor as a child

---

## Technical Details

### Files to Create

| File | Purpose |
|------|---------|
| `lib/jidoka/agents/context_manager.ex` | ContextManager GenServer |
| `test/jidoka/agents/context_manager_test.exs` | Unit tests |

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jidoka/session/supervisor.ex` | Replace Placeholder with ContextManager |
| `test/jidoka/session/supervisor_test.exs` | Update tests for ContextManager |

### ContextManager State

```elixir
defstruct [
  :session_id,           # required: session identifier
  :conversation_history,  # list: conversation messages
  :active_files,         # list: files currently in context
  :file_index,           # map: file metadata and stats
  :max_history,          # integer: max conversation history size
  :max_files,            # integer: max active files
]
```

### Registry Key Pattern

- Key: `"context_manager:#{session_id}"`
- Registry: `Jidoka.AgentRegistry`
- Allows lookup by session_id

### PubSub Topics

- Subscribe to: `"jido.session.#{session_id}"`
- Broadcast events:
  - `{:context_updated, %{session_id: ...}}`
  - `{:file_added, %{session_id: ..., file_path: ...}}`
  - `{:file_removed, %{session_id: ..., file_path: ...}}`
  - `{:conversation_added, %{session_id: ..., role: ...}}`

---

## Success Criteria

1. **ContextManager GenServer:** ✅ Starts with session_id
2. **Registry Registration:** ✅ Registers with correct key pattern
3. **Conversation History:** ✅ Isolated per session
4. **Active Files:** ✅ Isolated per session
5. **File Index:** ✅ Isolated per session
6. **build_context/3:** ✅ Returns session-specific context
7. **PubSub Events:** ✅ Session-scoped events broadcast
8. **SessionSupervisor Integration:** ✅ Replaces placeholder
9. **Test Coverage:** ✅ All tests passing

---

## Implementation Plan

### Step 1: Create ContextManager Module
- [ ] 3.4.1 Define ContextManager struct with session_id
- [ ] 3.4.2 Define conversation history storage
- [ ] 3.4.3 Define active files storage
- [ ] 3.4.4 Define file index storage
- [ ] 3.4.5 Define configuration (max_history, max_files)

### Step 2: Implement start_link/2
- [ ] 3.4.6 Accept session_id in options
- [ ] 3.4.7 Register in Registry with "context_manager:#{session_id}"
- [ ] 3.4.8 Initialize empty conversation history
- [ ] 3.4.9 Initialize empty active files list
- [ ] 3.4.10 Initialize empty file index

### Step 3: Implement Conversation Management
- [ ] 3.4.11 Implement `add_message/3` (role, content)
- [ ] 3.4.12 Implement `get_conversation_history/1`
- [ ] 3.4.13 Implement `clear_conversation/1`
- [ ] 3.4.14 Enforce max_history limit

### Step 4: Implement File Management
- [ ] 3.4.15 Implement `add_file/2` (file_path)
- [ ] 3.4.16 Implement `remove_file/2` (file_path)
- [ ] 3.4.17 Implement `get_active_files/1`
- [ ] 3.4.18 Implement `update_file_index/2` (file_path, metadata)
- [ ] 3.4.19 Enforce max_files limit

### Step 5: Implement build_context/3
- [ ] 3.4.20 Implement `build_context/3` for LLM context
- [ ] 3.4.21 Include conversation history
- [ ] 3.4.22 Include active files context
- [ ] 3.4.23 Include file index metadata

### Step 6: Integrate with SessionSupervisor
- [ ] 3.4.24 Replace Placeholder with ContextManager
- [ ] 3.4.25 Update child specification
- [ ] 3.4.26 Add `get_context_manager_pid/1` helper

### Step 7: Implement PubSub Events
- [ ] 3.4.27 Broadcast context updates to session topic
- [ ] 3.4.28 Broadcast file additions/removals
- [ ] 3.4.29 Broadcast conversation additions

### Step 8: Write Unit Tests
- [ ] 3.4.30 Test ContextManager starts with session_id
- [ ] 3.4.31 Test ContextManager registers correctly
- [ ] 3.4.32 Test conversation history is isolated per session
- [ ] 3.4.33 Test active files are isolated per session
- [ ] 3.4.34 Test build_context returns session-specific data
- [ ] 3.4.35 Test PubSub topics are scoped to session
- [ ] 3.4.36 Test max_history enforcement
- [ ] 3.4.37 Test max_files enforcement

---

## Current Status

**Status:** Complete ✅

### What Works
- ✅ ContextManager GenServer with session-isolated state
- ✅ Conversation history management with max_history limit
- ✅ Active files tracking with max_files limit
- ✅ File index with metadata merging
- ✅ build_context/3 for LLM context assembly
- ✅ Registry registration with "context_manager:#{session_id}" keys
- ✅ PubSub event broadcasting to session topics
- ✅ SessionSupervisor integration (replaced Placeholder)
- ✅ Comprehensive unit tests (48 tests passing)

### What's Next
- Phase 3.5+: Additional session-level agents as needed
- Phase 4: LLM Orchestrator implementation

### How to Run
```bash
# Compile
mix compile

# Run ContextManager tests
mix test test/jidoka/agents/context_manager_test.exs

# Run SessionSupervisor tests
mix test test/jidoka/session/supervisor_test.exs

# Run all tests
mix test
```

---

## Implementation Notes

### Key Design Decisions

1. **No Process Naming:** ContextManager does not use a name (via `name:` option). Instead, it relies solely on Registry registration for process lookup. This avoids issues with the global name registry and allows for better isolation.

2. **Registry Key Pattern:** Uses `"context_manager:" <> session_id` as the registry key in `Jidoka.AgentRegistry` (unique keys).

3. **Metadata Merging:** `update_file_index/3` merges new metadata with existing metadata using `Map.merge`, allowing incremental updates to file metadata.

4. **Duplicate Registration:** When a ContextManager with the same session_id is already registered, `start_link` returns `:ignore` (via `init/1` returning `:ignore`), preventing duplicate processes.

5. **Session-Specific PubSub:** All events are broadcast to `PubSub.session_topic(session_id)` for session-scoped event delivery.

### State Structure
```elixir
%{
  session_id: "session-123",
  conversation_history: [
    %{role: :user, content: "Hello", timestamp: ~U[2025-01-24 10:00:00Z]}
  ],
  active_files: [
    %{path: "/path/to/file.ex", added_at: ~U[2025-01-24 10:00:00Z]}
  ],
  file_index: %{
    "/path/to/file.ex" => %{language: :elixir, line_count: 42, last_accessed: ~U[2025-01-24 10:00:00Z]}
  },
  max_history: 100,
  max_files: 50
}
```

---

## Commits

### Branch: feature/phase-3.4-context-manager

| Commit | Description |
|--------|-------------|
| (pending) | Add ContextManager GenServer |
| (pending) | Integrate ContextManager with SessionSupervisor |
| (pending) | Add ContextManager unit tests |
| (pending) | Update integration tests for new child count |
| (pending) | Update planning documentation |

---

## References

- Planning Document: `notes/planning/01-foundation/phase-03.md`
- Phase 3.1: SessionManager implementation
- Phase 3.2: SessionSupervisor implementation
- Phase 3.3: Session.State implementation
- PubSub Module: `lib/jidoka/pubsub.ex`
- AgentRegistry: `Jidoka.AgentRegistry`
