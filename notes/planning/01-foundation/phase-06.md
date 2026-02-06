# Phase 6: Codebase Semantic Model

This phase implements the codebase semantic model using the Elixir ontology. The codebase is parsed, analyzed, and stored as RDF triples in the `jido:elixir-codebase` named graph, enabling sophisticated semantic queries about code structure, dependencies, and patterns.

---

## 6.1 Elixir Ontology Integration

- [x] **Task 6.1** Load and integrate the Elixir ontology (Complete: 2026-02-02)

Import the Elixir ontology for representing code constructs.

- [x] 6.1.1 Add Elixir ontology .ttl files to priv/ontologies
- [x] 6.1.2 Implement `load_elixir_ontology/0` function
- [x] 6.1.3 Parse ontology and insert into system-knowledge graph
- [x] 6.1.4 Create ontology class helpers (Module, Function, Struct, etc.)
- [x] 6.1.5 Create ontology property helpers
- [x] 6.1.6 Validate ontology loaded correctly

**Unit Tests for Section 6.1:**
- [x] Test Elixir ontology file exists
- [x] Test ontology parses without errors
- [x] Test ontology classes are accessible
- [x] Test ontology properties are accessible
- [x] Test ontology validation passes

---

## 6.2 Code Indexer (Integration with elixir-ontologies)

- [x] **Task 6.2** Implement code indexing process using elixir-ontologies library (Complete: 2026-02-03)

Create a GenServer wrapper around the `elixir-ontologies` library for indexing Elixir source files.

**Architecture Note:** The `elixir-ontologies` library already provides comprehensive AST parsing, extraction, and RDF generation. Our CodeIndexer acts as an integration layer that:
1. Calls `ElixirOntologies.analyze_project/2` and `analyze_file/2`
2. Inserts the resulting RDF graph into our `:elixir_codebase` named graph
3. Tracks indexing status via `IndexingStatusTracker`
4. Provides a convenient GenServer API for on-demand indexing

- [x] 6.2.1 Create `Jidoka.Indexing.CodeIndexer` GenServer
- [x] 6.2.2 Implement `index_project/1` wrapping `ElixirOntologies.analyze_project/2`
- [x] 6.2.3 Implement `index_file/2` wrapping `ElixirOntologies.analyze_file/2`
- [x] 6.2.4 Convert RDF.Graph to triple_store quad format
- [x] 6.2.5 Insert triples into elixir-codebase named graph
- [x] 6.2.6 Integrate with IndexingStatusTracker for status updates
- [x] 6.2.7 Add to supervision tree
- [x] 6.2.8 Handle errors gracefully (invalid syntax, missing files)

**Unit Tests for Section 6.2:**
- [x] Test CodeIndexer starts successfully
- [x] Test index_project processes all files
- [x] Test index_file processes single file
- [x] Test RDF graph conversion to quads
- [x] Test triples inserted to correct named graph
- [x] Test IndexingStatusTracker integration
- [x] Test error handling for invalid syntax

---

## 6.4 Incremental Indexing

- [x] **Task 6.4** Implement incremental indexing for file changes (Complete: 2026-02-04)

Update the code model incrementally when files change.

- [x] 6.4.1 Implement `reindex_file/2` for updating existing files
- [x] 6.4.2 Implement `remove_file/1` for deleted files
- [x] 6.4.3 Delete old triples before inserting new ones
- [x] 6.4.4 Update affected dependencies (N/A - no external dependencies)
- [x] 6.4.5 Add indexing status tracking

**Unit Tests for Section 6.4:**
- [x] Test reindex_file updates triples correctly
- [x] Test remove_file deletes all related triples
- [x] Test dependencies are updated
- [x] Test indexing status is tracked

**Status:** Complete - 34 tests passing, 0 failures

---

## 6.5 File System Integration

- [x] **Task 6.5** Integrate with file system watching (Complete: 2026-02-04)

Connect the code indexer to file system events for automatic updates.

- [x] 6.5.1 Subscribe to file system change events
- [x] 6.5.2 Filter for .ex and .ex files
- [x] 6.5.3 Trigger indexing on file changes
- [x] 6.5.4 Debounce rapid file changes
- [x] 6.5.5 Handle indexing errors gracefully

**Unit Tests for Section 6.5:**
- [x] Test file system events trigger indexing
- [x] Test filtering works correctly
- [x] Test debouncing prevents excessive indexing
- [x] Test errors don't crash the indexer

**Status:** Complete - 22 tests passing, 0 failures

---

## 6.6 Codebase Query Interface

- [x] **Task 6.6** Create query interface for codebase knowledge (Complete: 2026-02-03)

Provide high-level queries for common codebase questions.

- [x] 6.6.1 Create `Jidoka.Codebase.Queries` module
- [x] 6.6.2 Implement `find_module/2` for module lookup
- [x] 6.6.3 Implement `find_function/3` for function lookup
- [x] 6.6.4 Implement `get_call_graph/2` for call graph queries
- [x] 6.6.5 Implement `get_dependencies/2` for dependency queries
- [x] 6.6.6 Implement `find_implementations/2` for protocol queries
- [x] 6.6.7 Implement `list_modules/1` for module listing

**Unit Tests for Section 6.6:**
- [x] Test find_module returns module data
- [x] Test find_function finds functions by name
- [x] Test get_call_graph returns call relationships
- [x] Test get_dependencies returns module dependencies
- [x] Test find_implementations finds protocol implementations
- [x] Test list_modules returns all modules

**Status:** Complete - 28 tests passing, 0 failures, 7 skipped

---

## 6.7 ContextManager Integration

- [x] **Task 6.7** Integrate codebase queries into context building (Complete: 2026-02-04)

Use the semantic code model when building LLM context.

- [x] 6.7.1 Update ContextManager to use codebase queries
- [x] 6.7.2 Add project structure context from graph
- [x] 6.7.3 Add dependency information to context
- [x] 6.7.4 Add relevant module information to context
- [x] 6.7.5 Cache codebase query results

**Unit Tests for Section 6.7:**
- [x] Test ContextManager uses codebase queries
- [x] Test project structure is included in context
- [x] Test dependencies are included in context
- [x] Test relevant modules are found
- [x] Test caching improves performance

**Status:** Complete - 22 tests passing, 0 failures

---

## 6.8 Phase 6 Integration Tests ✅

Comprehensive integration tests verifying the codebase semantic model.

- [x] 6.8.1 Test full project indexing
- [x] 6.8.2 Test AST to RDF mapping accuracy
- [x] 6.8.3 Test incremental indexing updates
- [x] 6.8.4 Test file system integration
- [x] 6.8.5 Test codebase query interface
- [x] 6.8.6 Test context building integration
- [x] 6.8.7 Test concurrent indexing operations
- [x] 6.8.8 Test indexing error recovery

**Test Coverage:**
- Phase 6 Integration Tests: 21 tests passing (completed in Phase 6.8)

**Status:** Complete - 21 integration tests passing, 0 failures

---

## Success Criteria

1. **Ontology Loaded**: Elixir ontology is loaded and accessible
2. **Project Indexed**: Full project can be indexed to knowledge graph
3. **AST Mapping**: Code structures map to correct ontology triples
4. **Incremental Updates**: File changes trigger incremental updates
5. **Query Interface**: Common queries are available and efficient
6. **Context Integration**: Code model enriches LLM context
7. **Error Handling**: Invalid code doesn't crash the indexer
8. **Test Coverage**: All indexing modules have 80%+ test coverage

---

## Critical Files

**New Files:**
- `lib/jidoka/indexing/code_indexer.ex` - Code indexing GenServer (wraps elixir-ontologies)
- `lib/jidoka/codebase/queries.ex` - Codebase query interface
- `test/jidoka/indexing/code_indexer_test.exs`
- `test/jidoka/integration/phase6_test.exs`

**Modified Files:**
- `lib/jidoka/knowledge/named_graphs.ex` - Already has elixir-codebase graph defined
- `lib/jidoka/agents/context_manager.ex` - Integrate codebase queries
- `lib/jidoka/application.ex` - Add CodeIndexer to supervision

**Dependencies:**
- Phase 1: Core Foundation
- Phase 5: Knowledge Graph Layer
- `elixir-ontologies` library (already in mix.exs as path dependency)

---

## Dependencies

**Depends on:**
- Phase 1: Core Foundation (supervision, file access)
- Phase 5: Knowledge Graph Layer (SPARQL, named graphs)

**Enables:**
- Phase 7: Conversation History (can reference code entities)
