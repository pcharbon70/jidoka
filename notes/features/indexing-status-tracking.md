# Feature: Indexing Status Tracking

**Date:** 2026-02-02
**Branch:** `feature/indexing-status-tracking`
**Status:** Planning
**Phase:** 6.4.5 - Codebase Semantic Model - Incremental Indexing

---

## Problem Statement

The Phase 6 Codebase Semantic Model requires tracking the progress and state of code indexing operations. Currently, there is no mechanism to:

1. Track which files are currently being indexed
2. Monitor indexing completion status across a project
3. Record last indexed timestamps for files
4. Capture and persist indexing errors
5. Report overall indexing progress for projects

**Impact:**
- Without status tracking, indexing operations are "fire and forget" with no visibility
- Failed indexing operations leave no trace for debugging
- Cannot determine if a project's code model is up-to-date
- No way to resume interrupted indexing operations
- Clients cannot display indexing progress to users

---

## Solution Overview

Implement a comprehensive indexing status tracking system using a dual-storage approach:

1. **In-Memory Process State (GenServer)**: Fast access to current indexing operations
2. **Knowledge Graph Persistence**: Historical status records queryable via SPARQL

### Key Design Decisions

1. **Dual Storage Approach**: Process state for active operations, knowledge graph for persistence
2. **Status Enum**: Four-state lifecycle (`:pending`, `:in_progress`, `:completed`, `:failed`)
3. **Ontology Extension**: Add indexing status classes to Jido ontology
4. **Telemetry Integration**: Emit events for indexing lifecycle

### Architecture

```
IndexingStatusTracker (GenServer)
├── State:
│   ├── :active_operations - Map of file -> operation info
│   ├── :completed_operations - Map of file -> completion info
│   └── :failed_operations - Map of file -> error info
├── API:
│   ├── start_indexing/1 - Mark file as in_progress
│   ├── complete_indexing/2 - Mark file as completed
│   ├── fail_indexing/2 - Mark file as failed
│   ├── get_status/1 - Get status for a file
│   ├── get_project_status/1 - Get overall project status
│   └── list_failed/0 - List all failed files
└── Persistence:
    └── -> Knowledge Graph (elixir-codebase graph)
```

---

## Technical Details

### Module Structure

**Primary Module:** `lib/jidoka/indexing/indexing_status_tracker.ex`

**Ontology Extension:** `priv/ontologies/elixir_indexing.ttl` (new)

**Signal Module:** `lib/jidoka/signals/indexing_status.ex` (new)

### Data Structures

```elixir
@type indexing_status :: :pending | :in_progress | :completed | :failed

@type operation_info :: %{
  file_path: Path.t(),
  status: indexing_status(),
  started_at: DateTime.t() | nil,
  completed_at: DateTime.t() | nil,
  error: String.t() | nil,
  triple_count: non_neg_integer() | nil
}
```

### API Design

```elixir
defmodule Jidoka.Indexing.IndexingStatusTracker do
  use GenServer

  # Client API
  def start_link(opts \\ [])
  def start_indexing(file_path)
  def complete_indexing(file_path, triple_count \\ 0)
  def fail_indexing(file_path, error_message)
  def get_status(file_path)
  def get_project_status(project_root)
  def list_failed()
  def list_in_progress()
end
```

### Dependencies

**Existing:**
- `:jido` - Jido.Agent for GenServer base
- `:rdf` - RDF graph operations
- `:telemetry` - Event emission

---

## Success Criteria

### Functional Requirements

- [ ] IndexingStatusTracker GenServer created
- [ ] start_indexing/1 marks file as in_progress
- [ ] complete_indexing/2 marks file as completed
- [ ] fail_indexing/2 marks file as failed with error
- [ ] get_status/1 returns current status for file
- [ ] get_project_status/1 returns aggregate project status
- [ ] Status persists to knowledge graph
- [ ] Telemetry events emitted for status changes

### Test Coverage

- [ ] IndexingStatusTracker starts successfully
- [ ] start_indexing creates operation record
- [ ] complete_indexing updates status and persists
- [ ] fail_indexing captures error details
- [ ] get_status returns correct status atom
- [ ] get_project_status aggregates correctly
- [ ] list_failed returns only failed operations
- [ ] Knowledge graph triples are created correctly
- [ ] Telemetry events are emitted with correct data

---

## Implementation Plan

### Step 1: Create Ontology Extension

**Status:** Pending

**Tasks:**
- [ ] Create `priv/ontologies/elixir_indexing.ttl`
- [ ] Define `jido:IndexingOperation` class
- [ ] Define status classes (Pending, InProgress, Completed, Failed)
- [ ] Define properties (filePath, indexingStatus, tripleCount, errorMessage)
- [ ] Validate ontology with RDF.Turtle

**Files:**
- `priv/ontologies/elixir_indexing.ttl` (new)

---

### Step 2: Create IndexingStatusTracker Module

**Status:** Pending

**Tasks:**
- [ ] Create `lib/jidoka/indexing/indexing_status_tracker.ex`
- [ ] Add GenServer use statement
- [ ] Define state struct with operation maps
- [ ] Add module documentation with examples
- [ ] Implement start_link/1

**Files:**
- `lib/jidoka/indexing/indexing_status_tracker.ex` (new)
- `test/jidoka/indexing/indexing_status_tracker_test.exs` (new)

---

### Step 3: Implement Status Tracking API

**Status:** Pending

**Tasks:**
- [ ] Implement `start_indexing/1` - Add to active_operations
- [ ] Implement `complete_indexing/2` - Move to completed
- [ ] Implement `fail_indexing/2` - Move to failed
- [ ] Implement `get_status/1` - Return status for file
- [ ] Implement `get_project_status/1` - Aggregate by project root
- [ ] Implement `list_failed/0` - Return failed operations

**Files:**
- `lib/jidoka/indexing/indexing_status_tracker.ex` (modify)

---

### Step 4: Implement Knowledge Graph Persistence

**Status:** Pending

**Tasks:**
- [ ] Implement `persist_operation/1` - Write to knowledge graph
- [ ] Use SPARQL INSERT DATA for new operations
- [ ] Generate operation IRI from file path
- [ ] Load existing operations on startup

**Files:**
- `lib/jidoka/indexing/indexing_status_tracker.ex` (modify)

---

### Step 5: Add Telemetry Events

**Status:** Pending

**Tasks:**
- [ ] Add telemetry event functions to `Telemetry` module
- [ ] Emit `indexing_started` on start_indexing
- [ ] Emit `indexing_completed` on complete_indexing
- [ ] Emit `indexing_failed` on fail_indexing

**Files:**
- `lib/jidoka/telemetry.ex` (modify)
- `test/jidoka/telemetry_test.exs` (modify)

---

### Step 6: Add IndexingStatus Signal

**Status:** Pending

**Tasks:**
- [ ] Create `lib/jidoka/signals/indexing_status.ex`
- [ ] Follow existing Signal pattern
- [ ] Add to Signals convenience module

**Files:**
- `lib/jidoka/signals/indexing_status.ex` (new)
- `lib/jidoka/signals.ex` (modify)
- `test/jidoka/signals/indexing_status_test.exs` (new)

---

### Step 7: Add to Supervision Tree

**Status:** Pending

**Tasks:**
- [ ] Update `Application.ex` children list
- [ ] Add IndexingStatusTracker to supervision
- [ ] Add configuration to config.exs

**Files:**
- `lib/jidoka/application.ex` (modify)
- `config/config.exs` (modify)

---

### Step 8: Integration Tests

**Status:** Pending

**Tasks:**
- [ ] Create full indexing workflow test
- [ ] Test status query from knowledge graph
- [ ] Test process restart recovery

**Files:**
- `test/jidoka/integration/indexing_status_integration_test.exs` (new)

---

## Progress Tracking

| Step | Description | Status | Date Completed |
|------|-------------|--------|----------------|
| 1 | Create Ontology Extension | Completed | 2026-02-02 |
| 2 | Create IndexingStatusTracker Module | Completed | 2026-02-02 |
| 3 | Implement Status Tracking API | Completed | 2026-02-02 |
| 4 | Implement Knowledge Graph Persistence | Completed | 2026-02-02 |
| 5 | Add Telemetry Events | Completed | 2026-02-02 |
| 6 | Add IndexingStatus Signal | Completed | 2026-02-02 |
| 7 | Add to Supervision Tree | Completed | 2026-02-02 |
| 8 | Integration Tests | Completed | 2026-02-02 |

## Summary

All 8 steps have been completed successfully. The Indexing Status Tracking feature is now fully implemented with:

- **Ontology Extension** (`priv/ontologies/elixir_indexing.ttl`): Defines semantic structure for indexing status
- **IndexingStatusTracker GenServer** (`lib/jidoka/indexing/indexing_status_tracker.ex`): Core tracking logic with dual-storage approach
- **API Functions**: start_indexing/2, complete_indexing/3, fail_indexing/3, get_status/2, get_project_status/2, list_failed/0, list_in_progress/0, get_operation/2
- **Knowledge Graph Persistence**: SPARQL INSERT DATA operations to persist status to elixir-codebase graph
- **Telemetry Events**: [:jidoka, :indexing, :started|:completed|:failed] events
- **IndexingStatus Signal** (`lib/jidoka/signals/indexing_status.ex`): CloudEvents-compliant signal for status updates
- **Supervision Tree**: Added to main application supervision tree
- **Comprehensive Tests**: 16 unit tests, 8 signal tests, 11 integration tests

### Test Results
- Unit tests: 16/16 passing
- Signal tests: 8/8 passing
- Integration tests: 11/11 passing
- Total: 35/35 tests passing

---

## References

- [Phase 6 Planning Document](/home/ducky/code/agentjido/jidoka/notes/planning/01-foundation/phase-06.md)
- [Knowledge Engine](/home/ducky/code/agentjido/jidoka/lib/jidoka/knowledge/engine.ex)
- [Telemetry Module](/home/ducky/code/agentjido/jidoka/lib/jidoka/telemetry.ex)
- [Signals Module](/home/ducky/code/agentjido/jidoka/lib/jidoka/signals.ex)
