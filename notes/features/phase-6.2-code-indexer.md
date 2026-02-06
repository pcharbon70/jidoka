# Phase 6.2: Code Indexer (Integration with elixir-ontologies)

**Date:** 2026-02-03
**Branch:** `feature/code-indexer`
**Status:** In Progress
**Phase:** 6.2 from Phase 6 (Codebase Semantic Model)

## Problem Statement

The jidoka project needs to index Elixir source code into the knowledge graph for semantic querying. The `elixir-ontologies` library already provides comprehensive AST parsing, extraction, and RDF generation capabilities.

**Impact:**
- No way to query codebase structure using SPARQL
- LLM context lacks semantic code information
- Cannot perform code analysis (dependencies, call graphs, etc.)

## Solution Overview

Create a GenServer wrapper around the `elixir-ontologies` library that:
1. Calls `ElixirOntologies.analyze_project/2` and `analyze_file/2`
2. Inserts the resulting RDF graph into our `:elixir_codebase` named graph
3. Tracks indexing status via `IndexingStatusTracker`
4. Provides a convenient GenServer API for on-demand indexing

## Architecture

### elixir-ontologies Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                    Jidoka.Indexing.CodeIndexer           │
│                           (GenServer)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  API:                                                             │
│  ├── index_project(project_root, opts)                           │
│  ├── index_file(file_path, opts)                                 │
│  ├── get_stats()                                                 │
│  └── reindex_file(file_path, opts)                               │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ElixirOntologies Library                       │
│  ├── analyze_project/2 - Returns RDF.Graph                      │
│  ├── analyze_file/2 - Returns RDF.Graph                         │
│  ├── 30+ Extractors (Module, Function, Struct, Protocol, etc.)   │
│  └── RDF Builders (generates triples from AST)                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 RDF.Graph → TripleStore Conversion              │
│  ├── Convert RDF.Graph triples to quad format                   │
│  └── Insert into :elixir_codebase named graph                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              IndexingStatusTracker Integration                   │
│  ├── start_indexing/1 - Mark file as in_progress                │
│  ├── complete_indexing/2 - Mark as completed with triple count  │
│  └── fail_indexing/2 - Mark as failed with error                │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Wrapper not Reimplementation**: The `elixir-ontologies` library already has:
   - AST parsing via `Code.string_to_quoted/2`
   - 30+ extractors for all Elixir constructs
   - RDF builders for triple generation
   - Project file discovery
   - Our CodeIndexer is a thin integration layer

2. **Named Graph Storage**: Indexing results go into `:elixir_codebase` named graph
   - Already defined in `NamedGraphs`
   - Separated from `:system_knowledge` (ontologies)
   - Enables graph-specific queries and updates

3. **Status Tracking**: All indexing operations report status via `IndexingStatusTracker`
   - Enables progress tracking for large projects
   - Provides error recovery information
   - Telemetry for observability

4. **Error Handling**: Invalid syntax or missing files shouldn't crash the indexer
   - Individual file failures are logged and tracked
   - Project indexing continues with remaining files
   - Errors reported via `IndexingStatusTracker`

## Implementation Steps

### Step 1: Create CodeIndexer GenServer Skeleton

**File:** `lib/jidoka/indexing/code_indexer.ex`

```elixir
defmodule Jidoka.Indexing.CodeIndexer do
  @moduledoc """
  GenServer wrapper around ElixirOntologies for code indexing.

  Uses the elixir-ontologies library to analyze Elixir source code
  and store the resulting RDF triples in the :elixir_codebase named graph.
  """

  use GenServer
  require Logger

  alias Jidoka.Knowledge.{Engine, NamedGraphs}
  alias Jidoka.Indexing.IndexingStatusTracker

  # State
  defstruct [
    :engine_name,
    :tracker_name,
    :project_root
  ]

  # Client API
  def start_link(opts \\ [])
  def index_project(project_root, opts \\ [])
  def index_file(file_path, opts \\ [])
  def get_stats(opts \\ [])

  # Server Callbacks
  def init(opts)
  def handle_call/3
  def handle_cast/2
end
```

### Step 2: Implement Project Indexing

Call `ElixirOntologies.analyze_project/2` and insert results:

```elixir
def index_project(project_root, opts \\ []) do
  name = Keyword.get(opts, :name, __MODULE__)
  GenServer.call(name, {:index_project, project_root, opts}, :infinity)
end

def handle_call({:index_project, project_root, opts}, _from, state) do
  result = do_index_project(project_root, state, opts)
  {:reply, result, state}
end

defp do_index_project(project_root, state, opts) do
  # Normalize path
  project_root = Path.expand(project_root)

  # Configure elixir-ontologies
  config = %ElixirOntologies.Config{
    base_iri: "https://jido.ai/code#",
    include_source_text: false,
    include_git_info: false
  }

  case ElixirOntologies.analyze_project(project_root, config: config) do
    {:ok, result} ->
      # Insert into elixir_codebase graph
      insert_graph(result.graph, state)
      {:ok, %{metadata: result.metadata, errors: result.errors}}

    {:error, reason} ->
      {:error, reason}
  end
end
```

### Step 3: Implement Single File Indexing

Call `ElixirOntologies.analyze_file/2` and insert results:

```elixir
def index_file(file_path, opts \\ []) do
  name = Keyword.get(opts, :name, __MODULE__)
  GenServer.call(name, {:index_file, file_path, opts})
end

def handle_call({:index_file, file_path, opts}, _from, state) do
  result = do_index_file(file_path, state, opts)
  {:reply, result, state}
end

defp do_index_file(file_path, state, opts) do
  # Mark as in_progress
  IndexingStatusTracker.start_indexing(file_path)

  config = %ElixirOntologies.Config{
    base_iri: "https://jido.ai/code#",
    include_source_text: false,
    include_git_info: false
  }

  case ElixirOntologies.analyze_file(file_path, config: config) do
    {:ok, graph} ->
      # Insert into elixir_codebase graph
      triple_count = insert_graph(graph, state)
      IndexingStatusTracker.complete_indexing(file_path, triple_count)
      {:ok, %{triple_count: triple_count}}

    {:error, reason} ->
      IndexingStatusTracker.fail_indexing(file_path, inspect(reason))
      {:error, reason}
  end
end
```

### Step 4: Convert RDF.Graph to TripleStore Quads

The `elixir-ontologies` library returns `RDF.Graph` structs. We need to convert to triple_store quad format:

```elixir
defp insert_graph(graph, state) do
  ctx = Engine.context(state.engine_name)
  |> Map.put(:transaction, nil)
  |> Jidoka.Knowledge.Context.with_permit_all()

  # Get the elixir_codebase graph IRI
  {:ok, graph_iri} = NamedGraphs.iri_string(:elixir_codebase)

  # Convert RDF.Graph triples to quad format
  quads =
    graph
    |> RDF.Graph.triples()
    |> Enum.map(fn {s, p, o} ->
      {:quad, rdf_to_ast(s), rdf_to_ast(p), rdf_to_ast(o), {:named_node, graph_iri}}
    end)

  # Insert via UpdateExecutor
  case TripleStore.SPARQL.UpdateExecutor.execute_insert_data(ctx, quads) do
    {:ok, count} -> count
    {:error, reason} ->
      Logger.error("Failed to insert graph: #{inspect(reason)}")
      0
  end
end

defp rdf_to_ast(%RDF.IRI{} = iri), do: {:named_node, RDF.IRI.to_string(iri)}
defp rdf_to_ast(%RDF.Literal{} = lit), do: {:literal, :simple, RDF.Literal.value(lit)}
# ... other RDF types
```

### Step 5: Add to Supervision Tree

Update `lib/jidoka/application.ex`:

```elixir
children = [
  # ... existing children

  # CodeIndexer for codebase semantic model (Phase 6.2)
  {Jidoka.Indexing.CodeIndexer,
   [
     name: Jidoka.Indexing.CodeIndexer,
     engine_name: :knowledge_engine,
     tracker_name: Jidoka.Indexing.IndexingStatusTracker
   ]},
]
```

## API Examples

```elixir
# Index entire project
{:ok, result} = CodeIndexer.index_project(".")
result.metadata.file_count      #=> 42
result.metadata.module_count    #=> 15
result.metadata.error_count     #=> 0

# Index single file
{:ok, info} = CodeIndexer.index_file("lib/my_app/users.ex")
info.triple_count              #=> 125

# Check indexing status
{:ok, status} = IndexingStatusTracker.get_project_status(".")
status.completed              #=> 42
status.failed                 #=> 0
status.in_progress            #=> 0

# Query indexed code
{:ok, results} = TripleStore.SPARQL.Query.execute(ctx, """
  PREFIX struct: <https://w3id.org/elixir-code/structure#>

  SELECT ?module ?function ?arity
  WHERE {
    ?module a struct:Module .
    ?module struct:definesFunction ?function .
    ?function struct:arity ?arity .
  }
  LIMIT 10
""")
```

## Dependencies

- `elixir-ontologies` - Already in mix.exs as path dependency
- `rdf` - For RDF.Graph handling (already in mix.exs)
- `triple_store` - For quad insertion (already in mix.exs)
- Phase 5: Knowledge Engine, NamedGraphs
- Phase 6.4.5: IndexingStatusTracker

## Success Criteria

- [ ] CodeIndexer GenServer starts successfully
- [ ] `index_project/1` indexes all .ex/.exs files
- [ ] `index_file/2` indexes single file
- [ ] RDF.Graph converts to quad format correctly
- [ ] Triples inserted into `:elixir_codebase` graph
- [ ] IndexingStatusTracker integration works
- [ ] Errors handled gracefully (syntax errors, missing files)
- [ ] Unit tests pass (15 tests)
- [ ] Integration tests pass

## Notes

### elixir-ontologies Output Format

The `analyze_file/2` function returns an `ElixirOntologies.Graph` struct wrapping an `RDF.Graph`. The graph contains:

- **Module triples**: `?module a struct:Module`
- **Function triples**: `?function a struct:Function`
- **Struct triples**: `?struct a struct:Struct`
- **Protocol triples**: `?protocol a struct:Protocol`
- **Behaviour triples**: `?behaviour a struct:Behaviour`

All using the elixir-ontology namespaces (`https://w3id.org/elixir-code/structure#`).

### Named Graph Separation

- `:system_knowledge` - Ontologies only (loaded via `Ontology.load_elixir_ontology/0`)
- `:elixir_codebase` - Indexed code individuals (loaded via `CodeIndexer`)

This separation enables:
- Clearing and re-indexing code without affecting ontologies
- Graph-specific queries (e.g., only query code, not ontologies)
- Efficient graph dumps and restores

## Next Steps

After Phase 6.2:
- Phase 6.4: Incremental indexing (reindex_file, remove_file)
- Phase 6.6: Codebase query interface
- Phase 6.7: ContextManager integration
