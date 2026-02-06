# Feature: Remove SPARQLClient - Use TripleStore Directly

**Created:** 2026-01-28
**Status:** In Progress
**Branch:** `feature/remove-sparql-client-use-triplestore-directly`

## Problem Statement

The `JidoCoderLib.Knowledge.SPARQLClient` module is a thin wrapper around the `TripleStore` library's SPARQL functionality. For an embedded library architecture with direct database references, this wrapper adds unnecessary indirection without providing meaningful abstraction value.

### Current Issues

1. **Unnecessary Indirection**: SPARQLClient wraps `TripleStore.SPARQL.Query.query/3` and `TripleStore.update/2` with minimal added value
2. **Code Bloat**: ~430 lines of wrapper code for 2 actively used functions
3. **Confusion**: Developers must understand both SPARQLClient API and underlying TripleStore API
4. **Unused Functions**: `insert_data/3` and `delete_data/3` (for RDF.Graph) are never used in our codebase
5. **Maintenance Burden**: Another module to maintain when TripleStore API changes

### Dependencies Found

SPARQLClient is currently used in:
- `lib/jido_coder_lib/knowledge/queries.ex` - `SPARQLClient.query/4`
- `lib/jido_coder_lib/knowledge/engine.ex` - `SPARQLClient.update/2` (for graph creation)
- `lib/jido_coder_lib/memory/long_term/triple_store_adapter.ex` - `SPARQLClient.update/2`
- `lib/jido_coder_lib/knowledge/ontology.ex` - `SPARQLClient.query/4` and `SPARQLClient.update/2`
- Test files: `sparql_client_test.exs`, `triple_store_adapter_test.exs`

## Solution Overview

**Remove SPARQLClient entirely** and use TripleStore APIs directly. This is safe because:

1. We have an **embedded architecture** - no HTTP/remote calls to abstract
2. **TripleStore is a stable dependency** - we control the version and can update if needed
3. The wrapper provides minimal value - only context validation that would fail fast anyway

### Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Delete SPARQLClient entirely** | No meaningful abstraction for embedded use |
| **Call TripleStore.SPARQL.Query.query/3 directly** | Clean, direct API |
| **Call TripleStore.update/2 directly** | Simpler than wrapper |
| **Add helper module for permit_all** | Centralize authorization bypass logic |
| **Update all callers** | Straightforward find-replace |
| **Delete sparql_client_test.exs** | Tests for wrapper no longer needed |

## Technical Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_coder_lib/knowledge/sparql_client.ex` | **DELETE** |
| `lib/jido_coder_lib/knowledge/queries.ex` | Use `TripleStore.SPARQL.Query.query/3` directly |
| `lib/jido_coder_lib/knowledge/engine.ex` | Use `TripleStore.update/2` directly |
| `lib/jido_coder_lib/memory/long_term/triple_store_adapter.ex` | Use `TripleStore.update/2` directly |
| `lib/jido_coder_lib/knowledge/ontology.ex` | Use TripleStore APIs directly |
| `test/jido_coder_lib/knowledge/sparql_client_test.exs` | **DELETE** |
| `test/jido_coder_lib/knowledge/queries_test.exs` | Update if needed |

### New Helper Module (if needed)

May create `JidoCoderLib.Knowledge.Context` or similar for:
- `permit_all(ctx)` - Sets permit_all and returns context
- Common context preparation

### API Mapping

| Old (SPARQLClient) | New (TripleStore Direct) |
|---------------------|---------------------------|
| `SPARQLClient.query(ctx, query, :select, opts)` | `TripleStore.SPARQL.Query.query(ctx, query, opts)` |
| `SPARQLClient.query(ctx, query, :ask, opts)` | `TripleStore.SPARQL.Query.query(ctx, query, opts)` |
| `SPARQLClient.update(ctx, update_string)` | `TripleStore.update(ctx, update_string)` |

### permit_all Handling

Current pattern in SPARQLClient/Queries:
```elixir
TripleStore.SPARQL.Authorization.set_permit_all(true)
Map.put(ctx, :permit_all, true)
```

This should remain - it's needed for internal operations with quad schema ACLs.

## Success Criteria

1. ✅ SPARQLClient module deleted
2. ✅ All callers updated to use TripleStore directly
3. ✅ All tests pass (queries_test.exs, adapter_test.exs, etc.)
4. ✅ Code compiles without warnings
5. ✅ sparql_client_test.exs deleted
6. ✅ Documentation updated (remove SPARQLClient references)

## Implementation Plan

### Step 1: Analyze Current Usage ✅
- [x] Find all SPARQLClient usages
- [x] Identify actual API calls being made
- [x] Document mapping to TripleStore APIs

### Step 2: Create Helper for permit_all (Optional)
- [ ] Decide if helper module is needed
- [ ] If yes, create `Knowledge.Context` helper
- [ ] If no, use inline permit_all pattern

### Step 3: Update Engine.ex
- [ ] Replace `SPARQLClient.update/2` with `TripleStore.update/2`
- [ ] Update imports/aliases
- [ ] Test engine creation and graph operations

### Step 4: Update Queries.ex
- [ ] Replace `SPARQLClient.query/4` with `TripleStore.SPARQL.Query.query/3`
- [ ] Update imports/aliases
- [ ] Keep permit_all handling
- [ ] Test queries work correctly

### Step 5: Update TripleStoreAdapter.ex
- [ ] Replace `SPARQLClient.update/2` with `TripleStore.update/2`
- [ ] Update imports/aliases
- [ ] Test memory persistence and retrieval

### Step 6: Update Ontology.ex
- [ ] Replace SPARQLClient calls with TripleStore APIs
- [ ] Update imports/aliases
- [ ] Test ontology operations

### Step 7: Delete SPARQLClient Module
- [ ] Delete `lib/jido_coder_lib/knowledge/sparql_client.ex`
- [ ] Delete `test/jido_coder_lib/knowledge/sparql_client_test.exs`

### Step 8: Run Full Test Suite
- [ ] Run `mix test` to verify all tests pass
- [ ] Fix any issues found

### Step 9: Clean Up Documentation
- [ ] Update any module documentation referencing SPARQLClient
- [ ] Update architecture docs if needed

### Step 10: Final Verification
- [ ] Ensure no references to SPARQLClient remain
- [ ] Verify code compiles cleanly
- [ ] All tests pass

## Notes/Considerations

### permit_all Pattern

The permit_all pattern is critical for quad schema operations:
```elixir
# Set process-level permit_all
TripleStore.SPARQL.Authorization.set_permit_all(true)

# Add permit_all to context
Map.put(ctx, :permit_all, true)
```

This should be preserved in all callers.

### Error Handling

TripleStore returns different error formats than SPARQLClient wrapped. Need to verify error handling in callers works correctly.

### Performance

Direct calls should be slightly faster (one less function call and pattern match).

## Current Status

**Last Updated:** 2026-01-28 10:30 UTC

### What Works
- Current code with SPARQLClient functions (except for test failures we were fixing)
- Direct TripleStore API works (we tested in our debugging)

### What's Next
- Step 2: Decide on helper module for permit_all
- Step 3: Update Engine.ex to use TripleStore.update/2 directly

### Test Status
- Before this change: 24 tests, 10 failures (unrelated to SPARQLClient removal - those were result parsing issues we were fixing)

## Questions for Developer

1. **Helper Module**: Should we create a `Knowledge.Context` helper module for permit_all, or keep the inline pattern?
2. **Error Handling**: TripleStore returns `{:ok, count}` for updates, SPARQLClient returned `{:ok, :updated}`. This change in return value needs to be handled - should we adapt callers or normalize?
