defmodule Jidoka.Conversation.Tracker do
  @moduledoc """
  GenServer that tracks conversation state per session.

  This GenServer manages the conversation IRI and turn index for each session,
  providing a centralized location for conversation tracking. It follows the
  same pattern as SessionServer and STM.Server for consistency.

  ## Architecture

  * Process isolation - Each session's conversation state is tracked in ETS
  * Concurrent access safety - GenServer serializes state updates
  * Supervision - Can be restarted under a supervisor
  * Registry integration - Registered in SessionRegistry for lookup by session_id

  ## Client API

  All operations use GenServer.call for synchronous responses:

      {:ok, conversation_iri} = Tracker.get_or_create_conversation(pid, "session_123")
      {:ok, turn_index} = Tracker.next_turn_index(pid)
      {:ok, turn_index} = Tracker.current_turn_index(pid)

  ## Registry

  Sessions are registered in `Jidoka.Memory.SessionRegistry` for
  process lookup by session_id (same registry as SessionServer).
  """

  use GenServer
  require Logger

  defstruct [:session_id, :conversation_iri, :turn_index, :started_at]

  @type t :: %__MODULE__{
          session_id: String.t(),
          conversation_iri: String.t() | nil,
          turn_index: non_neg_integer(),
          started_at: DateTime.t()
        }

  # Client API

  @doc """
  Starts a Tracker for the given session_id.

  ## Parameters

  * `session_id` - The session identifier (validated)

  ## Returns

  * `{:ok, pid}` - Tracker started successfully
  * `{:error, reason}` - Start failed

  ## Examples

      {:ok, pid} = Tracker.start_link("session_123")

  """
  def start_link(session_id) when is_binary(session_id) do
    GenServer.start_link(__MODULE__, session_id, name: via_tuple(session_id))
  end

  # Handle list argument for supervision tree
  def start_link([session_id]) do
    start_link(session_id)
  end

  @doc """
  Gets or creates the conversation IRI for this session.

  If the conversation doesn't exist yet, creates it via Conversation.Logger.

  ## Examples

      {:ok, conversation_iri} = Tracker.get_or_create_conversation(pid)

  """
  def get_or_create_conversation(server) when is_pid(server) or is_atom(server) do
    GenServer.call(server, :get_or_create_conversation)
  end

  @doc """
  Gets the next turn index (atomically increments).

  ## Examples

      {:ok, turn_index} = Tracker.next_turn_index(pid)

  """
  def next_turn_index(server) when is_pid(server) or is_atom(server) do
    GenServer.call(server, :next_turn_index)
  end

  @doc """
  Gets the current turn index without incrementing.

  ## Examples

      {:ok, turn_index} = Tracker.current_turn_index(pid)

  """
  def current_turn_index(server) when is_pid(server) or is_atom(server) do
    GenServer.call(server, :current_turn_index)
  end

  @doc """
  Gets the conversation IRI if it exists.

  ## Examples

      {:ok, conversation_iri} = Tracker.conversation_iri(pid)

  """
  def conversation_iri(server) when is_pid(server) or is_atom(server) do
    GenServer.call(server, :conversation_iri)
  end

  @doc """
  Returns the session_id for this tracker.

  ## Examples

      "session_123" = Tracker.session_id(pid)

  """
  def session_id(server) when is_pid(server) or is_atom(server) do
    GenServer.call(server, :session_id)
  end

  @doc """
  Returns a summary of the tracker state.

  ## Examples

      summary = Tracker.summary(pid)

  """
  def summary(server) when is_pid(server) or is_atom(server) do
    GenServer.call(server, :summary)
  end

  # Server Callbacks

  @impl true
  def init(session_id) do
    state = %__MODULE__{
      session_id: session_id,
      conversation_iri: nil,
      turn_index: 0,
      started_at: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_or_create_conversation, _from, state) do
    case state.conversation_iri do
      nil ->
        # Create new conversation - use full module name to avoid Logger alias conflict
        case Jidoka.Conversation.Logger.ensure_conversation(state.session_id) do
          {:ok, conversation_iri} ->
            new_state = %{state | conversation_iri: conversation_iri}
            {:reply, {:ok, conversation_iri}, new_state}

          {:error, _} = error ->
            {:reply, error, state}
        end

      conversation_iri when is_binary(conversation_iri) ->
        # Return existing conversation
        {:reply, {:ok, conversation_iri}, state}
    end
  end

  @impl true
  def handle_call(:next_turn_index, _from, state) do
    current = state.turn_index
    new_state = %{state | turn_index: current + 1}
    {:reply, {:ok, current}, new_state}
  end

  @impl true
  def handle_call(:current_turn_index, _from, state) do
    {:reply, {:ok, state.turn_index}, state}
  end

  @impl true
  def handle_call(:conversation_iri, _from, state) do
    case state.conversation_iri do
      nil -> {:reply, {:error, :not_found}, state}
      conversation_iri -> {:reply, {:ok, conversation_iri}, state}
    end
  end

  @impl true
  def handle_call(:session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  @impl true
  def handle_call(:summary, _from, state) do
    summary = %{
      session_id: state.session_id,
      conversation_iri: state.conversation_iri,
      turn_index: state.turn_index,
      started_at: state.started_at
    }

    {:reply, summary, state}
  end

  @impl true
  def handle_info(msg, state) do
    # Logger is required above, not the aliased Jidoka.Conversation.Logger
    Logger.warning("Unexpected message in Conversation.Tracker: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Helpers

  defp via_tuple(session_id) do
    # Register in dedicated memory session registry
    {:via, Registry, {Jidoka.Memory.SessionRegistry, {:conversation_tracker, session_id}}}
  end
end
