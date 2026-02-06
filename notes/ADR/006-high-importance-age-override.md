# ADR 006: High Importance Age Override

## Status
Accepted

## Date
2025-01-25

## Context
The promotion engine uses age as a criterion to avoid promoting too-recent items that might still be relevant to the current conversation. However, some items are important enough that we don't want to risk losing them, regardless of age.

The problem: How do we balance "don't promote too recent" with "never lose important items"?

## Decision
Items with **importance >= 0.8 bypass the age check entirely**.

```elixir
defp check_age(item, criteria) do
  max_age = Map.get(criteria, :max_age_seconds, @default_max_age_seconds)

  if max_age == :infinity do
    {:ok, :promote, :age}
  else
    timestamp = Map.get(item, :timestamp, DateTime.utc_now())
    age_seconds = DateTime.diff(DateTime.utc_now(), timestamp)

    if age_seconds >= max_age do
      {:ok, :promote, :age}
    else
      # High importance override
      importance = Map.get(item, :importance, 0.0)
      if importance >= 0.8 do
        {:ok, :promote, :high_importance_override}
      else
        {:ok, :skip, :too_recent}
      end
    end
  end
end
```

## Rationale
- Importance 0.8 indicates high-value item
- Age check is a heuristic, not a hard rule
- Losing high-importance items is worse than promoting slightly early
- 0.8 threshold requires explicit user intent (default is 0.5)

## Consequences

### Positive
- High-value items never lost due to age threshold
- Users can ensure critical items are preserved
- Override is explicit (requires setting importance >= 0.8)

### Negative
- Important recent items promoted sooner than necessary
- Could pollute LTM with items still relevant to STM
- 0.8 threshold is arbitrary

### Mitigations
- High threshold (0.8) requires explicit intent
- Override only applies to age, not importance check
- Items still need minimum importance to pass
- Can be adjusted based on usage

## Alternative Considered
**No override**: Age is a hard limit.
- **Rejected**: Risk of losing high-value items

**Configurable threshold**: Let users set override level.
- **Rejected**: Added complexity without clear benefit; 0.8 is reasonable default

## Related
- ADR 005: Confidence Scoring Formula
- ADR 002: Implicit vs Explicit Promotion Modes
