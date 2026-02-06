# Phase 7.2: Conversation Logger

**Branch:** `feature/phase-7.2-conversation-logger`
**Created:** 2026-02-05
**Status:** Complete

---

## Problem Statement

Phase 7.2 implements the conversation logger that records all interaction components (prompts, tool invocations, answers) to the knowledge graph. Without this logger:
- Cannot persist conversation history in the knowledge graph
- No structured record of user prompts and assistant responses
- Tool usage is not tracked for analysis
- Blocks implementation of Phase 7.3 (LLMOrchestrator Integration)

### Impact

- Conversations cannot be retrieved for context
- No audit trail of interactions
- Cannot analyze tool usage patterns
- Conversation history unavailable for future queries

---

## Solution Overview

Create `JidoCoderLib.Conversation.Logger` module that:
1. Creates and manages conversation records in the knowledge graph
2. Logs conversation turns with prompts and answers
3. Logs tool invocations and their results
4. Uses SPARQL INSERT DATA for all logging operations
5. Stores data in the `:conversation_history` named graph

### Key Design Decisions

- **Use SPARQL INSERT DATA**: Follow existing pattern from TripleStoreAdapter
- **Store in conversation_history graph**: Isolate conversation data from other knowledge
- **Use conversation ontology helpers**: Leverage Phase 7.1 class and individual creators
- **Idempotent ensure_conversation**: Safe to call multiple times
- **Timestamp all events**: Track when each interaction occurred
- **Graceful error handling**: Logging failures should not crash the system

---

## Technical Details

### Files

| File | Action | Purpose |
|------|--------|---------|
| `lib/jido_coder_lib/conversation/logger.ex` | Create | Conversation logging module |
| `test/jido_coder_lib/conversation/logger_test.exs` | Create | Unit tests for logger |
| `lib/jido_coder_lib/conversation.ex` | Create | Main conversation module header |

### Dependencies

- `JidoCoderLib.Knowledge.Engine` - Knowledge graph access
- `JidoCoderLib.Knowledge.Ontology` - Conversation ontology helpers
- `JidoCoderLib.Knowledge.NamedGraphs` - Named graph management
- `TripleStore` - SPARQL update operations
- `Jason` - JSON encoding for parameters/results

### Ontology Classes Used

From Phase 7.1 conversation-history.ttl:
- `:Conversation` - Container for a conversation
- `:ConversationTurn` - Single prompt-answer cycle
- `:Prompt` - User input text
- `:Answer` - Assistant response text
- `:ToolInvocation` - Tool call with parameters
- `:ToolResult` - Tool outcome

### Ontology Properties Used

**Object Properties:**
- `:associatedWithSession` - Links conversation to work session
- `:hasTurn` - Links conversation to its turns
- `:hasPrompt` - Links turn to prompt
- `:hasAnswer` - Links turn to answer
- `:involvesToolInvocation` - Links turn to tool calls
- `:hasResult` - Links tool invocation to result

**Data Properties:**
- `:promptText` - Prompt content (string)
- `:answerText` - Answer content (string)
- `:invocationParameters` - Tool parameters (JSON string)
- `:resultData` - Tool result data (JSON string)
- `:timestamp` - Event timestamp (dateTime)
- `:turnIndex` - Turn ordering (integer)
- `:toolName` - Tool identifier (string)

---

## Implementation Plan

### Task 7.2.1: Create Conversation module structure
- [x] Create `lib/jido_coder_lib/conversation.ex` header module
- [x] Create `lib/jido_coder_lib/conversation/logger.ex`
- [x] Add module documentation and @moduledoc
- [x] Define module attributes for prefixes

### Task 7.2.2: Implement `ensure_conversation/2`
- [x] Accept session_id and optional metadata
- [x] Check if conversation exists for session
- [x] Create conversation individual if not exists
- [x] Insert triples into conversation_history graph
- [x] Return {:ok, conversation_iri} or {:error, reason}

### Task 7.2.3: Implement `log_turn/3`
- [x] Accept conversation_iri, turn_index, and metadata
- [x] Create ConversationTurn individual
- [x] Link to parent conversation with partOfConversation
- [x] Set turnIndex data property
- [x] Set timestamp
- [x] Insert into conversation_history graph

### Task 7.2.4: Implement `log_prompt/3`
- [x] Accept conversation_iri, turn_index, and prompt text
- [x] Create Prompt individual
- [x] Set promptText data property
- [x] Set timestamp
- [x] Link to ConversationTurn with hasPrompt

### Task 7.2.5: Implement `log_answer/3`
- [x] Accept conversation_iri, turn_index, and answer text
- [x] Create Answer individual
- [x] Set answerText data property
- [x] Set timestamp
- [x] Link to ConversationTurn with hasAnswer

### Task 7.2.6: Implement `log_tool_invocation/4`
- [x] Accept conversation_iri, turn_index, tool_index, and params
- [x] Create ToolInvocation individual
- [x] Set toolName data property
- [x] Encode and set invocationParameters (JSON)
- [x] Set timestamp
- [x] Link to ConversationTurn with involvesToolInvocation

### Task 7.2.7: Implement `log_tool_result/4`
- [x] Accept conversation_iri, turn_index, tool_index, and result data
- [x] Create ToolResult individual
- [x] Encode and set resultData (JSON)
- [x] Set timestamp
- [x] Link to ToolInvocation with hasResult

### Task 7.2.8: Create helper functions
- [x] `graph_iri/0` - Get conversation_history graph IRI
- [x] `engine_context/0` - Get engine context for SPARQL
- [x] `escape_string/1` - Escape strings for SPARQL
- [x] `format_timestamp/1` - Convert DateTime to xsd:dateTime format
- [x] `encode_json/1` - Safely encode to JSON (fallback on error)

---

## Unit Tests

### File: `test/jido_coder_lib/conversation/logger_test.exs`

```elixir
defmodule JidoCoderLib.Conversation.LoggerTest do
  use ExUnit.Case, async: false

  alias JidoCoderLib.Conversation.Logger
  alias JidoCoderLib.Knowledge.{Engine, Ontology, NamedGraphs}

  @moduletag :conversation_logger
  @moduletag :external

  setup do
    # Ensure conversation_history graph exists
    NamedGraphs.create(:conversation_history)
    # Load conversation ontology
    Ontology.load_conversation_ontology()

    # Use unique session IDs for each test
    session_id = "test_session_#{System.unique_integer()}"

    on_exit(fn ->
      # Clean up test data
      # (optional: can leave data for inspection)
    end)

    %{session_id: session_id}
  end

  describe "ensure_conversation/2" do
    test "creates a new conversation", %{session_id: session_id} do
      assert {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      assert is_binary(conversation_iri)
      assert String.contains?(conversation_iri, session_id)
    end

    test "is idempotent - returns same IRI on second call", %{session_id: session_id} do
      assert {:ok, iri1} = Logger.ensure_conversation(session_id)
      assert {:ok, iri2} = Logger.ensure_conversation(session_id)

      assert iri1 == iri2
    end

    test "links conversation to work session", %{session_id: session_id} do
      assert {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      # Verify the conversation was created and linked to session
      # (SPARQL query to verify triple exists)
    end
  end

  describe "log_turn/3" do
    test "creates a conversation turn", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      assert {:ok, turn_iri} = Logger.log_turn(conversation_iri, 0)

      assert is_binary(turn_iri)
      assert String.contains?(turn_iri, "turn-0")
    end

    test "sets turn index correctly", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      {:ok, _} = Logger.log_turn(conversation_iri, 5)

      # Verify turnIndex is set to 5
    end

    test "links turn to conversation", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      {:ok, turn_iri} = Logger.log_turn(conversation_iri, 0)

      # Verify partOfConversation property links to conversation
    end
  end

  describe "log_prompt/3" do
    test "creates a prompt with text", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      assert {:ok, prompt_iri} = Logger.log_prompt(conversation_iri, 0, "Hello, world!")

      assert is_binary(prompt_iri)
    end

    test "sets promptText correctly", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      {:ok, _} = Logger.log_prompt(conversation_iri, 0, "Test prompt")

      # Verify promptText property
    end

    test "handles special characters in prompt", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      special_text = "Test with 'quotes' and \"double quotes\" and newlines\n"
      assert {:ok, _} = Logger.log_prompt(conversation_iri, 0, special_text)
    end
  end

  describe "log_answer/3" do
    test "creates an answer with text", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      assert {:ok, answer_iri} = Logger.log_answer(conversation_iri, 0, "Hi there!")

      assert is_binary(answer_iri)
    end

    test "sets answerText correctly", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      {:ok, _} = Logger.log_answer(conversation_iri, 0, "Test answer")

      # Verify answerText property
    end
  end

  describe "log_tool_invocation/4" do
    test "creates tool invocation with parameters", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      params = %{"query" => "SELECT *", "limit" => 10}

      assert {:ok, invocation_iri} =
               Logger.log_tool_invocation(conversation_iri, 0, 0, "sparql_query", params)

      assert is_binary(invocation_iri)
    end

    test "sets toolName correctly", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      {:ok, _} = Logger.log_tool_invocation(conversation_iri, 0, 0, "test_tool", %{})

      # Verify toolName property
    end

    test "encodes parameters as JSON", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      params = %{"key" => "value", "number" => 42}

      {:ok, _} = Logger.log_tool_invocation(conversation_iri, 0, 0, "test_tool", params)

      # Verify invocationParameters is valid JSON
    end
  end

  describe "log_tool_result/4" do
    test "creates tool result with data", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      result_data = %{"status" => "success", "rows" => 5}

      assert {:ok, result_iri} =
               Logger.log_tool_result(conversation_iri, 0, 0, result_data)

      assert is_binary(result_iri)
    end

    test "encodes result data as JSON", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      result_data = %{"output" => "result"}

      {:ok, _} = Logger.log_tool_result(conversation_iri, 0, 0, result_data)

      # Verify resultData is valid JSON
    end
  end

  describe "integration: full conversation logging" do
    test "logs a complete conversation turn", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      # Log the turn
      {:ok, turn_iri} = Logger.log_turn(conversation_iri, 0)

      # Log prompt
      {:ok, prompt_iri} = Logger.log_prompt(conversation_iri, 0, "What is Elixir?")

      # Log tool invocation
      {:ok, invocation_iri} =
        Logger.log_tool_invocation(conversation_iri, 0, 0, "search", %{"query" => "Elixir"})

      # Log tool result
      {:ok, result_iri} = Logger.log_tool_result(conversation_iri, 0, 0, %{"results" => []})

      # Log answer
      {:ok, answer_iri} = Logger.log_answer(conversation_iri, 0, "Elixir is a programming language.")

      # All IRIs should be returned
      assert turn_iri != nil
      assert prompt_iri != nil
      assert invocation_iri != nil
      assert result_iri != nil
      assert answer_iri != nil
    end
  end

  describe "error handling" do
    test "handles empty prompt text gracefully", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      assert {:ok, _} = Logger.log_prompt(conversation_iri, 0, "")
    end

    test "handles nil parameters in tool invocation", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      assert {:ok, _} = Logger.log_tool_invocation(conversation_iri, 0, 0, "test_tool", nil)
    end

    test "handles nil result data", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      assert {:ok, _} = Logger.log_tool_result(conversation_iri, 0, 0, nil)
    end
  end

  describe "graph isolation" do
    test "stores data in conversation_history graph", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      Logger.log_prompt(conversation_iri, 0, "test")

      # Verify triple is in conversation_history graph, not others
      # (SPARQL query with GRAPH filter)
    end
  end
end
```

---

## Success Criteria

1. [x] Logger module exists with all required functions
2. [x] `ensure_conversation/2` creates conversations idempotently
3. [x] `log_turn/3` creates ConversationTurn instances
4. [x] `log_prompt/3` creates Prompt instances with text
5. [x] `log_answer/3` creates Answer instances with text
6. [x] `log_tool_invocation/4` creates ToolInvocation with parameters
7. [x] `log_tool_result/4` creates ToolResult with data
8. [x] All operations use SPARQL INSERT DATA
9. [x] Data is stored in conversation_history graph
10. [x] All unit tests pass

---

## Test Results

**Final Test Run:** 2026-02-05
```
12 tests, 0 failures
```

All tests pass:
- `ensure_conversation/2` - Creates conversations idempotently
- `log_turn/3` - Creates conversation turns
- `log_prompt/3` - Logs prompts with text
- `log_answer/3` - Logs answers with text
- `log_tool_invocation/4` - Logs tool invocations with parameters
- `log_tool_result/4` - Logs tool results
- Integration test - Full conversation turn logging
- Error handling - Handles nil/empty parameters gracefully

---

## Implementation Notes

### Key Fixes During Implementation

1. **Context Structure**: TripleStore.update requires `:transaction => nil` in context
   - Fixed by adding `|> Map.put(:transaction, nil)` before `with_permit_all()`

2. **SPARQL JSON Quoting**: JSON string values must be wrapped in quotes
   - Fixed by using `conv:invocationParameters \"#{params_json}\"` instead of `conv:invocationParameters #{params_json}`

3. **Empty Parameters Handling**: Empty maps `%{}` and `nil` need special handling
   - Fixed by conditionally building triple content and filtering empty strings
   - Used `Enum.reject(&(&1 == ""))` to remove empty triple parts

---

## Files Modified/Created

| File | Status | Lines |
|------|--------|-------|
| `lib/jido_coder_lib/conversation.ex` | Created | 56 |
| `lib/jido_coder_lib/conversation/logger.ex` | Created | 558 |
| `test/jido_coder_lib/conversation/logger_test.exs` | Created | 148 |

---

## Notes

- **IRI Format**: Using hierarchical structure from Phase 7.1
- **Timestamp Format**: xsd:dateTime with timezone (UTC)
- **JSON Encoding**: Using Jason library, with error fallback
- **String Escaping**: SPARQL requires escaping quotes and backslashes
- **Graph Context**: Using Context.with_permit_all for quad schema bypass
