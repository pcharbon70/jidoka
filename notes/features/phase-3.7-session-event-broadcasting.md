# Phase 3.7: Session Event Broadcasting

**Feature Branch:** `feature/phase-3.7-session-event-broadcasting`
**Status:** Complete ✅
**Started:** 2025-01-24
**Completed:** 2025-01-24

---

## Problem Statement

Phase 3.6 added basic session lifecycle events (`session_created`, `session_terminated`), but the system is missing:

1. **Session Status Change Events**: No events broadcast when session status changes (e.g., `:initializing` → `:active`, `:active` → `:idle`)
2. **Incomplete Event Coverage**: Clients can't track detailed session state transitions
3. **No Session-Specific Status Events**: Status events should go to both global and session-specific topics

**Impact:**
- Clients can't track session state changes in real-time
- No way to show session status transitions in UI
- Missing visibility into session lifecycle transitions

---

## Solution Overview

Add session status change broadcasting to SessionManager. When a session transitions to a new status, broadcast an event so clients can track the session lifecycle in real-time.

**Key Design Decisions:**

- **Broadcast on State Transition**: Emit `{:session_status, %{session_id: ..., status: ...}}` whenever `State.transition/2` is called
- **Dual Topic Broadcasting**: Status changes go to both:
  - Global events: `"jido.client.events"` (for multi-session dashboards)
  - Session-specific: `"jido.client.session.{session_id}"` (for individual session tracking)
- **No Changes to State Module**: State module remains pure - broadcasting happens in SessionManager
- **Include Timestamp**: Events include `updated_at` timestamp for accurate tracking

---

## Technical Details

### Current State (from Phase 3.6)

Already implemented:
- `{:session_created, %{session_id: ..., metadata: ...}}` - broadcast on session creation
- `{:session_terminated, %{session_id: ...}}` - broadcast on session termination
- Broadcasts to `"jido.client.events"` topic

### New Events to Add

| Event | Payload | Topics |
|-------|---------|--------|
| `{:session_status, %{session_id: ..., status: ..., previous_status: ..., updated_at: ...}}` | Status change details | Global + Session-specific |

### Event Payload Structure

```elixir
{:session_status, %{
  session_id: "session_abc123",
  status: :active,          # New status
  previous_status: :initializing,  # Previous status (optional)
  updated_at: ~U[2025-01-24 10:30:00Z]
}}
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_coder_lib/agents/session_manager.ex` | Add broadcast_session_status helper, call after state transitions |
| `test/jido_coder_lib/agents/session_manager_test.exs` | Add tests for status event broadcasting |

---

## Implementation Plan

### Step 1: Add Status Broadcasting Helper to SessionManager
- [x] 3.7.1 Add `broadcast_session_status/3` private function
- [x] 3.7.2 Include session_id, new_status, previous_status, updated_at in payload
- [x] 3.7.3 Broadcast to both global and session-specific topics

### Step 2: Integrate Broadcasting at Transition Points
- [x] 3.7.4 Add broadcast after `:initializing` → `:active` transition (create_session)
- [x] 3.7.5 Add broadcast after `:active` → `:terminating` transition (terminate_session)
- [x] 3.7.6 Add broadcast after crash handling (DOWN handler)
- [x] 3.7.7 Add broadcast after `:terminating` → `:terminated` transition

### Step 3: Write Unit Tests
- [x] 3.7.8 Test session_status event broadcast on creation
- [x] 3.7.9 Test session_status event broadcast on termination
- [x] 3.7.10 Test session_status event includes previous_status
- [x] 3.7.11 Test events received on both global and session-specific topics
- [x] 3.7.12 Test crash handling triggers status event

---

## Success Criteria

1. **Status Events**: ✅ Session status changes are broadcast
2. **Dual Topics**: ✅ Events sent to both global and session-specific topics
3. **Complete Payload**: ✅ Events include session_id, status, previous_status, updated_at
4. **Test Coverage**: ✅ All new event paths have tests (4 new tests)
5. **No Breaking Changes**: ✅ Existing events continue to work

## Test Results

```
Finished in 1.2 seconds (0.00s async, 1.2s sync)
23 tests, 0 failures
```

All SessionManager tests pass, including:
- 19 original tests (Phase 3.1)
- 4 new session_status event tests (Phase 3.7)

---

## Implementation Notes

### Current State Transition Points in SessionManager

1. **create_session** (line 200-256):
   - Creates session with `:initializing` status
   - Transitions to `:active` after SessionSupervisor starts
   - **Action**: Broadcast status change after transition

2. **terminate_session** (line 258-317):
   - Transitions `:active` → `:terminating`
   - Transitions `:terminating` → `:terminated`
   - **Action**: Broadcast each transition

3. **handle_info DOWN** (line 368-406):
   - Session crashes → transitions to `:terminated`
   - **Action**: Broadcast status change with error

### Broadcast Helper Design

```elixir
defp broadcast_session_status(session_id, new_status, previous_state) do
  event = {:session_status, %{
    session_id: session_id,
    status: new_status,
    previous_status: previous_state.status,
    updated_at: DateTime.utc_now()
  }}

  # Broadcast to global events
  PubSub.broadcast_client_event(event)

  # Broadcast to session-specific events
  PubSub.broadcast_client_session(session_id, event)
end
```

---

## References

- Planning Document: `notes/planning/01-foundation/phase-03.md`
- SessionManager: `lib/jido_coder_lib/agents/session_manager.ex`
- Session.State: `lib/jido_coder_lib/session/state.ex`
- PubSub: `lib/jido_coder_lib/pubsub.ex`
- Phase 3.6 Summary: `notes/summaries/phase-3.6-client-api.md`
