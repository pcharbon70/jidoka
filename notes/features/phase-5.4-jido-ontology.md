# Feature: Jido Ontology Loading

**Date:** 2025-01-26
**Branch:** `feature/phase-5.4-jido-ontology`
**Status:** In Progress

---

## Problem Statement

The jidoka project requires a domain ontology for memory types and work sessions. This ontology will define the semantic structure for storing facts, decisions, and lessons learned in the knowledge graph. Currently, there is no ontology file, no loading mechanism, and no validation of ontology integrity.

**Current State:**
- No Jido ontology file exists
- No mechanism to load ontology files into the knowledge graph
- No validation that ontology loaded correctly
- No helpers for ontology lookup
- No version tracking for ontology updates

**Impact:**
- Phase 5.5 (TripleStoreAdapter for LTM) cannot create typed memory triples
- Memory system lacks semantic type definitions
- Cannot validate memory data against ontology schema
- No queryable structure for memory-based reasoning

---

## Solution Overview

Implement Jido Ontology loading with a Turtle (.ttl) file defining memory types and work sessions, plus a loader module that parses and inserts the ontology into the system_knowledge graph.

**Key Design Decisions:**
1. **Turtle Format** - Standard RDF serialization, human-readable, compatible with RDF.ex
2. **Jido Namespace** - `https://jido.ai/ontologies/core#` for all Jido-defined classes
3. **System Knowledge Graph** - Load ontology into `:system_knowledge` named graph
4. **Version Tracking** - Store ontology version as triples for migration support
5. **Validation** - Check ontology triples exist after loading
6. **Lookup Helpers** - Provide convenient functions for common ontology queries

**Architecture:**
```
Jidoka.Knowledge.Ontology (loader module)
├── load_jido_ontology/0       - Load Jido ontology into system_knowledge
├── load_ontology/2            - Generic loader for any .ttl file
├── validate_loaded/1          - Verify ontology triples exist
├── ontology_version/0         - Get current ontology version
├── class_exists?/1            - Check if class is defined
├── get_class_iri/1            - Get IRI for class name
└── Helper Functions:
    ├── memory_type_iris/0     - Get all memory type IRIs
    ├── is_memory_type?/1      - Check if IRI is a memory type
    └── create_memory_triple/3 - Helper to create typed memory triple

priv/ontologies/jido.ttl
├── Memory Types:
│   ├── jido:Fact              - Factual information from work sessions
│   ├── jido:Decision          - Decisions made during development
│   └── jido:LessonLearned     - Lessons learned from experiences
└── Work Session:
    └── jido:WorkSession       - Represents a coding work session
```

---

## Technical Details

### Module Structure

**Primary Module:** `lib/jidoka/knowledge/ontology.ex`

**API Design:**
```elixir
defmodule Jidoka.Knowledge.Ontology do
  @moduledoc """
  Loader and validator for domain ontologies.

  Provides functions to load ontology files into the knowledge graph,
  validate that ontologies loaded correctly, and query ontology metadata.
  """

  alias Jidoka.Knowledge.Engine
  alias Jidoka.Knowledge.NamedGraphs

  # Public API - Loading
  def load_jido_ontology()
  def load_ontology(file_path, graph_name)
  def reload_jido_ontology()

  # Public API - Validation
  def validate_loaded(:jido)
  def ontology_version(:jido)

  # Public API - Lookup Helpers
  def class_exists?(class_name, opts \\ [])
  def get_class_iri(class_name, opts \\ [])
  def memory_type_iris()
  def is_memory_type?(iri)

  # Public API - Triple Creation Helpers
  def create_memory_triple(type, subject, object)
  def create_work_session_individual(session_id)
end
```

### Ontology File Structure

**Location:** `priv/ontologies/jido.ttl`

**Namespaces:**
```turtle
@prefix jido: <https://jido.ai/ontologies/core#> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix prov: <http://www.w3.org/ns/prov#> .
@prefix dcterms: <http://purl.org/dc/terms/> .
```

**Classes Defined:**
```turtle
# Memory Types
jido:Memory a owl:Class ;
    rdfs:label "Memory"@en ;
    rdfs:comment "Base class for all memory types stored in long-term context"@en ;
    rdfs:subClassOf prov:Entity .

jido:Fact a owl:Class ;
    rdfs:label "Fact"@en ;
    rdfs:comment "Factual information extracted from work sessions"@en ;
    rdfs:subClassOf jido:Memory .

jido:Decision a owl:Class ;
    rdfs:label "Decision"@en ;
    rdfs:comment "Decisions made during development work"@en ;
    rdfs:subClassOf jido:Memory .

jido:LessonLearned a owl:Class ;
    rdfs:label "Lesson Learned"@en ;
    rdfs:comment "Lessons learned from experiences and outcomes"@en ;
    rdfs:subClassOf jido:Memory .

# Work Session
jido:WorkSession a owl:Class ;
    rdfs:label "Work Session"@en ;
    rdfs:comment "Represents a coding work session with associated memories"@en ;
    rdfs:subClassOf prov:Activity .
```

**Properties Defined:**
```turtle
# Memory properties
jido:hasMemory a owl:ObjectProperty ;
    rdfs:label "has memory"@en ;
    rdfs:domain jido:WorkSession ;
    rdfs:range jido:Memory .

jido:memoryType a owl:ObjectProperty ;
    rdfs:label "memory type"@en ;
    rdfs:domain jido:Memory ;
    rdfs:range owl:Class .

jido:confidence a owl:DatatypeProperty ;
    rdfs:label "confidence"@en ;
    rdfs:domain jido:Memory ;
    rdfs:range xsd:decimal .

jido:timestamp a owl:DatatypeProperty ;
    rdfs:label "timestamp"@en ;
    rdfs:domain jido:Memory ;
    rdfs:range xsd:dateTime .

jido:sourceSession a owl:ObjectProperty ;
    rdfs:label "source session"@en ;
    rdfs:domain jido:Memory ;
    rdfs:range jido:WorkSession .
```

### Configuration

Uses existing `:knowledge_engine` from Engine module.

### Dependencies

**Existing:**
- `Jidoka.Knowledge.Engine` - For graph context
- `Jidoka.Knowledge.NamedGraphs` - For graph IRI resolution
- `RDF` - For Turtle parsing
- `RDF.Turtle` - For Turtle format reading

**New:**
- None (uses existing RDF.ex Turtle support)

---

## Success Criteria

### Functional Requirements
- [ ] 5.4.1 Add Jido ontology .ttl files to priv/ontologies
- [ ] 5.4.2 Implement `load_jido_ontology/0` function
- [ ] 5.4.3 Parse ontology file and insert into system-knowledge graph
- [ ] 5.4.4 Validate ontology loaded correctly
- [ ] 5.4.5 Create ontology lookup helpers
- [ ] 5.4.6 Add ontology version tracking

### Test Coverage
- [ ] Jido ontology file exists and is valid Turtle
- [ ] Ontology parses without errors
- [ ] Ontology triples are inserted into system_knowledge
- [ ] Ontology validation passes
- [ ] Ontology lookup returns correct classes
- [ ] Memory type IRIs are accessible
- [ ] Version tracking works

### Code Quality
- [ ] All public functions have @spec annotations
- [ ] All code formatted with `mix format`
- [ ] Module documentation complete
- [ ] Ontology file has proper comments
- [ ] Examples in @doc blocks

### Integration
- [ ] Functions work with Engine API
- [ ] Ontology loads into correct named graph
- [ ] SPARQL queries can find ontology classes
- [ ] Error handling is consistent

---

## Implementation Plan

### Step 1: Create Jido Ontology File

**Status:** Pending

**Tasks:**
- [ ] Create `priv/ontologies/` directory
- [ ] Create `priv/ontologies/jido.ttl` with ontology definitions
- [ ] Define Memory classes (Fact, Decision, LessonLearned)
- [ ] Define WorkSession class
- [ ] Define object properties (hasMemory, memoryType, sourceSession)
- [ ] Define datatype properties (confidence, timestamp)
- [ ] Add ontology metadata (version, creator, license)
- [ ] Add comments and documentation

**Files:**
- `priv/ontologies/jido.ttl` (new)

---

### Step 2: Create Ontology Loader Module

**Status:** Pending

**Tasks:**
- [ ] Create `lib/jidoka/knowledge/ontology.ex`
- [ ] Implement `load_ontology/2` for generic .ttl loading
- [ ] Implement `load_jido_ontology/0` for Jido-specific loading
- [ ] Use RDF.Turtle to parse .ttl files
- [ ] Use Engine.context() for execution context
- [ ] Use SPARQLClient.insert_data/2 to insert triples
- [ ] Handle parse errors gracefully

**Files:**
- `lib/jidoka/knowledge/ontology.ex` (new)

---

### Step 3: Implement Validation Functions

**Status:** Pending

**Tasks:**
- [ ] Implement `validate_loaded/1` for ontology validation
- [ ] Check that expected classes exist in graph
- [ ] Check that expected properties exist in graph
- [ ] Return `{:ok, metadata}` or `{:error, reason}`
- [ ] Implement `ontology_version/0` to get version from triples

**Files:**
- `lib/jidoka/knowledge/ontology.ex` (modify)

---

### Step 4: Implement Lookup Helpers

**Status:** Pending

**Tasks:**
- [ ] Implement `class_exists?/1` for class checking
- [ ] Implement `get_class_iri/1` for IRI resolution
- [ ] Implement `memory_type_iris/0` for getting memory types
- [ ] Implement `is_memory_type?/1` for type checking
- [ ] Implement `create_memory_triple/3` for triple creation
- [ ] Implement `create_work_session_individual/1` for session creation

**Files:**
- `lib/jidoka/knowledge/ontology.ex` (modify)

---

### Step 5: Write Tests

**Status:** Pending

**Tasks:**
- [ ] Create test file structure
- [ ] Test ontology file exists and is readable
- [ ] Test ontology parses without errors
- [ ] Test ontology loads into correct graph
- [ ] Test validation finds loaded classes
- [ ] Test lookup helpers return correct IRIs
- [ ] Test memory type helpers work
- [ ] Test triple creation helpers generate correct triples

**Files:**
- `test/jidoka/knowledge/ontology_test.exs` (new)

---

## Progress Tracking

| Step | Description | Status | Date Completed |
|------|-------------|--------|----------------|
| 1 | Create Jido Ontology File | Pending | - |
| 2 | Create Ontology Loader Module | Pending | - |
| 3 | Implement Validation Functions | Pending | - |
| 4 | Implement Lookup Helpers | Pending | - |
| 5 | Write Tests | Pending | - |

---

## Notes and Considerations

### RDF.ex Turtle Parsing

The RDF library provides `RDF.Turtle.read_file/1` for parsing Turtle files:
```elixir
{:ok, graph} = RDF.Turtle.read_file("priv/ontologies/jido.ttl")
```

The returned `RDF.Graph` can be converted to statements for insertion:
```elixir
statements = RDF.Graph.triples(graph)
```

### Graph Insertion

Use SPARQLClient.insert_data to insert triples:
```elixir
ctx = Engine.context(:knowledge_engine)
{:ok, :inserted} = SPARQLClient.insert_data(ctx, statements, graph: :system_knowledge)
```

### Version Tracking

Store ontology version as a triple:
```turtle
<https://jido.ai/ontologies/core> dcterms:version "1.0.0"^^xsd:string .
```

Query for version:
```sparql
SELECT ?v WHERE {
  <https://jido.ai/ontologies/core> dcterms:version ?v
}
```

### Class IRIs

Memory type IRIs will be:
- Fact: `https://jido.ai/ontologies/core#Fact`
- Decision: `https://jido.ai/ontologies/core#Decision`
- LessonLearned: `https://jido.ai/ontologies/core#LessonLearned`
- WorkSession: `https://jido.ai/ontologies/core#WorkSession`

### Future Improvements

1. **SHACL Validation** - Add SHACL shapes for memory data validation
2. **Ontology Migrations** - Version-controlled schema updates
3. **Multiple Ontologies** - Support for loading additional domain ontologies
4. **Inference Rules** - RDFS/OWL reasoning for implicit class membership
5. **Ontology Documentation** - Generate HTML docs from ontology

---

## References

- [Phase 5 Plan](/home/ducky/code/agentjido/jidoka/notes/planning/01-foundation/phase-05.md)
- [Elixir Ontologies](/home/ducky/code/elixir-ontologies)
- [RDF.ex Documentation](https://hexdocs.pm/rdf/)
- [W3C RDF Schema](https://www.w3.org/2001/sw/RDFSchema/)
- [W3C OWL Web Ontology Language](https://www.w3.org/OWL/)
