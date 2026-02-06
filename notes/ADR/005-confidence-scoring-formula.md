# ADR 005: Confidence Scoring Formula

## Status
Accepted

## Date
2025-01-25

## Context
The promotion engine needs to score how confident it is that an item should be promoted. This score is used for:
- Prioritizing which items to promote first
- Filtering low-confidence promotions
- Providing feedback on promotion decisions

Multiple factors contribute to promotion confidence:
- User-specified importance
- Data quality/completeness
- Type specificity
- Age/recency

## Decision
Implement a weighted linear combination of factors:

```
confidence = (importance × 0.4) +
             (data_quality × 0.3) +
             (type_specificity × 0.2) +
             (recency_bonus × 0.1)
```

### Factor Definitions

**Importance (40%)** - User's assessment of value
- Directly from item's `:importance` field (0.0-1.0)
- Defaults to 0.5 if not specified
- Highest weight because user intent is primary signal

**Data Quality (30%)** - Richness of data
- 0.0 if empty
- 0.5 if 1-2 fields
- 1.0 if 3+ fields
- +0.2 bonus for nested structures
- Well-structured data is more valuable for LTM

**Type Specificity (20%)** - Explicit type specification
- 1.0 if type is explicitly specified
- 0.5 if type would be inferred
- Explicit types indicate user intent

**Recency Bonus (10%)** - Age-based priority
- 0.0 if max_age is infinity (explicit mode)
- age / max_age (older items get higher bonus)
- Ensures older items are eventually promoted

## Consequences

### Positive
- Single 0.0-1.0 score is easy to reason about
- Weights prioritize user intent (importance)
- All factors contribute meaningfully
- Formula is transparent and debuggable

### Negative
- Weights are arbitrary (not empirically derived)
- Linear formula may not capture interactions
- Recency bonus counter-intuitive (older gets higher)

### Mitigations
- Weights are configurable via defaults
- Formula can be refined with real-world usage
- Recency bonus ensures oldest items get priority
- Results clamped to [0.0, 1.0] range

## Alternative Considered
**Machine learning model**: Train a classifier to predict promotion value.
- **Rejected**: Overkill for initial implementation, requires training data

## Related
- ADR 006: High Importance Age Override
- ADR 002: Implicit vs Explicit Promotion Modes
