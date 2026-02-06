# ADR 007: Defer Scheduled Promotion GenServer

## Status
Accepted

## Date
2025-01-25

## Context
Phase 4.7 requirements included "promotion scheduling/triggering" which suggests automatic, scheduled promotion. Common implementation would be a GenServer that:
- Periodically evaluates pending items
- Triggers promotion based on queue size
- Runs as a background process

However, implementing a GenServer adds complexity:
- Requires process supervision tree management
- Needs configuration for intervals/triggers
- Adds failure/restart logic
- Harder to test (need to handle async behavior)

## Decision
**Defer** GenServer-based scheduled promotion. Implement only the functional promotion engine with batch processing. Scheduled promotion can be added later as a separate layer.

### Current Implementation
- Functional API: `evaluate_and_promote/3` and `promote_all/2`
- Caller controls when promotion runs
- Synchronous, easy to test
- Batch processing with configurable size

### Future Enhancement (Not Now)
A GenServer wrapper could be added later that provides:
- `PeriodicPromoter` - Runs promotion every N seconds
- `ThresholdPromoter` - Runs when queue exceeds threshold
- `HybridPromoter` - Combination of both

## Rationale
1. **YAGNI Principle**: We don't know the scheduling requirements yet
2. **Layered Design**: Core functionality first, orchestration later
3. **Testing**: Functional code is easier to test
4. **Flexibility**: Callers can implement their own scheduling

## Consequences

### Positive
- Simpler initial implementation
- Easier to test and debug
- More flexible (callers decide when to promote)
- Less code to maintain

### Negative
- No automatic promotion out of the box
- Callers must implement their own scheduling
- Need to remember to call promotion

### Mitigations
- Functional API is sufficient for current use cases
- Can add GenServer later without breaking changes
- Clear documentation on when to call promotion
- Example implementations can be provided

## Implementation Guidance for Future GenServer
If implementing later, consider:
```elixir
defmodule JidoCoderLib.Memory.PeriodicPromoter do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    interval = Keyword.get(opts, :interval, 60_000)
    schedule_promotion(interval)
    {:ok, %{interval: interval}}
  end

  def handle_info(:promote, state) do
    # Get all sessions and run promotion
    schedule_promotion(state.interval)
    {:noreply, state}
  end

  defp schedule_promotion(interval) do
    Process.send_after(self(), :promote, interval)
  end
end
```

## Related
- ADR 002: Implicit vs Explicit Promotion Modes
- ADR 003: Re-enqueue Skipped Items
