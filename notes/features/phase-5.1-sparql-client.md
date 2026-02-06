# Feature: SPARQL Client Library

**Date:** 2025-01-26
**Branch:** `feature/phase-5.1-sparql-client`
**Status:** Complete

---

## Problem Statement

The jido_coder_lib project requires a SPARQL 1.1 compliant client library to query and update the knowledge graph layer. The existing triple_store backend provides comprehensive SPARQL support, but lacks a clean, high-level API for common operations.

**Current Issues:**
- No unified client interface for SPARQL operations
- Direct triple_store access requires knowledge of internal modules
- No connection pooling or management
- Inconsistent error handling across query types

**Impact:**
- Phase 5 (Knowledge Graph Layer) cannot proceed without SPARQL client
- Memory system cannot integrate with knowledge graph for semantic queries
- Learning capabilities (ontology-based reasoning) are blocked

---

## Solution Overview

Implement `JidoCoderLib.Knowledge.SPARQLClient` module that wraps the triple_store SPARQL functionality with a clean API.

**Key Design Decisions:**
1. **Wrap triple_store.SPARQL modules** - Leverage existing comprehensive implementation
2. **Support 4 query types** - SELECT, CONSTRUCT, ASK, DESCRIBE
3. **Support 3 update operations** - INSERT DATA, DELETE DATA, MODIFY
4. **Connection pooling via Registry** - Process-based connection management
5. **Result format standardization** - Consistent return types across operations

**Architecture:**
```
JidoCoderLib.Knowledge.SPARQLClient
├── query/3         - SELECT, CONSTRUCT, ASK, DESCRIBE
├── update/2        - Generic SPARQL UPDATE
├── insert_data/2   - Helper for INSERT DATA
├── delete_data/2   - Helper for DELETE DATA
├── modify/3        - Helper for MODIFY operations
└── Connection      - GenServer for connection pooling
```

---

## Agent Consultations Performed

| Agent | Topic | Outcome |
|-------|-------|---------|
| **explore** | SPARQL 1.1 specification, RDF.ex capabilities | Provided comprehensive SPARQL query types, result formats, and RDF.ex library patterns |
| **explore** | Triple store backend structure | Identified existing SPARQL modules: Query, Executor, Update operations |

---

## Technical Details

### Module Structure

**Primary Module:** `lib/jido_coder_lib/knowledge/sparql_client.ex`

**API Design:**
```elixir
defmodule JidoCoderLib.Knowledge.SPARQLClient do
  @doc """
  Execute a SPARQL query against the knowledge graph.

  ## Parameters
    - query: SPARQL query string
    - type: :select | :construct | :ask | :describe
    - opts: Keyword list of options

  ## Returns
    - {:ok, result} - Query result (type-dependent)
    - {:error, reason} - Query failed
  """
  @spec query(String.t(), atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def query(query_string, type, opts \\ [])

  @doc """
  Execute a SPARQL UPDATE operation.

  ## Parameters
    - update: SPARQL UPDATE string
    - opts: Keyword list of options

  ## Returns
    - {:ok, :updated} - Update succeeded
    - {:error, reason} - Update failed
  """
  @spec update(String.t(), keyword()) :: {:ok, :updated} | {:error, term()}
  def update(update_string, opts \\ [])

  @doc """
  Insert RDF triples into the knowledge graph.

  ## Parameters
    - triples: List of RDF triples or graph
    - opts: Keyword list of options (e.g., :graph)

  ## Returns
    - {:ok, :inserted} - Insert succeeded
    - {:error, reason} - Insert failed
  """
  @spec insert_data(RDF.Graph.t() | [RDF.Statement.t()], keyword()) :: {:ok, :inserted} | {:error, term()}
  def insert_data(triples, opts \\ [])

  @doc """
  Delete RDF triples from the knowledge graph.

  ## Parameters
    - triples: List of RDF triples or patterns
    - opts: Keyword list of options (e.g., :graph)

  ## Returns
    - {:ok, :deleted} - Delete succeeded
    - {:error, reason} - Delete failed
  """
  @spec delete_data(RDF.Graph.t() | [RDF.Statement.t()], keyword()) :: {:ok, :deleted} | {:error, term()}
  def delete_data(triples, opts \\ [])
end
```

### Dependencies

**Existing (from mix.exs):**
```elixir
{:rdf, "~> 2.0"},
{:sparql, "~> 0.3"},
{:triple_store, path: "/home/ducky/code/triple_store", override: true}
```

**Triple Store Modules to Use:**
- `TripleStore.SPARQL.Query` - Query parsing and validation
- `TripleStore.SPARQL.Executor` - Query execution
- `TripleStore.SPARQL.Update.InsertData` - INSERT operations
- `TripleStore.SPARQL.Update.DeleteData` - DELETE operations
- `TripleStore.SPARQL.Update.Modify` - MODIFY operations

### Connection Management

**Connection Pooling Strategy:**
- Use Registry for process naming and discovery
- Each connection is a GenServer holding triple_store reference
- Support named connections for different graph contexts
- Auto-cleanup on process termination

**Connection Module Structure:**
```elixir
defmodule JidoCoderLib.Knowledge.SPARQLClient.Connection do
  use GenServer

  def start_link(opts)
  def query(pid, query_string, type)
  def update(pid, update_string)

  # Callbacks
  def init(opts)
  def handle_call(:query, from, state)
  def terminate(_reason, _state)
end
```

### Result Format Standardization

**SELECT Query Results:**
```elixir
{:ok, %{
  results: [
    %{variable: "value", ...},
    ...
  ],
  metadata: %{
    count: 10,
    variables: [:variable, ...]
  }
}}
```

**CONSTRUCT Query Results:**
```elixir
{:ok, %RDF.Graph{
  triples: [...]
}}
```

**ASK Query Results:**
```elixir
{:ok, true}  # or {:ok, false}
```

**UPDATE Operation Results:**
```elixir
{:ok, :updated}  # or {:ok, :inserted}, {:ok, :deleted}
```

---

## Success Criteria

### Functional Requirements
- [ ] 5.1.1 Create `JidoCoderLib.Knowledge.SPARQLClient` module
- [ ] 5.1.2 Implement `query/3` for SELECT queries returning tabular results
- [ ] 5.1.3 Implement `query/3` for CONSTRUCT queries returning RDF graphs
- [ ] 5.1.4 Implement `query/3` for ASK queries returning boolean
- [ ] 5.1.5 Implement `update/2` for SPARQL UPDATE operations
- [ ] 5.1.6 Implement `insert_data/2` helper for triple insertion
- [ ] 5.1.7 Implement `delete_data/2` helper for triple deletion
- [ ] 5.1.8 Add connection pooling and management

### Test Coverage
- [ ] SELECT queries return correct result format
- [ ] CONSTRUCT queries build valid RDF graphs
- [ ] ASK queries return proper boolean values
- [ ] INSERT DATA adds triples to graph
- [ ] DELETE DATA removes triples from graph
- [ ] Connection pooling creates and reuses connections
- [ ] Malformed queries are rejected with clear errors
- [ ] Empty result sets are handled correctly

### Code Quality
- [ ] All public functions have @spec annotations
- [ ] All code formatted with `mix format`
- [ ] Module documentation complete
- [ ] Examples in @doc blocks tested as doctests

### Integration
- [ ] Integrates with existing triple_store backend
- [ ] Follows patterns from Memory.Ontology module
- [ ] Error handling consistent with rest of codebase

---

## Implementation Plan

### Step 1: Create SPARQLClient Module Structure

**Status:** Pending

**Tasks:**
- [ ] Create `lib/jido_coder_lib/knowledge/` directory
- [ ] Create `sparql_client.ex` with module definition
- [ ] Add module documentation with examples
- [ ] Define @spec types for all public functions
- [ ] Create basic function stubs

**Files:**
- `lib/jido_coder_lib/knowledge/sparql_client.ex` (new)

---

### Step 2: Implement SELECT Query Support

**Status:** Pending

**Tasks:**
- [ ] Implement `query/3` with `:select` type
- [ ] Call `TripleStore.SPARQL.Executor.execute_query/2`
- [ ] Parse result bindings into standardized format
- [ ] Handle empty result sets
- [ ] Add error handling for malformed queries

**Files:**
- `lib/jido_coder_lib/knowledge/sparql_client.ex` (modify)

---

### Step 3: Implement CONSTRUCT Query Support

**Status:** Pending

**Tasks:**
- [ ] Implement `query/3` with `:construct` type
- [ ] Return RDF.Graph from query results
- [ ] Validate graph structure
- [ ] Add error handling

**Files:**
- `lib/jido_coder_lib/knowledge/sparql_client.ex` (modify)

---

### Step 4: Implement ASK Query Support

**Status:** Pending

**Tasks:**
- [ ] Implement `query/3` with `:ask` type
- [ ] Return boolean result
- [ ] Add error handling

**Files:**
- `lib/jido_coder_lib/knowledge/sparql_client.ex` (modify)

---

### Step 5: Implement UPDATE Operations

**Status:** Pending

**Tasks:**
- [ ] Implement `update/2` for generic SPARQL UPDATE
- [ ] Call `TripleStore.SPARQL.Update` modules
- [ ] Return `{:ok, :updated}` on success
- [ ] Add error handling

**Files:**
- `lib/jido_coder_lib/knowledge/sparql_client.ex` (modify)

---

### Step 6: Implement insert_data and delete_data Helpers

**Status:** Pending

**Tasks:**
- [ ] Implement `insert_data/2` helper
- [ ] Convert RDF.Graph or triple list to SPARQL INSERT DATA
- [ ] Implement `delete_data/2` helper
- [ ] Convert patterns to SPARQL DELETE DATA
- [ ] Add @moduledoc examples

**Files:**
- `lib/jido_coder_lib/knowledge/sparql_client.ex` (modify)

---

### Step 7: Add Connection Pooling

**Status:** Pending

**Tasks:**
- [ ] Create `Connection` GenServer module
- [ ] Add Registry to Application supervision tree
- [ ] Implement connection pooling logic
- [ ] Add connection lifecycle management
- [ ] Update SPARQLClient to use connections

**Files:**
- `lib/jido_coder_lib/knowledge/sparql_client/connection.ex` (new)
- `lib/jido_coder_lib/application.ex` (modify)

---

### Step 8: Write Comprehensive Tests

**Status:** Pending

**Tasks:**
- [ ] Create test file structure
- [ ] Test SELECT queries with various patterns
- [ ] Test CONSTRUCT queries
- [ ] Test ASK queries (true and false cases)
- [ ] Test INSERT DATA operations
- [ ] Test DELETE DATA operations
- [ ] Test connection pooling
- [ ] Test error cases (malformed queries, empty results)

**Files:**
- `test/jido_coder_lib/knowledge/sparql_client_test.exs` (new)
- `test/jido_coder_lib/knowledge/sparql_client/connection_test.exs` (new)

---

## Notes and Considerations

### Dependencies Already Available

The project already has all necessary dependencies:
- `{:rdf, "~> 2.0"}` - RDF data structures
- `{:sparql, "~> 0.3"}` - SPARQL query language support
- `{:triple_store, path: "..."}` - Full SPARQL implementation

This means we can focus on API design rather than low-level SPARQL implementation.

### Integration with Memory System

The `Memory.Ontology` module already converts memory items to RDF triples using the Jido Memory Core ontology. The SPARQL client should:

1. Support querying memory items via SPARQL
2. Support inserting derived knowledge back into the knowledge graph
3. Use consistent namespace conventions (jmem, memory, session)

### Triple Store Backend

The local triple_store at `/home/ducky/code/triple_store` provides:
- Query optimization and execution
- Cost-based query planning
- Full SPARQL 1.1 UPDATE support
- Parser and validator

Our SPARQLClient wraps this functionality, not replaces it.

### Connection Pooling Strategy

Options considered:
1. **Poolboy** - External dependency, heavier weight
2. **Registry-based** - Built-in, lightweight, OTP-compliant (CHOSEN)
3. **Simple GenServer** - No pooling, single connection (not sufficient)

Registry approach allows:
- Named connections for different contexts
- Process-based isolation
- Automatic cleanup
- No additional dependencies

### Future Improvements

1. **DESCRIBE query support** - Not in initial scope but straightforward to add
2. **Federated queries** - Query multiple triple stores
3. **Transaction support** - Batch operations with rollback
4. **Query caching** - Cache frequent query results
5. **Telemetry** - Query performance metrics
6. **Connection health checks** - Monitor connection status

### Testing Strategy

Use RDF.ex's in-memory graph for testing:
- No external triple store required
- Deterministic test results
- Fast test execution
- Easy to set up test data

---

## Progress Tracking

| Step | Description | Status | Date Completed |
|------|-------------|--------|----------------|
| 1 | Create SPARQLClient Module Structure | Pending | - |
| 2 | Implement SELECT Query Support | Pending | - |
| 3 | Implement CONSTRUCT Query Support | Pending | - |
| 4 | Implement ASK Query Support | Pending | - |
| 5 | Implement UPDATE Operations | Pending | - |
| 6 | Implement insert_data/delete_data Helpers | Pending | - |
| 7 | Add Connection Pooling | Pending | - |
| 8 | Write Comprehensive Tests | Pending | - |

---

## References

- [SPARQL 1.1 Query Language](https://www.w3.org/TR/sparql11-query/)
- [SPARQL 1.1 Update](https://www.w3.org/TR/sparql11-update/)
- [RDF.ex Documentation](https://hexdocs.pm/rdf/)
- [Triple Store Backend](/home/ducky/code/triple_store)
- [Phase 5 Plan](/home/ducky/code/agentjido/jido_coder_lib/notes/planning/01-foundation/phase-05.md)
