# Phase 6.7: ContextManager Integration with Codebase

**Date:** 2026-02-04
**Branch:** `feature/contextmanager-integration`
**Status:** Completed
**Phase:** 6.7 from Phase 6 (Codebase Semantic Model)

---

## Problem Statement

The ContextManager builds LLM context from conversation history and active files, but it doesn't leverage the indexed codebase knowledge. This means:
- LLM lacks semantic information about the codebase
- No automatic discovery of related modules
- Missing dependency information in context
- Inefficient context building (manual file selection)

**Current State:**
- ContextManager builds context from conversation, files, and working_context
- CodeIndexer indexes code into `:elixir_codebase` graph
- Codebase.Queries provides high-level query interface
- No integration between ContextManager and Codebase.Queries

**Desired State:**
- ContextManager uses Codebase.Queries for intelligent context building
- Automatic inclusion of related modules based on active files
- Dependency information available in context
- Cached query results for performance

---

## Solution Overview

Created CodebaseContext module and integrated it with ContextManager:
1. New `CodebaseContext` module with caching
2. Module info retrieval with caching
3. Related module discovery
4. Dependency chain building
5. Integration with ContextManager's `build_context`
6. Graceful fallback when codebase not indexed

**Key Design Decisions:**

1. **Separate Module**: Created `CodebaseContext` as a separate GenServer for caching
2. **Opt-in Integration**: Codebase context is opt-in via `:codebase` in include list
3. **ETS Caching**: Use ETS table for query results with periodic cleanup
4. **Graceful Degradation**: Return empty context instead of errors when codebase unavailable
5. **Configurable Depth**: Control how deep to follow dependencies

---

## Technical Details

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ContextManager                           │
│  - build_context/3                                          │
│  - Includes: [:conversation, :files, :codebase]            │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              CodebaseContext (GenServer)                    │
│  - enrich/2                                                 │
│  - get_module_info/2                                        │
│  - find_related/2                                          │
│  - get_dependencies/2                                       │
│  - ETS cache table                                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                 Codebase.Queries                            │
│  - find_module/2                                            │
│  - list_modules/1                                           │
│  - get_dependencies/2                                       │
│  - find_function/3                                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              :elixir_codebase Graph                         │
│  - Indexed modules, functions, dependencies                 │
└─────────────────────────────────────────────────────────────┘
```

### File Location

- New Module: `Jidoka.Agents.CodebaseContext`
- File: `lib/jidoka/agents/codebase_context.ex`
- Modified: `lib/jidoka/agents/context_manager.ex`
- Tests: `test/jidoka/agents/codebase_context_test.exs`

### Dependencies

- Depends on: Codebase.Queries (Phase 6.6)
- Depends on: ContextManager (Phase 3.4)
- Uses: ETS for caching
- Error handling: Graceful fallback when codebase not indexed

---

## Implementation

### Step 1: Create CodebaseContext Module

**File:** `lib/jidoka/agents/codebase_context.ex`

- [x] 1.1 Create module with cache table
- [x] 1.2 Implement `start_link/1` for cache management
- [x] 1.3 Implement `get_module_info/2` - Get module info with caching
- [x] 1.4 Implement `find_related/2` - Find modules related to files
- [x] 1.5 Implement `get_dependencies/2` - Get dependency chain
- [x] 1.6 Implement `enrich/2` - Build context from files
- [x] 1.7 Implement cache invalidation

### Step 2: Integrate with ContextManager

**File:** `lib/jidoka/agents/context_manager.ex`

- [x] 2.1 Add `:codebase` to valid include types
- [x] 2.2 Add codebase context building to `handle_call`
- [x] 2.3 Implement `build_codebase_context/2`
- [x] 2.4 Add options for codebase context (depth, limit)
- [x] 2.5 Handle graceful fallback when queries fail

### Step 3: Add Context Building Logic

**File:** `lib/jidoka/agents/codebase_context.ex`

- [x] 3.1 Extract module names from active file paths
- [x] 3.2 Query module information from codebase
- [x] 3.3 Build dependency tree with configurable depth
- [x] 3.4 Format results for LLM consumption
- [x] 3.5 Add project structure summary

### Step 4: Implement Caching

**File:** `lib/jidoka/agents/codebase_context.ex`

- [x] 4.1 Create ETS table for query results
- [x] 4.2 Cache module info by module name
- [x] 4.3 Cache dependency results
- [x] 4.4 Implement TTL for cache entries (periodic cleanup)
- [x] 4.5 Provide cache invalidation interface

### Step 5: Write Tests

**File:** `test/jidoka/agents/codebase_context_test.exs`

- [x] 5.1 Test module info retrieval with caching
- [x] 5.2 Test related module discovery
- [x] 5.3 Test dependency chain building
- [x] 5.4 Test cache hit/miss
- [x] 5.5 Test graceful fallback
- [x] 5.6 Test integration with ContextManager

---

## Success Criteria

- [x] 6.7.1 Update ContextManager to use codebase queries
- [x] 6.7.2 Add project structure context from graph
- [x] 6.7.3 Add dependency information to context
- [x] 6.7.4 Add relevant module information to context
- [x] 6.7.5 Cache codebase query results
- [x] All tests passing (22/22)

---

## Progress Tracking

| Step | Description | Status | Date Completed |
|------|-------------|--------|----------------|
| 1 | Create CodebaseContext Module | Completed | 2026-02-04 |
| 2 | Integrate with ContextManager | Completed | 2026-02-04 |
| 3 | Add Context Building Logic | Completed | 2026-02-04 |
| 4 | Implement Caching | Completed | 2026-02-04 |
| 5 | Write Tests | Completed | 2026-02-04 |

---

## Current Status

**What Works:**
- CodebaseContext module with ETS caching
- Module info retrieval with caching
- Related module discovery
- Dependency chain building with configurable depth
- Integration with ContextManager via `:codebase` include option
- Graceful fallback when codebase not indexed
- Telemetry events for batch completion

**Test Results:**
- 22 tests passing
- 0 failures
- All test groups passing

**How to Test:**
```bash
mix test test/jidoka/agents/codebase_context_test.exs
```

---

## Files Modified

1. **lib/jidoka/agents/codebase_context.ex** - New file
2. **lib/jidoka/agents/context_manager.ex** - Added codebase integration
3. **test/jidoka/agents/codebase_context_test.exs** - New file

---

## API Documentation

### Using Codebase Context

```elixir
# Include codebase in context building
{:ok, context} = ContextManager.build_context("session-123",
  [:conversation, :files, :codebase],
  dependency_depth: 1,
  max_modules: 20
)

# Access codebase information
context.codebase.modules #=> [%{name: "MyApp.User", ...}]
context.codebase.project_structure #=> %{total_modules: 42, ...}
```

### Direct CodebaseContext API

```elixir
# Get module info
{:ok, info} = CodebaseContext.get_module_info("MyApp.User")

# Find related modules
{:ok, related} = CodebaseContext.find_related(["MyApp.User"],
  include_dependencies: true,
  max_results: 10
)

# Get dependencies
{:ok, deps} = CodebaseContext.get_dependencies("MyApp.User", depth: 1)

# Enrich active files
{:ok, context} = CodebaseContext.enrich(["lib/my_app/user.ex"])

# Invalidate cache
:ok = CodebaseContext.invalidate_cache()
```

---

## Notes/Considerations

### Module Name Extraction

To find modules from file paths:
- Query codebase for modules by file path
- Fallback to heuristic: `lib/my_app/users.ex` -> `MyApp.Users`
- Not always 100% accurate, but works for standard Elixir project structure

### Dependency Depth

Configurable depth for dependency traversal:
- Level 0: Only the active file's modules
- Level 1: Direct dependencies
- Level 2: Transitive dependencies
- Default: 1 (direct dependencies only)

### Cache Strategy

- ETS table with `:set` type
- Cache key: `{query_type, param}`
- TTL: 5 minutes (configurable)
- Periodic cleanup of all entries
- Manual invalidation via `invalidate_cache/0`

### Graceful Fallback

When codebase queries fail:
- Return empty codebase context
- Log warning for debugging
- Continue with other context sources
- Don't fail the entire build_context call

### Future Improvements

- Smarter module name extraction using AST
- Per-module cache entries
- File deletion detection
- More sophisticated dependency tracking
- Query result pagination for large codebases
