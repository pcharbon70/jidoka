# Phase 4.9: Memory System Integration with Agents

**Feature Branch**: `feature/phase-4.9-memory-integration`
**Date**: 2025-01-25
**Status**: In Progress

## Problem Statement

Section 4.9 of the Phase 4 planning document requires integrating the memory system with the agents that will use it. The current system has:

**Existing Memory Components:**
- Short-Term Memory (STM): ConversationBuffer, WorkingContext, PendingMemories
- Long-Term Memory (LTM): SessionAdapter with ETS persistence
- Promotion Engine: Moves items from STM to LTM
- Retrieval: Searches and ranks LTM for context enrichment

**Existing Agents:**
- ContextManager: Manages conversation history and active files
- Session.Supervisor: Manages per-session agent lifecycle
- SessionManager: Creates and tracks sessions

**What's Missing:**
1. **STM integration** - Agents don't use ConversationBuffer, WorkingContext, or PendingMemories
2. **LTM initialization** - Sessions don't initialize LTM adapters
3. **Context enrichment** - ContextManager doesn't use Retrieval for LTM context
4. **Promotion triggering** - No mechanism to trigger promotion from STM to LTM
5. **Memory signals** - No signal types for memory operations

## Solution Overview

Integrate the memory system into the agent layer by:

1. **Add STM to ContextManager** - Store conversation and working context in STM structures
2. **Initialize LTM per session** - Add SessionAdapter to session initialization
3. **Enrich context with LTM** - Use Retrieval to add relevant memories to LLM context
4. **Add promotion trigger** - Provide mechanism to promote items from STM to LTM
5. **Define memory signals** - Add signal types for memory-related events

### Integration Architecture

```
SessionManager
    └── Session.Supervisor (per session)
            ├── ContextManager (with STM integration)
            │       ├── ConversationBuffer (stores messages)
            │       ├── WorkingContext (stores active context)
            │       └── PendingMemories (queue for promotion)
            ├── SessionAdapter (LTM per session)
            └── MemorySignalRouter (broadcasts memory events)
```

## Agent Consultations Performed

**elixir-expert**: Consulted for Elixir patterns
- Use GenServer call for synchronous memory operations
- Use PubSub for memory event broadcasting
- Keep memory operations in private helper functions
- Use Registry for finding memory processes

**No external research required** - Using existing patterns from codebase

## Technical Details

### File Locations

**New Files:**
- `lib/jido_coder_lib/signals/memory.ex` - Memory signal type definitions
- `lib/jido_coder_lib/memory/integration.ex` - Memory integration helpers
- `test/jido_coder_lib/signals/memory_test.exs` - Signal tests

**Modified Files:**
- `lib/jido_coder_lib/agents/context_manager.ex` - Add STM integration
- `lib/jido_coder_lib/session/supervisor.ex` - Add LTM adapter initialization
- `lib/jido_coder_lib/agents/coordinator/actions/handle_chat_request.ex` - Add memory enrichment

### Dependencies

- `JidoCoderLib.Memory.ShortTerm` - STM structures
- `JidoCoderLib.Memory.LongTerm.SessionAdapter` - LTM adapter
- `JidoCoderLib.Memory.Retrieval` - Context enrichment
- `JidoCoderLib.Memory.PromotionEngine` - STM to LTM promotion
- `Jido.Signals` - Signal types
- `JidoCoderLib.PubSub` - Event broadcasting

## Success Criteria

- [ ] Feature branch created
- [ ] Memory signal types defined
- [ ] ContextManager integrated with STM (ConversationBuffer, WorkingContext)
- [ ] Session.Supervisor initializes LTM adapter per session
- [ ] ContextManager uses Retrieval for context enrichment
- [ ] Promotion engine accessible from agent API
- [ ] Unit tests for integration (15+ tests)
- [ ] All tests passing
- [ ] Planning document updated
- [ ] Summary created

## Implementation Plan

### Step 1: Define Memory Signal Types

Create `lib/jido_coder_lib/signals/memory.ex` with signal type definitions:

1. **Memory promoted signal** - `jido.memory.promoted`
   - Emitted when item is promoted from STM to LTM
   - Data: session_id, memory_id, type, confidence

2. **Memory stored signal** - `jido.memory.stored`
   - Emitted when memory is stored in LTM
   - Data: session_id, memory_id, type

3. **Memory retrieved signal** - `jido.memory.retrieved`
   - Emitted when memories are retrieved for context
   - Data: session_id, count, keywords

4. **Context enriched signal** - `jido.context.enriched`
   - Emitted when context is enriched with LTM
   - Data: session_id, memory_count, summary

### Step 2: Create Memory Integration Helpers

Create `lib/jido_coder_lib/memory/integration.ex` with:

1. **Initialize STM for session**
   - `initialize_stm(session_id, opts)` - Creates STM structures
   - Returns: `{:ok, stm}` with ConversationBuffer, WorkingContext, PendingMemories

2. **Initialize LTM for session**
   - `initialize_ltm(session_id)` - Creates SessionAdapter
   - Returns: `{:ok, ltm}` with adapter

3. **Promote pending memories**
   - `promote_memories(stm, ltm, opts)` - Triggers promotion
   - Returns: promotion results

### Step 3: Integrate STM into ContextManager

Update `lib/jido_coder_lib/agents/context_manager.ex`:

1. **Add STM to state**
   - Add `conversation_buffer`, `working_context` fields
   - Initialize in `init/1`

2. **Update add_message to use ConversationBuffer**
   - Store messages in buffer instead of raw list
   - Maintain backward compatibility with existing API

3. **Update build_context to include WorkingContext**
   - Merge working context items into context
   - Add LTM retrieval via Retrieval module

### Step 4: Add LTM to Session Initialization

Update `lib/jido_coder_lib/session/supervisor.ex`:

1. **Add SessionAdapter as child**
   - Start SessionAdapter for each session
   - Register in session state

2. **Add memory PID getters**
   - `get_ltm_adapter_pid(session_id)`
   - `get_stm_pid(session_id)`

### Step 5: Update ContextManager with LTM Retrieval

1. **Add enrich_context_with_ltm/3**
   - Keywords from user message or context
   - Call Retrieval.enrich_context/3
   - Merge LTM context into response

2. **Add optional LTM to build_context/3**
   - New option: `include_ltm: true`
   - Searches LTM with relevant keywords
   - Adds retrieved memories to context

### Step 6: Add Promotion Trigger

1. **Add trigger_promotion/2 to ContextManager**
   - Calls PromotionEngine.evaluate_and_promote/3
   - Broadcasts memory.promoted signals
   - Returns promotion results

2. **Add auto-promotion on message count**
   - Configurable threshold (default: every 10 messages)
   - Triggers promotion after threshold

### Step 7: Create Tests

Create comprehensive test suite:

1. **Signal type tests**
   - Verify signal types are valid
   - Test signal creation

2. **STM integration tests**
   - Test ConversationBuffer stores messages
   - Test WorkingContext integration
   - Test PendingMemories queue

3. **LTM initialization tests**
   - Test SessionAdapter starts per session
   - Test LTM isolation between sessions

4. **Context enrichment tests**
   - Test Retrieval is called
   - Test LTM context is merged
   - Test empty LTM returns gracefully

5. **Promotion tests**
   - Test promotion trigger works
   - Test signals are broadcast
   - Test items move from STM to LTM

### Step 8: Run Tests and Verify

1. Run test suite
2. Verify all tests pass
3. Check code coverage

### Step 9: Update Documentation

1. Update planning document (mark 4.9 complete)
2. Update feature planning document
3. Create summary document

## API Examples

### ContextManager with STM

```elixir
# Add message (stored in ConversationBuffer)
:ok = ContextManager.add_message("session_123", :user, "Hello")

# Get conversation (from ConversationBuffer)
{:ok, messages} = ContextManager.get_conversation_history("session_123")

# Build context with LTM enrichment
{:ok, context} = ContextManager.build_context("session_123",
  [:conversation, :files],
  include_ltm: true,
  ltm_keywords: ["file", "elixir"]
)
```

### Promotion Trigger

```elixir
# Trigger promotion manually
{:ok, _stm, results} = ContextManager.trigger_promotion("session_123",
  min_importance: 0.5,
  batch_size: 10
)

# Results include promoted, skipped, failed items
```

### Memory Signals

```elixir
# Subscribe to memory signals
:ok = PubSub.subscribe("signals")

# Receive promoted signal
receive do
  {:jido_signal, %Jido.Signal{type: "jido.memory.promoted"}, _metadata} ->
    # Handle promotion event
end
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:stm_enabled` | boolean | true | Enable STM integration |
| `:ltm_enabled` | boolean | true | Enable LTM adapter |
| `:ltm_enrichment` | boolean | false | Auto-enrich with LTM |
| `:auto_promote` | boolean | false | Auto-promote on threshold |
| `:promotion_threshold` | integer | 10 | Messages between promotions |
| `:max_ltm_results` | integer | 5 | Max LTM memories in context |

## Notes/Considerations

1. **Backward compatibility**: Keep existing ContextManager API working while adding STM

2. **Performance**: LTM retrieval adds latency; make it optional and cache results

3. **Isolation**: Ensure STM and LTM are properly isolated per session

4. **Signal ordering**: Memory signals should be emitted after the operation succeeds

5. **Error handling**: LTM failures should not crash agents; log and continue

6. **Future enhancements**:
   - Add LTM query builder for complex queries
   - Add memory statistics/analytics
   - Add memory export/import
   - Add vector embeddings for semantic search

## Current Status

### What Works
- [x] Feature branch created (`feature/phase-4.9-memory-integration`)
- [x] Memory signal types created (`lib/jido_coder_lib/signals/memory.ex`)
- [x] Integration helpers created (`lib/jido_coder_lib/memory/integration.ex`)
- [x] STM integrated into ContextManager with backward compatibility
- [x] LTM adapter added to Session.Supervisor (on-demand creation)
- [x] Tests created and passing (19 integration tests)
- [x] All memory tests passing (252 tests)

### What's Next
- Merge feature branch into foundation
- Continue with Phase 4.10 (Integration Tests) or next phase

### How to Run Tests
```bash
mix test test/jido_coder_lib/memory/integration_test.exs
mix test test/jido_coder_lib/signals/memory_test.exs
```
