# Phase 3.1: Session Manager Agent

**Feature Branch:** `feature/phase-3.1-session-manager`
**Status:** Completed
**Started:** 2025-01-23
**Completed:** 2025-01-23

---

## Problem Statement

The system currently lacks the ability to manage multiple concurrent work-sessions. Users need to work on different tasks simultaneously with proper isolation between sessions. A SessionManager agent is required to handle the lifecycle of all work-sessions including creation, termination, and listing.

**Impact:**
- No way to create or manage multiple concurrent sessions
- No session isolation between different user tasks
- No central authority for tracking active sessions
- No cleanup mechanism for terminated sessions

---

## Solution Overview

Implement a SessionManager agent that:
1. Acts as a Supervisor managing all session processes
2. Maintains an ETS table for tracking session metadata
3. Provides API for creating, terminating, and listing sessions
4. Generates unique session IDs using UUID
5. Integrates with the Application supervision tree

The SessionManager will be a GenServer that tracks sessions but delegates actual session management to individual SessionSupervisors (Phase 3.2).

---

## Technical Details

### Files to Create

| File | Purpose |
|------|---------|
| `lib/jido_coder_lib/agents/session_manager.ex` | SessionManager GenServer |
| `test/jido_coder_lib/agents/session_manager_test.exs` | Unit tests |

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_coder_lib/application.ex` | Add SessionManager to supervision tree |

### SessionManager API

```elixir
# Create a new session
create_session(opts \\ []) :: {:ok, session_id} | {:error, reason}

# Terminate a session
terminate_session(session_id) :: :ok | {:error, :not_found}

# List all active sessions
list_sessions() :: [%{session_id: ..., status: ..., ...}]

# Get session PID by ID
get_session_pid(session_id) :: {:ok, pid} | {:error, :not_found}

# Get session info
get_session_info(session_id) :: {:ok, map()} | {:error, :not_found}
```

### ETS Table Schema

Table: `:session_registry`
- Key: `session_id` (binary/string)
- Value: `%{session_id: ..., pid: ..., status: ..., created_at: ..., ...}`

---

## Success Criteria

1. **Session Creation:** ✅ create_session generates unique UUID
2. **Session Tracking:** ✅ Sessions are tracked in ETS table
3. **Session Termination:** ✅ terminate_session stops and cleans up
4. **Session Listing:** ✅ list_sessions returns all active sessions
5. **Session Lookup:** ✅ get_session_pid finds session by ID
6. **Error Handling:** ✅ Returns appropriate errors for unknown sessions
7. **Supervision:** ✅ SessionManager in Application supervision tree
8. **Test Coverage:** ✅ All 19 tests passing

---

## Implementation Plan

### Step 1: Create SessionManager Module
- [x] 3.1.1 Create `JidoCoderLib.Agents.SessionManager` as GenServer
- [x] 3.1.2 Define session state struct
- [x] 3.1.3 Define ETS table name

### Step 2: Implement GenServer Callbacks
- [x] 3.1.4 Implement `init/1` with ETS table creation
- [x] 3.1.5 Implement `handle_call/3` for API calls
- [x] 3.1.6 Implement `handle_info/2` for session monitoring
- [x] 3.1.7 Implement `terminate/2` for cleanup

### Step 3: Implement Public API
- [x] 3.1.8 Implement `start_link/1`
- [x] 3.1.9 Implement `create_session/1` with UUID generation
- [x] 3.1.10 Implement `terminate_session/1`
- [x] 3.1.11 Implement `list_sessions/0`
- [x] 3.1.12 Implement `get_session_pid/1`
- [x] 3.1.13 Implement `get_session_info/1`

### Step 4: Integrate with Application
- [x] 3.1.14 Add SessionManager to Application children
- [x] 3.1.15 Test SessionManager starts on application start

### Step 5: Write Unit Tests
- [x] 3.1.16 Test SessionManager starts with ETS table
- [x] 3.1.17 Test create_session generates unique IDs
- [x] 3.1.18 Test create_session stores session in ETS
- [x] 3.1.19 Test terminate_session stops session and cleans up
- [x] 3.1.20 Test list_sessions returns all active sessions
- [x] 3.1.21 Test get_session_pid finds session by ID
- [x] 3.1.22 Test get_session_pid returns :error for unknown sessions
- [x] 3.1.23 Test get_session_info returns session details
- [x] 3.1.24 Test ETS table is cleaned on terminate

---

## Current Status

### What Works
- SessionManager GenServer implemented
- ETS table for session tracking
- Public API: create_session, terminate_session, list_sessions, get_session_pid, get_session_info
- Integrated into Application supervision tree
- All 19 unit tests passing
- Concurrent session operations tested

### What's Next
- Phase 3.2: SessionSupervisor for individual session process management
- Phase 3.3: Session state structures
- Phase 3.4: ContextManager per session

### How to Run
```bash
# Compile
mix compile

# Run tests (after implementation)
mix test test/jido_coder_lib/agents/session_manager_test.exs

# Run all tests
mix test
```

---

## Notes/Considerations

1. **Session Supervisor Delegation:** SessionManager tracks sessions but actual session processes are managed by individual SessionSupervisors (Phase 3.2)

2. **UUID Generation:** Use `Ecto.UUID.generate()` or similar for unique session IDs

3. **ETS Table Type:** Use `:set` table type for session registry (one entry per session_id)

4. **Process Monitoring:** Use `Process.monitor/1` to track session lifecycle and clean up ETS on crash

5. **Concurrency:** ETS provides concurrent access - no need for additional locking

6. **Session Status:** Sessions start as `:initializing`, transition to `:active` when ready

7. **Backward Compatibility:** Design allows for gradual migration - existing single-session code can coexist

---

## Commits

### Branch: feature/phase-3.1-session-manager

| Commit | Description |
|--------|-------------|
| (pending) | Add SessionManager agent module |
| (pending) | Add SessionManager unit tests |
| (pending) | Integrate SessionManager into Application |

---

## References

- Planning Document: `notes/planning/01-foundation/phase-03.md`
- GenServer Documentation: https://hexdocs.pm/elixir/GenServer.html
- ETS Documentation: https://hexdocs.pm/elixir/ETS.html
- UUID Documentation: https://hexdocs.pm/ecto/Ecto.UUID.html
