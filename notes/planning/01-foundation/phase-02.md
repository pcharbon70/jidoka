# Phase 2: Agent Layer Base

This phase implements the base agent system including signal definitions, the Coordinator agent, and the foundational agent abstractions. The agents use Jido's framework for autonomous behavior with CloudEvents-based signal routing. This layer provides the orchestration backbone for all specialized agents.

---

## 2.1 Signal Definitions and Routing

- [x] **Task 2.1** Create CloudEvents-based signal system

Define the signal types and routing logic for inter-agent communication following the CloudEvents specification.

- [x] 2.1.1 Create `Jidoka.Signals` module with signal constructors
- [x] 2.1.2 Define `file_changed/2` signal for file system events
- [x] 2.1.3 Define `analysis_complete/2` signal for analysis results
- [x] 2.1.4 Define `broadcast_event/2` signal for client events
- [x] 2.1.5 Define `chat_request/2` signal for user messages
- [x] 2.1.6 Implement signal validation
- [x] 2.1.7 Add signal dispatch configuration for PubSub

**Unit Tests for Section 2.1:**
- [x] Test signal creation with valid data (37 tests passing)
- [x] Test signal validation via schema
- [x] Test signal includes required CloudEvents fields
- [x] Test signal dispatch routes to correct topic
- [x] Test signal structure

**Completed:** 2025-01-22

---

## 2.2 Coordinator Agent

- [x] **Task 2.2** Implement the Coordinator agent for orchestration

The Coordinator agent manages inter-agent communication and broadcasts events to subscribed clients.

- [x] 2.2.1 Create `Jidoka.Agents.Coordinator` using `Jido.Agent`
- [x] 2.2.2 Define agent actions (RouteTask, AggregateFindings, BroadcastEvent)
- [x] 2.2.3 Define agent schema (active_tasks, pending_broadcasts, event_aggregation)
- [x] 2.2.4 Implement `start_link/1` with Jido.Agent.Server
- [x] 2.2.5 Implement signal_routes/0 for automatic signal routing
- [x] 2.2.6 Handle `analysis.issue.found` signals and broadcast to clients
- [x] 2.2.7 Handle `chat.request` signals and route to LLM
- [x] 2.2.8 Add Coordinator to AgentSupervisor

**Unit Tests for Section 2.2:**
- [x] Test Coordinator starts and registers with Jido (2 tests)
- [x] Test signal routing to correct actions (3 tests)
- [x] Test broadcasting events to clients via PubSub (3 tests)
- [x] Test state management (active_tasks tracking) (1 test)

**Completed:** 2025-01-22

---

## 2.3 Agent Supervisor

- [x] **Task 2.3** Create the AgentSupervisor for global agents

Implement a supervisor that manages the lifecycle of global agents (Coordinator, CodeAnalyzer, IssueDetector).

- [x] 2.3.1 Create `Jidoka.AgentSupervisor` using `Supervisor`
- [x] 2.3.2 Configure `:rest_for_one` strategy for ordered dependencies
- [x] 2.3.3 Add Coordinator as first child
- [x] 2.3.4 Add placeholder children for CodeAnalyzer, IssueDetector (pending future agents)
- [x] 2.3.5 Add to Application supervision tree

**Unit Tests for Section 2.3:**
- [x] Test AgentSupervisor starts with correct strategy
- [x] Test children start in correct order
- [x] Test rest_for_one restart behavior
- [x] Test supervisor stops cleanly

**Completed:** 2025-01-22 (implemented as part of Phase 2.2)

---

## 2.4 Base Agent Behaviors

- [x] **Task 2.4** Define common agent behaviors and utilities

Create shared functionality that all agents can leverage for consistent behavior.

- [x] 2.4.1 Create `Jidoka.Agent` utilities module
- [x] 2.4.2 Implement `Jidoka.Agent.Directives` for common directive patterns
- [x] 2.4.3 Implement `Jidoka.Agent.State` for state management utilities
- [x] 2.4.4 Implement task ID generation helpers
- [x] 2.4.5 Implement session validation helpers
- [x] 2.4.6 Implement client broadcast directive helpers

**Unit Tests for Section 2.4:**
- [x] Test core utilities (13 tests passing)
- [x] Test directive helpers (13 tests passing)
- [x] Test state utilities (43 tests passing)

**Completed:** 2025-01-23

**Note:** Since Jido 2.0 provides the base agent behavior via `use Jido.Agent`, this section implements utility modules that complement Jido's framework rather than replacing it.

---

## 2.5 Agent Registry Integration

- [x] **Task 2.5** Integrate agents with the Registry system

Ensure agents can be discovered and communicated with via the Registry.

- [x] 2.5.1 Implement agent registration on startup
- [x] 2.5.2 Implement agent lookup functions
- [x] 2.5.3 Implement agent discovery by type
- [x] 2.5.4 Implement agent listing functions
- [x] 2.5.5 Handle registration conflicts gracefully

**Unit Tests for Section 2.5:**
- [x] Test agents register on startup (via Jido framework)
- [x] Test agents can be looked up by name (25 tests passing)
- [x] Test agents can be discovered by type
- [x] Test registration conflicts are handled (via Jido/AgentRegistry)

**Completed:** 2025-01-23

**Note:** Agent registration is handled by Jido 2.0's built-in registry via `Jido.whereis/2` and the existing `Jidoka.AgentRegistry`. This phase added unified discovery helpers that work with both registries.

---

## 2.6 Client Event Broadcasting

- [x] **Task 2.6** Define client event protocol

Establish the standard event types that are broadcast to connected clients.

- [x] 2.6.1 Define `{:llm_stream_chunk, %{content: ...}}` event
- [x] 2.6.2 Define `{:llm_response, %{content: ...}}` event
- [x] 2.6.3 Define `{:agent_status, %{status: ...}}` event
- [x] 2.6.4 Define `{:analysis_complete, %{results: ...}}` event
- [x] 2.6.5 Define `{:issue_found, %{severity: ..., message: ...}}` event
- [x] 2.6.6 Define `{:tool_call, ...}` and `{:tool_result, ...}` events
- [x] 2.6.7 Define `{:context_updated, %{project_path: ...}}` event
- [x] 2.6.8 Create event broadcasting helpers

**Unit Tests for Section 2.6:**
- [x] Test each event type is correctly formatted (42 tests passing)
- [x] Test events broadcast to client.events topic
- [x] Test events include required fields
- [x] Test event helpers create valid events

**Completed:** 2025-01-23

**Note:** Created `Jidoka.ClientEvents` module with standardized event type definitions, schema validation, and helper functions. Events are broadcast using existing `Directives.client_broadcast/2` infrastructure.

---

## 2.7 Phase 2 Integration Tests ✅

Comprehensive integration tests verifying the agent layer base functionality.

- [ ] 2.7.1 Test Coordinator lifecycle with PubSub
- [ ] 2.7.2 Test signal routing between agents
- [ ] 2.7.3 Test agent registration and discovery
- [ ] 2.7.4 Test event broadcasting to clients
- [ ] 2.7.5 Test agent supervisor fault tolerance
- [ ] 2.7.6 Test concurrent signal handling
- [ ] 2.7.7 Test signal validation and rejection
- [ ] 2.7.8 Test agent state persistence across restarts

**Expected Test Coverage:**
- Signal tests: 15 tests
- Coordinator tests: 20 tests
- Agent Supervisor tests: 10 tests
- Base Behavior tests: 12 tests
- Registry Integration tests: 10 tests
- Client Events tests: 14 tests

**Total: 81 integration tests**

---

## Success Criteria

1. **Signal System**: All agents can communicate via CloudEvents-compliant signals
2. **Coordinator**: Central agent routes signals and broadcasts client events
3. **Agent Discovery**: Agents can be found via Registry by name or type
4. **PubSub Integration**: All agents properly subscribe to and handle PubSub topics
5. **Fault Tolerance**: Agent failures are contained and do not cascade
6. **Event Broadcasting**: Client events are properly formatted and delivered
7. **Test Coverage**: All agent modules have 80%+ test coverage
8. **Documentation**: All agent behaviours and callbacks are documented

---

## Critical Files

**New Files:**
- `lib/jidoka/signals.ex` - Signal definitions and constructors
- `lib/jidoka/agents/coordinator.ex` - Coordinator agent
- `lib/jidoka/agents/coordinator_server.ex` - Coordinator server implementation
- `lib/jidoka/agent_supervisor.ex` - Agent supervisor
- `lib/jidoka/agent.ex` - Base agent behaviour
- `lib/jidoka/client_events.ex` - Client event definitions
- `test/jidoka/agents/coordinator_test.exs` - Coordinator tests
- `test/jidoka/signals_test.exs` - Signal tests
- `test/jidoka/integration/phase2_test.exs` - Phase 2 integration tests

**Modified Files:**
- `lib/jidoka/application.ex` - Add AgentSupervisor to children
- `lib/jidoka/pubsub.ex` - Add agent-specific topic helpers
- `config/config.exs` - Add agent configuration

**Dependencies:**
- Phase 1: Core Foundation (supervision tree, PubSub, Registry)

---

## Dependencies

**Depends on:**
- Phase 1: Core Foundation (requires supervision tree, PubSub, Registry)

**Enables:**
- Phase 3: Multi-Session Architecture (requires agent abstractions)
- Phase 4: Two-Tier Memory System (agents will use memory)
