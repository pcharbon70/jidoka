# ADR 004: Processed Set Tracking for Batch Promotion

## Status
Accepted

## Date
2025-01-25

## Context
When promoting items with re-enqueue enabled (see ADR 003), the same item can be encountered multiple times:

1. Item is dequeued and skipped
2. Item is re-enqueued at the back of the queue
3. Batch continues processing
4. Re-enqueued item is reached again

Without tracking, this creates an infinite loop where the same item is processed repeatedly.

## Decision
Use a `MapSet` to track processed item IDs within each batch. Before processing an item:

1. **Peek** at the next item in the queue
2. **Check** if its ID is in the processed set
3. **Skip** to next item if already processed (stops batch when only processed items remain)
4. **Add** item ID to processed set after processing

```elixir
defp process_batch(stm, ltm_adapter, criteria, remaining, explicit, promoted, skipped, failed, processed) do
  case PendingMemories.peek(stm.pending_memories) do
    {:ok, item} ->
      item_id = Map.get(item, :id)

      if MapSet.member?(processed, item_id) do
        # Already processed - stop batch
        {promoted, skipped, failed, stm}
      else
        # Process and add to set
        # ...
      end
  end
end
```

## Consequences

### Positive
- Prevents infinite loops with re-enqueued items
- O(log n) lookup time with MapSet
- Clean stop condition (when only re-enqueued items remain)
- No data loss - re-enqueued items preserved for next batch

### Negative
- Additional memory overhead for processed set
- Slightly more complex batch processing logic
- Processed set is per-batch (items can be re-processed across batches)

### Mitigations
- Set size bounded by batch_size (typically small, ~10)
- Per-batch scoping is actually desired behavior
- Memory overhead is minimal (MapSet is efficient)

## Alternative Considered
**Dequeue and check**: Dequeue first, then check if processed.
- **Rejected**: Would remove item from queue before deciding, causing data loss

## Related
- ADR 003: Re-enqueue Skipped Items
- ADR 005: Confidence Scoring Formula
