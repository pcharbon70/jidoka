# Phase 4.8: Memory Retrieval and Context Building

**Feature Branch**: `feature/phase-4.8-memory-retrieval`
**Date**: 2025-01-25
**Status**: Complete

## Problem Statement

Section 4.8 of the Phase 4 planning document requires implementing memory retrieval for context enrichment. The current system has:
- Long-Term Memory (LTM) storage via SessionAdapter
- Basic query capabilities (type filter, min_importance, limit)

What's missing:
- **Keyword-based retrieval** - Find memories matching specific terms/fields
- **Similarity-based retrieval** - Find semantically similar memories
- **Context enrichment** - Build context from retrieved memories for LLM calls
- **Result ranking** - Order retrieved memories by relevance
- **Retrieval caching** - Cache query results to improve performance

## Solution Overview

Create a `Jidoka.Memory.Retrieval` module that provides:

1. **Keyword Retrieval** - Search memories by matching keywords in data fields
2. **Similarity Retrieval** - Rank memories by relevance using TF-IDF or cosine similarity
3. **Context Building** - `enrich_context/3` to format retrieved memories for LLM consumption
4. **Result Ranking** - Multi-factor scoring (keyword match, recency, importance, type)
5. **Query Caching** - ETS-based cache for retrieval results

### Retrieval Flow

```
Query (keywords + filters)
    ↓
Retrieval.search/2
    ↓
SessionAdapter.query_memories/2 (base)
    ↓
Apply keyword filters
    ↓
Calculate relevance scores
    ↓
Rank and filter results
    ↓
Cache results (optional)
    ↓
Return ranked memories
```

### Context Building Flow

```
LLM Request + Query
    ↓
Retrieval.enrich_context/3
    ↓
Search LTM for relevant memories
    ↓
Format memories as context string
    ↓
Inject into LLM prompt
```

## Agent Consultations Performed

**elixir-expert**: Consulted for Elixir patterns
- Use ETS table for caching with TTL
- Use Enum.sort_by with stable sort for ranking
- Use Stream for lazy evaluation of large result sets

**research-agent**: Not required - using existing patterns from codebase

## Technical Details

### File Locations

- **Module**: `lib/jidoka/memory/retrieval.ex`
- **Tests**: `test/jidoka/memory/retrieval_test.exs`
- **Planning**: `notes/planning/01-foundation/phase-04.md` (section 4.8)

### Dependencies

- `Jidoka.Memory.LongTerm.SessionAdapter` - LTM storage and base queries
- `:ets` - For retrieval caching
- `DateTime` - For recency scoring

### Data Structures

#### Search Query
```elixir
@type query :: %{
  keywords: [String.t()],
  type: atom() | nil,
  min_importance: float() | nil,
  limit: integer() | nil,
  recency_boost: boolean()
}
```

#### Retrieval Result
```elixir
@type result :: %{
  memory: map(),
  score: float(),
  match_reasons: [String.t()]
}
```

#### Context Format
```elixir
@type context :: %{
  memories: [map()],
  summary: String.t(),
  count: integer(),
  last_retrieved: DateTime.t()
}
```

## Success Criteria

- [x] Feature branch created
- [x] Retrieval module created
- [x] Keyword-based search implemented
- [x] Similarity-based ranking implemented
- [x] Context enrichment function implemented
- [x] Result ranking and filtering implemented
- [x] Retrieval caching implemented
- [x] Unit tests for all operations (28 tests)
- [x] All tests passing
- [x] Planning document updated
- [x] Summary created
- [ ] ADRs written for key decisions

## Implementation Plan

### Step 1: Create Retrieval Module Structure

1. Create `lib/jidoka/memory/retrieval.ex`
2. Define module with @moduledoc
3. Define query and result types
4. Define default configuration

### Step 2: Implement Keyword-Based Retrieval

1. `search/2` - Main search function
   - Takes adapter and query map
   - Calls SessionAdapter.query_memories for base results
   - Filters by keyword matches in data fields
   - Returns list of matching memories

2. `match_keywords/2` - Check if memory matches keywords
   - Searches data fields for keyword matches
   - Supports substring and exact match modes
   - Returns match count and matched fields

### Step 3: Implement Similarity-Based Ranking

1. `calculate_relevance/3` - Score memory relevance
   - Combines keyword match score, recency, importance
   - Weighted formula: keyword 40%, recency 20%, importance 20%, type 20%
   - Returns 0.0-1.0 relevance score

2. `rank_results/2` - Sort results by relevance
   - Uses Enum.sort_by with stable sort
   - Descending order (highest relevance first)
   - Applies limit if specified

### Step 4: Implement Context Building

1. `enrich_context/3` - Build enriched context for LLM
   - Takes adapter, query, and context options
   - Searches for relevant memories
   - Formats memories as structured context string
   - Returns context map with memories, summary, metadata

2. `format_context/2` - Format memories for LLM consumption
   - Creates readable summary of memories
   - Groups by type or chronological order
   - Truncates to fit token budget if needed

### Step 5: Implement Retrieval Caching

1. `search_with_cache/2` - Cached search
   - Checks cache for existing query results
   - Uses query fingerprint as cache key
   - Returns cached results if available and fresh
   - Stores new results in cache

2. Cache implementation
   - ETS table with :named_table
   - TTL-based expiration (default 5 minutes)
   - Size-based eviction (max 100 entries)

### Step 6: Create Tests

1. Test keyword retrieval finds matches
2. Test similarity retrieval ranks correctly
3. Test enrich_context adds memories to context
4. Test ranking orders by relevance
5. Test caching improves performance
6. Test cache expiration and eviction
7. Test edge cases (empty results, no keywords, etc.)

### Step 7: Run Tests and Verify

1. Run test suite
2. Verify all tests pass
3. Check code coverage

### Step 8: Update Documentation

1. Update planning document (mark 4.8 complete)
2. Update feature planning document
3. Create summary document
4. Create ADRs for key decisions

## API Examples

### Keyword Search

```elixir
{:ok, adapter} = SessionAdapter.new("session_123")

{:ok, results} = Retrieval.search(adapter, %{
  keywords: ["file", "elixir"],
  type: :file_context,
  limit: 10
})
# => [%{memory: %{...}, score: 0.85, match_reasons: ["file", "elixir"]}, ...]
```

### Context Enrichment

```elixir
{:ok, context} = Retrieval.enrich_context(adapter, %{
  keywords: ["user", "preference"],
  limit: 5
}, max_tokens: 1000)

# => %{
#   memories: [%{...}, ...],
#   summary: "Found 3 related memories...",
#   count: 3,
#   last_retrieved: ~U[2025-01-25 12:00:00Z]
# }
```

### Cached Search

```elixir
{:ok, results} = Retrieval.search_with_cache(adapter, %{
  keywords: ["analysis"],
  cache_ttl: 300  # 5 minutes
})
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:keywords` | [String.t()] | [] | Keywords to search for |
| `:type` | atom() | nil | Filter by memory type |
| `:min_importance` | float() | nil | Minimum importance score |
| `:limit` | integer() | 10 | Max results to return |
| `:recency_boost` | boolean() | true | Apply recency boost to scoring |
| `:cache_ttl` | integer() | 300 | Cache TTL in seconds |
| `:match_mode` | atom() | :substring | :substring or :exact |

## Notes/Considerations

1. **Similarity Algorithm**: For initial implementation, using keyword-based similarity rather than full vector similarity. Vector similarity (embeddings) can be added later.

2. **Token Budget**: Context building should consider token limits and truncate appropriately.

3. **Cache Invalidation**: Cache is invalidated by TTL and by size. No manual invalidation for now.

4. **Performance**: ETS operations are fast, but large result sets may need streaming.

5. **Testing**: Use session-specific adapters to avoid test interference.

6. **Future Enhancements**:
   - Vector embeddings for semantic similarity
   - Hybrid search (keyword + vector)
   - Query expansion and synonym matching
   - Personalized ranking based on access patterns

## Current Status

### What Works
- Feature branch created
- Planning document written
- Requirements analyzed
- Retrieval module created with 540 lines of code
- 28 unit tests passing
- All core functions implemented:
  - `search/2` - Keyword-based search with relevance scoring
  - `search_with_cache/2` - Cached search with ETS
  - `enrich_context/3` - Context building for LLM consumption
  - `calculate_relevance/2` - Multi-factor relevance scoring
  - Cache management: `clear_cache/0`, `cache_stats/0`

### What's Next
- ADRs for key decisions (optional)
- Integration with ContextManager (Phase 4.9)

### How to Run Tests
```bash
mix test test/jidoka/memory/retrieval_test.exs
```

## Implementation Summary

### Files Created

1. **`lib/jidoka/memory/retrieval.ex`** (540 lines)
   - Main Retrieval module
   - Core API: `search/2`, `search_with_cache/2`, `enrich_context/3`
   - Relevance scoring with 4 factors (keyword 40%, recency 20%, importance 20%, type 20%)
   - ETS-based caching with TTL and size limits

2. **`test/jidoka/memory/retrieval_test.exs`** (382 lines)
   - 28 tests covering all operations
   - Test groups: search, caching, enrich_context, calculate_relevance, edge cases

### Key Design Decisions

1. **Keyword-based relevance scoring**: Used substring matching on data fields instead of full vector embeddings. This can be extended later.

2. **Multi-factor relevance scoring**: Combined keyword match score, recency, importance, and type relevance for ranking.

3. **Filtering by keyword matches**: When keywords are provided, only memories with at least one matching keyword are returned.

4. **ETS cache with TTL**: Used simple ETS table with TTL-based expiration and size-based eviction for caching query results.

5. **Map-based query interface**: Used maps for queries (not keyword lists) for consistency with the rest of the codebase.

### Test Results

All 28 tests passing:
- 6 tests for `search/2`
- 5 tests for `search_with_cache/2`
- 5 tests for `enrich_context/3`
- 4 tests for `calculate_relevance/2`
- 4 edge case tests
- 4 keyword matching integration tests
