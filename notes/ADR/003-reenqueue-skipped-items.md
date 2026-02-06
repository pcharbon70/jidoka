# ADR 003: Re-enqueue Skipped Items

## Status
Accepted

## Date
2025-01-25

## Context
During implicit promotion, items that don't meet promotion criteria need to be handled. Options:

1. **Discard skipped items**: Remove them from the queue permanently
2. **Keep in queue**: Leave them at the front of the queue for next evaluation
3. **Re-enqueue skipped items**: Move them to the back of the queue for future cycles

If we discard items, we lose data that might become valuable later. If we keep them at the front, the same items will be evaluated repeatedly without making progress.

## Decision
In implicit promotion mode, skipped and failed items are **re-enqueued at the back of the queue**. This:

- Preserves data for future promotion cycles
- Allows other items to be processed first
- Enables items to be promoted when criteria change (e.g., age threshold met)
- Prevents repeated evaluation of the same items in one batch

### Implementation
```elixir
defp maybe_promote(stm, _ltm_adapter, item, :skip, _criteria, explicit, _confidence) do
  stm =
    unless explicit do
      case PendingMemories.enqueue(stm.pending_memories, item) do
        {:ok, updated_pending} -> %{stm | pending_memories: updated_pending}
        _ -> stm
      end
    else
      stm
    end

  {:ok, :skipped, "below threshold", stm}
end
```

The batch processing uses a `processed` set to track which items have been seen and stops when only re-enqueued items remain.

## Consequences

### Positive
- No data loss from failed promotion attempts
- Natural aging of items (older items get more chances)
- Fair queue processing (new items processed first)
- Items can be promoted when criteria becomes more lenient

### Negative
- Queue can fill with low-importance items
- Repeated evaluation of same items
- Need `processed` set to prevent infinite loops

### Mitigations
- Configurable `batch_size` limits processing per cycle
- `processed` set prevents infinite loops in same batch
- Age-based promotion ensures old items eventually promoted
- Queue size limit (`max_size`) prevents unbounded growth
- High importance override (>= 0.8) ensures valuable items promoted quickly

## Related
- ADR 002: Implicit vs Explicit Promotion Modes
- ADR 004: Processed Set Tracking
