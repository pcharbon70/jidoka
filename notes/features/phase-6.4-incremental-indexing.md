# Phase 6.4: Incremental Indexing

**Date:** 2026-02-04
**Branch:** `feature/incremental-indexing`
**Status:** Completed
**Phase:** 6.4 from Phase 6 (Codebase Semantic Model)

---

## Problem Statement

The CodeIndexer (Phase 6.2) can index Elixir source code into the `:elixir_codebase` named graph. However, when files are modified during development, there's no efficient way to update only the changed portions of the index. This causes:
- Stale data in the knowledge graph (old versions of modules/functions)
- Need to re-index entire projects for single-file changes
- Inefficient for development workflows with frequent edits
- Potential for orphaned triples when files are deleted

**Current State:**
- `index_file/2` - Indexes a single file
- `index_project/2` - Indexes entire projects
- `reindex_file/2` - Calls `remove_file_triples/1` then `index_file/2` (basic implementation exists)
- `remove_file/2` - Calls `remove_file_triples/1` (basic implementation exists)
- IndexingStatusTracker tracks operation status

**Issues with Current Implementation:**
1. `remove_file_triples/1` only removes triples where file IRI is direct subject/object
2. Doesn't cascade delete modules, functions, structs defined in the file
3. elixir-ontologies uses blank nodes for many entities, making deletion harder
4. No clear way to find all triples associated with a given source file

**Impact:**
- Re-indexing leaves orphaned triples in the graph
- Query results may contain stale/outdated information
- Knowledge graph grows indefinitely with stale data
- Cannot reliably track code changes over time

---

## Solution Overview

Implement proper incremental indexing by:
1. Finding all entities (modules, functions, etc.) defined in a source file
2. Cascading deletion to remove all related triples
3. Ensuring reindexing properly cleans up before inserting new data

**Key Design Decisions:**

1. **Parse Source Files for Module Names**: Since elixir-ontologies doesn't link modules to source files directly, we parse files using AST to extract module names
2. **Delete by Module IRI**: Construct module IRIs (`https://jido.ai/code#{ModuleName}`) and delete all triples with those IRIs
3. **Code Graph Purity**: Removed IndexingOperation triples from code graph - code graph now only contains ontology-derived triples
4. **In-Memory Tracking Only**: IndexingStatusTracker no longer persists to knowledge graph

---

## Implementation

### Step 1: Analyze elixir-ontologies Data Model

**Discovery**: elixir-ontologies does NOT link modules to source files. Modules have IRIs like `https://jido.ai/code#ModuleName`. Functions are blank nodes with `belongsTo` relationship to modules.

### Step 2: Implement File Parsing

Added `parse_file_for_modules/1` to extract module names from source files:
- Uses `Code.string_to_quoted/2` for AST parsing
- Traverses AST to find `defmodule` nodes
- Extracts module names for IRI construction

### Step 3: Implement Cascade Delete by Module IRI

Added `delete_module_triples/3` to delete all triples for a module:
- DELETE query for subject position (module's properties)
- DELETE query for object position (references to module)
- Handles functions (blank nodes with `belongsTo`)

### Step 4: Remove IndexingOperation from Code Graph

**Key Decision**: IndexingOperations should NOT be in the code graph. The code graph should only contain:
- Ontology-derived triples
- Individuals representing current source code

**Changes:**
- `IndexingStatusTracker`: Removed all persistence logic
- `CodeIndexer`: Removed `delete_indexing_operation_triples`
- Both files now only track status in-memory

### Step 5: Update remove_file_triples/2

- Now parses file to get module names
- Constructs module IRIs
- Deletes all triples for each module
- Uses `state.base_iri` from struct

---

## Files Modified

1. **lib/jido_coder_lib/indexing/code_indexer.ex**
   - Added `@default_base_iri` module attribute
   - Added `base_iri` to GenServer state
   - Added `parse_file_for_modules/1` - Parse file for module names
   - Added `extract_module_names/1` - Extract modules from source code
   - Added `extract_modules_from_ast/2` - Traverse AST for defmodule
   - Added `delete_module_triples/3` - Delete all triples for a module IRI
   - Updated `remove_file_triples/2` - Parse and delete by module IRI
   - Removed `delete_indexing_operation_triples` function

2. **lib/jido_coder_lib/indexing/indexing_status_tracker.ex**
   - Removed `persist_operation` calls from all handlers
   - Removed unused helper functions (`persist_operation`, `operation_iri`, `status_iri`, `graph_iri`, `engine_context`, `escape_string`)
   - Removed unused imports
   - Updated moduledoc

---

## Success Criteria

- [x] 6.4.1 Implement `reindex_file/2` for updating existing files
- [x] 6.4.2 Implement `remove_file/1` for deleted files
- [x] 6.4.3 Delete old triples before inserting new ones
- [x] 6.4.4 Update affected dependencies (N/A - no external dependencies)
- [x] 6.4.5 Add indexing status tracking
- [x] All tests passing (34/34)

---

## Progress Tracking

| Step | Description | Status | Date Completed |
|------|-------------|--------|----------------|
| 1 | Analyze elixir-ontologies data model | Completed | 2026-02-04 |
| 2 | Implement cascade delete | Completed | 2026-02-04 |
| 3 | Improve reindex_file/2 | Completed | 2026-02-04 |
| 4 | Update remove_file/2 | Completed | 2026-02-04 |
| 5 | Write tests | Completed | 2026-02-04 |

---

## Test Results

All 34 tests passing:
- `test/jido_coder_lib/indexing/code_indexer_test.exs` - All tests pass
- `test/jido_coder_lib/indexing/indexing_status_tracker_test.exs` - All tests pass
