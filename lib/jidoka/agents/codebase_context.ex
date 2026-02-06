defmodule Jidoka.Agents.CodebaseContext do
  @moduledoc """
  Codebase context enrichment for LLM context building.

  This module provides integration between the ContextManager and the indexed
  codebase knowledge graph. It intelligently enriches context with:
  - Module information from active files
  - Related modules based on dependencies
  - Project structure overview
  - Cached query results for performance

  ## Architecture

  ```
  ContextManager
       │
       ▼
  CodebaseContext (this module)
       │
       ├── Cache (ETS table)
       │
       └── Codebase.Queries
             │
             ▼
       :elixir_codebase graph
  ```

  ## Usage

  The module is typically used by ContextManager to enrich context with
  codebase information:

      {:ok, enriched} = CodebaseContext.enrich(active_files, opts)
      {:ok, module_info} = CodebaseContext.get_module_info("MyApp.User")

  ## Caching

  Query results are cached in an ETS table with a configurable TTL (default 5 minutes).
  Cache keys are based on query type and parameters.

  ## Options

  * `:cache_ttl` - Cache time-to-live in milliseconds (default: 300_000)
  * `:dependency_depth` - How deep to follow dependencies (default: 1)
  * `:max_modules` - Maximum modules to include (default: 20)
  * `:engine_name` - Knowledge engine name (default: :knowledge_engine)

  """

  use GenServer
  require Logger

  alias Jidoka.Codebase.Queries
  alias Jidoka.Knowledge.{Engine, Context, NamedGraphs, SparqlHelpers}

  @type context_opts :: [
          {:cache_ttl, pos_integer()},
          {:dependency_depth, non_neg_integer()},
          {:max_modules, pos_integer()},
          {:engine_name, atom()}
        ]

  @type module_info :: %{
          name: String.t(),
          iri: String.t(),
          file: String.t() | nil,
          documentation: String.t() | nil,
          public_functions: [function_summary()],
          private_functions: [function_summary()],
          structs: [struct_summary()],
          behaviours: [String.t()],
          protocols: [String.t()],
          dependencies: [String.t()]
        }

  @type function_summary :: %{
          name: String.t(),
          arity: non_neg_integer(),
          visibility: :public | :private
        }

  @type struct_summary :: %{
          module: String.t(),
          fields: [String.t()]
        }

  # Default configuration
  @default_cache_ttl 300_000
  @default_dependency_depth 1
  @max_dependency_depth 5
  @default_max_modules 20
  @default_engine :knowledge_engine
  @max_cache_size 1000

  # Cache table
  @cache_table :codebase_context_cache

  # ========================================================================
  # Client API
  # ========================================================================

  @doc """
  Starts the CodebaseContext cache server.

  ## Options

  * `:name` - GenServer name (default: `__MODULE__`)
  * `:cache_ttl` - Cache TTL in milliseconds (default: 300_000)

  ## Examples

      {:ok, pid} = CodebaseContext.start_link()
      {:ok, pid} = CodebaseContext.start_link(name: :my_cache, cache_ttl: 600_000)

  """
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Enriches a list of active files with codebase context.

  Analyzes the active files to find related modules and builds a rich
  codebase context including dependencies and related code.

  ## Parameters

  * `active_files` - List of active file paths
  * `opts` - Enrichment options

  ## Options

  * `:dependency_depth` - How deep to follow dependencies (default: 1)
  * `:max_modules` - Maximum modules to include (default: 20)
  * `:engine_name` - Knowledge engine name (default: :knowledge_engine)

  ## Returns

  * `{:ok, context_map}` - Codebase context map
  * `{:error, reason}` - Failed to build context

  ## Context Structure

  ```elixir
  %{
    modules: [
      %{
        name: "MyApp.User",
        file: "lib/my_app/user.ex",
        documentation: "User schema and operations",
        public_functions: [%{name: "get_user", arity: 1}, ...],
        dependencies: ["MyApp.Repo", "Ecto.Schema"]
      }
    ],
    project_structure: %{
      total_modules: 42,
      indexed_files: 15
    },
    metadata: %{
      modules_count: 3,
      depth_used: 1,
      timestamp: ...
    }
  }
  ```

  ## Examples

      {:ok, context} = CodebaseContext.enrich(
        ["lib/my_app/user.ex", "lib/my_app/post.ex"],
        dependency_depth: 1
      )

  """
  @spec enrich([Path.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def enrich(active_files, opts \\ []) when is_list(active_files) do
    dependency_depth = Keyword.get(opts, :dependency_depth, @default_dependency_depth)
    max_modules = Keyword.get(opts, :max_modules, @default_max_modules)
    engine_name = Keyword.get(opts, :engine_name, @default_engine)

    with {:ok, module_names} <- extract_module_names_from_files(active_files, engine_name),
         {:ok, modules} <-
           get_modules_with_dependencies(module_names, dependency_depth, max_modules, engine_name),
         {:ok, project_stats} <- get_project_statistics(engine_name: engine_name) do
      context = %{
        modules: format_modules_for_context(modules),
        project_structure: project_stats,
        metadata: %{
          modules_count: length(modules),
          depth_used: dependency_depth,
          max_modules: max_modules,
          timestamp: DateTime.utc_now()
        }
      }

      {:ok, context}
    else
      {:error, reason} ->
        Logger.warning("CodebaseContext enrichment failed: #{inspect(reason)}")
        # Return empty context instead of error
        {:ok, empty_context()}
    end
  end

  @doc """
  Gets information about a specific module.

  Results are cached for TTL duration.

  ## Parameters

  * `module_name` - Module name as string or atom
  * `opts` - Additional options

  ## Options

  * `:engine_name` - Knowledge engine name
  * `:use_cache` - Whether to use cache (default: true)

  ## Returns

  * `{:ok, module_info}` - Module information
  * `{:error, :not_found}` - Module not found in codebase
  * `{:error, reason}` - Query failed

  ## Examples

      {:ok, info} = CodebaseContext.get_module_info("MyApp.User")
      info.name #=> "MyApp.User"
      info.public_functions #=> [%{name: "get_user", arity: 1}, ...]

  """
  @spec get_module_info(String.t() | atom(), keyword()) :: {:ok, module_info()} | {:error, term()}
  def get_module_info(module_name, opts \\ [])
      when is_binary(module_name) or is_atom(module_name) do
    module_str = to_string(module_name)
    engine_name = Keyword.get(opts, :engine_name, @default_engine)
    use_cache = Keyword.get(opts, :use_cache, true)

    cache_key = {:module_info, module_str}

    if use_cache do
      case get_cached(cache_key) do
        {:ok, cached} ->
          {:ok, cached}

        :miss ->
          fetch_and_cache_module_info(module_str, engine_name, cache_key)
      end
    else
      fetch_module_info(module_str, engine_name)
    end
  end

  @doc """
  Finds modules related to the given module names.

  Related modules include:
  - Direct dependencies
  - Modules in the same directory
  - Modules that reference the given modules

  ## Parameters

  * `module_names` - List of module names
  * `opts` - Additional options

  ## Options

  * `:include_dependencies` - Include dependency modules (default: true)
  * `:include_referenced_by` - Include modules that reference (default: false)
  * `:max_results` - Maximum results (default: 20)
  * `:engine_name` - Knowledge engine name

  ## Returns

  * `{:ok, [module_info]}` - List of related modules
  * `{:error, reason}` - Query failed

  ## Examples

      {:ok, related} = CodebaseContext.find_related(
        ["MyApp.User"],
        include_dependencies: true,
        max_results: 10
      )

  """
  @spec find_related([String.t()], keyword()) :: {:ok, [module_info()]} | {:error, term()}
  def find_related(module_names, opts \\ []) when is_list(module_names) do
    include_deps = Keyword.get(opts, :include_dependencies, true)
    max_results = Keyword.get(opts, :max_results, 20)
    engine_name = Keyword.get(opts, :engine_name, @default_engine)

    related = []

    related =
      if include_deps do
        Enum.flat_map(module_names, fn name ->
          case get_dependencies(name, engine_name: engine_name) do
            {:ok, deps} -> deps
            _ -> []
          end
        end)
      else
        related
      end

    # Limit results and get full info
    related
    |> Enum.uniq()
    |> Enum.take(max_results)
    |> Enum.map(fn name ->
      case get_module_info(name, engine_name: engine_name) do
        {:ok, info} -> info
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> then(&{:ok, &1})
  end

  @doc """
  Gets the dependency chain for a module.

  ## Parameters

  * `module_name` - Module name
  * `depth` - How deep to traverse (default: 1)
  * `opts` - Additional options

  ## Returns

  * `{:ok, [String.t()]}` - List of dependent module names
  * `{:error, reason}` - Query failed

  ## Examples

      {:ok, deps} = CodebaseContext.get_dependencies("MyApp.User", 1)

  """
  @spec get_dependencies(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def get_dependencies(module_name, opts \\ []) when is_binary(module_name) do
    depth = Keyword.get(opts, :depth, 1)
    engine_name = Keyword.get(opts, :engine_name, @default_engine)

    cache_key = {:dependencies, module_name, depth}

    case get_cached(cache_key) do
      {:ok, cached} ->
        {:ok, cached}

      :miss ->
        case fetch_dependencies(module_name, depth, engine_name) do
          {:ok, deps} ->
            put_cached(cache_key, deps)
            {:ok, deps}

          error ->
            error
        end
    end
  end

  @doc """
  Gets project statistics from the codebase.

  ## Parameters

  * `opts` - Additional options

  ## Options

  * `:engine_name` - Knowledge engine name

  ## Returns

  * `{:ok, stats}` - Project statistics

  ## Examples

      {:ok, stats} = CodebaseContext.get_project_statistics()
      stats.total_modules #=> 42

  """
  @spec get_project_statistics(keyword()) :: {:ok, map()} | {:error, term()}
  def get_project_statistics(opts \\ []) do
    engine_name = Keyword.get(opts, :engine_name, @default_engine)

    case Queries.list_modules(engine_name: engine_name, limit: 10_000) do
      {:ok, modules} ->
        stats = %{
          total_modules: length(modules),
          indexed_files: Enum.uniq(Enum.map(modules, & &1[:file])) |> length(),
          last_updated: DateTime.utc_now()
        }

        {:ok, stats}

      {:error, reason} ->
        {:ok, %{total_modules: 0, indexed_files: 0, last_updated: DateTime.utc_now()}}
    end
  end

  @doc """
  Invalidates the codebase context cache.

  Use this after reindexing to ensure fresh data.

  ## Examples

      :ok = CodebaseContext.invalidate_cache()

  """
  @spec invalidate_cache() :: :ok
  def invalidate_cache do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :invalidate_cache, 5000)
    else
      :ok
    end
  end

  @doc """
  Gets cache statistics for monitoring.

  Returns information about the current state of the cache.

  ## Returns

  * `{:ok, stats}` - Map with cache statistics:
    - `:size` - Current number of entries in cache
    - `:max_size` - Maximum cache size before eviction
    - `:memory` - Memory usage in bytes
    - `:memory_kb` - Memory usage in kilobytes

  ## Examples

      {:ok, stats} = CodebaseContext.get_cache_stats()
      stats.size #=> 42
      stats.max_size #=> 1000

  """
  @spec get_cache_stats() :: {:ok, map()} | {:error, term()}
  def get_cache_stats do
    if Process.whereis(__MODULE__) do
      try do
        size = :ets.info(@cache_table, :size)
        memory = :ets.info(@cache_table, :memory) * :erlang.system_info(:wordsize)

        {:ok,
         %{
           size: size,
           max_size: @max_cache_size,
           memory: memory,
           memory_kb: div(memory, 1024)
         }}
      rescue
        ArgumentError -> {:error, :cache_not_available}
      end
    else
      {:error, :not_started}
    end
  end

  # ========================================================================
  # Server Callbacks
  # ========================================================================

  @impl true
  def init(opts) do
    cache_ttl = Keyword.get(opts, :cache_ttl, @default_cache_ttl)

    # Create ETS table for caching
    table =
      :ets.new(@cache_table, [
        :named_table,
        :set,
        :public,
        read_concurrency: true
      ])

    # Setup periodic cache cleanup
    {:ok, _ref} = :timer.send_interval(cache_ttl, self(), :cleanup_cache)

    Logger.info("CodebaseContext cache started (TTL: #{cache_ttl}ms)")

    {:ok, %{cache_table: table, cache_ttl: cache_ttl}}
  end

  @impl true
  def handle_call(:invalidate_cache, _from, state) do
    :ets.delete_all_objects(@cache_table)
    Logger.debug("CodebaseContext cache invalidated")
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup_cache, state) do
    # ETS doesn't have built-in TTL, so we'd need to implement timestamp-based expiry
    # For now, we just do periodic full invalidation which is simpler
    # In production, you might want a more sophisticated approach
    :ets.delete_all_objects(@cache_table)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unexpected message in CodebaseContext: #{inspect(msg)}")
    {:noreply, state}
  end

  # ========================================================================
  # Private Helpers
  # ========================================================================

  # Extract module names from active file paths
  defp extract_module_names_from_files(file_paths, engine_name) do
    # First, try to query the codebase for modules by file path
    module_names =
      Enum.flat_map(file_paths, fn path ->
        case find_modules_by_file(path, engine_name) do
          {:ok, modules} -> modules
          _ -> []
        end
      end)

    if Enum.empty?(module_names) do
      # Fallback: try to guess module name from file path
      guessed = Enum.flat_map(file_paths, &guess_module_from_path/1)
      {:ok, guessed}
    else
      {:ok, module_names}
    end
  end

  # Find modules by file path from the codebase
  defp find_modules_by_file(file_path, engine_name) do
    ctx = build_context(engine_name)
    file_literal = SparqlHelpers.string_literal(file_path)

    query = """
    PREFIX elixir: <https://w3id.org/elixir-code/structure#>
    PREFIX jido: <https://jido.ai/code#>

    SELECT ?module_name
    WHERE {
      GRAPH <https://jido.ai/graphs/elixir-codebase> {
        ?module a elixir:Module ;
                 elixir:moduleName ?module_name ;
                 jido:sourceFile #{file_literal} .
      }
    }
    """

    case TripleStore.SPARQL.Query.query(ctx, query, []) do
      {:ok, results} ->
        names =
          Enum.map(results, fn result ->
            case Map.get(result, "module_name") do
              {:literal, :simple, name} -> name
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, names}

      {:error, _reason} ->
        {:ok, []}
    end
  end

  # Guess module name from file path (heuristic)
  defp guess_module_from_path(file_path) do
    # Remove common prefixes
    path =
      file_path
      |> String.replace_prefix("lib/", "")
      |> String.replace_prefix("test/", "")
      |> String.replace_suffix(".ex", "")
      |> String.replace_suffix(".exs", "")
      |> String.replace("/", ".")

    # Capitalize each part
    module_name =
      path
      |> String.split(".")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(".")

    # Only return if it looks like a valid module name
    if String.length(module_name) > 0 and String.contains?(module_name, ".") do
      [module_name]
    else
      []
    end
  end

  # Get modules with their dependencies
  defp get_modules_with_dependencies(module_names, depth, max_modules, engine_name) do
    {modules, _visited} =
      Enum.reduce_while(module_names, {[], MapSet.new()}, fn name, {acc, visited} ->
        if MapSet.size(visited) >= max_modules do
          {:halt, {acc, visited}}
        else
          case get_module_with_deps(name, depth, visited, engine_name) do
            {:ok, module_info, new_visited} ->
              {:cont, {[module_info | acc], new_visited}}

            :error ->
              {:cont, {acc, visited}}
          end
        end
      end)

    {:ok, Enum.reverse(modules)}
  end

  # Get a single module with its dependencies
  defp get_module_with_deps(module_name, depth, visited, engine_name) do
    # Enforce maximum depth limit to prevent excessive recursion
    depth = min(depth, @max_dependency_depth)

    if MapSet.member?(visited, module_name) do
      # Cycle detected - module already in dependency chain
      :error
    else
      case get_module_info(module_name, engine_name: engine_name) do
        {:ok, info} ->
          new_visited = MapSet.put(visited, module_name)

          if depth > 0 do
            case get_dependencies(module_name, limit: 100, engine_name: engine_name) do
              {:ok, deps} ->
                info_with_deps = Map.put(info, :dependencies, deps)
                {:ok, info_with_deps, new_visited}

              _ ->
                {:ok, info, new_visited}
            end
          else
            {:ok, info, new_visited}
          end

        {:error, _reason} ->
          :error
      end
    end
  end

  # Fetch module info (without cache)
  defp fetch_module_info(module_name, engine_name) do
    case Queries.find_module(module_name, engine_name: engine_name) do
      {:ok, module} ->
        info = %{
          name: module[:name] || module_name,
          iri: module[:iri] || "",
          file: module[:file],
          documentation: module[:documentation],
          public_functions: format_functions(module[:public_functions] || []),
          private_functions: format_functions(module[:private_functions] || []),
          structs: format_structs(module[:structs] || []),
          behaviours: module[:behaviours] || [],
          protocols: module[:protocols] || [],
          dependencies: []
        }

        {:ok, info}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fetch and cache module info
  defp fetch_and_cache_module_info(module_name, engine_name, cache_key) do
    case fetch_module_info(module_name, engine_name) do
      {:ok, info} ->
        put_cached(cache_key, info)
        {:ok, info}

      error ->
        error
    end
  end

  # Fetch dependencies with depth
  defp fetch_dependencies(module_name, depth, engine_name) do
    case Queries.get_dependencies(module_name, engine_name: engine_name) do
      {:ok, direct_deps} ->
        if depth > 0 do
          # Recursively get dependencies of dependencies
          {all_deps, _} =
            Enum.reduce(direct_deps, {MapSet.new(), MapSet.new()}, fn dep, {acc, visited} ->
              if MapSet.member?(visited, dep) do
                {acc, visited}
              else
                case fetch_dependencies(dep, depth - 1, engine_name) do
                  {:ok, indirect_deps} ->
                    new_acc = Enum.reduce(indirect_deps, acc, &MapSet.put(&2, &1))
                    new_visited = MapSet.put(visited, dep)
                    {MapSet.put(new_acc, dep), new_visited}

                  _ ->
                    {MapSet.put(acc, dep), MapSet.put(visited, dep)}
                end
              end
            end)

          {:ok, MapSet.to_list(all_deps)}
        else
          {:ok, direct_deps}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Format functions for summary
  defp format_functions(functions) do
    Enum.map(functions, fn fn_info ->
      %{
        name: fn_info[:name],
        arity: fn_info[:arity],
        visibility: fn_info[:visibility] || :public
      }
    end)
  end

  # Format structs for summary
  defp format_structs(structs) do
    Enum.map(structs, fn struct_info ->
      %{
        module: struct_info[:module],
        fields: struct_info[:fields] |> Enum.map(& &1[:name]) |> Enum.reject(&is_nil/1)
      }
    end)
  end

  # Format modules for LLM context
  defp format_modules_for_context(modules) do
    Enum.map(modules, fn module ->
      %{
        name: module.name,
        file: module.file,
        documentation: module.documentation,
        public_functions: Enum.map(module.public_functions, &"#{&1.name}/#{&1.arity}"),
        behaviours: module.behaviours,
        protocols: module.protocols,
        dependencies: module[:dependencies] || []
      }
    end)
  end

  # Build query context
  defp build_context(engine_name) do
    Engine.context(engine_name)
    |> Map.put(:transaction, nil)
    |> Jidoka.Knowledge.Context.with_permit_all()
  end

  # Empty context for graceful fallback
  defp empty_context do
    %{
      modules: [],
      project_structure: %{total_modules: 0, indexed_files: 0},
      metadata: %{
        modules_count: 0,
        depth_used: 0,
        timestamp: DateTime.utc_now(),
        note: "Codebase context unavailable - code may not be indexed"
      }
    }
  end

  # ========================================================================
  # Cache Functions
  # ========================================================================

  defp get_cached(key) do
    try do
      case :ets.lookup(@cache_table, key) do
        [{^key, value, _timestamp}] ->
          # Update access time for LRU tracking
          :ets.insert(@cache_table, {key, value, System.monotonic_time(:millisecond)})
          {:ok, value}
        [] -> :miss
      end
    rescue
      ArgumentError -> :miss
    end
  end

  defp put_cached(key, value) do
    current_time = System.monotonic_time(:millisecond)
    :ets.insert(@cache_table, {key, value, current_time})

    # Evict oldest entries if cache size exceeds limit
    maybe_evict_oldest()

    :ok
  end

  # Evict oldest entries to maintain cache size limit
  defp maybe_evict_oldest do
    try do
      current_size = :ets.info(@cache_table, :size)

      if current_size > @max_cache_size do
        # Evict 10% of entries to avoid frequent evictions
        evict_count = div(@max_cache_size, 10)

        # Get all entries and sort by timestamp (oldest first)
        entries = :ets.tab2list(@cache_table)

        # Sort by timestamp and evict oldest entries
        entries
        |> Enum.sort_by(fn {_key, _value, timestamp} -> timestamp end)
        |> Enum.take(evict_count)
        |> Enum.each(fn {key, _value, _timestamp} ->
          :ets.delete(@cache_table, key)
        end)
      end
    rescue
      ArgumentError -> :ok
    end
  end
end
