defmodule JidoCoderLib.Agents.SessionManager do
  @moduledoc """
  The SessionManager agent manages the lifecycle of all work-sessions.

  This agent is responsible for:
  - Creating new sessions with unique IDs
  - Tracking active sessions in an ETS table using Session.State structs
  - Terminating sessions and cleaning up resources
  - Listing all active sessions
  - Looking up sessions by ID

  ## Architecture

  The SessionManager uses an ETS table to track session state:
  - Session ID (UUID) -> Session.State struct
  - Each session has a status: :initializing, :active, :idle, :terminating, :terminated

  The actual session processes are managed by individual SessionSupervisors
  (one per session), which are started and supervised by the SessionManager.

  ## Session State

  Sessions are tracked using `JidoCoderLib.Session.State` structs which provide:
  - Type-safe session configuration
  - Validated state transitions
  - Serialization support for persistence
  - Consistent state representation

  ## Examples

  Starting the SessionManager:

      {:ok, pid} = JidoCoderLib.Agents.SessionManager.start_link()

  Creating a new session:

      {:ok, session_id} = JidoCoderLib.Agents.SessionManager.create_session()

  Listing all sessions:

      sessions = JidoCoderLib.Agents.SessionManager.list_sessions()

  Terminating a session:

      :ok = JidoCoderLib.Agents.SessionManager.terminate_session(session_id)

  """

  use GenServer
  require Logger

  alias JidoCoderLib.{PubSub, Session.State}

  @ets_table :session_registry

  # Client API

  @doc """
  Starts the SessionManager.

  ## Options

  * `:name` - Name for the GenServer process (default: `__MODULE__`)
  * `:ets_table` - ETS table name (default: `:session_registry`)

  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Creates a new session.

  ## Options

  * `:metadata` - Optional metadata map for the session
  * `:llm_config` - Optional LLM configuration for the session

  ## Returns

  * `{:ok, session_id}` - Session was created successfully
  * `{:error, reason}` - Session creation failed

  ## Examples

      {:ok, session_id} = SessionManager.create_session()
      {:ok, session_id} = SessionManager.create_session(metadata: %{project: "my-project"})

  """
  def create_session(opts \\ []) do
    GenServer.call(__MODULE__, {:create_session, opts})
  end

  @doc """
  Terminates a session.

  ## Parameters

  * `session_id` - The session ID to terminate

  ## Returns

  * `:ok` - Session was terminated successfully
  * `{:error, :not_found}` - Session does not exist

  ## Examples

      :ok = SessionManager.terminate_session(session_id)

  """
  def terminate_session(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:terminate_session, session_id})
  end

  @doc """
  Lists all active sessions.

  ## Returns

  List of session maps containing:
  * `:session_id` - The session UUID
  * `:status` - Current session status
  * `:created_at` - Creation timestamp
  * `:updated_at` - Last update timestamp
  * `:metadata` - Session metadata

  ## Examples

      sessions = SessionManager.list_sessions()

  """
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @doc """
  Gets the PID of a session by ID.

  ## Parameters

  * `session_id` - The session ID to look up

  ## Returns

  * `{:ok, pid}` - Session PID found
  * `{:error, :not_found}` - Session does not exist

  ## Examples

      {:ok, pid} = SessionManager.get_session_pid(session_id)

  """
  def get_session_pid(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:get_session_pid, session_id})
  end

  @doc """
  Gets detailed information about a session.

  ## Parameters

  * `session_id` - The session ID to look up

  ## Returns

  * `{:ok, session_info}` - Session information map
  * `{:error, :not_found}` - Session does not exist

  ## Examples

      {:ok, info} = SessionManager.get_session_info(session_id)

  """
  def get_session_info(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:get_session_info, session_id})
  end

  @doc """
  Returns the ETS table name used for session tracking.

  """
  def ets_table, do: @ets_table

  # GenServer Callbacks

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :ets_table, @ets_table)

    # Create ETS table for session tracking
    ^table_name = :ets.new(table_name, [:named_table, :set, :public, read_concurrency: true])

    # Trap exits so we don't crash when linked processes die
    Process.flag(:trap_exit, true)

    Logger.info("SessionManager started with ETS table: #{table_name}")

    {:ok, %{table: table_name}}
  end

  @impl true
  def handle_call({:create_session, opts}, _from, state) do
    session_id = generate_session_id()
    metadata = Keyword.get(opts, :metadata, %{})
    llm_config = Keyword.get(opts, :llm_config, %{})

    # Create initial session state
    case State.new(session_id, llm_config: llm_config, metadata: metadata) do
      {:ok, session_state} ->
        # Start the SessionSupervisor for this session
        case JidoCoderLib.Session.Supervisor.start_link(session_id, llm_config: llm_config) do
          {:ok, supervisor_pid} ->
            # Monitor the supervisor so we know if it crashes
            ref = Process.monitor(supervisor_pid)

            # Transition session to active
            {:ok, active_state} = State.transition(session_state, :active)

            # Broadcast status change
            broadcast_session_status(session_id, active_state, session_state)

            # Store session with runtime tracking info
            session_entry = %{
              state: active_state,
              pid: supervisor_pid,
              monitor_ref: ref
            }

            :ets.insert(state.table, {session_id, session_entry})

            Logger.info("Created session: #{session_id}")

            # Broadcast session_created event to global client events
            PubSub.broadcast_client_event(
              {:session_created, %{session_id: session_id, metadata: metadata}}
            )

            {:reply, {:ok, session_id}, state}

          {:error, reason} ->
            Logger.error(
              "Failed to start SessionSupervisor for #{session_id}: #{inspect(reason)}"
            )

            # Store session as failed (transition to terminated)
            {:ok, failed_state} = State.transition(session_state, :terminated)

            session_entry = %{
              state: State.update(failed_state, %{error: inspect(reason)}) |> elem(1),
              pid: nil,
              monitor_ref: nil
            }

            :ets.insert(state.table, {session_id, session_entry})

            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        Logger.error("Failed to create session state for #{session_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:terminate_session, session_id}, _from, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, session_entry}] ->
        # Transition session to terminating
        case State.transition(session_entry.state, :terminating) do
          {:ok, terminating_state} ->
            # Broadcast status change
            broadcast_session_status(session_id, terminating_state, session_entry.state)

            :ets.insert(state.table, {session_id, %{session_entry | state: terminating_state}})

            # Stop the SessionSupervisor if it exists and is alive
            if session_entry.pid && Process.alive?(session_entry.pid) do
              # Demonitor the process first
              if session_entry.monitor_ref do
                Process.demonitor(session_entry.monitor_ref, [:flush])
              end

              # Stop the supervisor which will stop all its children
              case Supervisor.stop(session_entry.pid, :normal, 5000) do
                :ok ->
                  Logger.info("Stopped SessionSupervisor for session: #{session_id}")

                {:error, reason} ->
                  Logger.warning(
                    "Failed to gracefully stop SessionSupervisor for #{session_id}: #{inspect(reason)}"
                  )

                  # Force kill if graceful stop fails
                  Process.exit(session_entry.pid, :kill)
              end
            end

            # Transition to terminated
            {:ok, terminated_state} = State.transition(terminating_state, :terminated)

            # Broadcast final status change
            broadcast_session_status(session_id, terminated_state, terminating_state)

            final_entry = %{
              state: terminated_state,
              pid: nil,
              monitor_ref: nil
            }

            :ets.insert(state.table, {session_id, final_entry})

            # Remove from registry after a delay
            Process.send_after(self(), {:cleanup_session, session_id}, 50)

            Logger.info("Terminated session: #{session_id}")

            # Broadcast session_terminated event to global client events
            PubSub.broadcast_client_event({:session_terminated, %{session_id: session_id}})

            {:reply, :ok, state}

          {:error, reason} ->
            Logger.error(
              "Failed to transition session #{session_id} to terminating: #{inspect(reason)}"
            )

            {:reply, {:error, reason}, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sessions =
      :ets.tab2list(state.table)
      |> Enum.filter(fn {_id, entry} -> entry.state.status != :terminated end)
      |> Enum.map(fn {_id, entry} ->
        # Return the session state with pid added
        Map.put(entry.state, :pid, entry.pid)
      end)

    {:reply, sessions, state}
  end

  @impl true
  def handle_call({:get_session_pid, session_id}, _from, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, %{pid: pid, state: session_state}}]
      when session_state.status != :terminated ->
        if pid && Process.alive?(pid) do
          {:reply, {:ok, pid}, state}
        else
          {:reply, {:error, :not_found}, state}
        end

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_session_info, session_id}, _from, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, session_entry}] ->
        # Return the session state with pid added
        info = Map.put(session_entry.state, :pid, session_entry.pid)
        {:reply, {:ok, info}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:cleanup_session, session_id}, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, session_entry}] ->
        # Verify the process is actually terminated before cleanup
        # If the process is still alive, reschedule cleanup
        if session_entry.pid && Process.alive?(session_entry.pid) do
          Logger.debug("Session #{session_id} process still alive, rescheduling cleanup")
          Process.send_after(self(), {:cleanup_session, session_id}, 50)
          {:noreply, state}
        else
          :ets.delete(state.table, session_id)
          Logger.debug("Cleaned up session: #{session_id}")
          {:noreply, state}
        end

      [] ->
        # Session already cleaned up, ignore
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Find the session associated with this monitor reference
    case Enum.find(:ets.tab2list(state.table), fn {_id, entry} ->
           entry.monitor_ref == ref or entry.pid == pid
         end) do
      {session_id, session_entry} ->
        # Transition session to terminated via error path
        # First transition to terminating, then to terminated
        case State.transition(session_entry.state, :terminated) do
          {:ok, terminated_state} ->
            # Broadcast status change due to crash
            broadcast_session_status(session_id, terminated_state, session_entry.state)

            # Add error information
            {:ok, error_state} =
              State.update(terminated_state, %{
                error: "SessionSupervisor crashed: #{inspect(reason)}"
              })

            updated_entry = %{
              state: error_state,
              pid: nil,
              monitor_ref: nil
            }

            :ets.insert(state.table, {session_id, updated_entry})

            Logger.error("Session crashed: #{session_id}, reason: #{inspect(reason)}")

            # Schedule cleanup
            Process.send_after(self(), {:cleanup_session, session_id}, 50)

            {:noreply, state}

          {:error, _reason} ->
            Logger.error("Failed to transition crashed session #{session_id} to terminated")
            {:noreply, state}
        end

      nil ->
        # Unknown process, ignore
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    # Ignore EXIT messages since we trap exits
    # We handle process crashes via DOWN messages from monitoring
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up ETS table on shutdown
    :ets.delete(state.table)
    Logger.info("SessionManager stopped")
    :ok
  end

  # Private Helpers

  defp generate_session_id do
    # Use uniq for UUID generation (already a dependency via req_llm)
    # If uniq is not available, fall back to a simple UUID
    case Code.ensure_loaded?(Uniq.UUID) do
      true ->
        "session_#{Uniq.UUID.uuid4()}"

      _ ->
        # Fallback: use timestamp and random integer
        "session_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"
    end
  end

  defp broadcast_session_status(session_id, new_state, previous_state) do
    event =
      {:session_status,
       %{
         session_id: session_id,
         status: new_state.status,
         previous_status: previous_state.status,
         updated_at: new_state.updated_at
       }}

    # Broadcast to global client events
    PubSub.broadcast_client_event(event)

    # Broadcast to session-specific client events
    PubSub.broadcast_client_session(session_id, event)
  end
end
