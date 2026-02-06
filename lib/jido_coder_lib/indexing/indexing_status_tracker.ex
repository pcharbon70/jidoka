defmodule JidoCoderLib.Indexing.IndexingStatusTracker do
  @moduledoc """
  Tracks the status of code indexing operations.

  This GenServer maintains the state of file indexing operations, tracking
  which files are currently being indexed, which have completed successfully,
  and which have failed. Status is stored in-memory for fast access.

  ## States

  An indexing operation can be in one of four states:

  * `:pending` - Queued for indexing
  * `:in_progress` - Currently being indexed
  * `:completed` - Successfully indexed
  * `:failed` - Indexing failed with error

  ## Client API

  * `start_indexing/1` - Mark a file as in_progress
  * `complete_indexing/2` - Mark a file as completed
  * `fail_indexing/2` - Mark a file as failed
  * `get_status/1` - Get status for a file
  * `get_project_status/1` - Get aggregate project status
  * `list_failed/0` - List all failed operations
  * `list_in_progress/0` - List active operations

  ## Example

      # Start indexing a file
      :ok = IndexingStatusTracker.start_indexing("lib/my_app.ex")

      # Complete indexing
      :ok = IndexingStatusTracker.complete_indexing("lib/my_app.ex", 42)

      # Check status
      {:ok, :completed} = IndexingStatusTracker.get_status("lib/my_app.ex")

      # Get project summary
      {:ok, %{completed: 10, failed: 2, in_progress: 1}} =
        IndexingStatusTracker.get_project_status("/path/to/project")

  """

  use GenServer
  require Logger

  @type indexing_status :: :pending | :in_progress | :completed | :failed

  @type operation_info :: %{
          file_path: Path.t(),
          status: indexing_status(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          error: String.t() | nil,
          triple_count: non_neg_integer() | nil
        }

  @type project_status :: %{
          total: non_neg_integer(),
          pending: non_neg_integer(),
          in_progress: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer()
        }

  defstruct [
    :active_operations,
    :completed_operations,
    :failed_operations,
    :engine_name
  ]

  # ========================================================================
  # Client API
  # ========================================================================

  @doc """
  Starts the indexing status tracker.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    engine_name = Keyword.get(opts, :engine_name, :knowledge_engine)

    GenServer.start_link(__MODULE__, %{engine_name: engine_name}, name: name)
  end

  @doc """
  Marks a file as being indexed.

  Creates a new indexing operation in `:in_progress` state.
  If an operation already exists for this file, it will be reset.

  ## Options

  * `:name` - The name of the tracker process (default: `__MODULE__`)
  """
  @spec start_indexing(Path.t(), keyword()) :: :ok
  def start_indexing(file_path, opts \\ []) when is_binary(file_path) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:start_indexing, file_path})
  end

  @doc """
  Marks a file as successfully indexed.

  Moves the operation to `:completed` state with the triple count.

  ## Options

  * `:name` - The name of the tracker process (default: `__MODULE__`)
  """
  @spec complete_indexing(Path.t(), non_neg_integer(), keyword()) :: :ok
  def complete_indexing(file_path, triple_count \\ 0, opts \\ [])
      when is_binary(file_path) and is_integer(triple_count) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:complete_indexing, file_path, triple_count})
  end

  @doc """
  Marks a file as failed to index.

  Moves the operation to `:failed` state with the error message.

  ## Options

  * `:name` - The name of the tracker process (default: `__MODULE__`)
  """
  @spec fail_indexing(Path.t(), String.t(), keyword()) :: :ok
  def fail_indexing(file_path, error_message, opts \\ [])
      when is_binary(file_path) and is_binary(error_message) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:fail_indexing, file_path, error_message})
  end

  @doc """
  Gets the current status of a file indexing operation.

  ## Options

  * `:name` - The name of the tracker process (default: `__MODULE__`)
  """
  @spec get_status(Path.t(), keyword()) :: {:ok, indexing_status()} | {:error, :not_found}
  def get_status(file_path, opts \\ []) when is_binary(file_path) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:get_status, file_path})
  end

  @doc """
  Gets aggregate status for a project.

  Returns counts of operations in each state that match the given project root.

  ## Options

  * `:name` - The name of the tracker process (default: `__MODULE__`)
  """
  @spec get_project_status(Path.t(), keyword()) :: {:ok, project_status()}
  def get_project_status(project_root, opts \\ []) when is_binary(project_root) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:get_project_status, project_root})
  end

  @doc """
  Lists all failed indexing operations.

  ## Options

  * `:name` - The name of the tracker process (default: `__MODULE__`)
  """
  @spec list_failed(keyword()) :: {:ok, [operation_info()]}
  def list_failed(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, :list_failed)
  end

  @doc """
  Lists all in-progress indexing operations.

  ## Options

  * `:name` - The name of the tracker process (default: `__MODULE__`)
  """
  @spec list_in_progress(keyword()) :: {:ok, [operation_info()]}
  def list_in_progress(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, :list_in_progress)
  end

  @doc """
  Gets the operation info for a specific file.

  ## Options

  * `:name` - The name of the tracker process (default: `__MODULE__`)
  """
  @spec get_operation(Path.t(), keyword()) :: {:ok, operation_info()} | {:error, :not_found}
  def get_operation(file_path, opts \\ []) when is_binary(file_path) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:get_operation, file_path})
  end

  # ========================================================================
  # Server Callbacks
  # ========================================================================

  @impl true
  def init(%{engine_name: engine_name}) do
    state = %__MODULE__{
      active_operations: %{},
      completed_operations: %{},
      failed_operations: %{},
      engine_name: engine_name
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_indexing, file_path}, _from, state) do
    started_at = DateTime.utc_now()

    # Move from completed or failed back to active if re-indexing
    state = remove_from_maps(state, file_path)

    operation = %{
      file_path: file_path,
      status: :in_progress,
      started_at: started_at,
      completed_at: nil,
      error: nil,
      triple_count: nil
    }

    state = %{state | active_operations: Map.put(state.active_operations, file_path, operation)}

    # Emit telemetry
    :telemetry.execute(
      [:jido_coder_lib, :indexing, :started],
      %{system_time: System.system_time(:millisecond)},
      %{file_path: file_path}
    )

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:complete_indexing, file_path, triple_count}, _from, state) do
    completed_at = DateTime.utc_now()

    case Map.get(state.active_operations, file_path) do
      nil ->
        {:reply, {:error, :not_found}, state}

      operation ->
        completed_operation = %{
          operation
          | status: :completed,
            completed_at: completed_at,
            triple_count: triple_count
        }

        # Move from active to completed
        state = %{
          state
          | active_operations: Map.delete(state.active_operations, file_path),
            completed_operations:
              Map.put(state.completed_operations, file_path, completed_operation)
        }

        # Emit telemetry
        duration = DateTime.diff(completed_at, operation.started_at, :millisecond)

        :telemetry.execute(
          [:jido_coder_lib, :indexing, :completed],
          %{duration: duration, triple_count: triple_count},
          %{file_path: file_path}
        )

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:fail_indexing, file_path, error_message}, _from, state) do
    completed_at = DateTime.utc_now()

    case Map.get(state.active_operations, file_path) do
      nil ->
        {:reply, {:error, :not_found}, state}

      operation ->
        failed_operation = %{
          operation
          | status: :failed,
            completed_at: completed_at,
            error: error_message
        }

        # Move from active to failed
        state = %{
          state
          | active_operations: Map.delete(state.active_operations, file_path),
            failed_operations: Map.put(state.failed_operations, file_path, failed_operation)
        }

        # Emit telemetry
        duration = DateTime.diff(completed_at, operation.started_at, :millisecond)

        :telemetry.execute(
          [:jido_coder_lib, :indexing, :failed],
          %{duration: duration},
          %{file_path: file_path, error_message: error_message}
        )

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:get_status, file_path}, _from, state) do
    status =
      cond do
        Map.has_key?(state.active_operations, file_path) -> :in_progress
        Map.has_key?(state.completed_operations, file_path) -> :completed
        Map.has_key?(state.failed_operations, file_path) -> :failed
        true -> nil
      end

    case status do
      nil -> {:reply, {:error, :not_found}, state}
      status -> {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call({:get_project_status, project_root}, _from, state) do
    # Normalize project root for comparison
    normalized_root = Path.expand(project_root)

    status = %{
      total: 0,
      pending: 0,
      in_progress: 0,
      completed: 0,
      failed: 0
    }

    # Count operations by status that are under this project root
    status =
      Enum.reduce(state.active_operations, status, fn {_path, op}, acc ->
        if under_project?(op.file_path, normalized_root) do
          %{acc | in_progress: acc.in_progress + 1, total: acc.total + 1}
        else
          acc
        end
      end)

    status =
      Enum.reduce(state.completed_operations, status, fn {_path, op}, acc ->
        if under_project?(op.file_path, normalized_root) do
          %{acc | completed: acc.completed + 1, total: acc.total + 1}
        else
          acc
        end
      end)

    status =
      Enum.reduce(state.failed_operations, status, fn {_path, op}, acc ->
        if under_project?(op.file_path, normalized_root) do
          %{acc | failed: acc.failed + 1, total: acc.total + 1}
        else
          acc
        end
      end)

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:list_failed, _from, state) do
    failed = Map.values(state.failed_operations)
    {:reply, {:ok, failed}, state}
  end

  @impl true
  def handle_call(:list_in_progress, _from, state) do
    in_progress = Map.values(state.active_operations)
    {:reply, {:ok, in_progress}, state}
  end

  @impl true
  def handle_call({:get_operation, file_path}, _from, state) do
    result =
      Map.get(state.active_operations, file_path) ||
        Map.get(state.completed_operations, file_path) ||
        Map.get(state.failed_operations, file_path)

    case result do
      nil -> {:reply, {:error, :not_found}, state}
      operation -> {:reply, {:ok, operation}, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message in IndexingStatusTracker: #{inspect(msg)}")
    {:noreply, state}
  end

  # ========================================================================
  # Private Helpers
  # ========================================================================

  defp remove_from_maps(state, file_path) do
    %{
      state
      | completed_operations: Map.delete(state.completed_operations, file_path),
        failed_operations: Map.delete(state.failed_operations, file_path)
    }
  end

  defp under_project?(file_path, project_root) do
    expanded = Path.expand(file_path)
    normalized_root = Path.expand(project_root)

    # Check if the file is under the project root
    # We need to ensure the root is followed by a path separator or is exactly the root
    String.starts_with?(expanded, normalized_root <> "/") or expanded == normalized_root
  end
end
