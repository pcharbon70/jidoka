# Summary: Multi-Tier Code Query Tools with Prompt Caching

**Feature Branch:** `feature/multi-tier-code-query-tools`
**Date Completed:** 2025-02-09
**Status:** Ready for commit

---

## Overview

Implemented a three-tiered code query tool system with prompt caching for the LLM agent. This enables the LLM to efficiently query the source-code ontology graph from elixir-ontologies using semantic queries, natural language search, and direct SPARQL.

---

## Implementation Summary

### Files Created

1. **`lib/jidoka/tools/ontology_cache.ex`** (173 lines)
   - Provides ontology schema for prompt caching
   - Functions: `schema_prompt/0`, `concise_schema/0`, `query_templates/0`
   - Contains elixir-ontologies reference (namespaces, classes, properties, examples)

2. **`lib/jidoka/tools/query_codebase.ex`** (271 lines)
   - Tier 1: Semantic query tool
   - 14 query types: find_module, list_modules, find_function, list_functions, get_dependencies, get_call_graph, find_protocol, list_protocols, find_behaviour, list_behaviours, find_struct, list_structs, search_by_name, get_index_stats
   - Wraps existing `Jidoka.Codebase.Queries` functions

3. **`lib/jidoka/tools/search_codebase.ex`** (78 lines)
   - Tier 2: Natural language to SPARQL bridge
   - Returns ontology schema and query templates for prompt caching
   - Future: Full NL-to-SPARQL translation

4. **`lib/jidoka/tools/sparql_query.ex`** (293 lines)
   - Tier 3: Direct SPARQL query tool
   - Read-only enforcement (SELECT/ASK only)
   - Automatic LIMIT injection
   - Result formatting with type information

### Files Modified

1. **`lib/jidoka/tools/registry.ex`**
   - Added 3 new tools to `@tools` list
   - New category: "knowledge_graph"

### Test Files Created

1. **`test/jidoka/tools/query_codebase_test.exs`** (80 lines)
   - 9 tests covering parameter validation, query types, visibility
   - Tests pass: 9/9

2. **`test/jidoka/tools/search_codebase_test.exs`** (42 lines)
   - 4 tests covering schema return, optional includes
   - Tests pass: 4/4

3. **`test/jidoka/tools/sparql_query_test.exs`** (114 lines)
   - 11 tests covering query type security enforcement
   - Tests pass: 11/11

---

## Token Cost Analysis

| Tier | Tool | Token Cost | Use Case |
|------|------|------------|----------|
| Tier 1 | query_codebase | ~50 tokens | Common semantic queries (80% of cases) |
| Tier 2 | search_codebase | ~150 tokens (with cached schema) | Natural language questions |
| Tier 3 | sparql_query | ~300 tokens | Complex analytical queries |

### Prompt Caching Strategy

The `OntologyCache.schema_prompt/0` function returns a static schema reference that can be cached by the LLM:
- First request: ~2000 tokens (schema + query)
- Subsequent requests: ~100-300 tokens (query only)

---

## Key Features

### Tier 1: Semantic Query Tool (`query_codebase`)

- **14 query types** covering all common codebase exploration needs
- **Parameter validation** for query_type, visibility, and required parameters
- **Delegates** to existing `Jidoka.Codebase.Queries` functions
- **~50 token cost** per query (minimal)

### Tier 2: Natural Language Search (`search_codebase`)

- **Returns ontology schema** for prompt caching
- **Returns query templates** for common patterns
- **Guidance** for tool selection
- **~150 token cost** with caching

### Tier 3: Direct SPARQL (`sparql_query`)

- **Read-only enforcement**: Only SELECT and ASK queries allowed
- **Security**: Rejects INSERT, DELETE, UPDATE, CONSTRUCT, DESCRIBE, LOAD, CLEAR, DROP, CREATE, COPY, MOVE, ADD
- **Automatic LIMIT injection**: Default 100 if not specified
- **Result formatting**: Type-aware (IRI, literal, boolean)
- **~300 token cost** per query

---

## Security Considerations

1. **Read-Only Enforcement**: SPARQL query tool only accepts SELECT and ASK queries
2. **Query Sanitization**: All other query types are explicitly rejected with clear error messages
3. **LIMIT Protection**: Automatic LIMIT injection prevents runaway queries
4. **Input Validation**: Parameter validation at multiple levels

---

## Test Coverage

- **24 tests** across 3 test files
- **100% passing**
- Coverage includes:
  - Parameter validation
  - Query type security enforcement
  - Schema and template return
  - Jido.Action integration

---

## Integration Points

- **Tool Registry**: Tools are automatically discovered via `Jidoka.Tools.Registry`
- **LLM Orchestrator**: Tools are available to the LLM via `HandleLLMRequest`
- **Schema Conversion**: Tools generate OpenAI-compatible function schemas
- **Knowledge Graph**: Tools query the `:elixir_codebase` named graph

---

## Known Limitations

1. **Tier 2 (search_codebase)**: Currently returns guidance rather than performing actual NL-to-SPARQL translation. Full translation is deferred to a future phase.

2. **CONSTRUCT/DESCRIBE**: Not supported in Tier 3. Can be added later if needed.

3. **Query Execution**: All tools require the knowledge graph to be populated. Tests use parameter validation to avoid this dependency.

---

## Future Enhancements

1. **Full NL-to-SPARQL**: Use a smaller LLM or template matching for automatic translation in Tier 2

2. **Query History**: Track common queries to optimize tool selection

3. **Result Caching**: Cache frequent query results

4. **CONSTRUCT/DESCRIBE Support**: Add these query types to Tier 3

---

## Git Status

```
Branch: feature/multi-tier-code-query-tools
Status: Ready to merge
Files changed:
  - lib/jidoka/tools/ontology_cache.ex (new)
  - lib/jidoka/tools/query_codebase.ex (new)
  - lib/jidoka/tools/search_codebase.ex (new)
  - lib/jidoka/tools/sparql_query.ex (new)
  - lib/jidoka/tools/registry.ex (modified)
  - test/jidoka/tools/query_codebase_test.exs (new)
  - test/jidoka/tools/search_codebase_test.exs (new)
  - test/jidoka/tools/sparql_query_test.exs (new)
```

---

## Documentation Updates

- Feature planning document: `notes/features/feature-multi-tier-code-query-tools.md`
- All modules have comprehensive `@moduledoc` and `@doc` annotations
- Examples included in documentation
