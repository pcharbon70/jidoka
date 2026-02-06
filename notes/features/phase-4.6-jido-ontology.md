# Phase 4.6: Jido Ontology Integration

**Feature Branch**: `feature/phase-4.6-jido-ontology`
**Date**: 2025-01-24
**Status**: In Progress

## Problem Statement

Section 4.6 of the Phase 4 planning document requires integrating memory items with the Jido ontology (jmem) for semantic representation. This enables:

1. **Semantic Querying**: Use SPARQL to query memories by semantic relationships
2. **Knowledge Graph Integration**: Connect memories to entities and contexts
3. **Standardized Representation**: Use W3C standards (RDF) for memory interchange
4. **Provenance Tracking**: Track source and derivation of memories

## Solution Overview

Create an `JidoCoderLib.Memory.Ontology` module that:

1. Maps memory type atoms to Jido Memory Core (jmem) ontology classes
2. Converts memory maps to RDF triples using the existing RDF library
3. Converts RDF triples back to memory maps
4. Links memories to WorkSession individuals (SessionContext)

### Jido Memory Core Ontology Reference

Based on `jido-memory-core.ttl` from jido_ai repository:

**Namespace**: `https://w3id.org/jido/memory/core#`

**Classes**:
- `jmem:Fact` - Base class for all memory items
- `jmem:Claim` - A fact expressed as a proposition
- `jmem:DerivedFact` - A fact inferred from other facts
- `jmem:PlanStepFact` - A plan step or decision
- `jmem:UserPreference` - User preferences and habits
- `jmem:ConstraintFact` - Constraints and rules
- `jmem:ToolResultFact` - Tool invocation results

**Context Classes**:
- `jmem:MemoryContext` - Base context class
- `jmem:SessionContext` - Session-specific context (links to WorkSession)
- `jmem:TaskContext` - Task-specific context
- `jmem:GlobalContext` - Cross-session context

**Properties**:
- `jmem:statementText` - Human-readable content
- `jmem:confidence` - Confidence score (0.0-1.0)
- `jmem:salience` - Importance/relevance (0.0-1.0)
- `jmem:createdAt` - Creation timestamp
- `jmem:updatedAt` - Update timestamp
- `jmem:inContext` - Links to MemoryContext
- `jmem:hasSource` - Provenance/source

## Agent Consultations Performed

**research-agent**: Consulted for Jido ontology structure
- Found `jido-memory-core.ttl` in jido_ai repository
- Found `jido-memory-shapes.ttl` for SHACL validation
- Found existing `JidoCode.Prompt.RDFMapper` as reference implementation

**elixir-expert**: N/A - Using existing RDF library patterns

## Technical Details

### File Locations

- **Module**: `lib/jido_coder_lib/memory/ontology.ex`
- **Tests**: `test/jido_coder_lib/memory/ontology_test.exs`
- **Planning**: `notes/planning/01-foundation/phase-04.md` (section 4.6)

### Dependencies

- `:rdf` ~> 2.0 - Already in mix.exs
- `:sparql` ~> 0.3 - Already in mix.exs
- `:triple_store` - For future triple store backend

### Memory Type to Ontology Mapping

| Memory Type Atom | Ontology Class |
|------------------|----------------|
| `:fact` | `jmem:Fact` |
| `:claim` | `jmem:Claim` |
| `:derived_fact` | `jmem:DerivedFact` |
| `:analysis` | `jmem:Claim` |
| `:conversation` | `jmem:Claim` |
| `:file_context` | `jmem:DocumentSource` |
| `:decision` | `jmem:PlanStepFact` |
| `:assumption` | `jmem:Claim` |
| `:user_preference` | `jmem:UserPreference` |
| `:constraint` | `jmem:ConstraintFact` |
| `:tool_result` | `jmem:ToolResultFact` |

### Memory Field to Property Mapping

| Memory Field | Ontology Property |
|--------------|-------------------|
| `:id` | `rdf:about` (URI generation) |
| `:data` | `jmem:statementText` (if string) or custom properties |
| `:importance` | `jmem:salience` |
| `:created_at` | `jmem:createdAt` |
| `:updated_at` | `jmem:updatedAt` |
| `:session_id` | `jmem:inContext` -> SessionContext URI |
| `:type` | `rdf:type` -> ontology class |

## Success Criteria

- [x] Feature branch created
- [x] Ontology module created
- [x] Memory type atoms defined with mapping to jmem classes
- [x] to_rdf/1 converts memory maps to RDF.Description
- [x] from_rdf/1 converts RDF.Description back to memory maps
- [x] WorkSession linking via SessionContext implemented
- [x] Unit tests for all conversions (15+ tests)
- [x] All tests passing
- [x] Planning document updated
- [ ] Summary created

## Implementation Plan

### Step 1: Create Ontology Module Structure

1. Create `lib/jido_coder_lib/memory/ontology.ex`
2. Define module with @moduledoc
3. Define namespace constants (@jmem_ns, @memory_ns)
4. Define memory type to class mapping

### Step 2: Implement to_rdf/1

1. Generate URI for memory individual
2. Generate URI for SessionContext
3. Create RDF.Description with:
   - rdf:type mapping to correct jmem class
   - jmem:statementText from data
   - jmem:salience from importance
   - jmem:createdAt/jmem:updatedAt from timestamps
   - jmem:inContext linking to SessionContext
4. Return RDF.Description or {:error, reason}

### Step 3: Implement from_rdf/1

1. Parse RDF.Description
2. Extract memory type from rdf:type
3. Extract fields from properties
4. Convert URIs back to IDs (session_id, etc.)
5. Return memory map or {:error, reason}

### Step 4: Add Helper Functions

1. `memory_uri/2` - Generate URI for memory individual
2. `session_context_uri/1` - Generate URI for SessionContext
3. `class_for_type/1` - Map type atom to class URI
4. `type_for_class/1` - Map class URI back to type atom
5. `property_map/0` - Map of field -> property URIs

### Step 5: Create Tests

1. Test type atom definitions
2. Test to_rdf produces valid RDF.Description
3. Test from_rdf reconstructs memory maps
4. Test round-trip conversion (to_rdf -> from_rdf)
5. Test WorkSession linking via SessionContext
6. Test error handling for invalid inputs

### Step 6: Run Tests and Verify

1. Run test suite
2. Verify all tests pass
3. Check code coverage

### Step 7: Update Documentation

1. Update planning document (mark 4.6 complete)
2. Update feature planning document
3. Create summary document

## API Examples

### Convert Memory to RDF

```elixir
memory = %{
  id: "mem_1",
  session_id: "session_123",
  type: :fact,
  data: %{key: "value"},
  importance: 0.8,
  created_at: DateTime.utc_now(),
  updated_at: DateTime.utc_now()
}

{:ok, description} = Ontology.to_rdf(memory)
# Returns %RDF.Description{
#   subject: ~I<https://jido.ai/memory/mem_1>,
#   predications: [
#     {~I<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>, ~I<https://w3id.org/jido/memory/core#Fact>},
#     {~I<https://w3id.org/jido/memory/core#statementText>, "value"},
#     {~I<https://w3id.org/jido/memory/core#salience>, 0.8},
#     ...
#   ]
# }
```

### Convert RDF to Memory

```elixir
description = %RDF.Description{...}

{:ok, memory} = Ontology.from_rdf(description)
# Returns memory map
```

### WorkSession Linking

```elixir
# Memory is linked to SessionContext
# SessionContext links to WorkSession individual
session_context_uri = "https://jido.ai/sessions/session_123#context"
```

## Notes/Considerations

1. **URI Design**: Memory URIs follow pattern `https://jido.ai/memory/{id}`
2. **SessionContext URIs**: Follow pattern `https://jido.ai/sessions/{session_id}#context`
3. **Data Serialization**: Complex `:data` maps serialized to JSON string for statementText
4. **Future Enhancement**: Add full triple store persistence (Phase 4.9+)
5. **SHACL Validation**: Can add jmem:FactShape validation in future
6. **Provenance**: Source tracking can be added with jmem:hasSource

## Current Status

### What Works
- Feature branch created
- Planning document written
- Research completed on Jido ontology structure

### What's Next
- Create Ontology module
- Implement to_rdf/1
- Implement from_rdf/1
- Create comprehensive tests

### How to Run Tests
```bash
mix test test/jido_coder_lib/memory/ontology_test.exs
```
