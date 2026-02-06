# Phase 6.6: Codebase Query Interface

**Date:** 2026-02-03
**Branch:** `feature/codebase-queries`
**Status:** Complete
**Phase:** 6.6 from Phase 6 (Codebase Semantic Model)

---

## Problem Statement

The CodeIndexer (Phase 6.2) now indexes Elixir source code into the `:elixir_codebase` named graph. However, to query the indexed code, users must write raw SPARQL queries against the knowledge graph. This is:

- **Error-prone**: Syntax errors, incorrect IRIs, malformed queries
- **Verbose**: Requires knowledge of RDF/SPARQL and the Elixir ontology structure
- **Inconvenient**: Cannot easily answer common questions like "find all functions in module X" or "what modules implement protocol Y"

**Current State:**
- CodeIndexer successfully indexes code as RDF triples
- Triples stored in `:elixir_codebase` named graph
- Elixir ontology classes defined (Module, Function, Struct, Protocol, Behaviour, Macro)
- No high-level query interface for common codebase questions

**Impact:**
- LLM agents cannot easily query codebase structure
- Code analysis features require manual SPARQL construction
- Risk of query errors increases with complexity
- Cannot efficiently support code navigation, refactoring tools, or dependency analysis

---

## Solution Overview

Create a `JidoCoderLib.Codebase.Queries` module that provides high-level query functions for common codebase questions. This module follows the pattern established by `JidoCoderLib.Knowledge.Queries` (Phase 5.6) but focuses on Elixir code constructs rather than memory types.

**Key Design Decisions:**

1. **Convenience Functions**: Type-safe wrappers around common SPARQL patterns for code queries
2. **Composable Queries**: Options-based filtering with sensible defaults (limit, offset, filters)
3. **Result Transformation**: Convert SPARQL results to clean Elixir maps with domain-relevant keys
4. **Graph Isolation**: All queries scoped to `:elixir_codebase` named graph
5. **Ontology Alignment**: Use elixir-ontologies structure classes and properties consistently
6. **IRI Management**: Leverage existing `Ontology` module for class IRIs and individual creation

---

## Implementation Notes

### SPARQL Compatibility Workarounds

During implementation, several SPARQL compatibility issues with the triple_store were identified and worked around:

1. **VALUES clause not supported**: The `get_index_stats/1` function was rewritten to use separate queries for each entity type instead of a VALUES clause.

2. **UNION with type detection**: Functions have both `Function` and `PublicFunction`/`PrivateFunction` types. Using UNION with OPTIONAL returns multiple rows per function. Fixed by querying PublicFunction and PrivateFunction separately and combining results.

3. **Result extraction**: SPARQL results are returned as maps with string keys. Helper functions properly extract values from the triple store term format (e.g., `{:literal, :simple, value}`).

### elixir-ontologies Integration Notes

- elixir-ontologies stores each function with TWO rdf:type statements: one for `Function` and one for `PublicFunction` or `PrivateFunction`
- Protocols, behaviours, and structs are indexed as part of module definitions, not as separate entities
- Module and function names are stored using the `struct:moduleName` and `struct:functionName` properties
- Private functions are indexed with type `struct:PrivateFunction`

---

## Success Criteria

- [x] 6.6.1 Create `JidoCoderLib.Codebase.Queries` module
- [x] 6.6.2 Implement `find_module/2` for module lookup
- [x] 6.6.3 Implement `find_function/4` for function lookup
- [x] 6.6.4 Implement `get_call_graph/2` for call relationships
- [x] 6.6.5 Implement `get_dependencies/2` for dependency queries
- [x] 6.6.6 Implement `find_implementations/2` for protocol queries
- [x] 6.6.7 Implement `list_modules/1` for module listing
- [x] All tests passing (28 tests, 0 failures, 7 skipped)

---

## Progress Tracking

| Step | Description | Status | Date Completed |
|------|-------------|--------|----------------|
| 1 | Create Codebase.Queries Module Structure | Complete | 2026-02-03 |
| 2 | Implement Module Query Functions | Complete | 2026-02-03 |
| 3 | Implement Function Query Functions | Complete | 2026-02-03 |
| 4 | Implement Relationship Query Functions | Complete | 2026-02-03 |
| 5 | Implement Protocol Query Functions | Complete | 2026-02-03 |
| 6 | Implement Behaviour Query Functions | Complete | 2026-02-03 |
| 7 | Implement Struct Query Functions | Complete | 2026-02-03 |
| 8 | Implement Utility Query Functions | Complete | 2026-02-03 |
| 9 | Write Tests | Complete | 2026-02-03 |

---

## Files Created/Modified

### Created Files
- `lib/jido_coder_lib/codebase/queries.ex` - Main query interface module
- `test/jido_coder_lib/codebase/queries_test.exs` - Comprehensive test suite

### Modified Files
- `lib/jido_coder_lib/indexing/code_indexer.ex` - Fixed base_iri configuration to pass individual options instead of config struct
