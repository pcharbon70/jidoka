# Phase 2.6: Client Event Broadcasting

**Feature Branch:** `feature/phase-2.6-client-event-broadcasting`
**Status:** Completed
**Started:** 2025-01-23
**Completed:** 2025-01-23

---

## Problem Statement

While jidoka has broadcasting infrastructure via `Directives.client_broadcast/2`, there is no standardization of client event types or their payload schemas. Event types are currently arbitrary strings, which can lead to:
- Inconsistent event naming across agents
- No validation of event payload structure
- No single source of truth for what events clients should expect
- Difficulty discovering available event types

**Impact:**
- Client implementations need to manually track event types
- No compile-time validation of event payloads
- Event structure inconsistencies between agents
- Harder to maintain client compatibility

---

## Solution Overview

Created a `Jidoka.ClientEvents` module that defines standardized client event types with schemas and helper functions for creating properly structured events.

**Key Design Decisions:**
- Define event types as atoms with schema validation
- Provide helper functions for creating events
- Use existing `Directives.client_broadcast/2` for actual broadcasting
- Keep event payloads as maps for flexibility
- Support both global and session-specific events

---

## Technical Details

### Files Created

| File | Lines | Purpose |
|------|-------|---------|
| `lib/jidoka/client_events.ex` | 660 | Event type definitions and helpers |
| `test/jidoka/client_events_test.exs` | 370 | Tests for event creation and validation |

### Event Types Defined

1. **LLM Events:**
   - `:llm_stream_chunk` - Streaming LLM response chunk
   - `:llm_response` - Final LLM response

2. **Agent Status:**
   - `:agent_status` - Agent status changes

3. **Analysis Events:**
   - `:analysis_complete` - Code analysis results

4. **Issue Events:**
   - `:issue_found` - Issue detected during analysis

5. **Tool Events:**
   - `:tool_call` - Tool being called
   - `:tool_result` - Tool execution result

6. **Context Events:**
   - `:context_updated` - Context/project changes

### Helper Functions Provided

- `new/2` - Create event with validation
- `new!/2` - Create event or raise
- `to_directive/1` - Convert to broadcast directive
- `to_directive/2` - Convert to session-specific directive
- Convenience functions for each event type (e.g., `llm_stream_chunk/3`)

---

## Success Criteria

1. **Standardized Events:** ✅ All 8 event types defined with schemas
2. **Validation:** ✅ Event payloads validated against schemas
3. **Backward Compatible:** ✅ Works with existing broadcast infrastructure
4. **Test Coverage:** ✅ 42 tests passing
5. **Documentation:** ✅ All events documented with examples
6. **Helper Functions:** ✅ Easy event creation helpers

---

## Implementation Plan

### Step 1: Create ClientEvents Module ✅
- [x] 2.6.1 Create `lib/jidoka/client_events.ex`
- [x] 2.6.2 Define event type atoms and schemas
- [x] 2.6.3 Implement validation helper

### Step 2: Define LLM Events ✅
- [x] 2.6.4 Define `:llm_stream_chunk` event schema
- [x] 2.6.5 Define `:llm_response` event schema

### Step 3: Define Agent Status Events ✅
- [x] 2.6.6 Define `:agent_status` event schema

### Step 4: Define Analysis Events ✅
- [x] 2.6.7 Define `:analysis_complete` event schema

### Step 5: Define Issue Events ✅
- [x] 2.6.8 Define `:issue_found` event schema

### Step 6: Define Tool Events ✅
- [x] 2.6.9 Define `:tool_call` event schema
- [x] 2.6.10 Define `:tool_result` event schema

### Step 7: Define Context Events ✅
- [x] 2.6.11 Define `:context_updated` event schema

### Step 8: Create Helper Functions ✅
- [x] 2.6.12 Create `new/2` helper for event creation
- [x] 2.6.13 Create `to_directive/1` helper for broadcasting
- [x] 2.6.14 Create `to_directive/2` for session-specific events

### Step 9: Write Tests ✅
- [x] 2.6.15 Test event creation for all types
- [x] 2.6.16 Test event validation
- [x] 2.6.17 Test directive creation
- [x] 2.6.18 Test invalid event rejection

### Step 10: Integration ✅
- [x] 2.6.19 Run full test suite (42 tests passing)
- [x] 2.6.20 Verify mix compile succeeds
- [x] 2.6.21 Check formatting with mix format

---

## Current Status

### What Works
- All 8 event types defined with schemas
- Event payload validation
- Helper functions for easy event creation
- Directive conversion for broadcasting
- Convenience functions for each event type

### What's Next
- Phase 2.7: Integration tests

### How to Run
```bash
# Compile
mix compile

# Run tests
mix test test/jidoka/client_events_test.exs
```

---

## Notes/Considerations

1. **Event Type Naming:** Used atoms internally, converted to strings for broadcasts
2. **Payload Validation:** Validates at event creation time, fails fast
3. **Extensibility:** Easy to add new event types by adding schema clauses
4. **Documentation:** Included examples for each event type
5. **Backward Compatibility:** Doesn't break existing code using string event types

---

## Commits

### Branch: feature/phase-2.6-client-event-broadcasting

| Commit | Description |
|--------|-------------|
| (pending) | Add ClientEvents module with event type definitions and tests |

---

## References

- Planning Document: `notes/planning/01-foundation/phase-02.md`
- Existing Directives: `lib/jidoka/agent/directives.ex`
- Existing PubSub: `lib/jidoka/pubsub.ex`
- BroadcastEvent Signal: `lib/jidoka/signals/broadcast_event.ex`
