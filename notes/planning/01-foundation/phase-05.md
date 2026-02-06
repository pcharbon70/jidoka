# Phase 5: Knowledge Graph Layer

This phase implements the Knowledge Graph Layer with SPARQL client, quad-store engine, and named graphs for different types of semantic knowledge. This layer provides the persistent, queryable foundation for both long-term memory and codebase understanding.

---

## 5.1 SPARQL Client Library

- [x] **Task 5.1** Implement SPARQL 1.1 client library (Complete: 2025-01-26)

Create a fully qualified SPARQL client for executing queries and updates against the knowledge graph engine.

- [x] 5.1.1 Create `Jidoka.Knowledge.SPARQLClient` module
- [x] 5.1.2 Implement `query/3` for SELECT queries
- [x] 5.1.3 Implement `query/3` for CONSTRUCT queries
- [x] 5.1.4 Implement `query/3` for ASK queries
- [x] 5.1.5 Implement `update/2` for SPARQL UPDATE operations
- [x] 5.1.6 Implement `insert_data/2` helper
- [x] 5.1.7 Implement `delete_data/2` helper
- [x] 5.1.8 Add connection pooling and management (deferred - handled by triple_store)

**Unit Tests for Section 5.1:**
- [x] Test SELECT queries return correct results
- [x] Test CONSTRUCT queries build graphs
- [x] Test ASK queries return booleans
- [x] Test INSERT DATA adds triples
- [x] Test DELETE DATA removes triples
- [x] Test connection pooling works (deferred)
- [x] Test malformed queries are rejected

---

## 5.2 Knowledge Graph Engine

- [ ] **Task 5.2** Set up the quad-store knowledge graph engine

Configure and start the quad-store backend for storing RDF quads with named graph support.

- [ ] 5.2.1 Select quad-store implementation (RDF.ex with backend)
- [ ] 5.2.2 Create `Jidoka.Knowledge.Engine` module
- [ ] 5.2.3 Implement `start_link/1` for engine initialization
- [ ] 5.2.4 Configure named graph support
- [ ] 5.2.5 Add engine to supervision tree
- [ ] 5.2.6 Implement health checking
- [ ] 5.2.7 Add data migration support

**Unit Tests for Section 5.2:**
- Test engine starts successfully
- Test named graphs can be created
- Test named graphs can be dropped
- Test health checks pass
- Test data migration works

---

## 5.3 Named Graphs Management

- [ ] **Task 5.3** Implement named graphs for different knowledge types

Create and manage the standard named graphs used throughout the system.

- [ ] 5.3.1 Create `Jidoka.Knowledge.NamedGraphs` module
- [ ] 5.3.2 Define `jido:long-term-context` graph for memories
- [ ] 5.3.3 Define `jido:elixir-codebase` graph for code model
- [ ] 5.3.4 Define `jido:conversation-history` graph for conversations
- [ ] 5.3.5 Define `jido:system-knowledge` graph (optional)
- [ ] 5.3.6 Implement `create_graph/1` for initialization
- [ ] 5.3.7 Implement `drop_graph/1` for cleanup
- [ ] 5.3.8 Implement `list_graphs/0` for discovery
- [ ] 5.3.9 Add graph existence checking

**Unit Tests for Section 5.3:**
- Test long-term-context graph is created
- Test elixir-codebase graph is created
- Test conversation-history graph is created
- Test graphs can be dropped
- Test list_graphs returns all graphs
- Test existence checking works

---

## 5.4 Jido Ontology Loading

- [ ] **Task 5.4** Load and integrate the Jido ontology

Import the Jido ontology into the knowledge graph for memory type definitions.

- [ ] 5.4.1 Add Jido ontology .ttl files to priv/ontologies
- [ ] 5.4.2 Implement `load_jido_ontology/0` function
- [ ] 5.4.3 Parse ontology file and insert into system-knowledge graph
- [ ] 5.4.4 Validate ontology loaded correctly
- [ ] 5.4.5 Create ontology lookup helpers
- [ ] 5.4.6 Add ontology version tracking

**Unit Tests for Section 5.4:**
- Test Jido ontology file exists
- Test ontology parses without errors
- Test ontology triples are inserted
- Test ontology validation passes
- Test ontology lookup returns correct classes

---

## 5.5 Triple Store Adapter for LTM

- [ ] **Task 5.5** Implement TripleStoreAdapter for long-term memory

Replace the placeholder LTM adapter with full SPARQL-based implementation.

- [ ] 5.5.1 Create `Jidoka.Memory.LongTerm.TripleStoreAdapter` module
- [ ] 5.5.2 Implement `persist_memory/2` using SPARQL INSERT
- [ ] 5.5.3 Implement `query_memories/2` using SPARQL SELECT
- [ ] 5.5.4 Implement `update_memory/2` using SPARQL UPDATE
- [ ] 5.5.5 Implement `delete_memory/2` using SPARQL DELETE
- [ ] 5.5.6 Use Jido ontology for triple generation
- [ ] 5.5.7 Link memories to WorkSession individuals

**Unit Tests for Section 5.5:**
- Test persist_memory creates correct triples
- Test query_memories finds stored memories
- Test update_memory modifies triples
- Test delete_memory removes triples
- Test WorkSession linking works
- Test session isolation is maintained

---

## 5.6 Knowledge Graph Query Helpers

- [ ] **Task 5.6** Create query helper functions for common patterns

Provide reusable SPARQL query templates for common knowledge operations.

- [ ] 5.6.1 Create `Jidoka.Knowledge.Queries` module
- [ ] 5.6.2 Implement `find_facts/2` for fact retrieval
- [ ] 5.6.3 Implement `find_decisions/2` for decision retrieval
- [ ] 5.6.4 Implement `find_lessons/2` for lesson retrieval
- [ ] 5.6.5 Implement `session_memories/2` for session-scoped queries
- [ ] 5.6.6 Implement `memory_by_type/3` for type-based queries
- [ ] 5.6.7 Implement `recent_memories/2` for temporal queries

**Unit Tests for Section 5.6:**
- Test find_facts returns Fact items
- Test find_decisions returns Decision items
- Test find_lessons returns LessonLearned items
- Test session_memories scopes correctly
- Test memory_by_type filters by type
- Test recent_memories orders by timestamp

---

## 5.7 Knowledge Graph Initialization

- [ ] **Task 5.7** Implement automatic knowledge graph initialization

Set up the knowledge graph layer on application startup.

- [ ] 5.7.1 Create `Jidoka.Knowledge` supervisor
- [ ] 5.7.2 Add engine to supervision tree
- [ ] 5.7.3 Add SPARQL client to supervision tree
- [ ] 5.7.4 Initialize named graphs on startup
- [ ] 5.7.5 Load Jido ontology on startup
- [ ] 5.7.6 Add to Application supervision tree
- [ ] 5.7.7 Create startup health checks

**Unit Tests for Section 5.7:**
- Test Knowledge supervisor starts
- Test engine starts under supervisor
- Test SPARQL client starts under supervisor
- Test named graphs are created on startup
- Test ontology is loaded on startup
- Test health checks pass

---

## 5.8 Phase 5 Integration Tests ✅

Comprehensive integration tests verifying the knowledge graph layer.

- [ ] 5.8.1 Test SPARQL query and update operations
- [ ] 5.8.2 Test named graph creation and management
- [ ] 5.8.3 Test Jido ontology loading and usage
- [ ] 5.8.4 Test TripleStoreAdapter for LTM
- [ ] 5.8.5 Test query helpers for common patterns
- [ ] 5.8.6 Test knowledge graph initialization
- [ ] 5.8.7 Test concurrent SPARQL operations
- [ ] 5.8.8 Test knowledge graph fault tolerance

**Expected Test Coverage:**
- SPARQL Client tests: 25 tests
- Knowledge Graph Engine tests: 15 tests
- Named Graphs tests: 20 tests
- Jido Ontology tests: 15 tests
- TripleStoreAdapter tests: 30 tests
- Query Helpers tests: 25 tests
- Initialization tests: 15 tests

**Total: 145 integration tests**

---

## Success Criteria

1. **SPARQL Support**: Full SPARQL 1.1 query and update capability
2. **Named Graphs**: All standard named graphs created and manageable
3. **Ontology Loaded**: Jido ontology loaded and queryable
4. **LTM Integration**: TripleStoreAdapter replaces placeholder
5. **Query Helpers**: Common patterns have reusable helpers
6. **Initialization**: Knowledge graph initializes on application start
7. **Fault Tolerance**: Engine failures are handled gracefully
8. **Test Coverage**: All knowledge modules have 80%+ test coverage

---

## Critical Files

**New Files:**
- `lib/jidoka/knowledge/sparql_client.ex` - SPARQL client
- `lib/jidoka/knowledge/engine.ex` - Quad-store engine
- `lib/jidoka/knowledge/named_graphs.ex` - Named graph management
- `lib/jidoka/knowledge/queries.ex` - Query helpers
- `lib/jidoka/knowledge/supervisor.ex` - Knowledge layer supervisor
- `lib/jidoka/memory/long_term/triple_store_adapter.ex` - LTM with SPARQL
- `priv/ontologies/jido.ttl` - Jido ontology file
- `test/jidoka/knowledge/sparql_client_test.exs`
- `test/jidoka/knowledge/engine_test.exs`
- `test/jidoka/integration/phase5_test.exs`

**Modified Files:**
- `lib/jidoka/application.ex` - Add Knowledge supervisor
- `lib/jidoka/memory/long_term/session_adapter.ex` - Use TripleStoreAdapter
- `config/config.exs` - Add knowledge graph configuration

**Dependencies:**
- Phase 1: Core Foundation
- Phase 2: Agent Layer Base
- Phase 3: Multi-Session Architecture
- Phase 4: Two-Tier Memory System

---

## Dependencies

**Depends on:**
- Phase 1: Core Foundation (supervision, configuration)
- Phase 3: Multi-Session Architecture (session scoping)
- Phase 4: Two-Tier Memory System (LTM interface)

**Enables:**
- Phase 6: Codebase Semantic Model (uses elixir-codebase graph)
- Phase 7: Conversation History (uses conversation-history graph)
