defmodule Jidoka.Indexing.ProjectAnalyzer do
  @moduledoc """
  Functional API for analyzing Elixir projects and loading to knowledge graph.

  This module provides a direct, non-GenServer interface to analyze Elixir
  projects using elixir-ontologies and load the results into the knowledge
  engine's named graphs. It replicates the behavior of the
  `mix elixir_ontologies.analyze` task with programmatic control.

  ## Comparison to CodeIndexer

  - `CodeIndexer` - GenServer-based, maintains state, tracks indexing status
  - `ProjectAnalyzer` - Functional, stateless, direct analysis and loading

  Use `ProjectAnalyzer` for:
  - One-time analysis operations
  - Scripts and automation
  - Direct control over options
  - Testing and debugging

  Use `CodeIndexer` for:
  - Long-running processes
  - Background indexing
  - Status tracking across operations
  - Re-indexing workflows

  ## Options

  All analysis functions accept the same options as `mix elixir_ontologies.analyze`:

  | Option | Type | Default | Description |
  |--------|------|---------|-------------|
  | `:base_iri` | string | `"https://jido.ai/code#"` | Base IRI for generated resources |
  | `:include_source` | boolean | `false` | Include source code text in graph |
  | `:include_git` | boolean | `true` | Include git provenance information |
  | `:exclude_tests` | boolean | `true` | Exclude test files from analysis |
  | `:validate` | boolean | `false` | Validate against SHACL shapes |

  Loading functions also accept:
  | Option | Type | Default | Description |
  |--------|------|---------|-------------|
  | `:engine_name` | atom | `:knowledge_engine` | Knowledge engine to use |
  | `:graph_name` | atom | `:elixir_codebase` | Named graph to load into |
  | `:clear_existing` | boolean | `false` | Clear graph before loading |

  ## Examples

      # Analyze a project, get Turtle string
      {:ok, turtle} = ProjectAnalyzer.analyze_project_to_turtle(".")
      File.write!("project.ttl", turtle)

      # Analyze and load directly to knowledge graph
      {:ok, result} = ProjectAnalyzer.analyze_and_load(".",
        base_iri: "https://myapp.org/code#",
        exclude_tests: false
      )

      # Load existing Turtle file to named graph
      {:ok, count} = ProjectAnalyzer.load_turtle_file("project.ttl")

  """

  alias Jidoka.Knowledge.{Engine, Context, NamedGraphs}
  alias TripleStore.SPARQL.UpdateExecutor

  # Default base IRI for generated resources
  @default_base_iri "https://jido.ai/code#"

  # Default named graph for code analysis
  @default_graph :elixir_codebase

  @doc """
  Analyzes an Elixir project and returns the RDF graph as a Turtle string.

  This function replicates the behavior of `mix elixir_ontologies.analyze`
  but returns the Turtle string directly instead of writing to a file.

  ## Parameters

  - `project_path` - Path to project root (containing mix.exs)
  - `opts` - Keyword list of options

  ## Returns

  - `{:ok, turtle_string}` - Successfully analyzed, Turtle as string
  - `{:error, reason}` - Analysis failed

  ## Examples

      {:ok, turtle} = ProjectAnalyzer.analyze_project_to_turtle(".")
      # Write to file
      File.write!("output.ttl", turtle)

      # With options
      {:ok, turtle} = ProjectAnalyzer.analyze_project_to_turtle(".",
        base_iri: "https://myapp.org#",
        include_git: false
      )

  """
  @spec analyze_project_to_turtle(Path.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def analyze_project_to_turtle(project_path, opts \\ []) do
    with {:ok, result} <- analyze_project(project_path, opts),
         {:ok, turtle} <- serialize_to_turtle(result.graph) do
      {:ok, turtle}
    end
  end

  @doc """
  Analyzes a single file and returns the RDF graph as a Turtle string.

  ## Parameters

  - `file_path` - Path to the Elixir source file
  - `opts` - Keyword list of options

  ## Returns

  - `{:ok, turtle_string}` - Successfully analyzed, Turtle as string
  - `{:error, reason}` - Analysis failed

  ## Examples

      {:ok, turtle} = ProjectAnalyzer.analyze_file_to_turtle("lib/my_app.ex")

  """
  @spec analyze_file_to_turtle(Path.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def analyze_file_to_turtle(file_path, opts \\ []) do
    with {:ok, graph} <- analyze_file(file_path, opts),
         {:ok, turtle} <- serialize_to_turtle(graph) do
      {:ok, turtle}
    end
  end

  @doc """
  Analyzes an Elixir project and loads the result into a named graph.

  This combines analysis and loading in a single operation. The graph is
  loaded as quads with all triples in the specified named graph.

  ## Parameters

  - `project_path` - Path to project root
  - `opts` - Keyword list of options

  ## Options

  Analysis options (same as CLI flags):
  - `:base_iri` - Base IRI for generated resources
  - `:include_source` - Include source code text
  - `:include_git` - Include git provenance
  - `:exclude_tests` - Exclude test files (default: true)

  Loading options:
  - `:engine_name` - Knowledge engine name (default: `:knowledge_engine`)
  - `:graph_name` - Named graph to load into (default: `:elixir_codebase`)
  - `:clear_existing` - Clear graph before loading (default: `false`)

  ## Returns

  - `{:ok, result}` - Successfully analyzed and loaded
    - `:triple_count` - Number of triples/quads inserted
    - `:metadata` - Analysis metadata (file_count, module_count, etc.)
    - `:errors` - List of file errors
  - `{:error, reason}` - Operation failed

  ## Examples

      {:ok, result} = ProjectAnalyzer.analyze_and_load(".")
      result.triple_count  # => 1234
      result.metadata.file_count  # => 42

      # Load to custom graph with options
      {:ok, result} = ProjectAnalyzer.analyze_and_load(".",
        base_iri: "https://myapp.org/code#",
        graph_name: :my_codebase,
        clear_existing: true
      )

  """
  @spec analyze_and_load(Path.t(), keyword()) ::
          {:ok, %{triple_count: non_neg_integer(), metadata: map(), errors: list()}} | {:error, term()}
  def analyze_and_load(project_path, opts \\ []) do
    with {:ok, analysis_result} <- analyze_project(project_path, opts),
         {:ok, triple_count} <- load_graph_to_named_graph(
           analysis_result.graph,
           opts
         ) do
      {:ok,
       %{
         triple_count: triple_count,
         metadata: analysis_result.metadata,
         errors: analysis_result.errors
       }}
    end
  end

  @doc """
  Analyzes a single file and loads the result into a named graph.

  ## Parameters

  - `file_path` - Path to the Elixir source file
  - `opts` - Keyword list of options

  ## Returns

  - `{:ok, triple_count}` - Number of triples/quads inserted
  - `{:error, reason}` - Operation failed

  ## Examples

      {:ok, count} = ProjectAnalyzer.analyze_and_load_file("lib/my_app/user.ex")

  """
  @spec analyze_and_load_file(Path.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def analyze_and_load_file(file_path, opts \\ []) do
    with {:ok, graph} <- analyze_file(file_path, opts),
         {:ok, count} <- load_graph_to_named_graph(graph, opts) do
      {:ok, count}
    end
  end

  @doc """
  Loads a Turtle file into a named graph in the knowledge engine.

  Reads a Turtle file (produced by elixir-ontologies) and loads all
  triples into the specified named graph as quads.

  ## Parameters

  - `turtle_file` - Path to the Turtle file
  - `opts` - Keyword list of options

  ## Options

  - `:engine_name` - Knowledge engine name (default: `:knowledge_engine`)
  - `:graph_name` - Named graph to load into (default: `:elixir_codebase`)
  - `:clear_existing` - Clear graph before loading (default: `false`)

  ## Returns

  - `{:ok, triple_count}` - Number of triples/quads loaded
  - `{:error, reason}` - Loading failed

  ## Examples

      {:ok, count} = ProjectAnalyzer.load_turtle_file("project.ttl")

      # Clear existing data first
      {:ok, count} = ProjectAnalyzer.load_turtle_file("project.ttl",
        clear_existing: true
      )

      # Load to custom graph
      {:ok, count} = ProjectAnalyzer.load_turtle_file("project.ttl",
        graph_name: :my_codebase
      )

  """
  @spec load_turtle_file(Path.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def load_turtle_file(turtle_file, opts \\ []) do
    with {:ok, graph} <- read_turtle_file(turtle_file),
         {:ok, count} <- load_graph_to_named_graph(graph, Keyword.put(opts, :source_file, turtle_file)) do
      {:ok, count}
    end
  end

  @doc """
  Loads a Turtle string into a named graph in the knowledge engine.

  ## Parameters

  - `turtle_string` - Turtle format RDF as string
  - `opts` - Keyword list of options (same as load_turtle_file/2)

  ## Returns

  - `{:ok, triple_count}` - Number of triples/quads loaded
  - `{:error, reason}` - Loading failed

  ## Examples

      turtle = File.read!("project.ttl")
      {:ok, count} = ProjectAnalyzer.load_turtle_string(turtle)

  """
  @spec load_turtle_string(String.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def load_turtle_string(turtle_string, opts \\ []) do
    with {:ok, graph} <- parse_turtle_string(turtle_string),
         {:ok, count} <- load_graph_to_named_graph(graph, opts) do
      {:ok, count}
    end
  end

  @doc """
  Clears all triples from a named graph.

  ## Parameters

  - `opts` - Keyword list of options
    - `:graph_name` - Named graph to clear (default: `:elixir_codebase`)
    - `:engine_name` - Knowledge engine name (default: `:knowledge_engine`)

  ## Returns

  - `:ok` - Graph cleared successfully
  - `{:error, reason}` - Failed to clear

  ## Examples

      :ok = ProjectAnalyzer.clear_graph()

      :ok = ProjectAnalyzer.clear_graph(graph_name: :my_codebase)

  """
  @spec clear_graph(keyword()) :: :ok | {:error, term()}
  def clear_graph(opts \\ []) do
    graph_name = Keyword.get(opts, :graph_name, @default_graph)
    engine_name = Keyword.get(opts, :engine_name, :knowledge_engine)

    with {:ok, graph_iri} <- NamedGraphs.iri_string(graph_name),
         ctx <- build_context(engine_name),
         {:ok, _} <- execute_clear_graph(ctx, graph_iri) do
      :ok
    end
  end

  # ===========================================================================
  # Private Helpers - Analysis
  # ===========================================================================

  defp analyze_project(project_path, opts) do
    # Build options for ElixirOntologies.analyze_project
    ont_opts = [
      base_iri: Keyword.get(opts, :base_iri, @default_base_iri),
      include_source_text: Keyword.get(opts, :include_source, false),
      include_git_info: Keyword.get(opts, :include_git, true),
      exclude_tests: Keyword.get(opts, :exclude_tests, true)
    ]

    # Run validation if requested
    validate = Keyword.get(opts, :validate, false)

    case ElixirOntologies.analyze_project(project_path, ont_opts) do
      {:ok, result} ->
        if validate do
          case validate_graph(result.graph) do
            :ok -> {:ok, result}
            {:error, reason} -> {:error, {:validation_failed, reason}}
          end
        else
          {:ok, result}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp analyze_file(file_path, opts) do
    ont_opts = [
      base_iri: Keyword.get(opts, :base_iri, @default_base_iri),
      include_source_text: Keyword.get(opts, :include_source, false),
      include_git_info: Keyword.get(opts, :include_git, true)
    ]

    case ElixirOntologies.analyze_file(file_path, ont_opts) do
      {:ok, graph} -> {:ok, graph}
      {:error, reason} -> {:error, reason}
    end
  end

  # ===========================================================================
  # Private Helpers - Serialization
  # ===========================================================================

  defp serialize_to_turtle(graph) do
    # Convert ElixirOntologies.Graph to RDF.Graph and serialize
    rdf_graph = ElixirOntologies.Graph.to_rdf_graph(graph)
    RDF.Turtle.write_string(rdf_graph)
  end

  # ===========================================================================
  # Private Helpers - Turtle Parsing
  # ===========================================================================

  defp read_turtle_file(file_path) do
    case File.read(file_path) do
      {:ok, content} -> parse_turtle_string(content)
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  defp parse_turtle_string(turtle_string) do
    case RDF.Turtle.read_string(turtle_string) do
      {:ok, graph} -> {:ok, graph}
      {:error, reason} -> {:error, {:turtle_parse_error, reason}}
    end
  end

  # ===========================================================================
  # Private Helpers - Loading to Named Graph
  # ===========================================================================

  defp load_graph_to_named_graph(graph, opts) do
    graph_name = Keyword.get(opts, :graph_name, @default_graph)
    engine_name = Keyword.get(opts, :engine_name, :knowledge_engine)
    clear_existing = Keyword.get(opts, :clear_existing, false)

    with {:ok, graph_iri} <- NamedGraphs.iri_string(graph_name),
         ctx <- build_context(engine_name),
         :ok <- maybe_clear_graph(clear_existing, ctx, graph_iri),
         {:ok, count} <- insert_quads(ctx, graph, graph_iri) do
      {:ok, count}
    end
  end

  defp build_context(engine_name) do
    Engine.context(engine_name)
    |> Map.put(:transaction, nil)
    |> Context.with_permit_all()
  end

  defp maybe_clear_graph(false, _ctx, _graph_iri), do: :ok

  defp maybe_clear_graph(true, ctx, graph_iri) do
    case execute_clear_graph(ctx, graph_iri) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:clear_failed, reason}}
    end
  end

  defp execute_clear_graph(ctx, graph_iri) do
    # Clear all triples in the named graph
    delete_query = """
    DELETE {
      GRAPH <#{graph_iri}> {
        ?s ?p ?o .
      }
    }
    WHERE {
      GRAPH <#{graph_iri}> {
        ?s ?p ?o .
      }
    }
    """

    TripleStore.update(ctx, delete_query)
  end

  defp insert_quads(ctx, graph, graph_iri) do
    # Convert RDF.Graph triples to quad format
    quads =
      graph
      |> RDF.Graph.triples()
      |> Enum.map(fn {s, p, o} ->
        {:quad, rdf_term_to_ast(s), rdf_term_to_ast(p), rdf_term_to_ast(o),
         {:named_node, graph_iri}}
      end)

    case UpdateExecutor.execute_insert_data(ctx, quads) do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, {:insert_failed, reason}}
    end
  end

  # Convert RDF terms to AST format expected by UpdateExecutor
  defp rdf_term_to_ast(%RDF.IRI{} = iri) do
    {:named_node, RDF.IRI.to_string(iri)}
  end

  defp rdf_term_to_ast(%RDF.BlankNode{} = bn) do
    {:blank_node, to_string(bn)}
  end

  defp rdf_term_to_ast(%RDF.Literal{} = lit) do
    value = RDF.Literal.value(lit)
    # Check for typed literal with language
    case RDF.Literal.language(lit) do
      nil -> {:literal, :simple, value}
      lang -> {:literal, :lang, value, lang}
    end
  end

  defp rdf_term_to_ast(%RDF.LangString{} = lit) do
    {:literal, :lang, RDF.Literal.value(lit), RDF.Literal.language(lit)}
  end

  # Fallback for other XSD types
  defp rdf_term_to_ast(literal) do
    {:literal, :simple, RDF.Literal.value(literal)}
  end

  # ===========================================================================
  # Private Helpers - Validation
  # ===========================================================================

  defp validate_graph(graph) do
    # ElixirOntologies.Validator.validate/1 expects a Graph
    rdf_graph = ElixirOntologies.Graph.to_rdf_graph(graph)

    case ElixirOntologies.Validator.validate(rdf_graph) do
      {:ok, report} ->
        if report.conforms? do
          :ok
        else
          violations =
            Enum.filter(report.results, fn r -> r.severity == :violation end)
            |> Enum.map(fn v -> v.message end)

          {:error, {:validation_violations, violations}}
        end

      {:error, reason} ->
        {:error, {:validation_error, reason}}
    end
  end
end
