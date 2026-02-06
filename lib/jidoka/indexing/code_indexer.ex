defmodule Jidoka.Indexing.CodeIndexer do
  @moduledoc """
  GenServer wrapper around ElixirOntologies for code indexing.

  This module integrates the elixir-ontologies library to analyze Elixir
  source code and store the resulting RDF triples in the `:elixir_codebase`
  named graph.

  ## Architecture

  The elixir-ontologies library already provides:
  - AST parsing via `Code.string_to_quoted/2`
  - 30+ extractors for all Elixir constructs (modules, functions, structs, etc.)
  - RDF builders for triple generation
  - Project file discovery

  This CodeIndexer acts as an integration layer that:
  1. Calls `ElixirOntologies.analyze_project/2` and `analyze_file/2`
  2. Inserts the resulting RDF graph into our `:elixir_codebase` named graph
  3. Tracks indexing status via `IndexingStatusTracker`
  4. Provides a convenient GenServer API for on-demand indexing

  ## Client API

  * `start_link/1` - Starts the CodeIndexer GenServer
  * `index_project/2` - Indexes an entire Mix project
  * `index_file/2` - Indexes a single Elixir source file
  * `get_stats/1` - Gets indexing statistics

  ## Examples

      # Index an entire project
      {:ok, result} = CodeIndexer.index_project("/path/to/project")

      # Index a single file
      {:ok, info} = CodeIndexer.index_file("lib/my_app.ex")

      # Get indexing statistics
      {:ok, stats} = CodeIndexer.get_stats()

  """

  use GenServer
  require Logger

  alias Jidoka.Knowledge.{Engine, NamedGraphs}
  alias Jidoka.Indexing.IndexingStatusTracker
  alias Jidoka.Utils.PathValidator

  # Default engine name
  @default_engine :knowledge_engine

  # Default base IRI for generated resources
  @default_base_iri "https://jido.ai/code#"

  # Maximum timeout for indexing operations (5 minutes)
  @max_timeout 300_000

  # ========================================================================
  # Client API
  # ========================================================================

  @doc """
  Starts the CodeIndexer GenServer.

  ## Options

  * `:name` - The name of the GenServer (default: `__MODULE__`)
  * `:engine_name` - The Knowledge Engine name (default: `:knowledge_engine`)
  * `:tracker_name` - The IndexingStatusTracker name (default: `IndexingStatusTracker`)

  ## Examples

      {:ok, pid} = CodeIndexer.start_link()

      {:ok, pid} = CodeIndexer.start_link(
        name: MyCodeIndexer,
        engine_name: :knowledge_engine
      )

  """
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Indexes an entire Mix project.

  Analyzes all `.ex` and `.exs` files in the project and inserts the
  resulting RDF triples into the `:elixir_codebase` named graph.

  ## Parameters

  * `project_root` - Path to the project root (containing mix.exs)
  * `opts` - Keyword list of options

  ## Options

  * `:name` - The name of the CodeIndexer GenServer (default: `__MODULE__`)
  * `:base_iri` - Base IRI for generated resources (default: `"https://jido.ai/code#"`)
  * `:exclude_tests` - Skip test/ directories (default: `true`)
  * `:include_source_text` - Include source code in graph (default: `false`)
  * `:include_git_info` - Include git provenance (default: `false`)

  ## Returns

  * `{:ok, result}` - Successfully indexed project
    - `:metadata` - Map with file_count, module_count, error_count
    - `:errors` - List of {file_path, error} tuples
  * `{:error, reason}` - Indexing failed

  ## Examples

      {:ok, result} = CodeIndexer.index_project(".")
      # result.metadata.file_count => number of files indexed
      # result.metadata.module_count => number of modules found

  """
  @spec index_project(Path.t(), keyword()) ::
          {:ok, %{metadata: map(), errors: list()}} | {:error, term()}
  def index_project(project_root, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    timeout = Keyword.get(opts, :timeout, @max_timeout)

    # Get allowed directories from options or use default
    allowed_dirs =
      case Keyword.get(opts, :allowed_dirs) do
        nil -> PathValidator.allowed_directories()
        dirs when is_list(dirs) -> dirs
        dir when is_binary(dir) -> [dir]
      end

    # Validate project root is a directory and within allowed paths
    case PathValidator.validate_within(project_root, allowed_dirs) do
      :ok ->
        GenServer.call(name, {:index_project, project_root, opts}, timeout)

      {:error, reason} ->
        {:error, {:path_validation_failed, reason}}
    end
  end

  @doc """
  Indexes a single Elixir source file.

  Analyzes the file and inserts the resulting RDF triples into the
  `:elixir_codebase` named graph.

  ## Parameters

  * `file_path` - Path to the Elixir source file
  * `opts` - Keyword list of options

  ## Options

  * `:name` - The name of the CodeIndexer GenServer (default: `__MODULE__`)
  * `:base_iri` - Base IRI for generated resources
  * `:include_source_text` - Include source code in graph
  * `:include_git_info` - Include git provenance

  ## Returns

  * `{:ok, info}` - Successfully indexed file
    - `:triple_count` - Number of triples inserted
  * `{:error, reason}` - Indexing failed

  ## Examples

      {:ok, info} = CodeIndexer.index_file("lib/my_app/users.ex")
      # info.triple_count => number of triples inserted

  """
  @spec index_file(Path.t(), keyword()) ::
          {:ok, %{triple_count: non_neg_integer()}} | {:error, term()}
  def index_file(file_path, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    timeout = Keyword.get(opts, :timeout, @max_timeout)

    # Get allowed directories from options or use default
    allowed_dirs =
      case Keyword.get(opts, :allowed_dirs) do
        nil -> PathValidator.allowed_directories()
        dirs when is_list(dirs) -> dirs
        dir when is_binary(dir) -> [dir]
      end

    # Validate file path
    case PathValidator.safe_path?(file_path,
      allowed_dirs: allowed_dirs,
      allowed_extensions: [".ex", ".exs"]
    ) do
      :ok ->
        GenServer.call(name, {:index_file, file_path, opts}, timeout)

      {:error, reason} ->
        {:error, {:path_validation_failed, reason}}
    end
  end

  @doc """
  Gets indexing statistics.

  Returns counts of files in each indexing state for a project.

  ## Parameters

  * `project_root` - Path to the project root
  * `opts` - Keyword list of options

  ## Options

  * `:name` - The name of the CodeIndexer GenServer (default: `__MODULE__`)

  ## Returns

  * `{:ok, stats}` - Statistics map with keys:
    - `:total` - Total files tracked
    - `:pending` - Files pending indexing
    - `:in_progress` - Files currently being indexed
    - `:completed` - Files successfully indexed
    - `:failed` - Files that failed to index

  ## Examples

      {:ok, stats} = CodeIndexer.get_stats(".")
      # stats.completed => number of successfully indexed files
      # stats.failed => number of failed files

  """
  @spec get_stats(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_stats(project_root, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:get_stats, project_root})
  end

  @doc """
  Re-indexes a file, removing any previous triples.

  ## Parameters

  * `file_path` - Path to the Elixir source file
  * `opts` - Keyword list of options (same as `index_file/2`)

  ## Returns

  * `{:ok, info}` - Successfully re-indexed file
  * `{:error, reason}` - Re-indexing failed

  ## Examples

      {:ok, info} = CodeIndexer.reindex_file("lib/my_app/users.ex")

  """
  @spec reindex_file(Path.t(), keyword()) ::
          {:ok, %{triple_count: non_neg_integer()}} | {:error, term()}
  def reindex_file(file_path, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:reindex_file, file_path, opts})
  end

  @doc """
  Removes all triples associated with a file.

  ## Parameters

  * `file_path` - Path to the source file
  * `opts` - Keyword list of options

  ## Options

  * `:name` - The name of the CodeIndexer GenServer (default: `__MODULE__`)

  ## Returns

  * `:ok` - Triples removed successfully
  * `{:error, reason}` - Removal failed

  """
  @spec remove_file(Path.t(), keyword()) :: :ok | {:error, term()}
  def remove_file(file_path, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:remove_file, file_path})
  end

  # ========================================================================
  # Server Callbacks
  # ========================================================================

  @impl true
  def init(opts) do
    state = %{
      engine_name: Keyword.get(opts, :engine_name, @default_engine),
      tracker_name: Keyword.get(opts, :tracker_name, IndexingStatusTracker),
      base_iri: Keyword.get(opts, :base_iri, @default_base_iri)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:index_project, project_root, opts}, _from, state) do
    result = do_index_project(project_root, state, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:index_file, file_path, opts}, _from, state) do
    result = do_index_file(file_path, state, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_file, file_path}, _from, state) do
    result = remove_file_triples(file_path, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:reindex_file, file_path, opts}, _from, state) do
    # First remove the file's triples
    result = do_reindex_file(file_path, state, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_stats, project_root}, _from, state) do
    result = IndexingStatusTracker.get_project_status(project_root, name: state.tracker_name)
    {:reply, result, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message in CodeIndexer: #{inspect(msg)}")
    {:noreply, state}
  end

  # ========================================================================
  # Private Helpers
  # ========================================================================

  defp do_index_project(project_root, state, opts) do
    # Normalize project path
    project_root = Path.expand(project_root)

    # Validate project path
    cond do
      not File.dir?(project_root) ->
        {:error, {:not_a_directory, project_root}}

      true ->
        Logger.info("Starting project indexing: #{project_root}")

        # Build elixir-ontologies config options
        # Pass individual options since analyze_project doesn't accept a :config key
        ont_opts = [
          base_iri: Keyword.get(opts, :base_iri, @default_base_iri),
          include_source_text: Keyword.get(opts, :include_source_text, false),
          include_git_info: Keyword.get(opts, :include_git_info, false),
          exclude_tests: Keyword.get(opts, :exclude_tests, true)
        ]

        # Call ElixirOntologies.analyze_project
        case ElixirOntologies.analyze_project(project_root, ont_opts) do
          {:ok, result} ->
            # Insert the resulting graph into elixir_codebase
            triple_count = insert_graph(result.graph, state)

            Logger.info(
              "Project indexing complete: #{result.metadata.file_count} files, " <>
                "#{result.metadata.module_count} modules, #{triple_count} triples"
            )

            {:ok,
             %{
               metadata: %{
                 file_count: result.metadata.file_count,
                 module_count: result.metadata.module_count,
                 triple_count: triple_count,
                 error_count: length(result.errors)
               },
               errors: result.errors
             }}

          {:error, reason} ->
            Logger.error("Project indexing failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp do_reindex_file(file_path, state, opts) do
    # First remove the file's triples
    with :ok <- remove_file_triples(file_path, state),
         {:ok, info} <- do_index_file(file_path, state, opts) do
      {:ok, info}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_index_file(file_path, state, opts) do
    # Normalize file path
    file_path = Path.expand(file_path)

    cond do
      # Validate file exists
      not File.exists?(file_path) ->
        {:error, {:file_not_found, file_path}}

      # Must be .ex or .exs file
      Path.extname(file_path) not in [".ex", ".exs"] ->
        {:error, {:invalid_file_type, Path.extname(file_path)}}

      true ->
        # Mark as in_progress
        IndexingStatusTracker.start_indexing(
          file_path,
          name: state.tracker_name
        )

        Logger.debug("Indexing file: #{file_path}")

        # Build elixir-ontologies config options
        # Pass individual options since analyze_file doesn't accept a :config key
        ont_opts = [
          base_iri: Keyword.get(opts, :base_iri, @default_base_iri),
          include_source_text: Keyword.get(opts, :include_source_text, false),
          include_git_info: Keyword.get(opts, :include_git_info, false)
        ]

        # Call ElixirOntologies.analyze_file
        case ElixirOntologies.analyze_file(file_path, ont_opts) do
          {:ok, graph} ->
            # Insert into elixir_codebase graph
            triple_count = insert_graph(graph, state)

            # Mark as completed
            IndexingStatusTracker.complete_indexing(
              file_path,
              triple_count,
              name: state.tracker_name
            )

            Logger.debug("Indexed #{file_path}: #{triple_count} triples")

            {:ok, %{triple_count: triple_count}}

          {:error, reason} ->
            # Mark as failed
            error_msg = inspect(reason)
            IndexingStatusTracker.fail_indexing(file_path, error_msg, name: state.tracker_name)

            Logger.error("Failed to index #{file_path}: #{error_msg}")

            {:error, reason}
        end
    end
  end

  defp insert_graph(graph, state) do
    ctx = engine_context(state)

    # Get the elixir_codebase graph IRI
    {:ok, graph_iri} = NamedGraphs.iri_string(:elixir_codebase)

    # Convert RDF.Graph triples to quad format
    quads =
      graph
      |> rdf_graph_triples()
      |> Enum.map(fn {s, p, o} ->
        {:quad, rdf_to_ast(s), rdf_to_ast(p), rdf_to_ast(o), {:named_node, graph_iri}}
      end)

    # Insert via UpdateExecutor
    case TripleStore.SPARQL.UpdateExecutor.execute_insert_data(ctx, quads) do
      {:ok, count} ->
        count

      {:error, reason} ->
        Logger.error("Failed to insert graph into knowledge store: #{inspect(reason)}")
        0
    end
  end

  # Handle both our Graph wrapper and RDF.Graph
  defp rdf_graph_triples(%ElixirOntologies.Graph{} = graph) do
    # ElixirOntologies.Graph has a to_rdf_graph/1 function
    ElixirOntologies.Graph.to_rdf_graph(graph)
    |> RDF.Graph.triples()
  end

  defp rdf_graph_triples(%RDF.Graph{} = graph), do: RDF.Graph.triples(graph)
  defp rdf_graph_triples(_), do: []

  defp remove_file_triples(file_path, state) do
    ctx = engine_context(state)
    base_iri = state.base_iri

    {:ok, graph_iri} = NamedGraphs.iri_string(:elixir_codebase)

    # Parse the file to get module names, then delete by module IRI
    # elixir-ontologies doesn't link modules to source files directly
    module_names = parse_file_for_modules(file_path)

    # If we couldn't parse the file, try to clean up what we can
    # (e.g., if file was deleted, we can't parse it)
    modules_to_delete =
      if module_names == [] do
        # File might not exist or be unparseable
        # Try to find modules that were last indexed from this file
        # by checking the IndexingStatusTracker
        Logger.debug("Could not parse modules from #{file_path}, attempting cleanup anyway")
        []
      else
        module_names
      end

    # Delete all triples for each module
    results =
      Enum.map(modules_to_delete, fn module_name ->
        module_iri = "#{base_iri}#{module_name}"
        delete_module_triples(ctx, graph_iri, module_iri)
      end)

    # If all deletions succeeded or there was nothing to delete, return :ok
    if Enum.all?(results, fn
         :ok -> true
         {:error, :not_found} -> true
         _ -> false
       end) do
      :ok
    else
      # At least one deletion failed
      {:error, results}
    end
  end

  # Parse an Elixir source file and extract module names
  defp parse_file_for_modules(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        extract_module_names(content)

      {:error, _reason} ->
        []
    end
  end

  # Extract module names from Elixir source code
  defp extract_module_names(content) do
    # Use Code.string_to_quoted to get AST, then traverse for defmodule
    case Code.string_to_quoted(content, columns: true) do
      {:ok, ast} ->
        extract_modules_from_ast(ast, [])

      {:error, _reason} ->
        []
    end
  end

  defp extract_modules_from_ast(ast, acc) do
    case ast do
      {:defmodule, _meta, [{:__aliases__, _, parts}, _body]} ->
        [List.last(parts) | acc]

      {:defmodule, _meta, [{:__aliases__, _, parts}, _attrs, _body]} ->
        [List.last(parts) | acc]

      # Handle nested module definitions
      {:__block__, _, statements} ->
        Enum.reduce(statements, acc, fn stmt, inner_acc ->
          extract_modules_from_ast(stmt, inner_acc)
        end)

      # Other nodes - ignore
      _ ->
        acc
    end
  end

  # Delete all triples where subject is the module IRI
  defp delete_module_triples(ctx, graph_iri, module_iri) do
    # Delete triples where subject is the module IRI
    subject_query = """
    DELETE {
      GRAPH <#{graph_iri}> {
        <#{module_iri}> ?p ?o .
      }
    }
    WHERE {
      GRAPH <#{graph_iri}> {
        <#{module_iri}> ?p ?o .
      }
    }
    """

    # Delete triples where object is the module IRI
    # (e.g., functions with belongsTo -> Module)
    object_query = """
    DELETE {
      GRAPH <#{graph_iri}> {
        ?s ?p <#{module_iri}> .
      }
    }
    WHERE {
      GRAPH <#{graph_iri}> {
        ?s ?p <#{module_iri}> .
      }
    }
    """

    with {:ok, _} <- TripleStore.update(ctx, subject_query),
         {:ok, _} <- TripleStore.update(ctx, object_query) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to delete triples for module #{module_iri}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp rdf_to_ast(%RDF.IRI{} = iri), do: {:named_node, RDF.IRI.to_string(iri)}

  defp rdf_to_ast(%RDF.Literal{} = lit) do
    {:literal, :simple, RDF.Literal.value(lit)}
  end

  defp rdf_to_ast(%RDF.LangString{} = lit) do
    {:literal, :lang, RDF.Literal.value(lit), RDF.Literal.language(lit)}
  end

  defp rdf_to_ast(%RDF.XSD.String{} = lit) do
    {:literal, :simple, RDF.Literal.value(lit)}
  end

  defp rdf_to_ast(%RDF.XSD.Integer{} = lit) do
    {:literal, :simple, RDF.Literal.value(lit)}
  end

  defp rdf_to_ast(%RDF.XSD.Boolean{} = lit) do
    {:literal, :simple, RDF.Literal.value(lit)}
  end

  defp rdf_to_ast(%RDF.XSD.Double{} = lit) do
    {:literal, :simple, RDF.Literal.value(lit)}
  end

  defp rdf_to_ast(%RDF.XSD.Decimal{} = lit) do
    {:literal, :simple, RDF.Literal.value(lit)}
  end

  defp rdf_to_ast(%RDF.XSD.Float{} = lit) do
    {:literal, :simple, RDF.Literal.value(lit)}
  end

  defp rdf_to_ast(%RDF.XSD.DateTime{} = lit) do
    {:literal, :simple, RDF.Literal.value(lit)}
  end

  defp rdf_to_ast(%RDF.BlankNode{} = bn) do
    {:blank_node, to_string(bn)}
  end

  defp engine_context(state) do
    Engine.context(state.engine_name)
    |> Map.put(:transaction, nil)
    |> Jidoka.Knowledge.Context.with_permit_all()
  end
end
