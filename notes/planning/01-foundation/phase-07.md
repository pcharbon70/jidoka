# Phase 7: Conversation History

This phase implements the conversation history system using a dedicated OWL ontology. All interactions (prompts, tool invocations, answers) are logged to the `jido:conversation-history` named graph, providing a structured, queryable record of all conversations.

---

## 7.1 Conversation History Ontology

- [ ] **Task 7.1** Load and integrate the Conversation History ontology

Import the conversation history ontology for representing interactions.

- [ ] 7.1.1 Add conversation-history.ttl to priv/ontologies
- [ ] 7.1.2 Implement `load_conversation_ontology/0` function
- [ ] 7.1.3 Parse and insert into system-knowledge graph
- [ ] 7.1.4 Create ontology class helpers (Conversation, ConversationTurn, Prompt, Answer, ToolInvocation, ToolResult)
- [ ] 7.1.5 Create ontology property helpers
- [ ] 7.1.6 Validate ontology loaded correctly

**Unit Tests for Section 7.1:**
- Test conversation-history ontology file exists
- Test ontology parses without errors
- Test ontology classes are accessible
- Test ontology properties are accessible
- Test ontology validation passes

---

## 7.2 Conversation Logger

- [ ] **Task 7.2** Implement the conversation logger

Create the logger that records all interaction components to the knowledge graph.

- [ ] 7.2.1 Create `JidoCoderLib.Conversation.Logger` module
- [ ] 7.2.2 Implement `ensure_conversation/2` for conversation creation
- [ ] 7.2.3 Implement `log_turn/3` for conversation turn logging
- [ ] 7.2.4 Implement `log_prompt/3` for prompt logging
- [ ] 7.2.5 Implement `log_answer/3` for answer logging
- [ ] 7.2.6 Implement `log_tool_invocation/4` for tool calls
- [ ] 7.2.7 Implement `log_tool_result/4` for tool results
- [ ] 7.2.8 Use SPARQL INSERT for all logging operations

**Unit Tests for Section 7.2:**
- Test ensure_conversation creates new conversations
- Test log_turn creates ConversationTurn instances
- Test log_prompt creates Prompt instances
- Test log_answer creates Answer instances
- Test log_tool_invocation creates ToolInvocation instances
- Test log_tool_result creates ToolResult instances
- Test logging uses conversation-history graph

---

## 7.3 LLMOrchestrator Integration

- [ ] **Task 7.3** Integrate conversation logging into LLMOrchestrator

Automatically log all interactions as they occur in the LLM agent.

- [ ] 7.3.1 Auto-create conversation on first prompt
- [ ] 7.3.2 Log prompts when received
- [ ] 7.3.3 Log tool invocations during LLM processing
- [ ] 7.3.4 Log tool results when received
- [ ] 7.3.5 Log final LLM answers
- [ ] 7.3.6 Handle logging errors gracefully
- [ ] 7.3.7 Maintain turn ordering with turnIndex

**Unit Tests for Section 7.3:**
- Test conversation is created on first prompt
- Test prompts are logged correctly
- Test tool invocations are logged with parameters
- Test tool results are logged with data
- Test answers are logged correctly
- Test turnIndex increments properly
- Test logging errors don't interrupt processing

---

## 7.4 Conversation Retrieval

- [ ] **Task 7.4** Implement conversation history retrieval

Provide functions for retrieving and querying conversation history.

- [ ] 7.4.1 Create `JidoCoderLib.Conversation.Retrieval` module
- [ ] 7.4.2 Implement `get_recent_turns/3` for recent history
- [ ] 7.4.3 Implement `get_turn_by_index/3` for specific turns
- [ ] 7.4.4 Implement `search_conversations/3` for text search
- [ ] 7.4.5 Implement `get_tool_usage/3` for tool invocation history
- [ ] 7.4.6 Implement `get_conversation_summary/2` for overview
- [ ] 7.4.7 Add result caching

**Unit Tests for Section 7.4:**
- Test get_recent_turns returns correct turns
- Test get_turn_by_index finds specific turns
- Test search_conversations finds matching content
- Test get_tool_usage returns tool invocations
- Test get_conversation_summary returns overview
- Test caching improves repeated queries

---

## 7.5 Context Integration with Conversation History

- [ ] **Task 7.5** Integrate conversation history into context building

Use conversation history to enrich the LLM context.

- [ ] 7.5.1 Update ContextManager to query conversation history
- [ ] 7.5.2 Add recent conversation to context layers
- [ ] 7.5.3 Add conversation summaries to context
- [ ] 7.5.4 Reference related tool usage in context
- [ ] 7.5.5 Optimize query frequency

**Unit Tests for Section 7.5:**
- Test ContextManager queries conversation history
- Test recent conversations are in context
- Test conversation summaries are included
- Test tool usage is referenced
- Test queries don't impact performance

---

## 7.6 Conversation Analysis

- [ ] **Task 7.6** Implement conversation analysis utilities

Provide tools for analyzing conversation patterns and content.

- [ ] 7.6.1 Create `JidoCoderLib.Conversation.Analysis` module
- [ ] 7.6.2 Implement `tool_frequency/2` for tool usage stats
- [ ] 7.6.3 Implement `conversation_length/2` for turn counting
- [ ] 7.6.4 Implement `session_summary/2` for overview
- [ ] 7.6.5 Implement `extract_insights/2` for finding patterns

**Unit Tests for Section 7.6:**
- Test tool_frequency returns correct counts
- Test conversation_length counts turns
- Test session_summary provides overview
- Test extract_insights finds patterns

---

## 7.7 Promotion from Conversation History

- [ ] **Task 7.7** Enable promotion of insights from conversation to LTM

Extract and promote significant insights from conversation logs to long-term memory.

- [ ] 7.7.1 Create conversation-to-LTM promotion logic
- [ ] 7.7.2 Identify significant decisions in conversations
- [ ] 7.7.3 Extract facts from conversation turns
- [ ] 7.7.4 Create derived MemoryItems linked to source turns
- [ ] 7.7.5 Store promoted memories in long-term-context graph

**Unit Tests for Section 7.7:**
- Test decisions are identified in conversations
- Test facts are extracted correctly
- Test derived memories link to source turns
- Test promoted memories are in correct graph

---

## 7.8 Phase 7 Integration Tests ✅

Comprehensive integration tests verifying the conversation history system.

- [ ] 7.8.1 Test full conversation logging lifecycle
- [ ] 7.8.2 Test conversation retrieval and queries
- [ ] 7.8.3 Test context integration with history
- [ ] 7.8.4 Test conversation analysis utilities
- [ ] 7.8.5 Test promotion from conversation to LTM
- [ ] 7.8.6 Test concurrent conversation logging
- [ ] 7.8.7 Test session isolation in conversation history
- [ ] 7.8.8 Test conversation history error handling

**Expected Test Coverage:**
- Conversation Ontology tests: 12 tests
- Conversation Logger tests: 30 tests
- LLMOrchestrator Integration tests: 25 tests
- Conversation Retrieval tests: 20 tests
- Context Integration tests: 15 tests
- Conversation Analysis tests: 12 tests
- Promotion tests: 15 tests

**Total: 129 integration tests**

---

## Success Criteria

1. **Ontology Loaded**: Conversation history ontology is loaded and usable
2. **Complete Logging**: All interaction components are logged
3. **Queryable History**: Conversations can be retrieved and searched
4. **Context Enrichment**: History enriches LLM context
5. **Analysis Support**: Conversation patterns can be analyzed
6. **LTM Promotion**: Insights can be promoted to long-term memory
7. **Session Isolation**: Conversations are isolated per session
8. **Test Coverage**: All conversation modules have 80%+ test coverage

---

## Critical Files

**New Files:**
- `lib/jido_coder_lib/conversation/logger.ex` - Conversation logging
- `lib/jido_coder_lib/conversation/retrieval.ex` - History retrieval
- `lib/jido_coder_lib/conversation/analysis.ex` - Analysis utilities
- `priv/ontologies/conversation-history.ttl` - Conversation ontology
- `test/jido_coder_lib/conversation/logger_test.exs`
- `test/jido_coder_lib/conversation/retrieval_test.exs`
- `test/jido_coder_lib/integration/phase7_test.exs`

**Modified Files:**
- `lib/jido_coder_lib/agents/llm_orchestrator.ex` - Integrate logging
- `lib/jido_coder_lib/agents/context_manager.ex` - Integrate history retrieval
- `lib/jido_coder_lib/memory/promotion_engine.ex` - Add conversation promotion
- `lib/jido_coder_lib/knowledge/named_graphs.ex` - Add conversation-history graph

**Dependencies:**
- Phase 1: Core Foundation
- Phase 3: Multi-Session Architecture
- Phase 4: Two-Tier Memory System
- Phase 5: Knowledge Graph Layer

---

## Dependencies

**Depends on:**
- Phase 1: Core Foundation (supervision, configuration)
- Phase 3: Multi-Session Architecture (session isolation)
- Phase 4: Two-Tier Memory System (LTM for promotion)
- Phase 5: Knowledge Graph Layer (SPARQL, named graphs)

**Enables:**
- Phase 8: Client API & Protocols (history accessible via API)
