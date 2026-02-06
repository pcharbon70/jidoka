# Phase 4.7: Promotion Engine

**Feature Branch**: `feature/phase-4.7-promotion-engine`
**Date**: 2025-01-24
**Status**: Complete ✅

## Problem Statement

Section 4.7 of the Phase 4 planning document requires implementing a promotion engine that evaluates and moves important items from Short-Term Memory (STM) to Long-Term Memory (LTM).

The promotion engine needs to:
1. Evaluate items in the PendingMemories queue for promotion eligibility
2. Support implicit promotion (automatic based on heuristics)
3. Support explicit promotion (agent-initiated)
4. Infer appropriate memory types from suggestions
5. Score confidence for promotions
6. Provide scheduling/triggering mechanisms

## Solution Overview

Create a `JidoCoderLib.Memory.PromotionEngine` module that:

1. **Evaluates** pending memory items against promotion criteria
2. **Promotes** qualified items to LTM via SessionAdapter
3. **Scores** each promotion with confidence metrics
4. **Infers** types when not explicitly specified
5. **Reports** promotion results for logging/telemetry

### Promotion Flow

```
PendingMemories (STM)
    ↓ dequeue
PromotionEngine.evaluate_and_promote
    ↓ checks heuristics
PromotionCriteria (importance, age, type)
    ↓ passes
SessionAdapter.persist_memory (LTM)
    ↓
PromotionResult (success/failure, confidence)
```

## Agent Consultations Performed

**elixir-expert**: Consulted for Elixir patterns
- Use GenServer for stateful promotion scheduling
- Use Stream for batch processing
- Pattern matching for result handling

**research-agent**: Not required - using existing patterns from codebase

## Technical Details

### File Locations

- **Module**: `lib/jido_coder_lib/memory/promotion_engine.ex`
- **Tests**: `test/jido_coder_lib/memory/promotion_engine_test.exs`
- **Planning**: `notes/planning/01-foundation/phase-04.md` (section 4.7)

### Dependencies

- `JidoCoderLib.Memory.ShortTerm` - Source of pending memories
- `JidoCoderLib.Memory.LongTerm.SessionAdapter` - LTM storage
- `JidoCoderLib.Memory.ShortTerm.PendingMemories` - Queue interface

### Promotion Criteria

| Criterion | Description | Threshold |
|-----------|-------------|-----------|
| `:min_importance` | Minimum importance score | 0.5 (default) |
| `:max_age` | Maximum age before forced promotion | 5 minutes (default) |
| `:min_confidence` | Minimum confidence for promotion | 0.3 (default) |
| `:required_fields` | Required fields in memory item | [:id, :type, :data] |

### Confidence Scoring

Confidence = weighted combination of:
- `importance * 0.4` - Higher importance = more confident
- `data_quality * 0.3` - Non-empty, structured data
- `type_specificity * 0.2` - Explicit type > inferred
- `recency_bonus * 0.1` - Recent items get slight bonus

## Success Criteria

- [x] Feature branch created
- [x] PromotionEngine module created
- [x] evaluate_and_promote/3 for batch promotion
- [x] Implicit promotion with heuristics
- [x] Explicit promotion (agent-initiated)
- [x] Type inference from suggested_type
- [x] Confidence scoring implemented
- [ ] Scheduling/triggering mechanism (deferred - basic batch processing sufficient)
- [x] Unit tests for all operations (32 tests)
- [x] All tests passing
- [x] Planning document updated
- [x] Summary created

## Implementation Plan

### Step 1: Create PromotionEngine Module Structure

1. Create `lib/jido_coder_lib/memory/promotion_engine.ex`
2. Define module with @moduledoc
3. Define struct for promotion state
4. Define default configuration constants

### Step 2: Implement Core Promotion Logic

1. `evaluate_and_promote/3` - Main entry point
   - Takes STM, LTM adapter, and options
   - Processes items from PendingMemories
   - Returns promotion results

2. `evaluate_item/2` - Check if item qualifies
   - Validates required fields
   - Checks importance threshold
   - Checks age threshold
   - Returns evaluation result

3. `promote_item/3` - Move item to LTM
   - Enriches item with metadata
   - Calls SessionAdapter.persist_memory
   - Returns promotion result

### Step 3: Implement Confidence Scoring

1. `calculate_confidence/2` - Score promotion confidence
   - Weight importance, data quality, type
   - Return 0.0-1.0 score

2. `data_quality_score/1` - Assess data quality
   - Check for empty data
   - Check for structured data
   - Return quality score

### Step 4: Implement Type Inference

1. `infer_type/1` - Infer type from data content
   - Analyze data structure and keys
   - Return suggested type atom
   - Returns default (:fact) if uncertain

2. `type_for_data/1` - Pattern match on data
   - File references → :file_context
   - Analysis results → :analysis
   - Conversational → :conversation
   - Default → :fact

### Step 5: Implement Implicit/Explicit Promotion

1. `promote_all/2` - Explicit batch promotion
   - Process all pending items regardless of criteria
   - Used for agent-initiated promotion

2. `promote_ready/2` - Implicit promotion
   - Only promote items meeting criteria
   - Used for automatic/scheduled promotion

### Step 6: Add Scheduling/Triggering

1. GenServer wrapper for scheduled promotion
2. Periodic promotion based on time intervals
3. Trigger-based promotion (queue size threshold)

### Step 7: Create Tests

1. Test evaluate_and_promote processes items
2. Test implicit promotion uses heuristics
3. Test explicit promotion processes requested items
4. Test type inference assigns correct types
5. Test confidence scoring works
6. Test promotion scheduling triggers correctly
7. Test error handling for invalid items
8. Test LTM integration

### Step 8: Run Tests and Verify

1. Run test suite
2. Verify all tests pass
3. Check code coverage

### Step 9: Update Documentation

1. Update planning document (mark 4.7 complete)
2. Update feature planning document
3. Create summary document

## API Examples

### Evaluate and Promote (Implicit)

```elixir
stm = ShortTerm.new("session_123")
{:ok, adapter} = SessionAdapter.new("session_123")

# Add pending items
{:ok, stm} = ShortTerm.enqueue_memory(stm, %{
  id: "mem_1",
  type: :fact,
  data: %{key: "value"},
  importance: 0.8,
  timestamp: DateTime.utc_now()
})

# Promote ready items
{:ok, results} = PromotionEngine.evaluate_and_promote(stm, adapter)
# => %{
#   promoted: [%{id: "mem_1", confidence: 0.85}],
#   skipped: [],
#   failed: []
# }
```

### Explicit Promotion

```elixir
# Promote all regardless of criteria
{:ok, results} = PromotionEngine.promote_all(stm, adapter)
```

### Type Inference

```elixir
# No type specified
item = %{id: "mem_1", data: %{file_path: "/path/to/file.ex"}}
type = PromotionEngine.infer_type(item)
# => :file_context
```

### Confidence Scoring

```elixir
confidence = PromotionEngine.calculate_confidence(item, default: 0.5)
# => 0.82
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:min_importance` | float | 0.5 | Minimum importance for promotion |
| `:max_age_seconds` | integer | 300 | Max age before forced promotion |
| `:min_confidence` | float | 0.3 | Minimum confidence score |
| `:batch_size` | integer | 10 | Max items to process per batch |
| `:infer_types` | boolean | true | Whether to infer missing types |
| `:on_promotion` | function | nil | Callback for each promotion |

## Notes/Considerations

1. **Idempotency**: Same item promoted multiple times should update rather than duplicate
2. **Error Handling**: Failed promotions shouldn't block subsequent items
3. **STM Updates**: Promoted items should be removed from PendingMemories
4. **Telemetry**: Consider adding telemetry events for promotion tracking
5. **Performance**: Batch processing for large pending queues
6. **Type Safety**: Validate all memory items before promotion

## Current Status

### What Works
- Feature branch created
- Planning document written
- Requirements analyzed

### What's Next
- Create PromotionEngine module
- Implement core promotion logic
- Add confidence scoring
- Create comprehensive tests

### How to Run Tests
```bash
mix test test/jido_coder_lib/memory/promotion_engine_test.exs
```
