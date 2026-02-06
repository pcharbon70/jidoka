# Phase 2.1: Signal Definitions and Routing

**Feature Branch:** `feature/phase-2.1-signals`
**Status:** Completed
**Started:** 2025-01-22
**Completed:** 2025-01-22

---

## Problem Statement

The jido_coder_lib agent system requires a CloudEvents-based signal system for inter-agent communication following the CloudEvents v1.0.2 specification. Without a unified signal system, agents cannot communicate reliably, and client events cannot be properly broadcast to connected clients.

**Impact:**
- No standard way for agents to send/receive messages
- No event broadcasting mechanism for clients
- Tight coupling between components
- No audit trail for agent interactions

---

## Solution Overview

Implement a CloudEvents-based signal system using Jido 2.0's `Jido.Signal` module. The solution will:

1. Define individual signal modules using `use Jido.Signal` with schema validation
2. Create a convenience module for signal creation and dispatch
3. Integrate with Phoenix PubSub for signal routing
4. Provide comprehensive test coverage

**Key Design Decisions:**
- Use individual signal modules for type safety and validation
- Use convenience wrapper functions for consistent API
- Optional dispatch flag for flexibility (create without broadcasting)
- Follow Jido's signal type naming convention: `domain.entity.action`

---

## Agent Consultations Performed

### 1. Research Agent (Jido CloudEvents Research)
**Agent ID:** adc53f1

**Findings:**
- Jido 2.0 provides `Jido.Signal` module with CloudEvents v1.0.2 support
- Required fields: `specversion`, `id`, `source`, `type`
- Signal type format: `<domain>.<entity>.<action>[.<qualifier>]`
- PubSub integration via `Jido.Signal.Dispatch.PubSub` adapter
- Topic naming: `jido.agent.<name>`, `jido.session.<id>`, `jido.signal.<type>`

### 2. Elixir Expert (Pattern Guidance)
**Agent ID:** a031d5f

**Recommendations:**
- Use individual signal modules with `use Jido.Signal` macro
- Create convenience module for unified API
- Return `{:ok, signal} | {:error, reason}` tuples
- Separate dispatch function with optional dispatch flag
- Schema validation via NimbleOptions in `use Jido.Signal`

---

## Technical Details

### Files to Create

| File | Purpose |
|------|---------|
| `lib/jido_coder_lib/signals.ex` | Convenience module for signal creation/dispatch |
| `lib/jido_coder_lib/signals/file_changed.ex` | File system event signal |
| `lib/jido_coder_lib/signals/analysis_complete.ex` | Analysis result signal |
| `lib/jido_coder_lib/signals/broadcast_event.ex` | Client broadcast signal |
| `lib/jido_coder_lib/signals/chat_request.ex` | User chat request signal |
| `test/jido_coder_lib/signals_test.exs` | Comprehensive signal tests |

### Dependencies

- `{:jido, "~> 2.0.0-rc.1"}` - Provides `Jido.Signal` module
- `{:phoenix_pubsub, "~> 2.1"}` - Already in deps for PubSub routing

### Signal Types

| Signal Type | Source | Purpose |
|-------------|--------|---------|
| `jido_coder.file.changed` | `/jido_coder/filesystem` | File system events |
| `jido_coder.analysis.complete` | `/jido_coder/analyzer` | Analysis results |
| `jido_coder.client.broadcast` | `/jido_coder/coordinator` | Client events |
| `jido_coder.chat.request` | `/jido_coder/client` | User messages |

---

## Success Criteria

1. **Signal Creation**: All 4 signal types can be created with valid data
2. **Validation**: Invalid data is rejected with clear error messages
3. **CloudEvents Compliance**: All signals include required CloudEvents fields
4. **PubSub Dispatch**: Signals broadcast to correct topics
5. **Serialization**: Signals can serialize/deserialize
6. **Test Coverage**: 80%+ test coverage, all tests passing
7. **Documentation**: All modules have @moduledoc with examples

---

## Implementation Plan

### Step 1: Create Individual Signal Modules ✅
- [x] 2.1.1 Create `JidoCoderLib.Signals.FileChanged`
- [x] 2.1.2 Create `JidoCoderLib.Signals.AnalysisComplete`
- [x] 2.1.3 Create `JidoCoderLib.Signals.BroadcastEvent`
- [x] 2.1.4 Create `JidoCoderLib.Signals.ChatRequest`

### Step 2: Create Convenience Module ✅
- [x] 2.1.5 Create `JidoCoderLib.Signals` with helper functions
- [x] 2.1.6 Implement `create_and_dispatch/3` private helper
- [x] 2.1.7 Implement `dispatch_signal/1` for PubSub integration

### Step 3: Add PubSub Helpers (if needed) ✅
- [x] 2.1.8 PubSub module already had `broadcast_signal/3`
- [x] 2.1.9 PubSub module already had `broadcast_client_event/2`

### Step 4: Write Tests ✅
- [x] 2.1.10 Test signal creation with valid data
- [x] 2.1.11 Test signal validation via schema
- [x] 2.1.12 Test CloudEvents required fields present
- [x] 2.1.13 Test PubSub dispatch to correct topics
- [x] 2.1.14 Test signal structure
- [x] 2.1.15 Test optional dispatch flag (create without broadcasting)

### Step 5: Integration ✅
- [x] 2.1.16 Run full test suite (37 tests passing)
- [x] 2.1.17 Verify mix compile succeeds
- [x] 2.1.18 Check formatting with mix format

---

## Current Status

### What Works ✅
- All 4 signal modules implemented with proper CloudFields compliance
- Convenience module with optional dispatch flag
- PubSub integration for signal routing
- Client-facing signals also broadcast to client events topic
- 37 tests passing (100% pass rate)

### What's Next
- Phase 2.2: Coordinator Agent implementation
- Phase 2.3: Agent Supervisor

### How to Run
```bash
# Compile
mix compile

# Run tests
mix test test/jido_coder_lib/signals_test.exs

# Format
mix format
```

---

## Notes/Considerations

1. **Signal vs Event Terminology**: We use "signals" for inter-agent communication (Jido terminology) and "events" for client-facing broadcasts (Phoenix terminology)

2. **Topic Naming**: Need to ensure PubSub topic helpers exist or add them:
   - `jido.signal.<signal_type>` for signal-specific topics
   - `jido.client.events` for global client events

3. **Future Extensions**: Additional signals will be added in later phases:
   - `jido_coder.agent.started` / `jido_coder.agent.stopped`
   - `jido_coder.tool.executed` / `jido_coder.tool.failed`
   - `jido_coder.session.created` / `jido_coder.session.terminated`

4. **Performance Considerations**: PubSub broadcasts are synchronous - consider async dispatch for high-volume signals if needed

5. **Testing Isolation**: Tests use `async: true` where possible - ensure PubSub topics don't conflict between tests

---

## Commits

### Branch: feature/phase-2.1-signals

| Commit | Description |
|--------|-------------|
| (pending) | Initial signal implementation |
| (pending) | Add convenience module |
| (pending) | Add comprehensive tests |

### Test Results
- **Total Tests**: 37
- **Passed**: 37
- **Failed**: 0
- **Coverage**: Comprehensive coverage of all signal types

---

## References

- CloudEvents v1.0.2 Spec: https://github.com/cloudevents/spec
- Jido Signal Documentation: Check hexdocs.pm for jido 2.0.0-rc.1
- Planning Document: `notes/planning/01-foundation/phase-02.md`
