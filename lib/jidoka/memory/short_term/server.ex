defmodule Jidoka.Memory.ShortTerm.Server do
  @moduledoc """
  GenServer that owns and manages a ShortTerm memory struct for a session.

  This GenServer provides process isolation for the STM (ShortTerm Memory),
  which was previously a pure struct-based approach. The GenServer owns
  the state and handles all state updates through GenServer.call.

  ## Architecture Improvements over Pure Struct Approach

  * Process isolation - Each session's STM is a separate GenServer
  * Concurrent access safety - GenServer serializes state updates
  * Supervision - Can be restarted under a supervisor
  * Hot code swapping - GenServer supports code reload

  ## Client API

  All operations use GenServer.call for synchronous responses:

      {:ok, pid} = Server.start_link("session_123")
      {:ok, stm} = Server.add_message(pid, %{role: :user, content: "Hello"})
      {:ok, value} = Server.get_context(pid, "current_file")

  ## Registry

  Sessions are registered in `Jidoka.Memory.SessionRegistry` for
  process lookup by session_id (same registry as SessionServer).

  ## Note

  This GenServer wraps the existing ShortTerm struct. The struct-based
  API is still available for cases where process isolation isn't needed.
  """

  use GenServer
  alias Jidoka.Memory.{ShortTerm, Validation}

  defstruct [:session_id, :stm, :started_at]

  @type t :: %__MODULE__{
          session_id: String.t(),
          stm: ShortTerm.t(),
          started_at: DateTime.t()
        }

  # Client API

  @doc """
  Starts a Server for the given session_id.

  ## Parameters

  * `session_id` - The session identifier (validated)
  * `opts` - Options to pass to ShortTerm.new/2

  ## Returns

  * `{:ok, pid}` - Server started successfully
  * `{:error, reason}` - Start failed

  ## Examples

      {:ok, pid} = Server.start_link("session_123")
      {:ok, pid} = Server.start_link("session_123", max_tokens: 8000)

  """
  # Handle list argument for supervision tree (must come first to avoid conflict)
  def start_link([session_id]) do
    start_link(session_id, [])
  end

  def start_link([session_id], opts) when is_list(opts) do
    start_link(session_id, opts)
  end

  def start_link(session_id, opts \\ []) do
    # Validate session_id first
    with :ok <- Validation.validate_session_id(session_id) do
      GenServer.start_link(__MODULE__, {session_id, opts})
    end
  end

  @doc """
  Adds a message to the conversation buffer.

  ## Examples

      {:ok, stm} = Server.add_message(pid, %{role: :user, content: "Hello"})

  """
  def add_message(server, message) when is_map(message) do
    GenServer.call(server, {:add_message, message})
  end

  @doc """
  Gets recent messages from the conversation buffer.

  ## Examples

      messages = Server.recent_messages(pid, 10)
      messages = Server.recent_messages(pid)  # all messages

  """
  def recent_messages(server, count \\ nil) do
    GenServer.call(server, {:recent_messages, count})
  end

  @doc """
  Gets all messages in chronological order.

  ## Examples

      messages = Server.all_messages(pid)

  """
  def all_messages(server) do
    GenServer.call(server, :all_messages)
  end

  @doc """
  Gets the message count.

  ## Examples

      count = Server.message_count(pid)

  """
  def message_count(server) do
    GenServer.call(server, :message_count)
  end

  @doc """
  Gets the current token count.

  ## Examples

      tokens = Server.token_count(pid)

  """
  def token_count(server) do
    GenServer.call(server, :token_count)
  end

  @doc """
  Stores a value in the working context.

  ## Examples

      {:ok, stm} = Server.put_context(pid, "current_file", "/path/to/file.ex")

  """
  def put_context(server, key, value) when is_binary(key) do
    GenServer.call(server, {:put_context, key, value})
  end

  @doc """
  Gets a value from the working context.

  ## Examples

      {:ok, value} = Server.get_context(pid, "current_file")
      value = Server.get_context(pid, "key", "default")

  """
  def get_context(server, key) when is_binary(key) do
    GenServer.call(server, {:get_context, key})
  end

  def get_context(server, key, default) when is_binary(key) do
    GenServer.call(server, {:get_context, key, default})
  end

  @doc """
  Deletes a value from the working context.

  ## Examples

      {:ok, stm} = Server.delete_context(pid, "current_file")

  """
  def delete_context(server, key) when is_binary(key) do
    GenServer.call(server, {:delete_context, key})
  end

  @doc """
  Returns all context keys.

  ## Examples

      keys = Server.context_keys(pid)

  """
  def context_keys(server) do
    GenServer.call(server, :context_keys)
  end

  @doc """
  Updates multiple context values.

  ## Examples

      {:ok, stm} = Server.put_context_many(pid, %{"key1" => "val1", "key2" => "val2"})

  """
  def put_context_many(server, updates) when is_map(updates) do
    GenServer.call(server, {:put_context_many, updates})
  end

  @doc """
  Enqueues a memory item for LTM promotion.

  ## Examples

      {:ok, stm} = Server.enqueue_memory(pid, %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8
      })

  """
  def enqueue_memory(server, item) when is_map(item) do
    GenServer.call(server, {:enqueue_memory, item})
  end

  @doc """
  Dequeues the next memory item for promotion.

  ## Examples

      {:ok, item, stm} = Server.dequeue_memory(pid)

  """
  def dequeue_memory(server) do
    GenServer.call(server, :dequeue_memory)
  end

  @doc """
  Peeks at the next pending memory.

  ## Examples

      {:ok, item} = Server.peek_pending_memory(pid)

  """
  def peek_pending_memory(server) do
    GenServer.call(server, :peek_pending_memory)
  end

  @doc """
  Gets the pending memory count.

  ## Examples

      count = Server.pending_count(pid)

  """
  def pending_count(server) do
    GenServer.call(server, :pending_count)
  end

  @doc """
  Records an access in the access log.

  ## Examples

      {:ok, stm} = Server.record_access(pid)

  """
  def record_access(server) do
    GenServer.call(server, :record_access)
  end

  @doc """
  Gets the access log.

  ## Examples

      log = Server.access_log(pid)

  """
  def access_log(server) do
    GenServer.call(server, :access_log)
  end

  @doc """
  Gets access statistics.

  ## Examples

      stats = Server.access_stats(pid)

  """
  def access_stats(server) do
    GenServer.call(server, :access_stats)
  end

  @doc """
  Gets a summary of the STM state.

  ## Examples

      summary = Server.summary(pid)

  """
  def summary(server) do
    GenServer.call(server, :summary)
  end

  @doc """
  Returns the session_id for this server.

  ## Examples

      "session_123" = Server.session_id(pid)

  """
  def session_id(server) do
    GenServer.call(server, :session_id)
  end

  @doc """
  Returns the STM struct (for inspection/testing).

  ## Examples

      {:ok, stm} = Server.get_stm(pid)

  """
  def get_stm(server) do
    GenServer.call(server, :get_stm)
  end

  # Server Callbacks

  @impl true
  def init({session_id, opts}) do
    stm = ShortTerm.new(session_id, opts)

    state = %__MODULE__{
      session_id: session_id,
      stm: stm,
      started_at: DateTime.utc_now()
    }

    {:ok, state}
  end

  # Conversation Buffer handlers

  @impl true
  def handle_call({:add_message, message}, _from, state) do
    case ShortTerm.add_message(state.stm, message) do
      {:ok, stm} ->
        {:reply, {:ok, stm}, %{state | stm: stm}}

      {:ok, stm, evicted} ->
        {:reply, {:ok, stm, evicted}, %{state | stm: stm}}
    end
  end

  @impl true
  def handle_call({:recent_messages, count}, _from, state) do
    result =
      if is_nil(count) do
        ShortTerm.recent_messages(state.stm)
      else
        ShortTerm.recent_messages(state.stm, count)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:all_messages, _from, state) do
    {:reply, ShortTerm.all_messages(state.stm), state}
  end

  @impl true
  def handle_call(:message_count, _from, state) do
    {:reply, ShortTerm.message_count(state.stm), state}
  end

  @impl true
  def handle_call(:token_count, _from, state) do
    {:reply, ShortTerm.token_count(state.stm), state}
  end

  # Working Context handlers

  @impl true
  def handle_call({:put_context, key, value}, _from, state) do
    case ShortTerm.put_context(state.stm, key, value) do
      {:ok, stm} ->
        {:reply, {:ok, stm}, %{state | stm: stm}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_context, key}, _from, state) do
    {:reply, ShortTerm.get_context(state.stm, key), state}
  end

  @impl true
  def handle_call({:get_context, key, default}, _from, state) do
    {:reply, ShortTerm.get_context(state.stm, key, default), state}
  end

  @impl true
  def handle_call({:delete_context, key}, _from, state) do
    case ShortTerm.delete_context(state.stm, key) do
      {:ok, stm} ->
        {:reply, {:ok, stm}, %{state | stm: stm}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:context_keys, _from, state) do
    {:reply, ShortTerm.context_keys(state.stm), state}
  end

  @impl true
  def handle_call({:put_context_many, updates}, _from, state) do
    case ShortTerm.put_context_many(state.stm, updates) do
      {:ok, stm} ->
        {:reply, {:ok, stm}, %{state | stm: stm}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  # Pending Memories handlers

  @impl true
  def handle_call({:enqueue_memory, item}, _from, state) do
    case ShortTerm.enqueue_memory(state.stm, item) do
      {:ok, stm} ->
        {:reply, {:ok, stm}, %{state | stm: stm}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:dequeue_memory, _from, state) do
    case ShortTerm.dequeue_memory(state.stm) do
      {:ok, item, stm} ->
        {:reply, {:ok, item, stm}, %{state | stm: stm}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:peek_pending_memory, _from, state) do
    {:reply, ShortTerm.peek_pending_memory(state.stm), state}
  end

  @impl true
  def handle_call(:pending_count, _from, state) do
    {:reply, ShortTerm.pending_count(state.stm), state}
  end

  # Utility handlers

  @impl true
  def handle_call(:record_access, _from, state) do
    stm = ShortTerm.record_access(state.stm)
    {:reply, {:ok, stm}, %{state | stm: stm}}
  end

  @impl true
  def handle_call(:access_log, _from, state) do
    {:reply, ShortTerm.access_log(state.stm), state}
  end

  @impl true
  def handle_call(:access_stats, _from, state) do
    {:reply, ShortTerm.access_stats(state.stm), state}
  end

  @impl true
  def handle_call(:summary, _from, state) do
    {:reply, ShortTerm.summary(state.stm), state}
  end

  @impl true
  def handle_call(:session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  @impl true
  def handle_call(:get_stm, _from, state) do
    {:reply, {:ok, state.stm}, state}
  end

  @impl true
  def handle_info(msg, state) do
    require Logger
    Logger.warning("Unexpected message in STM.Server: #{inspect(msg)}")
    {:noreply, state}
  end
end
