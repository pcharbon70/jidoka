# ADR 001: Optional Type Field with Inference

## Status
Accepted

## Date
2025-01-25

## Context
The PendingMemories queue requires memory items to have a `:type` field specifying the memory type (:fact, :conversation, :analysis, or :file_context). This requires the caller to know and specify the correct type when enqueuing items.

However, in many cases the type can be determined from the data content itself:
- Items with `file_path`, `module`, or `function` keys are clearly file context
- Items with `analysis`, `conclusion`, or `reasoning` keys are analysis
- Items with `message`, `role`, or `content` keys are conversation

Forcing explicit type specification adds boilerplate and creates potential for mismatched types.

## Decision
Make the `:type` field optional in PendingMemories validation. When an item is enqueued without a type, it will still be accepted. The PromotionEngine will infer the type from data content when processing items for promotion.

### Type Inference Rules
```elixir
# File Context
- Data contains: file_path, file, path, code, module, function

# Analysis
- Data contains: analysis, conclusion, reasoning, summary, finding

# Conversation
- Data contains: message, utterance, role, content, user, assistant

# Fact (default)
- All other data
```

## Consequences

### Positive
- Reduces boilerplate when enqueuing items
- Allows type inference based on actual data content
- Maintains backward compatibility with explicitly typed items
- Enables automatic categorization of heterogeneous data sources

### Negative
- Type inference may not always match user intent
- Inferred types could be wrong for edge cases
- Adds cognitive overhead (need to remember both explicit and implicit)

### Mitigations
- Type inference is deterministic and well-documented
- Explicit types always take precedence over inference
- `infer_types` option allows disabling inference when needed
- Validation still requires `:id` and `:data` fields

## Related
- ADR 002: Implicit vs Explicit Promotion Modes
- ADR 003: Re-enqueue Skipped Items
