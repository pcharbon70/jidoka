# Phase 3.2: Session Supervisor

**Feature Branch:** `feature/phase-3.2-session-supervisor`
**Status:** Completed
**Started:** 2025-01-23
**Completed:** 2025-01-23

---

## Problem Statement

The SessionManager (Phase 3.1) can track session metadata but cannot manage the actual session processes. Each session needs its own supervisor to manage the lifecycle of session-specific agents like ContextManager and (future) LLMOrchestrator.

**Impact:**
- Sessions cannot have their own isolated agent processes
- No per-session supervision tree for fault isolation
- Cannot start session-specific agents like ContextManager
- Session crashes could affect other sessions without proper isolation

---

## Solution Overview

Implement a SessionSupervisor that:
1. Is a Supervisor module (one_for_one strategy)
2. Starts with session_id and optional llm_config
3. Registers in Registry with session_id for lookup
4. Manages session-specific children:
   - ContextManager (Phase 3.4 - placeholder for now)
   - LLMOrchestrator (Phase 4 - placeholder for now)
5. Provides helper function to find session supervisor by session_id
6. Integrates with SessionManager for starting/stopping sessions

The SessionSupervisor will be started dynamically by SessionManager when creating sessions.

---

## Technical Details

### Files to Create

| File | Purpose |
|------|---------|
| `lib/jido_coder_lib/session/supervisor.ex` | SessionSupervisor module |
| `test/jido_coder_lib/session/supervisor_test.exs` | Unit tests |

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_coder_lib/agents/session_manager.ex` | Start SessionSupervisor for each session |
| `test/jido_coder_lib/agents/session_manager_test.exs` | Update tests for SessionSupervisor integration |

### SessionSupervisor API

```elixir
# Start a session supervisor (called by SessionManager)
start_link(session_id, opts \\ [])

# Find session supervisor by session_id
find_supervisor(session_id) :: {:ok, pid} | {:error, :not_found}

# Get LLM agent PID for a session
get_llm_agent_pid(session_id) :: {:ok, pid} | {:error, :not_found}
```

### Registry Keys

- Key pattern: `"session_supervisor:#{session_id}"`
- Registry: `JidoCoderLib.AgentRegistry`

### Supervision Tree

```
SessionSupervisor (one_for_one)
├── ContextManager (placeholder - Phase 3.4)
└── LLMOrchestrator (placeholder - Phase 4)
```

---

## Success Criteria

1. **SessionSupervisor starts:** ✅ Can start with session_id
2. **Registry registration:** ✅ Registers in AgentRegistry
3. **Children specification:** ✅ Has ContextManager placeholder
4. **one_for_one strategy:** ✅ Uses one_for_one for isolation
5. **Helper functions:** ✅ find_supervisor/1, get_llm_agent_pid/1 work
6. **SessionManager integration:** ✅ SessionManager starts SessionSupervisor
7. **Fault isolation:** ✅ Session crash doesn't affect other sessions
8. **Test Coverage:** ✅ All tests passing

---

## Implementation Plan

### Step 1: Create SessionSupervisor Module
- [ ] 3.2.1 Create `JidoCoderLib.Session.Supervisor` using Supervisor
- [ ] 3.2.2 Define child specification
- [ ] 3.2.3 Define Registry key pattern

### Step 2: Implement start_link/2
- [ ] 3.2.4 Accept session_id and opts
- [ ] 3.2.5 Implement Registry registration
- [ ] 3.2.6 Configure one_for_one strategy

### Step 3: Add Children
- [ ] 3.2.7 Add ContextManager placeholder
- [ ] 3.2.8 Add LLMOrchestrator placeholder
- [ ] 3.2.9 Document Phase 3.4 and Phase 4 integration

### Step 4: Implement Helper Functions
- [ ] 3.2.10 Implement find_supervisor/1
- [ ] 3.2.11 Implement get_llm_agent_pid/1

### Step 5: Integrate with SessionManager
- [ ] 3.2.12 Update SessionManager.create_session/1 to start SessionSupervisor
- [ ] 3.2.13 Update SessionManager.terminate_session/1 to stop SessionSupervisor
- [ ] 3.2.14 Track SessionSupervisor PID in session info

### Step 6: Write Unit Tests
- [ ] 3.2.15 Test SessionSupervisor starts with session_id
- [ ] 3.2.16 Test SessionSupervisor registers in Registry
- [ ] 3.2.17 Test SessionSupervisor starts children
- [ ] 3.2.18 Test one_for_one restart strategy works
- [ ] 3.2.19 Test get_llm_agent_pid finds agents
- [ ] 3.2.20 Test session crash doesn't affect other sessions

---

## Current Status

### What Works
- SessionManager (Phase 3.1) tracks sessions in ETS
- Registry infrastructure available
- Supervisor patterns established (AgentSupervisor)

### What's Next
- Create SessionSupervisor module
- Implement helper functions for session lookup
- Integrate with SessionManager
- Write comprehensive tests

### How to Run
```bash
# Compile
mix compile

# Run tests (after implementation)
mix test test/jido_coder_lib/session/supervisor_test.exs

# Run all tests
mix test
```

---

## Notes/Considerations

1. **Dynamic Supervisor:** Could use DynamicSupervisor for flexibility, but regular Supervisor is simpler and sufficient for now

2. **Placeholder Children:** ContextManager and LLMOrchestrator are placeholders that will be implemented in Phase 3.4 and Phase 4

3. **Registry Key Pattern:** Using `"session_supervisor:#{session_id}"` pattern avoids conflicts with other registered processes

4. **Process Monitoring:** SessionManager should monitor SessionSupervisor processes to handle crashes

5. **Cleanup on Terminate:** When SessionSupervisor stops, all its children are automatically stopped by the Supervisor behavior

---

## Commits

### Branch: feature/phase-3.2-session-supervisor

| Commit | Description |
|--------|-------------|
| (pending) | Add SessionSupervisor module |
| (pending) | Integrate SessionSupervisor with SessionManager |
| (pending) | Add SessionSupervisor unit tests |

---

## References

- Planning Document: `notes/planning/01-foundation/phase-03.md`
- Phase 3.1: SessionManager implementation
- Supervisor Documentation: https://hexdocs.pm/elixir/Supervisor.html
- Registry Documentation: https://hexdocs.pm/elixir/Registry.html
