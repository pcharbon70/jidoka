defmodule Jidoka.Session.Supervisor do
  @moduledoc """
  Supervisor for a single session's agents.

  Each session has its own supervisor that manages the lifecycle of
  session-specific agents including ContextManager and LTM adapter.

  ## Architecture

  The SessionSupervisor is started dynamically by the SessionManager
  when a new session is created. Each session gets its own supervisor
  with isolated child processes.

  ## Supervision Tree

  ```
  SessionSupervisor (one_for_one)
  ├── ContextManager (with STM integration)
  ├── Conversation.Tracker (conversation tracking)
  └── SessionAdapter (LTM per session)
  └── LLMOrchestrator (Phase 4 - placeholder)
  ```

  ## Registry

  Each SessionSupervisor registers itself in the AgentRegistry with:
  - Key pattern: `"session_supervisor:" <> session_id`
  - This allows looking up the supervisor by session_id

  ## Examples

  Starting a session supervisor (typically done by SessionManager):

      {:ok, pid} = Jidoka.Session.Supervisor.start_link("session-123", [])

  Finding a session supervisor:

      {:ok, pid} = Jidoka.Session.Supervisor.find_supervisor("session-123")

  Getting the LLM agent for a session:

      {:ok, llm_pid} = Jidoka.Session.Supervisor.get_llm_agent_pid("session-123")

  Getting the ContextManager for a session:

      {:ok, ctx_pid} = Jidoka.Session.Supervisor.get_context_manager_pid("session-123")

  Getting the Conversation.Tracker for a session:

      {:ok, tracker_pid} = Jidoka.Session.Supervisor.get_conversation_tracker_pid("session-123")

  Getting the LTM adapter for a session:

      {:ok, ltm_pid} = Jidoka.Session.Supervisor.get_ltm_adapter_pid("session-123")

  Getting the STM for a session:

      {:ok, stm} = Jidoka.Session.Supervisor.get_stm("session-123")

  """

  use Supervisor
  require Logger

  alias Jidoka.{AgentRegistry, Memory}
  alias Memory.LongTerm.SessionAdapter

  @registry_key_prefix "session_supervisor:"

  # Client API

  @doc """
  Starts a session supervisor for the given session_id.

  ## Parameters

  * `session_id` - Unique session identifier
  * `opts` - Optional keyword list
    * `:llm_config` - LLM configuration for the session
    * `:stm_enabled` - Enable STM in ContextManager (default: true)
    * `:ltm_enabled` - Enable LTM adapter (default: true)
    * `:name` - Optional name for the supervisor process

  ## Returns

  * `{:ok, pid}` - Supervisor started successfully
  * `{:error, reason}` - Failed to start

  ## Examples

      {:ok, pid} = Session.Supervisor.start_link("session-123", [])
      {:ok, pid} = Session.Supervisor.start_link("session-123", llm_config: %{model: "gpt-4"})
      {:ok, pid} = Session.Supervisor.start_link("session-123", stm_enabled: false, ltm_enabled: false)

  """
  def start_link(session_id, opts \\ []) do
    llm_config = Keyword.get(opts, :llm_config, %{})
    stm_enabled = Keyword.get(opts, :stm_enabled, true)
    ltm_enabled = Keyword.get(opts, :ltm_enabled, true)
    name = Keyword.get(opts, :name)

    # Build the child spec for the supervisor
    # We pass session_id and llm_config in the init args
    Supervisor.start_link(
      __MODULE__,
      [
        session_id: session_id,
        llm_config: llm_config,
        stm_enabled: stm_enabled,
        ltm_enabled: ltm_enabled
      ],
      name: name
    )
  end

  @doc """
  Finds a session supervisor by session_id.

  ## Parameters

  * `session_id` - The session ID to look up

  ## Returns

  * `{:ok, pid}` - Supervisor found
  * `{:error, :not_found}` - Supervisor not found

  ## Examples

      {:ok, pid} = Session.Supervisor.find_supervisor("session-123")

  """
  def find_supervisor(session_id) when is_binary(session_id) do
    key = registry_key(session_id)

    case Registry.lookup(AgentRegistry, key) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets the LLM agent PID for a session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, pid}` - LLM agent found
  * `{:error, :not_found}` - LLM agent not found (Phase 4)

  ## Examples

      {:ok, llm_pid} = Session.Supervisor.get_llm_agent_pid("session-123")

  """
  def get_llm_agent_pid(session_id) when is_binary(session_id) do
    with {:ok, supervisor_pid} <- find_supervisor(session_id),
         {:ok, children} <- get_children(supervisor_pid) do
      # Look for LLM orchestrator in children
      # Phase 4: This will find the actual LLMOrchestrator process
      # For now, we only have Placeholder, so we return :not_found
      case Enum.find(children, fn
             {:llm_orchestrator, pid, _, _} when is_pid(pid) -> true
             _ -> false
           end) do
        nil -> {:error, :not_found}
        {_id, pid, _, _} -> {:ok, pid}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Gets the ContextManager PID for a session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, pid}` - ContextManager found
  * `{:error, :not_found}` - ContextManager not found

  ## Examples

      {:ok, ctx_pid} = Session.Supervisor.get_context_manager_pid("session-123")

  """
  def get_context_manager_pid(session_id) when is_binary(session_id) do
    with {:ok, supervisor_pid} <- find_supervisor(session_id),
         {:ok, children} <- get_children(supervisor_pid) do
      # Look for ContextManager in children
      case Enum.find(children, fn
             {:context_manager, pid, _, _} when is_pid(pid) -> true
             _ -> false
           end) do
        nil -> {:error, :not_found}
        {_id, pid, _, _} -> {:ok, pid}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Gets the Conversation.Tracker PID for a session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, pid}` - Conversation.Tracker found
  * `{:error, :not_found}` - Conversation.Tracker not found

  ## Examples

      {:ok, tracker_pid} = Session.Supervisor.get_conversation_tracker_pid("session-123")

  """
  def get_conversation_tracker_pid(session_id) when is_binary(session_id) do
    with {:ok, supervisor_pid} <- find_supervisor(session_id),
         {:ok, children} <- get_children(supervisor_pid) do
      # Look for Conversation.Tracker in children
      case Enum.find(children, fn
             {:conversation_tracker, pid, _, _} when is_pid(pid) -> true
             _ -> false
           end) do
        nil -> {:error, :not_found}
        {_id, pid, _, _} -> {:ok, pid}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Gets the LTM adapter PID for a session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, pid}` - LTM adapter found
  * `{:error, :not_found}` - LTM adapter not found or disabled

  ## Examples

      {:ok, ltm_pid} = Session.Supervisor.get_ltm_adapter_pid("session-123")

  """
  def get_ltm_adapter_pid(session_id) when is_binary(session_id) do
    with {:ok, supervisor_pid} <- find_supervisor(session_id),
         {:ok, children} <- get_children(supervisor_pid) do
      # Look for SessionAdapter in children
      case Enum.find(children, fn
             {:ltm_adapter, pid, _, _} when is_pid(pid) -> true
             _ -> false
           end) do
        nil -> {:error, :not_found}
        {_id, pid, _, _} -> {:ok, pid}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Gets the STM (ShortTerm Memory) for a session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, stm}` - STM struct found
  * `{:error, :not_found}` - ContextManager or STM not found

  ## Examples

      {:ok, stm} = Session.Supervisor.get_stm("session-123")

  """
  def get_stm(session_id) when is_binary(session_id) do
    with {:ok, ctx_pid} <- get_context_manager_pid(session_id) do
      # Get STM from ContextManager via call
      case GenServer.call(ctx_pid, :get_stm) do
        {:ok, stm} -> {:ok, stm}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Gets the LTM adapter for a session.

  Creates the adapter on-demand if it doesn't exist.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, ltm}` - LTM adapter found or created
  * `{:error, reason}` - Failed to get or create adapter

  ## Examples

      {:ok, ltm} = Session.Supervisor.get_ltm_adapter("session_123")

  """
  def get_ltm_adapter(session_id) when is_binary(session_id) do
    # LTM adapter is created on-demand via SessionAdapter.new/1
    # It's not a supervised process, just a struct wrapper around ETS
    case SessionAdapter.new(session_id) do
      {:ok, adapter} -> {:ok, adapter}
      error -> error
    end
  end

  @doc """
  Returns the registry key for a given session_id.

  """
  def registry_key(session_id) when is_binary(session_id) do
    @registry_key_prefix <> session_id
  end

  # Supervisor Callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    llm_config = Keyword.get(opts, :llm_config, %{})
    stm_enabled = Keyword.get(opts, :stm_enabled, true)
    ltm_enabled = Keyword.get(opts, :ltm_enabled, true)

    # Register this supervisor in the Registry
    key = registry_key(session_id)

    # Try to register - if already registered, return :ignore to prevent duplicate starts
    case Registry.register(AgentRegistry, key, %{}) do
      {:ok, _} ->
        Logger.info(
          "SessionSupervisor started for session: #{session_id} (STM: #{stm_enabled}, LTM: #{ltm_enabled})"
        )

        # Build child specifications
        children = build_children(session_id, llm_config, stm_enabled, ltm_enabled)

        # Use one_for_one strategy so each child restarts independently
        # This ensures a crash in one agent doesn't affect others
        supervisor_opts = [
          strategy: :one_for_one,
          max_restarts: 10,
          max_seconds: 60
        ]

        Supervisor.init(children, supervisor_opts)

      {:error, {:already_started, _pid}} ->
        :ignore

      {:error, {:already_registered, _pid}} ->
        # This can happen if a process with this key already exists but wasn't started through start_link
        :ignore
    end
  end

  # Private Helpers

  defp build_children(session_id, _llm_config, stm_enabled, _ltm_enabled) do
    # Build the list of children for this session
    # Note: LTM (SessionAdapter) is NOT a separate process
    # It's accessed via ContextManager.get_ltm_adapter/1 or Session.Supervisor.get_ltm_adapter/1
    # which returns the struct directly from the ContextManager's state

    # Add ContextManager for session-isolated context management
    # ContextManager holds both STM and initializes LTM on demand
    context_opts = [session_id: session_id]

    context_opts =
      if stm_enabled,
        do: context_opts ++ [stm_enabled: true],
        else: context_opts ++ [stm_enabled: false]

    [
      # Conversation.Tracker for conversation IRI and turn index tracking
      # Registered in SessionRegistry with key {:conversation_tracker, session_id}
      {Jidoka.Conversation.Tracker, session_id},
      # ContextManager for session-isolated context management
      # Note: ContextManager registers itself in AgentRegistry, not by name
      {Jidoka.Agents.ContextManager, context_opts}
    ]
  end

  defp get_children(supervisor_pid) do
    # Get all children from the supervisor
    try do
      children = Supervisor.which_children(supervisor_pid)
      {:ok, children}
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end
end
