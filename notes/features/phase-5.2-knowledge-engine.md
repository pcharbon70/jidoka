# Feature: Knowledge Graph Engine

**Date:** 2025-01-26
**Branch:** `feature/phase-5.2-knowledge-engine`
**Status:** In Progress

---

## Problem Statement

The jidoka project requires a supervised knowledge graph engine to provide a persistent, queryable RDF quad-store. The existing triple_store backend provides comprehensive functionality, but needs to be wrapped in a GenServer with proper supervision, health checking, and lifecycle management.

**Current Issues:**
- No supervised process for triple store lifecycle
- No health checking mechanism for the knowledge graph
- No named graph management API
- No data migration support for schema changes
- No integration with application supervision tree

**Impact:**
- Phase 5.3 (Named Graphs) cannot proceed without engine
- Memory system cannot persist to knowledge graph
- Codebase semantic model (Phase 6) has no storage layer

---

## Solution Overview

Implement `Jidoka.Knowledge.Engine` GenServer that wraps the triple_store backend with proper OTP supervision.

**Key Design Decisions:**
1. **Use existing triple_store** - Leverages comprehensive RDF/SPARQL implementation
2. **GenServer wrapper** - Provides OTP lifecycle and supervision
3. **Named graph IRI management** - Standard IRIs for system graphs
4. **Health checking** - Periodic verification of store availability
5. **Graceful shutdown** - Proper resource cleanup on termination
6. **Migration support** - Version-controlled schema updates

**Architecture:**
```
Jidoka.Knowledge.Engine (GenServer)
├── start_link/1        - Initialize engine with config
├── health/0            - Check engine health
├── stats/0             - Get store statistics
├── backup/1            - Create backup
├── close/0             - Graceful shutdown
├── Named Graph API:
│   ├── create_graph/1  - Create named graph
│   ├── drop_graph/1    - Drop named graph
│   ├── list_graphs/0   - List all graphs
│   └── graph_exists/1  - Check graph existence
└── Migration API:
    ├── current_version/0 - Get schema version
    ├── migrate/0        - Run migrations
    └── rollback/1       - Rollback to version
```

---

## Agent Consultations Performed

| Agent | Topic | Outcome |
|-------|-------|---------|
| **explore** | TripleStore.open/2 API, store lifecycle | Provided store initialization options, health checking, and close patterns |
| **explore** | Application supervision tree | Identified existing supervision structure and insertion point for Engine |

---

## Technical Details

### Module Structure

**Primary Module:** `lib/jidoka/knowledge/engine.ex`

**API Design:**
```elixir
defmodule Jidoka.Knowledge.Engine do
  @moduledoc """
  GenServer wrapper for triple_store backend.

  Manages the lifecycle of the RDF quad-store with proper OTP supervision,
  health checking, and named graph management.
  """

  use GenServer

  # Public API
  def start_link(opts)
  def health(pid)
  def stats(pid)
  def backup(pid, path)
  def close(pid)

  # Named Graph API
  def create_graph(pid, graph_name)
  def drop_graph(pid, graph_name)
  def list_graphs(pid)
  def graph_exists(pid, graph_name)

  # Migration API
  def current_version(pid)
  def migrate(pid)
  def rollback(pid, version)

  # Callbacks
  def init(opts)
  def handle_call(request, from, state)
  def handle_info(msg, state)
  def terminate(reason, state)
end
```

### Configuration

**Application Config:**
```elixir
config :jidoka, :knowledge_engine,
  # Data directory for triple store
  data_dir: "data/knowledge_graph",
  # Enable health checking
  enable_health_check: true,
  # Health check interval (milliseconds)
  health_check_interval: 30_000,
  # Enable named graph support
  named_graphs: true,
  # Standard named graphs
  standard_graphs: [
    "jido:long-term-context",
    "jido:elixir-codebase",
    "jido:conversation-history",
    "jido:system-knowledge"
  ]
```

### Dependencies

**Existing (from mix.exs):**
```elixir
{:rdf, "~> 2.0"},
{:sparql, "~> 0.3"},
{:triple_store, path: "/home/ducky/code/triple_store", override: true}
```

**TripleStore API Used:**
- `TripleStore.open/2` - Open/create store
- `TripleStore.close/1` - Close store
- `TripleStore.health/1` - Health check
- `TripleStore.stats/1` - Statistics
- `TripleStore.backup/2` - Backup

### Named Graph IRIs

Standard graph names use the `jido:` prefix:

| Name | IRI | Purpose |
|------|-----|---------|
| long-term-context | `https://jido.ai/graphs/long-term-context` | Persistent memories |
| elixir-codebase | `https://jido.ai/graphs/elixir-codebase` | Code model |
| conversation-history | `https://jido.ai/graphs/conversation-history` | Conversations |
| system-knowledge | `https://jido.ai/graphs/system-knowledge` | Ontologies |

---

## Success Criteria

### Functional Requirements
- [x] 5.2.1 Select quad-store implementation (RDF.ex with triple_store backend)
- [x] 5.2.2 Create `Jidoka.Knowledge.Engine` module
- [x] 5.2.3 Implement `start_link/1` for engine initialization
- [x] 5.2.4 Configure named graph support
- [x] 5.2.5 Add engine to supervision tree
- [x] 5.2.6 Implement health checking
- [ ] 5.2.7 Add data migration support (deferred to future work)

### Test Coverage
- [x] Engine starts successfully (16 tests passing)
- [x] Named graphs can be created
- [ ] Named graphs can be dropped (skipped - requires SPARQL parser fix)
- [x] Health checks pass
- [ ] Data migration works (deferred to future work)

### Code Quality
- [x] All public functions have @spec annotations
- [x] All code formatted with `mix format`
- [x] Module documentation complete
- [ ] Examples in @doc blocks tested as doctests (deferred)

### Integration
- [x] Engine starts under Application supervisor
- [x] SPARQLClient can use Engine context
- [ ] Named graph functions work with SPARQL queries (partially - SPARQL parser has alias issue)

---

## Implementation Plan

### Step 1: Create Engine Module Structure

**Status:** Complete

**Tasks:**
- [x] Create `lib/jidoka/knowledge/engine.ex`
- [x] Add GenServer use statement
- [x] Define state struct
- [x] Add module documentation
- [x] Add @spec types

**Files:**
- `lib/jidoka/knowledge/engine.ex` (new)

---

### Step 2: Implement start_link/1

**Status:** Complete

**Tasks:**
- [x] Implement `init/1` callback
- [x] Call `TripleStore.open/2` with data directory
- [x] Store database and dict_manager in state
- [x] Initialize standard named graphs
- [x] Handle open failures gracefully

**Files:**
- `lib/jidoka/knowledge/engine.ex` (modify)

---

### Step 3: Configure Named Graph Support

**Status:** Pending

**Tasks:**
- [ ] Define standard graph IRI constants
- [ ] Implement `create_graph/2`
- [ ] Implement `drop_graph/2`
- [ ] Implement `list_graphs/1`
- [ ] Implement `graph_exists/2`
- [ ] Initialize standard graphs on startup

**Files:**
- `lib/jidoka/knowledge/engine.ex` (modify)

---

### Step 4: Implement Health Checking

**Status:** Pending

**Tasks:**
- [ ] Implement `health/1` public API
- [ ] Implement periodic health check in `handle_info`
- [ ] Call `TripleStore.health/1`
- [ ] Publish telemetry events for health status
- [ ] Handle health check failures

**Files:**
- `lib/jidoka/knowledge/engine.ex` (modify)

---

### Step 5: Implement Statistics and Backup

**Status:** Pending

**Tasks:**
- [ ] Implement `stats/1` API
- [ ] Implement `backup/2` API
- [ ] Return formatted statistics map
- [ ] Handle backup failures

**Files:**
- `lib/jidoka/knowledge/engine.ex` (modify)

---

### Step 6: Implement Migration Support

**Status:** Pending

**Tasks:**
- [ ] Define migration version schema
- [ ] Implement `current_version/1`
- [ ] Implement `migrate/1`
- [ ] Implement `rollback/2`
- [ ] Create initial migration (v1: create standard graphs)

**Files:**
- `lib/jidoka/knowledge/engine.ex` (modify)
- `lib/jidoka/knowledge/migrations.ex` (new)

---

### Step 7: Add to Supervision Tree

**Status:** Pending

**Tasks:**
- [ ] Update `Application.ex` children list
- [ ] Add Engine to supervision tree
- [ ] Update supervision tree documentation
- [ ] Add engine configuration to config.exs

**Files:**
- `lib/jidoka/application.ex` (modify)
- `config/config.exs` (modify)

---

### Step 8: Write Tests

**Status:** Pending

**Tasks:**
- [ ] Create test file structure
- [ ] Test engine starts successfully
- [ ] Test named graph creation/dropping
- [ ] Test health checks
- [ ] Test statistics retrieval
- [ ] Test migration functionality
- [ ] Test graceful shutdown

**Files:**
- `test/jidoka/knowledge/engine_test.exs` (new)

---

## Notes and Considerations

### Triple Store Backend Selection

The **triple_store** local dependency is selected as the quad-store implementation because:

1. **Comprehensive SPARQL 1.1 support** - Full query and update capabilities
2. **RocksDB persistence** - Fast, durable storage via Rust NIFs
3. **OWL 2 RL reasoning** - Built-in materialization
4. **Quad store support** - Named graphs out of the box
5. **Active development** - Already part of the project dependencies

Alternative considered:
- **RDF.ex only** - In-memory only, not suitable for production

### Data Directory

The engine will store data in:
- Development: `./data/knowledge_graph/dev`
- Test: `./data/knowledge_graph/test`
- Production: Configurable via environment variable

### Named Graph Implementation

Named graphs are implemented as SPARQL graph IRIs. The engine provides:
- Helper functions to convert short names (`:long_term_context`) to full IRIs
- Initialization of standard graphs on startup
- Existence checking via SPARQL ASK queries

Example:
```elixir
# Short name to IRI
def graph_name_to_iri(:long_term_context),
  do: RDF.iri("https://jido.ai/graphs/long-term-context")

# Check existence
def graph_exists?(pid, name) do
  query = "ASK { GRAPH <#{graph_name_to_iri(name)}> { ?s ?p ?o } }"
  # Execute query...
end
```

### Health Check Strategy

Health checks run periodically (default: 30 seconds) and:
1. Call `TripleStore.health/1` to verify store integrity
2. Publish telemetry events for monitoring
3. Log warnings for degraded health
4. Continue operation on minor issues

### Migration System

Migrations are versioned and stored in the triple store itself:
- Version stored as a triple in `system-knowledge` graph
- Migrations are SPARQL UPDATE files or Elixir functions
- Rollback support via version decrement

### Future Improvements

1. **Clustering** - Multiple engine nodes with data sharding
2. **Replication** - Master-replica setup for high availability
3. **Snapshots** - Point-in-time snapshots for quick recovery
4. **Compression** - Reduce disk usage for large graphs
5. **Query cache** - Cache frequent query results

---

## Progress Tracking

| Step | Description | Status | Date Completed |
|------|-------------|--------|----------------|
| 1 | Create Engine Module Structure | Pending | - |
| 2 | Implement start_link/1 | Pending | - |
| 3 | Configure Named Graph Support | Pending | - |
| 4 | Implement Health Checking | Pending | - |
| 5 | Implement Statistics and Backup | Pending | - |
| 6 | Implement Migration Support | Pending | - |
| 7 | Add to Supervision Tree | Pending | - |
| 8 | Write Tests | Pending | - |

---

## References

- [TripleStore Documentation](/home/ducky/code/triple_store)
- [SPARQL 1.1 Query Language](https://www.w3.org/TR/sparql11-query/)
- [RDF.ex Documentation](https://hexdocs.pm/rdf/)
- [Phase 5 Plan](/home/ducky/code/agentjido/jidoka/notes/planning/01-foundation/phase-05.md)
- [GenServer Documentation](https://hexdocs.pm/elixir/GenServer.html)
