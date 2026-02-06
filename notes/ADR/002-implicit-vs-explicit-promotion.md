# ADR 002: Implicit vs Explicit Promotion Modes

## Status
Accepted

## Date
2025-01-25

## Context
The promotion engine needs to move items from STM to LTM. There are two distinct use cases:

1. **Automatic Promotion**: Items should be periodically evaluated and promoted if they meet importance/age criteria
2. **Agent-Initiated Promotion**: The agent decides to explicitly promote items regardless of criteria

A single promotion function that always applies the same behavior doesn't support both use cases well.

## Decision
Implement two separate promotion functions with different behaviors:

### Implicit Promotion (`evaluate_and_promote/3`)
- Only promotes items meeting promotion criteria
- Skipped items are re-enqueued for future promotion cycles
- Doesn't count skips against batch size
- Used for automatic/scheduled promotion

```elixir
# Only promotes items with importance >= 0.5
{:ok, stm, results} = PromotionEngine.evaluate_and_promote(stm, ltm_adapter)
```

### Explicit Promotion (`promote_all/2`)
- Promotes all items regardless of criteria
- All items count against batch size
- Used for agent-initiated promotion

```elixir
# Promotes everything, even low importance items
{:ok, stm, results} = PromotionEngine.promote_all(stm, ltm_adapter)
```

## Consequences

### Positive
- Clear separation of use cases
- Implicit mode preserves items that don't meet criteria
- Explicit mode gives agent full control
- Each mode optimized for its use case

### Negative
- More complex API (two functions instead of one)
- Users need to understand which mode to use
- Different behaviors could be confusing

### Mitigations
- Clear documentation for each function
- Explicit naming (`evaluate_and_promote` vs `promote_all`)
- Default to implicit mode for automatic operations
- Examples showing both use cases

## Implementation Details
The `explicit` flag is passed through the batch processing logic:
- **Explicit mode**: Skipped/failed items count against batch limit, are not re-enqueued
- **Implicit mode**: Skipped/failed items don't count against batch limit, are re-enqueued

## Related
- ADR 001: Optional Type Field with Inference
- ADR 003: Re-enqueue Skipped Items
