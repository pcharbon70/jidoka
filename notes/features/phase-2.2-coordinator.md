# Phase 2.2: Coordinator Agent

**Feature Branch:** `feature/phase-2.2-coordinator`
**Status:** Completed
**Started:** 2025-01-22
**Completed:** 2025-01-22

---

## Problem Statement

The jidoka agent system requires a Coordinator agent to manage inter-agent communication and broadcast events to subscribed clients. Without a central coordinator, agents cannot efficiently route messages, aggregate results, or broadcast events to connected clients in a unified manner.

**Impact:**
- No central point for agent coordination
- Client events must be handled by individual agents (tight coupling)
- No aggregation of results from multiple agents
- Difficult to manage task routing and distribution

---

## Solution Overview

Implemented a Coordinator agent using Jido 2.0's `Jido.Agent` framework. The Coordinator:

1. Subscribes to and routes signals from other agents
2. Aggregates findings from multiple agents
3. Broadcasts events to connected clients via Phoenix PubSub
4. Manages active task tracking

**Key Design Decisions:**
- Use Jido.Agent with `signal_routes/0` for automatic signal routing
- Actions as separate modules under `agents/coordinator/actions/`
- Emit directives for client broadcasting (keeps agent pure)
- Simple maps for agent state (process-isolated)
- Jido's built-in Registry for agent discovery
- StateOp.SetState for agent state updates

---

## Agent Consultations Performed

### 1. Research Agent (Jido Agent Patterns)
**Agent ID:** a861f2a

**Findings:**
- Jido.Agent uses `use Jido.Agent` macro with schema definition
- Actions are separate modules using `use Jido.Action`
- Signal routing via `signal_routes/0` callback
- Actions return `{:ok, result, directives}` or `{:error, reason}`
- Jido.AgentServer manages lifecycle and signal processing
- Directives (like `Emit`) handle side effects

### 2. Elixir Expert (Implementation Patterns)
**Agent ID:** aed7ee9

**Recommendations:**
- Actions should be separate top-level modules under `actions/` directory
- Use `signal_routes/0` for routing - AgentServer handles subscription
- Coordinator should emit signals via directives, not broadcast directly
- Use Jido's built-in Registry for agent registration
- Test actions in isolation, test agent through AgentServer for integration
- Simple maps for state - only use :ets for large datasets

---

## Technical Details

### Files Created/Modified

| File | Purpose |
|------|---------|
| `lib/jidoka/jido.ex` | Jido instance module (required for agents) |
| `lib/jidoka/agents/coordinator.ex` | Coordinator agent definition |
| `lib/jidoka/agents/coordinator/actions/handle_analysis_complete.ex` | Handle analysis signals |
| `lib/jidoka/agents/coordinator/actions/handle_issue_found.ex` | Handle issue signals |
| `lib/jidoka/agents/coordinator/actions/handle_chat_request.ex` | Handle chat signals |
| `lib/jidoka/agent_supervisor.ex` | Supervisor for agents |
| `test/jidoka/agents/coordinator_test.exs` | Integration tests |
| `test/jidoka/agent_supervisor_test.exs` | Supervisor tests |

### Dependencies

- `{:jido, "~> 2.0.0-rc.1", override: true}` - Provides `Jido.Agent` and `Jido.AgentServer`
- `{:phoenix_pubsub, "~> 2.1"}` - For client event broadcasting

### Signal Routes

| Signal Type | Action | Purpose |
|-------------|--------|---------|
| `jido_coder.analysis.complete` | HandleAnalysisComplete | Analysis results |
| `jido_coder.analysis.issue.found` | HandleIssueFound | Code issues |
| `jido_coder.chat.request` | HandleChatRequest | User messages |

### Agent Schema

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `active_tasks` | `map()` | `{}` | Currently running tasks |
| `pending_broadcasts` | `list()` | `[]` | Pending client broadcasts |
| `event_aggregation` | `map()` | `{}` | Aggregated event data |

---

## Success Criteria

1. **Agent Starts**: ✅ Coordinator agent starts via AgentServer
2. **Signal Routing**: ✅ Routes analysis/issue/chat signals to correct actions
3. **Client Broadcasting**: ✅ Broadcasts events to `jido.client.events` topic
4. **State Management**: ✅ Tracks active tasks and aggregations
5. **Test Coverage**: ✅ 9 tests, all passing
6. **Documentation**: ✅ All modules have @moduledoc with examples

---

## Implementation Plan

### Step 1: Create Coordinator Agent Module
- [x] 2.2.1 Create `Jidoka.Agents.Coordinator` with schema
- [x] 2.2.2 Define `signal_routes/0` callback
- [x] 2.2.3 Add `start_link/1` function

### Step 2: Create Action Modules
- [x] 2.2.4 Create `HandleAnalysisComplete` action
- [x] 2.2.5 Create `HandleIssueFound` action
- [x] 2.2.6 Create `HandleChatRequest` action

### Step 3: Create AgentSupervisor
- [x] 2.2.7 Create `Jidoka.AgentSupervisor` module
- [x] 2.2.8 Configure `:rest_for_one` strategy
- [x] 2.2.9 Add Coordinator as child
- [x] 2.2.10 Add to Application supervision tree

### Step 4: Write Tests
- [x] 2.2.11 Test Coordinator starts via AgentServer
- [x] 2.2.12 Test signal routing to correct actions
- [x] 2.2.13 Test client event broadcasting
- [x] 2.2.14 Test state updates after signal processing

### Step 5: Integration
- [x] 2.2.15 Run full test suite
- [x] 2.2.16 Verify mix compile succeeds
- [x] 2.2.17 Check formatting with mix format

---

## Current Status

### What Works
- Coordinator agent starts and registers with Jido instance
- Signal routing automatically subscribes to configured signal types
- Actions process signals and return state operations + emit directives
- Client broadcasting works via PubSub adapter
- State tracking for active_tasks and event_aggregation
- AgentSupervisor with :rest_for_one strategy restarts agents
- All 9 tests passing (6 coordinator tests + 3 supervisor tests)

### What's Next
- Phase 2.3: Additional agents (CodeAnalyzer, IssueDetector)
- Phase 2.4: LLM integration agent
- Phase 3: Protocol layer implementation

### How to Run
```bash
# Compile
mix compile

# Run tests
mix test test/jidoka/agents/coordinator_test.exs
mix test test/jidoka/agent_supervisor_test.exs

# Start agent manually (for testing)
iex -S mix
```

---

## Important Implementation Notes

### PubSub Dispatch Configuration
The `:pubsub` dispatch adapter requires both `:target` and `:topic`:
```elixir
% Emit{
  signal: broadcast_signal,
  dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
}
```

### State Updates with StateOp
Actions must return `Jido.Agent.StateOp.SetState` structs to update agent state:
```elixir
{:ok, result_map, [
  %SetState{attrs: %{active_tasks: %{...}}},
  %Emit{signal: signal, dispatch: {...}}
]}
```

### Signal Message Format
The PubSub adapter broadcasts signals directly, not wrapped in tuples:
```elixir
# Test expects signal directly, not {from_pid, signal}
assert_receive(broadcast_signal, 500)
```

### Jido Instance Requirement
All AgentServer instances require a `:jido` option pointing to a Jido instance module:
```elixir
defmodule Jidoka.Jido do
  use Jido, otp_app: :jidoka
end
```

---

## Commits

### Branch: feature/phase-2.2-coordinator

| Commit | Description |
|--------|-------------|
| (pending) | Add Jido instance module |
| (pending) | Add Coordinator agent with signal routing |
| (pending) | Add action modules (HandleAnalysisComplete, HandleIssueFound, HandleChatRequest) |
| (pending) | Add AgentSupervisor with :rest_for_one strategy |
| (pending) | Add comprehensive tests for Coordinator and AgentSupervisor |

---

## References

- Jido Agent Documentation: hexdocs.pm for jido 2.0.0-rc.1
- Jido.Signal.Dispatch.PubSub: PubSub adapter requires `:target` and `:topic`
- Jido.Agent.StateOp: State operations for agent state updates
- Planning Document: `notes/planning/01-foundation/phase-02.md`
- Phase 2.1 Signal System: Already implemented
