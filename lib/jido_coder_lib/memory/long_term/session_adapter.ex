defmodule JidoCoderLib.Memory.LongTerm.SessionAdapter do
  @moduledoc """
  An adapter for long-term memory operations with session-scoped persistence.

  The SessionAdapter provides a simple interface for storing, retrieving,
  updating, and deleting memories in long-term memory. All operations are
  scoped to a specific session_id for isolation.

  This initial implementation uses ETS for in-memory storage. Future versions
  may integrate with RDF triple stores or databases.

  **Note:** This module is deprecated in favor of SessionServer GenServer,
  which provides better security and process isolation. SessionServer uses
  :protected ETS tables (only owner can write), table references (not named
  tables to prevent atom creation), and automatic cleanup on termination.

  ## Fields

  * `:session_id` - The session scope for all operations
  * `:table_name` - The ETS table name for this session

  ## Memory Item Structure

  Each memory item is a map with:
  * `:id` - Unique identifier
  * `:session_id` - Session scope (automatically added)
  * `:type` - Memory type (:fact, :analysis, :conversation, :file_context)
  * `:data` - The actual memory data
  * `:importance` - Importance score (0.0-1.0)
  * `:created_at` - Creation timestamp
  * `:updated_at` - Last update timestamp

  ## Examples

      {:ok, adapter} = SessionAdapter.new("session_123")

      {:ok, memory} = SessionAdapter.persist_memory(adapter, %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8
      })

      {:ok, memories} = SessionAdapter.query_memories(adapter)

  """

  alias JidoCoderLib.Memory.Validation

  defstruct [:session_id, :table_name]

  @type t :: %__MODULE__{
          session_id: String.t(),
          table_name: atom()
        }

  @table_prefix "ltm_session_"

  @doc """
  Creates a new SessionAdapter for the given session_id.

  Initializes a new ETS table for this session if it doesn't exist.

  ## Parameters

  * `session_id` - The session identifier

  ## Returns

  * `{:ok, adapter}` - Adapter created successfully
  * `{:error, reason}` - Creation failed

  ## Examples

      {:ok, adapter} = SessionAdapter.new("session_123")

  """
  def new(session_id) when is_binary(session_id) do
    # Validate session_id first (security: prevents atom creation from bad input)
    with :ok <- Validation.validate_session_id(session_id) do
      table_name = table_name(session_id)

      case :ets.whereis(table_name) do
        :undefined ->
          try do
            # Create a new named table with :set type
            # Note: :public is a security concern - SessionServer uses :protected
            ^table_name =
              :ets.new(table_name, [:named_table, :set, :public, read_concurrency: true])

            {:ok, %__MODULE__{session_id: session_id, table_name: table_name}}
          rescue
            ArgumentError -> {:error, :invalid_session_id}
          end

        _ref ->
          # Table already exists
          {:ok, %__MODULE__{session_id: session_id, table_name: table_name}}
      end
    end
  end

  @doc """
  Creates a new SessionAdapter, raising on error.

  ## Examples

      adapter = SessionAdapter.new!("session_123")

  """
  def new!(session_id) when is_binary(session_id) do
    case new(session_id) do
      {:ok, adapter} -> adapter
      {:error, reason} -> raise ArgumentError, "Failed to create adapter: #{inspect(reason)}"
    end
  end

  @doc """
  Persists a memory item to long-term memory.

  Adds session_id, created_at, and updated_at timestamps to the memory item.

  ## Parameters

  * `adapter` - The SessionAdapter struct
  * `item` - Map with at least `:id`, `:type`, `:data`, `:importance`

  ## Returns

  * `{:ok, memory}` - Memory persisted with added fields
  * `{:error, reason}` - Persistence failed

  ## Examples

      {:ok, memory} = SessionAdapter.persist_memory(adapter, %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8
      })

  """
  def persist_memory(%__MODULE__{} = adapter, item) when is_map(item) do
    # Use shared Validation module for consistent validation (fixes SEC-3)
    with :ok <- Validation.validate_required_fields(item),
         :ok <- Validation.validate_memory_size(Map.get(item, :data, %{})),
         :ok <- Validation.validate_importance(Map.get(item, :importance)),
         :ok <- Validation.validate_type(Map.get(item, :type)),
         now <- DateTime.utc_now() do
      memory =
        item
        |> Map.put(:session_id, adapter.session_id)
        |> Map.put(:created_at, now)
        |> Map.put(:updated_at, now)

      true = :ets.insert(adapter.table_name, {Map.get(memory, :id), memory})

      {:ok, memory}
    end
  end

  @doc """
  Queries memories from long-term memory with optional filters.

  ## Parameters

  * `adapter` - The SessionAdapter struct
  * `opts` - Keyword list of filters:
    * `:type` - Filter by memory type
    * `:min_importance` - Minimum importance score
    * `:limit` - Maximum number of results

  ## Returns

  * `{:ok, memories}` - List of memory items (may be empty)
  * `{:error, reason}` - Query failed

  ## Examples

      {:ok, all} = SessionAdapter.query_memories(adapter)
      {:ok, facts} = SessionAdapter.query_memories(adapter, type: :fact)
      {:ok, important} = SessionAdapter.query_memories(adapter, min_importance: 0.7)

  """
  def query_memories(%__MODULE__{} = adapter, opts \\ []) do
    # Get all memories from the table
    memories =
      adapter.table_name
      |> :ets.tab2list()
      |> Enum.map(fn {_id, memory} -> memory end)

    # Apply filters
    memories =
      memories
      |> maybe_filter_by_type(Keyword.get(opts, :type))
      |> maybe_filter_by_importance(Keyword.get(opts, :min_importance))
      |> maybe_apply_limit(Keyword.get(opts, :limit))

    {:ok, memories}
  end

  @doc """
  Retrieves a single memory by ID.

  ## Parameters

  * `adapter` - The SessionAdapter struct
  * `memory_id` - The memory ID to retrieve

  ## Returns

  * `{:ok, memory}` - Memory found
  * `{:error, :not_found}` - Memory not found

  ## Examples

      {:ok, memory} = SessionAdapter.get_memory(adapter, "mem_1")
      {:error, :not_found} = SessionAdapter.get_memory(adapter, "nonexistent")

  """
  def get_memory(%__MODULE__{} = adapter, memory_id) do
    case :ets.lookup(adapter.table_name, memory_id) do
      [{^memory_id, memory}] -> {:ok, memory}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Updates an existing memory in long-term memory.

  Only updates the fields provided; maintains id, session_id, and created_at.
  Updates the updated_at timestamp.

  ## Parameters

  * `adapter` - The SessionAdapter struct
  * `memory_id` - The ID of the memory to update
  * `updates` - Map of fields to update

  ## Returns

  * `{:ok, updated_memory}` - Memory updated
  * `{:error, :not_found}` - Memory not found

  ## Examples

      {:ok, updated} = SessionAdapter.update_memory(adapter, "mem_1", %{
        importance: 0.9,
        data: %{new: "data"}
      })

  """
  def update_memory(%__MODULE__{} = adapter, memory_id, updates) when is_map(updates) do
    case get_memory(adapter, memory_id) do
      {:error, :not_found} = error ->
        error

      {:ok, existing} ->
        updated =
          existing
          |> Map.merge(updates)
          |> Map.put(:updated_at, DateTime.utc_now())

        true = :ets.insert(adapter.table_name, {memory_id, updated})

        {:ok, updated}
    end
  end

  @doc """
  Deletes a memory from long-term memory.

  ## Parameters

  * `adapter` - The SessionAdapter struct
  * `memory_id` - The ID of the memory to delete

  ## Returns

  * `{:ok, adapter}` - Memory deleted
  * `{:error, :not_found}` - Memory not found

  ## Examples

      {:ok, adapter} = SessionAdapter.delete_memory(adapter, "mem_1")

  """
  def delete_memory(%__MODULE__{} = adapter, memory_id) do
    case get_memory(adapter, memory_id) do
      {:error, :not_found} = error ->
        error

      {:ok, _memory} ->
        true = :ets.delete(adapter.table_name, memory_id)
        {:ok, adapter}
    end
  end

  @doc """
  Returns the count of memories in this session.

  ## Examples

      count = SessionAdapter.count(adapter)

  """
  def count(%__MODULE__{} = adapter) do
    adapter.table_name
    |> :ets.info(:size)
  end

  @doc """
  Clears all memories from this session's ETS table.

  ## Examples

      {:ok, adapter} = SessionAdapter.clear(adapter)

  """
  def clear(%__MODULE__{} = adapter) do
    true = :ets.delete_all_objects(adapter.table_name)
    {:ok, adapter}
  end

  @doc """
  Returns the session_id for this adapter.

  ## Examples

      "session_123" = SessionAdapter.session_id(adapter)

  """
  def session_id(%__MODULE__{session_id: session_id}) do
    session_id
  end

  @doc """
  Drops the ETS table for this session.

  This should be called when a session is terminated to free resources.

  ## Examples

      :ok = SessionAdapter.drop_table(adapter)

  """
  def drop_table(%__MODULE__{} = adapter) do
    :ets.delete(adapter.table_name)
    :ok
  end

  # Private Helpers

  defp table_name(session_id) do
    # Create a valid atom table name from session_id
    # Replace invalid characters with underscores
    safe_name =
      session_id
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.to_charlist()
      # Atom name limit
      |> Enum.take(255)
      |> List.to_string()

    table_name = :"#{@table_prefix}#{safe_name}"

    # Ensure the table name is unique per session
    table_name
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
end
