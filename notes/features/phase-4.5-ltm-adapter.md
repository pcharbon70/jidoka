# Phase 4.5: Long-Term Memory Adapter - Feature Planning

**Feature Branch**: `feature/phase-4.5-ltm-adapter`
**Date**: 2025-01-24
**Status**: In Progress

## Problem Statement

Section 4.5 of the Phase 4 planning document specifies implementation of a Long-Term Memory (LTM) adapter for session-scoped persistence. The LTM adapter provides an interface for persisting memories from short-term to long-term storage, with session isolation for multi-user/session scenarios.

## Context

The memory system has two tiers:
1. **Short-Term Memory (STM)** - Session-scoped, ephemeral, already implemented
2. **Long-Term Memory (LTM)** - Persistent, semantic knowledge, needs adapter

The LTM adapter will serve as the interface for:
- Promoting memories from STM to LTM
- Querying memories for context enrichment
- Updating existing memories
- Deleting memories

## Important Design Decisions

### Storage Backend

For this phase, we'll implement an **in-memory ETS-based LTM** as the initial storage backend. This provides:
- Fast in-memory operations
- Session-scoped isolation via named ETS tables
- Foundation for future backends (RDF triple store, database, etc.)

### Memory Item Structure

Each memory item stored in LTM will have:
- `:id` - Unique identifier
- `:session_id` - Session scope for isolation
- `:type` - Memory type (:fact, :analysis, :conversation, :file_context)
- `:data` - The actual memory data
- `:importance` - Importance score (0.0-1.0)
- `:created_at` - Timestamp when created
- `:updated_at` - Timestamp when last updated

### Session Isolation

All operations will be scoped to a specific session_id. This ensures:
- Multi-session support (different users/sessions have separate memories)
- Memory isolation per session
- Easy cleanup on session termination

## Implementation Plan

### Module Structure

Create `JidoCoderLib.Memory.LongTerm.SessionAdapter` module with:

**Public API:**
1. `new/1` - Initialize adapter with session_id
2. `persist_memory/2` - Store a memory item
3. `query_memories/2` - Retrieve memories (with filters)
4. `update_memory/2` - Update existing memory
5. `delete_memory/2` - Delete memory by ID
6. `count/1` - Count memories in session
7. `clear/1` - Clear all session memories
8. `session_id/1` - Get the session_id

**Helper Functions:**
- Table management (create per session)
- Timestamp generation
- Item validation

### Implementation Steps

1. ✅ Create feature branch
2. ✅ Create SessionAdapter module with struct
3. ✅ Implement new/1
4. ✅ Implement persist_memory/2 with ETS operations
5. ✅ Implement query_memories/2 with filtering
6. ✅ Implement update_memory/2
7. ✅ Implement delete_memory/2
8. ✅ Add count/1 and clear/1 helper functions
9. ✅ Create comprehensive tests
10. ✅ Run all tests to verify
11. ✅ Update planning document
12. Create summary

## Success Criteria

- [x] Feature branch created
- [x] SessionAdapter module created
- [x] All CRUD operations implemented
- [x] Session isolation enforced
- [x] Comprehensive test coverage (20+ tests)
- [x] All tests passing
- [x] Planning document updated
- [ ] Summary created

## Files to Create

1. `lib/jido_coder_lib/memory/long_term/session_adapter.ex` - Main adapter module
2. `test/jido_coder_lib/memory/long_term/session_adapter_test.exs` - Test file

## Files to Modify

1. `notes/planning/01-foundation/phase-04.md` - Mark section 4.5 as complete

## API Design

### Initialization

```elixir
{:ok, adapter} = SessionAdapter.new("session_123")
# or
adapter = SessionAdapter.new!("session_123")  # Raises on error
```

### Persist Memory

```elixir
memory_item = %{
  id: "mem_1",
  type: :fact,
  data: %{key: "value"},
  importance: 0.8
}

{:ok, memory} = SessionAdapter.persist_memory(adapter, memory_item)
# Returns memory with added timestamps and session_id
```

### Query Memories

```elixir
# All memories
{:ok, memories} = SessionAdapter.query_memories(adapter)

# Filtered by type
{:ok, facts} = SessionAdapter.query_memories(adapter, type: :fact)

# Filtered by importance
{:ok, important} = SessionAdapter.query_memories(adapter, min_importance: 0.7)

# Combined filters
{:ok, results} = SessionAdapter.query_memories(adapter,
  type: :analysis,
  min_importance: 0.5
)
```

### Update Memory

```elixir
{:ok, updated} = SessionAdapter.update_memory(adapter, "mem_1", %{
  importance: 0.9,
  data: %{new_data: "value"}
})
```

### Delete Memory

```elixir
{:ok, adapter} = SessionAdapter.delete_memory(adapter, "mem_1")
```

## ETS Table Design

Table name pattern: `ltm_session_#{session_id}`

Table structure (as a map):
```elixir
%{
  id: "mem_1",
  session_id: "session_123",
  type: :fact,
  data: %{...},
  importance: 0.8,
  created_at: ~U[2024-01-24 12:00:00Z],
  updated_at: ~U[2024-01-24 12:00:00Z]
}
```

Index: `id` as the primary key (using `{:id, memory_id}` for lookups)

## Notes

- This is an initial in-memory implementation
- Future phases will integrate with RDF triple store
- Session cleanup should drop ETS table when session ends
- Consider adding backup/restore for persistence across restarts
