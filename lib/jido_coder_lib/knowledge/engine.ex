defmodule JidoCoderLib.Knowledge.Engine do
  @moduledoc """
  GenServer wrapper for the triple_store backend.

  Manages the lifecycle of the RDF quad-store with proper OTP supervision,
  health checking, and named graph management.

  ## Named Graphs

  The engine manages several standard named graphs:

  | Name | IRI | Purpose |
  |------|-----|---------|
  | `:long_term_context` | `https://jido.ai/graphs/long-term-context` | Persistent memories |
  | `:elixir_codebase` | `https://jido.ai/graphs/elixir-codebase` | Code model |
  | `:conversation_history` | `https://jido.ai/graphs/conversation-history` | Conversations |
  | `:system_knowledge` | `https://jido.ai/graphs/system-knowledge` | Ontologies |

  ## Examples

  Start the engine:

      {:ok, pid} = Engine.start_link(data_dir: "./data/kg")

  Check health:

      {:ok, health} = Engine.health(pid)

  Create a named graph:

      :ok = Engine.create_graph(pid, :my_graph)

  Query with SPARQL:

      ctx = Engine.context(pid)
      {:ok, results} = TripleStore.SPARQL.Query.query(ctx, "SELECT ?s WHERE { ?s ?p ?o }")

  """

  use GenServer
  require Logger

  alias JidoCoderLib.Knowledge.{Context, NamedGraphs}
  alias RDF.IRI
  alias TripleStore.SPARQL.Query
  import TripleStore, only: [update: 2]

  # ========================================================================
  # Type Definitions
  # ========================================================================

  @type graph_name :: atom() | String.t()
  @type graph_iri :: IRI.t()
  @type opts :: keyword()

  # State struct
  defstruct [
    :db,
    :dict_manager,
    :data_dir,
    :health_check_timer,
    :health_check_interval,
    :standard_graphs,
    :name
  ]

  # ========================================================================
  # Standard Named Graphs
  # ========================================================================

  @standard_graphs [
    :long_term_context,
    :elixir_codebase,
    :conversation_history,
    :system_knowledge
  ]

  @graph_iris %{
    long_term_context: "https://jido.ai/graphs/long-term-context",
    elixir_codebase: "https://jido.ai/graphs/elixir-codebase",
    conversation_history: "https://jido.ai/graphs/conversation-history",
    system_knowledge: "https://jido.ai/graphs/system-knowledge"
  }

  # ========================================================================
  # Public API - Lifecycle
  # ========================================================================

  @doc """
  Starts the Knowledge Engine.

  ## Options

  - `:name` - Name for the GenServer (required)
  - `:data_dir` - Directory for triple store data (required)
  - `:health_check_interval` - Interval in milliseconds (default: 30000)
  - `:standard_graphs` - List of standard graphs to create (default: @standard_graphs)
  - `:create_standard_graphs` - Whether to create standard graphs on startup (default: true)

  ## Returns

  - `{:ok, pid}` - Engine started successfully
  - `{:error, reason}` - Failed to start

  ## Examples

      {:ok, pid} = Engine.start_link(
        name: :knowledge_engine,
        data_dir: "./data/kg"
      )

      {:ok, pid} = Engine.start_link(
        name: :knowledge_engine,
        data_dir: "./data/kg",
        health_check_interval: 60_000
      )

  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    # Validate required options early to provide clear error messages
    unless Keyword.has_key?(opts, :name) do
      raise ArgumentError, "required option :name not found"
    end

    unless Keyword.has_key?(opts, :data_dir) do
      raise ArgumentError, "required option :data_dir not found"
    end

    {name_opts, init_opts} = Keyword.split(opts, [:name])
    name = Keyword.fetch!(name_opts, :name)

    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Stops the Knowledge Engine gracefully.

  ## Examples

      :ok = Engine.stop(pid)

  """
  @spec stop(GenServer.server()) :: :ok
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal, :infinity)
  end

  def stop(name) when is_atom(name) do
    GenServer.stop(name, :normal, :infinity)
  end

  @doc """
  Gets the execution context for SPARQL operations.

  Returns a map with `:db` and `:dict_manager` keys for use with TripleStore SPARQL operations.

  ## Examples

      ctx = Engine.context(pid)
      {:ok, results} = TripleStore.SPARQL.Query.query(ctx, "SELECT ?s WHERE { ?s ?p ?o }", [])

  """
  @spec context(GenServer.server()) :: map()
  def context(pid) when is_pid(pid) do
    GenServer.call(pid, :get_context)
  end

  def context(name) when is_atom(name) do
    GenServer.call(name, :get_context)
  end

  # ========================================================================
  # Public API - Health and Stats
  # ========================================================================

  @doc """
  Gets the health status of the engine.

  ## Returns

  - `{:ok, health_map}` - Health status with keys:
    - `:status` - `:healthy`, `:degraded`, or `:unhealthy`
    - `:db_open` - Boolean indicating database is open
    - `:triple_count` - Number of triples in store
    - `:graph_count` - Number of named graphs
    - `:last_check` - Timestamp of last health check

  ## Examples

      {:ok, health} = Engine.health(pid)
      health.status #=> :healthy

  """
  @spec health(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def health(pid) when is_pid(pid) do
    GenServer.call(pid, :health)
  end

  def health(name) when is_atom(name) do
    GenServer.call(name, :health)
  end

  @doc """
  Gets statistics about the triple store.

  ## Returns

  - `{:ok, stats_map}` - Statistics with keys:
    - `:triple_count` - Total triples
    - `:graph_count` - Number of graphs
    - `:data_size` - Disk usage in bytes

  ## Examples

      {:ok, stats} = Engine.stats(pid)

  """
  @spec stats(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def stats(pid) when is_pid(pid) do
    GenServer.call(pid, :stats)
  end

  def stats(name) when is_atom(name) do
    GenServer.call(name, :stats)
  end

  # ========================================================================
  # Public API - Named Graphs
  # ========================================================================

  @doc """
  Creates a named graph in the triple store.

  ## Parameters

  - `pid_or_name` - Engine PID or registered name
  - `graph_name` - Atom name or full IRI string

  ## Returns

  - `:ok` - Graph created or already exists
  - `{:error, reason}` - Failed to create

  ## Examples

      :ok = Engine.create_graph(pid, :my_graph)
      :ok = Engine.create_graph(pid, "https://example.com/my-graph")

  """
  @spec create_graph(GenServer.server(), graph_name()) :: :ok | {:error, term()}
  def create_graph(pid_or_name, graph_name) do
    GenServer.call(pid_or_name, {:create_graph, graph_name})
  end

  @doc """
  Drops a named graph from the triple store.

  ## Parameters

  - `pid_or_name` - Engine PID or registered name
  - `graph_name` - Atom name or full IRI string

  ## Returns

  - `:ok` - Graph dropped
  - `{:error, reason}` - Failed to drop

  ## Examples

      :ok = Engine.drop_graph(pid, :my_graph)

  """
  @spec drop_graph(GenServer.server(), graph_name()) :: :ok | {:error, term()}
  def drop_graph(pid_or_name, graph_name) do
    GenServer.call(pid_or_name, {:drop_graph, graph_name})
  end

  @doc """
  Lists all named graphs in the triple store.

  ## Returns

  - `{:ok, graph_list}` - List of graph IRIs

  ## Examples

      {:ok, graphs} = Engine.list_graphs(pid)

  """
  @spec list_graphs(GenServer.server()) :: {:ok, [String.t()]} | {:error, term()}
  def list_graphs(pid_or_name) do
    GenServer.call(pid_or_name, :list_graphs)
  end

  @doc """
  Checks if a named graph exists in the triple store.

  ## Parameters

  - `pid_or_name` - Engine PID or registered name
  - `graph_name` - Atom name or full IRI string

  ## Returns

  - `true` - Graph exists
  - `false` - Graph does not exist

  ## Examples

      true = Engine.graph_exists?(pid, :long_term_context)

  """
  @spec graph_exists?(GenServer.server(), graph_name()) :: boolean()
  def graph_exists?(pid_or_name, graph_name) do
    GenServer.call(pid_or_name, {:graph_exists, graph_name})
  end

  # ========================================================================
  # Public API - Backup
  # ========================================================================

  @doc """
  Creates a backup of the triple store.

  ## Parameters

  - `pid_or_name` - Engine PID or registered name
  - `path` - Destination path for backup

  ## Returns

  - `{:ok, metadata}` - Backup created successfully
  - `{:error, reason}` - Backup failed

  ## Examples

      {:ok, metadata} = Engine.backup(pid, "./backups/mydb")

  """
  @spec backup(GenServer.server(), Path.t()) :: {:ok, map()} | {:error, term()}
  def backup(pid_or_name, path) when is_binary(path) do
    GenServer.call(pid_or_name, {:backup, path})
  end

  # ========================================================================
  # GenServer Callbacks
  # ========================================================================

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    schema = Keyword.get(opts, :schema, :quad)
    health_check_interval = Keyword.get(opts, :health_check_interval, 30_000)
    create_standard_graphs = Keyword.get(opts, :create_standard_graphs, true)
    standard_graphs = Keyword.get(opts, :standard_graphs, @standard_graphs)

    # Ensure data directory exists
    File.mkdir_p!(data_dir)

    # Open the triple store with specified schema
    case TripleStore.open(data_dir, schema: schema) do
      {:ok, store} ->
        state = %__MODULE__{
          db: store.db,
          dict_manager: store.dict_manager,
          data_dir: data_dir,
          health_check_interval: health_check_interval,
          standard_graphs: standard_graphs,
          name: nil
        }

        # Create standard graphs if requested
        if create_standard_graphs do
          Enum.each(standard_graphs, fn graph_name ->
            create_graph_internal(state, graph_name)
          end)
        end

        # Start health check timer
        {:ok, timer} = :timer.send_interval(health_check_interval, self(), :health_check)

        state = %{state | health_check_timer: timer}

        Logger.info("Knowledge Engine started: data_dir=#{data_dir}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start Knowledge Engine: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_context, _from, state) do
    ctx = %{
      db: state.db,
      dict_manager: state.dict_manager
    }

    {:reply, ctx, state}
  end

  def handle_call(:health, _from, state) do
    health = do_health_check(state)
    {:reply, {:ok, health}, state}
  end

  def handle_call(:stats, _from, state) do
    store = %{db: state.db, dict_manager: state.dict_manager}

    try do
      case TripleStore.stats(store) do
        {:ok, stats} ->
          {:reply, {:ok, stats}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    rescue
      # Handle cases where TripleStore.stats fails due to missing column families
      # or other database state issues
      _error ->
        {:reply, {:ok, %{}}, state}
    end
  end

  def handle_call({:create_graph, graph_name}, _from, state) do
    case create_graph_internal(state, graph_name) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:drop_graph, graph_name}, _from, state) do
    iri = graph_name_to_iri(graph_name)
    graph_iri_str = IRI.to_string(iri)

    # Use SPARQL UPDATE to clear the graph
    # DROP GRAPH is not directly supported, so we delete all triples from the graph
    update = "DELETE DATA { GRAPH <#{graph_iri_str}> { ?s ?p ?o } }"

    store = %{db: state.db, dict_manager: state.dict_manager}
    ctx = Context.with_permit_all(store)

    case update(ctx, update) do
      {:ok, _count} ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list_graphs, _from, state) do
    # Query for all named graphs
    query = """
    SELECT DISTINCT ?g WHERE {
      GRAPH ?g { ?s ?p ?o }
      FILTER(?g != <http://www.w3.org/2002/07/owl#sameAs>)
    }
    """

    store = %{db: state.db, dict_manager: state.dict_manager}

    case Query.query(store, query, []) do
      {:ok, results} when is_list(results) ->
        graphs =
          Enum.map(results, fn
            %{"g" => {:iri, iri}} -> IRI.to_string(iri)
            %{"g" => {:named_node, iri}} -> IRI.to_string(iri)
            %{"g" => iri_string} when is_binary(iri_string) -> iri_string
          end)

        {:reply, {:ok, graphs}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      _ ->
        {:reply, {:ok, []}, state}
    end
  end

  def handle_call({:graph_exists, graph_name}, _from, state) do
    iri = graph_name_to_iri(graph_name)
    graph_iri_str = IRI.to_string(iri)

    query = "ASK { GRAPH <#{graph_iri_str}> { ?s ?p ?o } }"

    store = %{db: state.db, dict_manager: state.dict_manager}

    case Query.query(store, query, []) do
      {:ok, exists?} when is_boolean(exists?) ->
        {:reply, exists?, state}

      _ ->
        {:reply, false, state}
    end
  end

  def handle_call({:backup, path}, _from, state) do
    # TripleStore.Backup.create requires a store with :path key
    store = %{
      db: state.db,
      dict_manager: state.dict_manager,
      path: state.data_dir
    }

    case TripleStore.Backup.create(store, path) do
      {:ok, metadata} ->
        {:reply, {:ok, metadata}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform periodic health check
    health = do_health_check(state)

    # Log warnings for degraded health
    if health.status != :healthy do
      Logger.warning("Knowledge Engine health: #{health.status}")
    end

    # Telemetry event
    :telemetry.execute(
      [:jido_coder_lib, :knowledge_engine, :health_check],
      %{status: health.status},
      %{}
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel health check timer
    if state.health_check_timer do
      :timer.cancel(state.health_check_timer)
    end

    # Close the triple store
    TripleStore.close(%{db: state.db, dict_manager: state.dict_manager})

    Logger.info("Knowledge Engine stopped")
    :ok
  end

  # ========================================================================
  # Private Helpers
  # ========================================================================

  defp do_health_check(state) do
    store = %{db: state.db, dict_manager: state.dict_manager}

    try do
      case TripleStore.health(store) do
        {:ok, store_health} ->
          %{
            status: :healthy,
            db_open: true,
            triple_count: Map.get(store_health, :triple_count, 0),
            graph_count: Map.get(store_health, :graph_count, 0),
            last_check: DateTime.utc_now()
          }

        {:error, _reason} ->
          %{
            status: :unhealthy,
            db_open: false,
            triple_count: 0,
            graph_count: 0,
            last_check: DateTime.utc_now()
          }
      end
    rescue
      # Handle cases where TripleStore.health fails due to missing column families
      # or other database state issues (e.g., during startup or with fresh databases)
      _error ->
        %{
          status: :degraded,
          db_open: true,
          triple_count: 0,
          graph_count: 0,
          last_check: DateTime.utc_now()
        }
    end
  end

  defp create_graph_internal(state, graph_name) do
    iri = graph_name_to_iri(graph_name)
    graph_iri_str = IRI.to_string(iri)

    # Use SPARQL INSERT DATA to create a placeholder triple in the named graph
    # This creates the named graph by inserting a triple into it
    update = """
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX jido: <https://jido.ai/ontologies/core#>

    INSERT DATA {
      GRAPH <#{graph_iri_str}> {
        <#{graph_iri_str}> rdf:type jido:NamedGraph .
      }
    }
    """

    # Prepare context with permit_all for quad schema ACL bypass
    store = %{db: state.db, dict_manager: state.dict_manager, transaction: nil}
    ctx = Context.with_permit_all(store)

    case update(ctx, update) do
      {:ok, _count} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to create graph #{graph_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Converts a graph name atom to its full IRI.

  ## Examples

      iex> Engine.graph_name_to_iri(:long_term_context)
      ~I<https://jido.ai/graphs/long-term-context>

      iex> Engine.graph_name_to_iri("https://example.com/custom")
      ~I<https://example.com/custom>

  """
  @spec graph_name_to_iri(graph_name()) :: IRI.t()
  def graph_name_to_iri(graph_name) when is_atom(graph_name) do
    case Map.get(@graph_iris, graph_name) do
      nil ->
        # For custom atom names, convert to string and create IRI
        # This allows dynamic graph names like :my_graph
        name_str = Atom.to_string(graph_name)
        IRI.new("https://jido.ai/graphs/#{name_str}")

      iri_string ->
        IRI.new(iri_string)
    end
  end

  def graph_name_to_iri(graph_name) when is_binary(graph_name) do
    IRI.new(graph_name)
  end

  @doc """
  Lists the standard graph names.

  ## Examples

      iex> Engine.standard_graphs()
      [:long_term_context, :elixir_codebase, :conversation_history, :system_knowledge]

  """
  @spec standard_graphs() :: [atom()]
  def standard_graphs, do: @standard_graphs
end
