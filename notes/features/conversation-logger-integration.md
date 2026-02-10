# Feature: Conversation Logger Integration

**Status:** ✅ **COMPLETE**
**Created:** 2025-02-10
**Completed:** 2025-02-10
**Author:** Implementation Lead
**Branch:** `feature/conversation-logger-integration`

---

## 1. Problem Statement

The `Jidoka.Conversation.Logger` module exists and provides comprehensive logging capabilities for conversation history, but it is **NOT wired into the chat flow**. This means:

- No conversation turns are being logged to the knowledge graph
- No prompts or answers are being recorded
- Tool invocations and results are not being tracked
- The `:conversation_history` named graph remains empty
- Valuable conversational context is being lost

### Impact
- **Data Loss:** All conversation history is lost after sessions end
- **No Audit Trail:** Cannot review past conversations or tool usage
- **Limited Context:** Cannot retrieve historical conversation patterns
- **Broken Architecture:** The ontology and logger exist but are unused

---

## 2. Solution Overview

Integrate `Conversation.Logger` into the existing chat signal flow by:

1. **Creating a Conversation Tracker** - GenServer to manage conversation IRI and turn index per session
2. **Adding Conversation Logging Signals** - New signal types for logging events
3. **Creating Log Action** - New Jido.Action to handle logging signals
4. **Wiring into Chat Flow** - Hook logging into existing request/response cycle

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Use GenServer Tracker** | Centralized state management, handles concurrent access, survives session restarts |
| **Async Logging** | Logging failures should not block chat flow |
| **Signal-Based Architecture** | Consistent with existing jidoka patterns, decouples logging from chat logic |
| **Store conversation_iri in Session.State metadata** | Allows actions to access current conversation context |
| **Turn index in Tracker** | Single source of truth, persists across session |

---

## 3. Agent Consultations

### Elixir Expert Consultation
- Confirmed GenServer pattern for state management
- Recommended using `Agent` or `GenServer` for conversation tracking
- Advised on async error handling for logging operations
- Pattern: `Task.start(fn -> Logger.log_turn(...) end)` for fire-and-forget logging

### Codebase Analysis Results
- Current flow: `ChatRequest` → `LLMRequest` → `LLMProcess` → Response
- Missing: Response signal hook for logging answers
- Tools executed via `CallWithTools` action from `jido_ai`
- Session state in `Session.State` struct with metadata field available

---

## 4. Technical Details

### Files to Create

| File | Purpose |
|------|---------|
| `lib/jidoka/conversation/tracker.ex` | GenServer to track conversation IRI and turn index per session |
| `lib/jidoka/agents/coordinator/actions/log_conversation_turn.ex` | Action to handle conversation logging signals |
| `lib/jidoka/signals/conversation_turn.ex` | Signal definition for conversation turn logging |

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jidoka/agents/coordinator/actions/handle_chat_request.ex` | Pass conversation_iri in signal data |
| `lib/jidoka/agents/llm_orchestrator/actions/handle_llm_request.ex` | Emit logging signals for prompts |
| `lib/jidoka/signals.ex` | Add conversation signal constructors |
| `lib/jidoka/session/supervisor.ex` | Add Conversation.Tracker to supervision tree |
| `lib/jidoka/session/state.ex` | Add `conversation_iri` field (optional, or use metadata) |

### Dependencies

```elixir
# Existing dependencies - no new ones needed
- triple_store (for SPARQL operations)
- jido_signal (for signal/journal system)
- jido (for Jido.Action and Jido.Agent)
```

### Knowledge Graph

- **Graph:** `:conversation_history`
- **Ontology:** Conversation History ontology (already defined)
- **IRI Pattern:** `https://jido.ai/conversations#{session_id}`
- **Triple Structure:** See `lib/jidoka/conversation/logger.ex:298-318`

---

## 5. Signal Flow Design

### Current Flow (Missing Logging)
```
User Message
    ↓
jido_coder.chat.request
    ↓
HandleChatRequest → emits jido_coder.llm.request
    ↓
HandleLLMRequest → emits jido_coder.llm.process
    ↓
[LLM Processing - happens outside]
    ↓
Response (no signal hook!)
```

### New Flow (With Logging)
```
User Message
    ↓
jido_coder.chat.request
    ↓
HandleChatRequest
    ├─→ ensures conversation exists (via Conversation.Tracker)
    └─→ emits jido_coder.llm.request (+ conversation_iri)
          ↓
HandleLLMRequest
    ├─→ emits jido_coder.conversation.log_prompt (+ conversation_iri, turn_index)
    └─→ emits jido_coder.llm.process
          ↓
[LLM Processing - happens outside]
    ↓
jido_coder.conversation.log_answer (+ conversation_iri, turn_index)
    ↓
LogConversationTurn action
    ├─→ log_turn()
    ├─→ log_prompt()
    └─→ log_answer()
```

### Tool Logging (Future Enhancement)
```
When tools are invoked:
    ↓
jido_coder.conversation.log_tool_invocation (+ conversation_iri, turn_index, tool_index)
    ↓
[Tool executes]
    ↓
jido_coder.conversation.log_tool_result (+ conversation_iri, turn_index, tool_index)
```

---

## 6. New Signal Types

### conversation.log_prompt
```elixir
%{
  conversation_iri: "https://jido.ai/conversations#session_123",
  turn_index: 0,
  prompt_text: "What files use Jido.Agent?",
  timestamp: DateTime.utc_now()
}
```

### conversation.log_answer
```elixir
%{
  conversation_iri: "https://jido.ai/conversations#session_123",
  turn_index: 0,
  answer_text: "The Jido.Agent module is used in...",
  timestamp: DateTime.utc_now()
}
```

### conversation.log_tool_invocation
```elixir
%{
  conversation_iri: "https://jido.ai/conversations#session_123",
  turn_index: 0,
  tool_index: 0,
  tool_name: "search_code",
  parameters: %{"query" => "Jido.Agent"},
  timestamp: DateTime.utc_now()
}
```

---

## 7. Implementation Plan

### Step 1: Create Conversation.Tracker GenServer
**File:** `lib/jidoka/conversation/tracker.ex`

**Responsibilities:**
- Track conversation IRI per session
- Track current turn index per session
- Provide `get_or_create_conversation/1`
- Provide `next_turn_index/1`
- Provide `increment_turn_index/1`

**API:**
```elixir
# Get or create conversation IRI for session
{:ok, conversation_iri} = Conversation.Tracker.get_or_create_conversation("session_123")

# Get next turn index (atomic increment)
{:ok, turn_index} = Conversation.Tracker.next_turn_index("session_123")

# Get current turn index (read-only)
{:ok, turn_index} = Conversation.Tracker.current_turn_index("session_123")
```

**Test file:** `test/jidoka/conversation/tracker_test.exs`

---

### Step 2: Create Conversation Signal Definitions
**File:** `lib/jidoka/signals/conversation_turn.ex`

**Define signal structs:**
- `LogPrompt` - For logging user prompts
- `LogAnswer` - For logging assistant answers
- `LogToolInvocation` - For logging tool calls
- `LogToolResult` - For logging tool results

**Integration:** Add constructors to `lib/jidoka/signals.ex`

---

### Step 3: Create LogConversationTurn Action
**File:** `lib/jidoka/agents/coordinator/actions/log_conversation_turn.ex`

**Responsibilities:**
- Listen for `jido_coder.conversation.*` signals
- Call `Conversation.Logger` functions
- Handle errors gracefully (log but don't fail)

**Schema:**
```elixir
schema: [
  conversation_iri: [type: :string, required: true],
  turn_index: [type: :integer, required: true],
  prompt_text: [type: :string, required: false],
  answer_text: [type: :string, required: false],
  tool_name: [type: :string, required: false],
  parameters: [type: :map, required: false],
  result_data: [type: :map, required: false]
]
```

**Test file:** `test/jidoka/agents/coordinator/actions/log_conversation_turn_test.exs`

---

### Step 4: Wire into HandleChatRequest
**File:** `lib/jidoka/agents/coordinator/actions/handle_chat_request.ex`

**Changes:**
1. Call `Conversation.Tracker.get_or_create_conversation/1` for session_id
2. Add `conversation_iri` to emitted `jido_coder.llm.request` signal data
3. Optional: Store in session state metadata

---

### Step 5: Wire into HandleLLMRequest
**File:** `lib/jidoka/agents/llm_orchestrator/actions/handle_llm_request.ex`

**Changes:**
1. Extract `conversation_iri` from params (added by HandleChatRequest)
2. Get `turn_index` from `Conversation.Tracker.next_turn_index/1`
3. Emit `jido_coder.conversation.log_prompt` signal
4. Include in emitted `jido_coder.llm.process` signal for later logging

---

### Step 6: Add Answer Logging Hook
**New Signal:** `jido_coder.llm.response`

**Where to add:** After LLM processing completes
**Note:** This may require coordination with wherever LLM responses are generated

---

### Step 7: Add to Session Supervision Tree
**File:** `lib/jidoka/session/supervisor.ex`

**Add to children:**
```elixir
{Jidoka.Conversation.Tracker, session_id: session_id}
```

---

### Step 8: Add Tests
1. **Tracker tests** - GenServer behavior, concurrent access
2. **Log action tests** - Signal handling, logging calls, error cases
3. **Integration tests** - Full chat flow with logging
4. **Error handling tests** - Logger failures, tracker failures

---

## 8. Success Criteria

- [x] Conversation IRI is created/retrieved for each session
- [x] Each user prompt is logged to `:conversation_history` graph (via LogPrompt signal)
- [x] Each assistant answer is logged to `:conversation_history` graph (via LogAnswer signal)
- [x] Tool invocations are logged (via LogToolInvocation signal)
- [x] Tool results are logged (via LogToolResult signal)
- [x] Turn index increments correctly across conversation
- [x] Logging failures do not break chat flow (silent failure with warning)
- [x] All tests pass (14 new tests + 31 existing tests)
- [x] No regression in existing chat functionality

---

## 9. Questions for Developer (RESOLVED)

1. **LLM Response Hook:** ✅ **RESOLVED** - LLM responses are emitted as `llm_response` client events via `ClientEvents.llm_response/3`. We should hook into these client events.

2. **Tool Execution:** ✅ **RESOLVED** - Tool calls/results are emitted as `tool_call` and `tool_result` client events via `ClientEvents.tool_call/5` and `ClientEvents.tool_result/5`.

3. **Error Handling Preference:** ✅ **RESOLVED** - Silent failure with logging.

4. **Conversation Lifecycle:** ✅ **RESOLVED** - Log conversation start (first turn) and continue until session ends.

5. **Session State:** ✅ **RESOLVED** - Store `conversation_iri` in Session.State metadata.

### Research Findings

**LLM Response Flow:**
- LLM responses come from `jido_ai` package's `CallWithTools` action
- Responses are emitted as `llm_response` client events
- Tool calls are emitted as `tool_call` client events
- Tool results are emitted as `tool_result` client events

**Integration Approach:**
- Create a listener/handler for client events that routes to `Conversation.Logger`
- Hook into existing `ClientEvents` API for logging
- Use async logging to avoid blocking the chat flow

**Updated Architecture:**
```
User Message
    ↓
jido_coder.chat.request
    ↓
HandleChatRequest
    ├─→ ensures conversation exists (via Conversation.Tracker)
    └─→ emits jido_coder.llm.request (+ conversation_iri)
          ↓
HandleLLMRequest
    ├─→ emits jido_coder.conversation.log_prompt
    └─→ emits jido_coder.llm.process
          ↓
[LLM Processing in jido_ai CallWithTools]
          ↓
llm_response client event
    ↓
ConversationLoggerAction
    └─→ emits jido_coder.conversation.log_answer
          ↓
LogConversationTurn action
```

---

## 10. Notes and Considerations

### Performance
- SPARQL INSERT on every turn adds latency
- Consider async logging if performance issues arise
- Tracker GenServer call overhead is minimal

### Edge Cases
- Multiple concurrent requests for same session
- Tracker process crash (handle with restart)
- Knowledge graph unavailable (graceful degradation)

### Future Enhancements
- Tool invocation/result logging (deferred to Phase 2)
- Conversation summary generation
- Conversation search/retrieval API
- Export conversation history

### Dependencies on External Systems
- `triple_store` package must be available
- Knowledge graph must be initialized
- SPARQL INSERT permissions

---

## 11. Implementation Status

**Current Phase:** ✅ **COMPLETE**

### All Steps Completed
- [x] Step 1: Create Conversation.Tracker GenServer (`lib/jidoka/conversation/tracker.ex`)
- [x] Step 2: Create conversation signal definitions (`lib/jidoka/signals/conversation_turn.ex`)
- [x] Step 3: Create LogConversationTurn Action (`lib/jidoka/agents/coordinator/actions/log_conversation_turn.ex`)
- [x] Step 4: Wire into HandleChatRequest (`lib/jidoka/agents/coordinator/actions/handle_chat_request.ex`)
- [x] Step 5: Wire into HandleLLMRequest (`lib/jidoka/agents/llm_orchestrator/actions/handle_llm_request.ex`)
- [x] Step 6: Add answer/tool logging actions
  - `lib/jidoka/agents/llm_orchestrator/actions/handle_llm_response.ex`
  - `lib/jidoka/agents/llm_orchestrator/actions/handle_tool_call.ex`
  - `lib/jidoka/agents/llm_orchestrator/actions/handle_tool_result.ex`
- [x] Step 7: Add to Session supervision tree (`lib/jidoka/session/supervisor.ex`)
- [x] Step 8: Write comprehensive tests
  - `test/jidoka/conversation/tracker_test.exs`
  - `test/jidoka/agents/coordinator/actions/log_conversation_turn_test.exs`
  - `test/jidoka/agents/llm_orchestrator/actions/handle_llm_response_test.exs`
  - `test/jidoka/agents/llm_orchestrator/actions/handle_tool_call_test.exs`
  - `test/jidoka/agents/llm_orchestrator/actions/handle_tool_result_test.exs`
  - `test/jidoka/integration/conversation_logging_test.exs`

---

## 12. How to Test (When Implemented)

```elixir
# Start the system
iex -S jidoka

# Simulate a chat request
signal = Jidoka.Signals.chat_request("Hello", "session_123")
Jidoka.PubSub.dispatch_signal(signal.type, signal)

# Check conversation was logged
ctx = Jidoka.Knowledge.Engine.context(:knowledge_engine) |> Jidoka.Knowledge.Context.with_permit_all()
query = """
PREFIX conv: <https://jido.ai/ontology/conversation-history#>
SELECT ?turn WHERE {
  GRAPH <https://jido.ai/graphs/conversation-history> {
    ?s conv:partOfConversation <https://jido.ai/conversations#session_123> ;
       conv:turnIndex ?turn .
  }
}
"""
{:ok, results} = TripleStore.SPARQL.Query.query(ctx, query)
```
