# Phase 3.6: Client API for Session Management

**Feature Branch:** `feature/phase-3.6-client-api`
**Status:** Complete ✅
**Started:** 2025-01-24

---

## Problem Statement

Currently, clients must interact directly with the SessionManager GenServer to manage sessions. This creates several issues:

1. **Tight Coupling:** Clients are tightly coupled to internal agent processes
2. **No Client Abstraction:** No unified API for different client types (TUI, web, API)
3. **Direct GenServer Calls:** Clients must use GenServer.call/2 directly
4. **No Event Subscription:** No standard way for clients to subscribe to session events
5. **Missing Message Routing:** No standardized way to send messages to sessions

**Impact:**
- Difficult to add new client types
- No separation between core logic and client concerns
- Clients must know internal implementation details
- No consistent event delivery mechanism

---

## Solution Overview

Create a `Jidoka.Client` module that provides a clean, high-level API for session management. This module:

1. Wraps SessionManager operations with a clean client-facing API
2. Provides standard functions for session lifecycle (create, terminate, list, get info)
3. Integrates with PubSub for event subscription
4. Provides message routing to sessions
5. Abstracts away GenServer details from clients

**Key Design Decisions:**

- **Function Wrappers:** Client module wraps SessionManager calls with better ergonomics
- **PubSub Integration:** Uses existing PubSub system for event broadcasting
- **No Process:** Client is a module, not a GenServer (stateless API)
- **Direct Delegation:** Most operations delegate directly to SessionManager
- **Event Forwarding:** Session events are broadcast to PubSub for client consumption

---

## Technical Details

### Files to Create

| File | Purpose |
|------|---------|
| `lib/jidoka/client.ex` | Client API module |
| `test/jidoka/client_test.exs` | Client API tests |

### Files to Reference

| File | Purpose |
|------|---------|
| `lib/jidoka/agents/session_manager.ex` | Session management operations |
| `lib/jidoka/pubsub.ex` | PubSub topic helpers |
| `lib/jidoka/agents/context_manager.ex` | Session context management |

### Client API Functions

| Function | Purpose | Delegates To |
|----------|---------|--------------|
| `create_session/1` | Create a new session | `SessionManager.create_session/1` |
| `terminate_session/1` | Terminate a session | `SessionManager.terminate_session/1` |
| `list_sessions/0` | List all sessions | `SessionManager.list_sessions/0` |
| `get_session_info/1` | Get session details | `SessionManager.get_session_info/1` |
| `send_message/3` | Send message to session | `ContextManager.add_message/3` |
| `subscribe_to_session/1` | Subscribe to session events | `PubSub.subscribe/2` |
| `subscribe_to_all_sessions/0` | Subscribe to all session events | `PubSub.subscribe_client_events/1` |
| `unsubscribe_from_session/1` | Unsubscribe from session | `PubSub.unsubscribe/2` |

### PubSub Topics

| Topic | Purpose |
|-------|---------|
| `"jido.client.events"` | Global client events (session_created, session_terminated) |
| `"jido.session.{session_id}"` | Session-specific events |

### Events to Broadcast

| Event | Payload | Topic |
|-------|---------|-------|
| `{:session_created, %{session_id: ...}}` | Session creation details | Global client events |
| `{:session_terminated, %{session_id: ...}}` | Session termination details | Global client events |
| `{:session_status, %{session_id: ..., status: ...}}` | Status change | Session-specific |
| `{:message_added, %{session_id: ..., role: ..., content: ...}}` | New message | Session-specific |

---

## Implementation Plan

### Step 1: Create Client Module Structure
- [x] 3.6.1 Create `Jidoka.Client` module
- [x] 3.6.2 Add module documentation with examples
- [x] 3.6.3 Define aliases (SessionManager, PubSub, ContextManager)

### Step 2: Implement Session Lifecycle Functions
- [x] 3.6.4 Implement `create_session/1` - delegates to SessionManager
- [x] 3.6.5 Implement `terminate_session/1` - delegates to SessionManager
- [x] 3.6.6 Implement `list_sessions/0` - delegates to SessionManager
- [x] 3.6.7 Implement `get_session_info/1` - delegates to SessionManager

### Step 3: Implement Message and Event Functions
- [x] 3.6.8 Implement `send_message/3` - sends to ContextManager
- [x] 3.6.9 Implement `subscribe_to_session/1` - PubSub subscription
- [x] 3.6.10 Implement `subscribe_to_all_sessions/0` - global events
- [x] 3.6.11 Implement `unsubscribe_from_session/1` - PubSub unsubscribe

### Step 4: Update SessionManager for Event Broadcasting
- [x] 3.6.12 Add PubSub broadcast on session creation
- [x] 3.6.13 Add PubSub broadcast on session termination
- [x] 3.6.14 Add PubSub broadcast on status changes

### Step 5: Write Unit Tests
- [x] 3.6.15 Test create_session returns session ID
- [x] 3.6.16 Test terminate_session removes session
- [x] 3.6.17 Test list_sessions returns session info
- [x] 3.6.18 Test get_session_info returns session details
- [x] 3.6.19 Test send_message routes to correct session
- [x] 3.6.20 Test subscribe_to_session receives session events
- [x] 3.6.21 Test subscribe_to_all_sessions receives global events
- [x] 3.6.22 Test unsubscribe stops receiving events

---

## Success Criteria

1. **Client Module:** ✅ `Jidoka.Client` module exists
2. **Session Functions:** ✅ All session lifecycle functions work
3. **Message Routing:** ✅ Messages route to correct session
4. **Event Subscription:** ✅ Clients can subscribe to events
5. **Test Coverage:** ✅ All tests passing
6. **Documentation:** ✅ Module docs with examples

---

## Current Status

### What Works
- Phase 3.1: SessionManager with ETS tracking
- Phase 3.2: SessionSupervisor per session
- Phase 3.3: Session.State with type-safe state management
- Phase 3.4: ContextManager with session-isolated context
- Phase 3.5: Session-scoped ETS cache operations

### What's Next
- Create Client API module
- Add event broadcasting to SessionManager
- Write comprehensive tests

### How to Run
```bash
# Compile
mix compile

# Run tests (after implementation)
mix test test/jidoka/client_test.exs

# Run all tests
mix test
```

---

## Notes/Considerations

1. **No Client Process:** The Client module is stateless and doesn't run as a process. It's just a convenient API wrapper around existing processes.

2. **Event Broadcasting:** SessionManager needs to be updated to broadcast events on session lifecycle changes. This is part of Phase 3.7 but partially needed here.

3. **ContextManager Location:** To send messages to a session, we need to find the ContextManager for that session. The ContextManager module already has `find_context_manager/1` for this.

4. **Message Content:** The `send_message/3` function should accept role (:user or :assistant) and content. This maps to ContextManager's `add_message/3`.

5. **Future Extensions:** The Client API will grow to include more operations like:
   - File operations (add_file, remove_file)
   - LLM interaction (send_prompt, stream_response)
   - Configuration updates

---

## Commits

### Branch: feature/phase-3.6-client-api

| Commit | Description |
|--------|-------------|
| (pending) | Create Client module with session lifecycle functions |
| (pending) | Add message and event subscription functions |
| (pending) | Update SessionManager for event broadcasting |
| (pending) | Add Client API unit tests |
| (pending) | Update documentation |

---

## References

- Planning Document: `notes/planning/01-foundation/phase-03.md`
- SessionManager: `lib/jidoka/agents/session_manager.ex`
- PubSub: `lib/jidoka/pubsub.ex`
- ContextManager: `lib/jidoka/agents/context_manager.ex`
- Phase 3.1: SessionManager implementation
- Phase 3.4: ContextManager implementation
