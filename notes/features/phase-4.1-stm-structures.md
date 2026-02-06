# Phase 4.1: Short-Term Memory Structures

**Feature Branch:** `feature/phase-4.1-stm-structures`
**Status:** In Progress
**Started:** 2025-01-24
**Planning:** `notes/planning/01-foundation/phase-04.md`

---

## Problem Statement

Phase 3 implemented multi-session architecture with ContextManager, but the memory system lacks structured short-term memory (STM) capabilities. The current ContextManager stores conversation history but lacks:

1. **ConversationBuffer** - Token-aware sliding window for message history
2. **WorkingContext** - Semantic scratchpad for session understanding
3. **PendingMemories** - Queue for items to promote to long-term memory
4. **Access Logging** - Tracking access patterns for importance scoring
5. **Token Budget** - Configuration for token limits

**Impact:**
- No token-aware conversation trimming
- No semantic working context storage
- No bridge to long-term memory promotion
- Limited session context management

---

## Solution Overview

Create the core STM data structures as a foundation for the two-tier memory system:

1. **ShortTerm Module** - Main STM module with initialization
2. **ConversationBuffer** - Sliding window buffer with token-aware eviction
3. **WorkingContext** - Key-value semantic scratchpad
4. **PendingMemories** - FIFO queue for LTM promotion candidates
5. **AccessLog** - Timestamp tracking for importance scoring
6. **TokenBudget** - Configuration struct for token limits

**Key Design Decisions:**

- **Struct-based** - Use Elixir structs for type safety and documentation
- **Functional updates** - Return updated structs rather than mutating state
- **Session-scoped** - Each STM instance tied to a session_id
- **Token-aware** - Track estimated token counts for conversation trimming
- **GenState Server** - Use GenServer for STM state management per session

---

## Technical Details

### Files to Create

| File | Purpose | Lines (est.) |
|------|---------|--------------|
| `lib/jido_coder_lib/memory/short_term.ex` | Main STM module | 200 |
| `lib/jido_coder_lib/memory/short_term/conversation_buffer.ex` | Sliding window buffer | 250 |
| `lib/jido_coder_lib/memory/short_term/working_context.ex` | Semantic scratchpad | 180 |
| `lib/jido_coder_lib/memory/short_term/pending_memories.ex` | Promotion queue | 150 |
| `lib/jido_coder_lib/memory/token_budget.ex` | Token config struct | 100 |

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_coder_lib/application.ex` | Add STM supervisor to supervision tree |
| `test/test_helper.exs` | Add STM test setup if needed |

### Module Hierarchy

```
JidoCoderLib.Memory.ShortTerm
├── ConversationBuffer (sliding window)
├── WorkingContext (semantic scratchpad)
└── PendingMemories (promotion queue)

JidoCoderLib.Memory.TokenBudget (configuration)
```

---

## Success Criteria

1. **Structures Created:**
   - [ ] ConversationBuffer struct with sliding window
   - [ ] WorkingContext struct for semantic storage
   - [ ] PendingMemories struct for FIFO queue
   - [ ] TokenBudget config struct

2. **Functions Working:**
   - [ ] ShortTerm.new/1 initializes STM
   - [ ] ConversationBuffer.add/2 adds messages with eviction
   - [ ] WorkingContext put/get/delete operations
   - [ ] PendingMemories enqueue/dequeue operations

3. **Test Coverage:**
   - [ ] All structs have unit tests
   - [ ] Edge cases tested (empty, overflow, etc.)
   - [ ] Token counting tested
   - [ ] Access logging tested

4. **Integration:**
   - [ ] STM can be started per session
   - [ ] Works with existing session architecture

---

## Implementation Plan

### 4.1.1-4.1.2: Create ShortTerm Module and ConversationBuffer

**Tasks:**
- [ ] 4.1.1 Create `JidoCoderLib.Memory.ShortTerm` module
- [ ] 4.1.2 Create `ConversationBuffer` struct with fields:
  - `messages` - List of conversation messages
  - `max_messages` - Maximum message count
  - `token_budget` - TokenBudget struct
  - `current_tokens` - Estimated token count
- [ ] 4.1.2 Implement `new/2` for buffer initialization
- [ ] 4.1.2 Implement `add/2` for adding messages
- [ ] 4.1.2 Implement token-aware eviction logic
- [ ] 4.1.2 Return evicted messages from add/2
- [ ] Add ConversationBuffer tests

### 4.1.3: Create WorkingContext

**Tasks:**
- [ ] 4.1.3 Create `WorkingContext` struct with fields:
  - `data` - Map of key-value pairs
  - `max_items` - Maximum items limit
  - `access_log` - List of {key, timestamp} tuples
- [ ] 4.1.3 Implement `new/1` for initialization
- [ ] 4.1.3 Implement `put/3` for storing values
- [ ] 4.1.3 Implement `get/2` for retrieving values
- [ ] 4.1.3 Implement `delete/2` for removing values
- [ ] 4.1.3 Implement `keys/1` for listing keys
- [ ] Add WorkingContext tests

### 4.1.4: Create PendingMemories

**Tasks:**
- [ ] 4.1.4 Create `PendingMemories` struct with fields:
  - `queue` - :queue.queue() of memory items
  - `max_size` - Maximum queue size
- [ ] 4.1.4 Implement `new/1` for initialization
- [ ] 4.1.4 Implement `enqueue/2` for adding items
- [ ] 4.1.4 Implement `dequeue/1` for removing items
- [ ] 4.1.4 Implement `peek/1` for viewing next item
- [ ] 4.1.4 Implement `size/1` for queue size
- [ ] Add PendingMemories tests

### 4.1.5-4.1.7: STM Initialization, Access Logging, Token Budget

**Tasks:**
- [ ] 4.1.5 Implement `ShortTerm.new/1` for STM initialization
- [ ] 4.1.5 Create main STM struct containing all sub-structures
- [ ] 4.1.6 Add access_log tracking to all operations
- [ ] 4.1.6 Implement `get_access_pattern/1` for analysis
- [ ] 4.1.7 Create TokenBudget config struct
- [ ] 4.1.7 Add token counting utilities
- [ ] Add ShortTerm tests

### Integration Tasks

- [ ] Update Application supervision tree if needed
- [ ] Ensure tests pass
- [ ] Update planning document

---

## Current Status

### What Works
- Phase 3 multi-session architecture complete
- ContextManager handles basic conversation history
- Session persistence working

### What's Being Added
- Structured STM data structures
- Token-aware conversation buffer
- Semantic working context
- Promotion queue for LTM

### Known Limitations
- Token estimation is approximate (character count / 4)
- LTM integration comes in later phases
- Promotion engine not implemented yet

---

## Notes/Considerations

### Token Estimation

For now, we'll use a simple approximation: `token_count = String.length(text) / 4`. This is roughly accurate for English text. In production, a proper tokenizer would be used.

### Session Scoping

Each STM instance will be tied to a session_id. The STM itself doesn't need to be a GenServer - it's just data structures. The SessionManager or ContextManager will hold STM state.

### GenServer Decision

We'll keep STM as functional data structures (not GenServers) for simplicity. The owning process (likely ContextManager) will hold STM state and manage updates.

---

## Data Structures

### ConversationBuffer

```elixir
defmodule JidoCoderLib.Memory.ShortTerm.ConversationBuffer do
  defstruct [
    :messages,      # [%{role: :user, content: "...", tokens: 10}]
    :max_messages,  # 100
    :token_budget,  # %TokenBudget{}
    :current_tokens # 0
  ]
end
```

### WorkingContext

```elixir
defmodule JidoCoderLib.Memory.ShortTerm.WorkingContext do
  defstruct [
    :data,        # %{"current_file" => "/path/to/file.ex"}
    :max_items,   # 50
    :access_log   # [{"current_file", ~U[2025-01-24...]}]
  ]
end
```

### PendingMemories

```elixir
defmodule JidoCoderLib.Memory.ShortTerm.PendingMemories do
  defstruct [
    :queue,     # :queue.new()
    :max_size   # 20
  ]
end
```

### TokenBudget

```elixir
defmodule JidoCoderLib.Memory.TokenBudget do
  defstruct [
    :max_tokens,           # 4000
    :reserve_percentage,   # 0.1 (10% reserve)
    :overhead_threshold    # 0.9 (90% triggers eviction)
  ]
end
```

---

## References

- Planning Document: `notes/planning/01-foundation/phase-04.md`
- Phase 3 Architecture: Multi-session with ContextManager
- Research: `research/1.07-memory-system/`
