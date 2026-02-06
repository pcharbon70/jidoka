# Phase 7.1: Conversation History Ontology

**Branch:** `feature/phase-7.1-conversation-ontology`
**Created:** 2026-02-05
**Status:** In Progress

---

## Problem Statement

Phase 7 requires implementing a conversation history system to track all interactions (prompts, tool invocations, answers) in the knowledge graph. Section 7.1 focuses specifically on loading and integrating the Conversation History ontology that defines the data model for storing conversations.

### Impact

Without the conversation ontology:
- Cannot structure conversation data in the knowledge graph
- No defined schema for conversation turns, prompts, answers, and tool usage
- Cannot query conversation history effectively
- Blocks implementation of Phase 7.2 (Conversation Logger)

---

## Solution Overview

1. **Copy ontology file** from research notes to `priv/ontologies/conversation-history.ttl`
2. **Create helper functions** in `Ontology` module for conversation-related classes and properties
3. **Load and validate** the ontology into the `:system_knowledge` graph
4. **Create tests** to verify ontology loading and accessibility

### Key Design Decisions

- **Use existing pattern**: Follow the same loading pattern as `load_jido_ontology()` and `load_elixir_ontology()`
- **Load into system_knowledge**: The ontology definition goes into `:system_knowledge`, while actual conversation instances will go into `:conversation_history`
- **Helper functions**: Create convenience functions for IRIs similar to existing memory type helpers

---

## Technical Details

### Files

| File | Action | Purpose |
|------|--------|---------|
| `priv/ontologies/conversation-history.ttl` | Create | Conversation ontology definition |
| `lib/jidoka/knowledge/ontology.ex` | Modify | Add conversation ontology loading and helpers |
| `test/jidoka/knowledge/ontology_test.exs` | Modify | Add conversation ontology tests |

### Ontology Classes

| Class | IRI | Purpose |
|-------|-----|---------|
| `:Conversation` | `https://jido.ai/ontology/conversation-history#Conversation` | Sequence of turns |
| `:ConversationTurn` | `https://jido.ai/ontology/conversation-history#ConversationTurn` | Single prompt-answer cycle |
| `:Prompt` | `https://jido.ai/ontology/conversation-history#Prompt` | User input |
| `:Answer` | `https://jido.ai/ontology/conversation-history#Answer` | Assistant response |
| `:ToolInvocation` | `https://jido.ai/ontology/conversation-history#ToolInvocation` | Tool call |
| `:ToolResult` | `https://jido.ai/ontology/conversation-history#ToolResult` | Tool outcome |

### Ontology Properties (Key)

| Property | Type | Purpose |
|----------|------|---------|
| `:hasTurn` | ObjectProperty | Conversation -> ConversationTurn |
| `:hasPrompt` | ObjectProperty | ConversationTurn -> Prompt |
| `:hasAnswer` | ObjectProperty | ConversationTurn -> Answer |
| `:promptText` | DatatypeProperty | Prompt content (string) |
| `:answerText` | DatatypeProperty | Answer content (string) |
| `:timestamp` | DatatypeProperty | Event timestamp (dateTime) |
| `:turnIndex` | DatatypeProperty | Turn ordering (integer) |

---

## Implementation Plan

### Task 7.1.1: Add conversation-history.ttl to priv/ontologies
- [x] Copy ontology from `notes/research/1.00-architecture/conversation.ttl`
- [x] Verify file is valid TTL syntax
- [x] Ensure consistent with other ontologies

### Task 7.1.2: Implement `load_conversation_ontology/0` function
- [x] Add `load_conversation_ontology/0` function to `Ontology` module
- [x] Follow pattern of `load_jido_ontology()`
- [x] Load into `:system_knowledge` graph
- [x] Return metadata map with version, triple count, etc.

### Task 7.1.3: Parse and insert into system-knowledge graph
- [x] Use existing `load_ontology/2` function
- [x] Target `:system_knowledge` named graph
- [x] Verify triples inserted correctly

### Task 7.1.4: Create ontology class helpers
- [x] Add `@conv_namespace` constant for conversation namespace
- [x] Add `@conv_classes` map with class IRIs
- [x] Add `conversation_class_iris/0` helper
- [x] Add `create_conversation_individual/1` helper

### Task 7.1.5: Create ontology property helpers
- [x] Add `@conv_properties` map with property IRIs
- [x] Add helper functions for key properties (hasTurn, hasPrompt, etc.)

### Task 7.1.6: Validate ontology loaded correctly
- [x] Add `validate_conversation_ontology/0` function
- [x] Check that all expected classes exist
- [x] Return validation results

---

## Unit Tests

### File: `test/jidoka/knowledge/ontology_test.exs`

Tests added:
- `conversation ontology file` - 3 tests for file existence, readability, and prefixes
- `load_conversation_ontology/0` - 2 tests for loading and reload
- `validate_conversation_ontology/0` - 2 tests for validation
- `ontology_version/1 for conversation` - 1 test for version
- `conversation_class_iris/0` - 2 tests for class IRIs
- `conversation_class_names/0` - 2 tests for class names
- `conversation_class_exists?/1` - 2 tests for class existence
- `conversation class IRI helpers` - 6 tests for individual class IRIs
- `conversation individual creators` - 6 tests for individual creators

Total: 26 new tests for conversation ontology

---

## Success Criteria

1. [x] Ontology file exists in `priv/ontologies/conversation-history.ttl`
2. [x] `load_conversation_ontology/0` function loads ontology successfully
3. [x] Ontology triples are inserted into `:system_knowledge` graph
4. [x] Class helper functions return correct IRIs
5. [x] Property helper functions return correct IRIs
6. [x] `validate_conversation_ontology/0` confirms all classes present
7. [x] All unit tests pass (61 tests, 0 failures)

---

## Current Status

**Status: COMPLETED** (2026-02-05)

All tasks completed successfully. The conversation ontology is now loaded and accessible in the knowledge graph.

**How to Test:**
```bash
# Run ontology tests
mix test test/jidoka/knowledge/ontology_test.exs

# Run all tests
mix test
```

---

## Notes

- The conversation ontology was already designed in `notes/research/1.00-architecture/conversation.ttl`
- Following the same pattern as Jido and Elixir ontology loading
- Conversation instances will go into `:conversation_history` graph, but ontology definition goes into `:system_knowledge`
