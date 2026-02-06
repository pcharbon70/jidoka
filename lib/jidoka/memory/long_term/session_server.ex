defmodule Jidoka.Memory.LongTerm.SessionServer do
  @moduledoc """
  GenServer that owns and manages an ETS table for a session's long-term memory.

  This GenServer provides proper access control (:protected table) and automatic
  cleanup when the process terminates. It replaces the SessionAdapter struct-based
  approach with a process-based approach that follows OTP best practices.

  ## Security Improvements over SessionAdapter

  * Uses `:protected` ETS table - only this GenServer can write
  * Uses table references instead of named tables - no atom creation from user input
  * Automatic cleanup on process termination - prevents ETS table leaks
  * Validates all memory operations using the Validation module

  ## Client API

  All operations use GenServer.call for synchronous responses:

      {:ok, pid} = SessionServer.start_link("session_123")
      {:ok, memory} = SessionServer.persist_memory(pid, item)
      {:ok, memories} = SessionServer.query_memories(pid)

  The GenServer automatically cleans up its ETS table when it terminates.

  ## Architecture

  ```
  SessionServer (GenServer)
    ├── owns ETS table (reference, not named)
    ├── table access: :protected (only owner can write)
    └── terminate/2 callback: deletes table
  ```

  ## Registry

  Sessions are registered in `Jidoka.Memory.SessionRegistry` for
  process lookup by session_id.
  """

  use GenServer
  alias Jidoka.Memory.Validation

  defstruct [:session_id, :table_id, :started_at]

  @type t :: %__MODULE__{
          session_id: String.t(),
          table_id: :ets.tid(),
          started_at: DateTime.t()
        }

  # Client API

  @doc """
  Starts a SessionServer for the given session_id.

  ## Parameters

  * `session_id` - The session identifier (validated)

  ## Returns

  * `{:ok, pid}` - Server started successfully
  * `{:error, reason}` - Start failed

  ## Examples

      {:ok, pid} = SessionServer.start_link("session_123")

  """
  def start_link(session_id) when is_binary(session_id) do
    # Validate session_id before starting GenServer
    case Validation.validate_session_id(session_id) do
      :ok -> GenServer.start_link(__MODULE__, session_id)
      {:error, _} = error -> error
    end
  end

  def start_link(_session_id), do: {:error, :invalid_session_id}

  @doc """
  Starts a SessionServer as part of a supervision tree.

  ## Examples

      {SessionServer, ["session_123"]}

  """
  def start_link([session_id]) do
    GenServer.start_link(__MODULE__, session_id, name: via_tuple(session_id))
  end

  @doc """
  Persists a memory item to long-term memory.

  Validates the memory item before storage, including data size limits.

  ## Parameters

  * `server` - PID or name of the SessionServer
  * `item` - Map with at least `:id`, `:type`, `:data`, `:importance`

  ## Returns

  * `{:ok, memory}` - Memory persisted with added fields (session_id, timestamps)
  * `{:error, reason}` - Persistence failed

  ## Examples

      {:ok, memory} = SessionServer.persist_memory(pid, %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8
      })

  """
  def persist_memory(server, item) when is_map(item) do
    GenServer.call(server, {:persist, item})
  end

  @doc """
  Queries memories from long-term memory with optional filters.

  ## Parameters

  * `server` - PID or name of the SessionServer
  * `opts` - Keyword list of filters:
    * `:type` - Filter by memory type
    * `:min_importance` - Minimum importance score
    * `:limit` - Maximum number of results

  ## Returns

  * `{:ok, memories}` - List of memory items (may be empty)

  ## Examples

      {:ok, all} = SessionServer.query_memories(pid)
      {:ok, facts} = SessionServer.query_memories(pid, type: :fact)
      {:ok, important} = SessionServer.query_memories(pid, min_importance: 0.7)

  """
  def query_memories(server, opts \\ []) when is_list(opts) do
    GenServer.call(server, {:query, opts})
  end

  @doc """
  Retrieves a single memory by ID.

  ## Parameters

  * `server` - PID or name of the SessionServer
  * `memory_id` - The memory ID to retrieve

  ## Returns

  * `{:ok, memory}` - Memory found
  * `{:error, :not_found}` - Memory not found

  ## Examples

      {:ok, memory} = SessionServer.get_memory(pid, "mem_1")
      {:error, :not_found} = SessionServer.get_memory(pid, "nonexistent")

  """
  def get_memory(server, memory_id) do
    GenServer.call(server, {:get, memory_id})
  end

  @doc """
  Updates an existing memory in long-term memory.

  ## Parameters

  * `server` - PID or name of the SessionServer
  * `memory_id` - The ID of the memory to update
  * `updates` - Map of fields to update

  ## Returns

  * `{:ok, updated_memory}` - Memory updated
  * `{:error, :not_found}` - Memory not found

  ## Examples

      {:ok, updated} = SessionServer.update_memory(pid, "mem_1", %{
        importance: 0.9,
        data: %{new: "data"}
      })

  """
  def update_memory(server, memory_id, updates) when is_map(updates) do
    GenServer.call(server, {:update, memory_id, updates})
  end

  @doc """
  Deletes a memory from long-term memory.

  ## Parameters

  * `server` - PID or name of the SessionServer
  * `memory_id` - The ID of the memory to delete

  ## Returns

  * `:ok` - Memory deleted
  * `{:error, :not_found}` - Memory not found

  ## Examples

      :ok = SessionServer.delete_memory(pid, "mem_1")

  """
  def delete_memory(server, memory_id) do
    GenServer.call(server, {:delete, memory_id})
  end

  @doc """
  Returns the count of memories in this session.

  ## Examples

      count = SessionServer.count(pid)

  """
  def count(server) do
    GenServer.call(server, :count)
  end

  @doc """
  Clears all memories from this session's ETS table.

  ## Examples

      :ok = SessionServer.clear(pid)

  """
  def clear(server) do
    GenServer.call(server, :clear)
  end

  @doc """
  Returns the session_id for this server.

  ## Examples

      "session_123" = SessionServer.session_id(pid)

  """
  def session_id(server) do
    GenServer.call(server, :session_id)
  end

  @doc """
  Returns the table reference for this server's ETS table.

  Note: This is for read-only access by other processes. The table
  is :protected, so only the SessionServer can write to it.

  ## Examples

      table_id = SessionServer.table_id(pid)

  """
  def table_id(server) do
    GenServer.call(server, :table_id)
  end

  # Server Callbacks

  @impl true
  def init(session_id) do
    # Validate session_id first (security: prevents atom creation from bad input)
    case Validation.validate_session_id(session_id) do
      :ok ->
        # Create :protected ETS table with reference (not named - no atom creation)
        # read_concurrency: true allows concurrent reads
        table_id = :ets.new(:ltm_session, [:set, :protected, read_concurrency: true])

        state = %__MODULE__{
          session_id: session_id,
          table_id: table_id,
          started_at: DateTime.utc_now()
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:persist, item}, _from, state) do
    # Validate item without session_id first, then enrich and re-validate
    with :ok <- Validation.validate_required_fields(item),
         :ok <- Validation.validate_memory_size(Map.get(item, :data, %{})),
         :ok <- Validation.validate_importance(Map.get(item, :importance)),
         :ok <- Validation.validate_type(Map.get(item, :type)),
         memory = enrich_memory(item, state.session_id),
         :ok <- Validation.validate_session_id(memory.session_id),
         true <- :ets.insert(state.table_id, {Map.get(memory, :id), memory}) do
      {:reply, {:ok, memory}, state}
    else
      {:error, _} = error ->
        {:reply, error, state}

      false ->
        {:reply, {:error, :ets_insert_failed}, state}
    end
  end

  @impl true
  def handle_call({:query, opts}, _from, state) do
    memories = query_table(state.table_id, opts)
    {:reply, {:ok, memories}, state}
  end

  @impl true
  def handle_call({:get, memory_id}, _from, state) do
    case :ets.lookup(state.table_id, memory_id) do
      [{^memory_id, memory}] -> {:reply, {:ok, memory}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:update, memory_id, updates}, _from, state) do
    case :ets.lookup(state.table_id, memory_id) do
      [{^memory_id, existing}] ->
        updated =
          existing
          |> Map.merge(updates)
          |> Map.put(:updated_at, DateTime.utc_now())

        true = :ets.insert(state.table_id, {memory_id, updated})
        {:reply, {:ok, updated}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:delete, memory_id}, _from, state) do
    case :ets.lookup(state.table_id, memory_id) do
      [{^memory_id, _memory}] ->
        true = :ets.delete(state.table_id, memory_id)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:count, _from, state) do
    count = :ets.info(state.table_id, :size)
    {:reply, count, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    true = :ets.delete_all_objects(state.table_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  @impl true
  def handle_call(:table_id, _from, state) do
    {:reply, state.table_id, state}
  end

  @impl true
  def handle_info(msg, state) do
    # Log unexpected messages
    require Logger
    Logger.warning("Unexpected message in SessionServer: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Auto-cleanup: Delete ETS table when process terminates
    # This prevents ETS table leaks (fixes ARCH-2, SEC-5)
    :ets.delete(state.table_id)
    :ok
  end

  # Private Helpers

  defp enrich_memory(item, session_id) do
    now = DateTime.utc_now()

    item
    |> Map.put(:session_id, session_id)
    |> Map.put(:created_at, Map.get(item, :created_at, now))
    |> Map.put(:updated_at, now)
  end

  defp query_table(table_id, opts) do
    # Get all memories from the table
    memories =
      table_id
      |> :ets.tab2list()
      |> Enum.map(fn {_id, memory} -> memory end)
      |> maybe_filter_by_type(Keyword.get(opts, :type))
      |> maybe_filter_by_importance(Keyword.get(opts, :min_importance))
      |> maybe_apply_limit(Keyword.get(opts, :limit))

    memories
  end

  defp maybe_filter_by_type(memories, nil), do: memories

  defp maybe_filter_by_type(memories, type) when is_atom(type) do
    Enum.filter(memories, fn memory ->
      Map.get(memory, :type) == type
    end)
  end

  defp maybe_filter_by_importance(memories, nil), do: memories

  defp maybe_filter_by_importance(memories, min_importance) when is_float(min_importance) do
    Enum.filter(memories, fn memory ->
      Map.get(memory, :importance, 0.0) >= min_importance
    end)
  end

  defp maybe_apply_limit(memories, nil), do: memories

  defp maybe_apply_limit(memories, limit) when is_integer(limit) and limit > 0 do
    Enum.take(memories, limit)
  end

  defp maybe_apply_limit(memories, _limit), do: memories

  defp via_tuple(session_id) do
    # Register in dedicated memory session registry
    {:via, Registry, {Jidoka.Memory.SessionRegistry, session_id}}
  end
end
