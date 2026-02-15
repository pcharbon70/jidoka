defmodule Jidoka.Client do
  @moduledoc """
  Client API for session management and interaction.

  This module provides a clean, high-level API for clients (TUI, web, API, etc.)
  to manage work-sessions without directly interacting with internal GenServers.

  The Client module is stateless and delegates to:
  - `SessionManager` for session lifecycle operations
  - `Messaging` for conversation persistence
  - `PubSub` for event subscription and broadcasting

  ## Architecture

  The Client API serves as the public interface for all client types:

  ```
  ┌─────────────────────────────────────────────────────────────┐
  │                   CLIENT LAYER                              │
  │   TUI │ Web │ API │ Custom - all use Client API             │
  ├─────────────────────────────────────────────────────────────┤
  │                   Jidoka.Client (this module)         │
  │   - Session lifecycle (create, terminate, list, get_info)    │
  │   - Message routing (send_message)                           │
  │   - Event subscription (subscribe_to_session)                │
  ├─────────────────────────────────────────────────────────────┤
  │              Internal Agents (not accessed directly)         │
  │   SessionManager │ Messaging │ PubSub                       │
  └─────────────────────────────────────────────────────────────┘
  ```

  ## Session Lifecycle

  Create a new session:

      {:ok, session_id} = Jidoka.Client.create_session()
      {:ok, session_id} = Jidoka.Client.create_session(metadata: %{project: "my-project"})

  List active sessions:

      sessions = Jidoka.Client.list_sessions()

  Get session details:

      {:ok, info} = Jidoka.Client.get_session_info(session_id)

  Terminate a session:

      :ok = Jidoka.Client.terminate_session(session_id)

  ## Messaging

  Send a message to a session:

      :ok = Jidoka.Client.send_message(session_id, :user, "Hello!")
      :ok = Jidoka.Client.send_message(session_id, :assistant, "Hi there!")

  ## Event Subscription

  Subscribe to events for a specific session:

      :ok = Jidoka.Client.subscribe_to_session(session_id)

      # Then in your process:
      receive do
        {:conversation_added, %{session_id: ^session_id, role: :user, content: content}} ->
          # Handle new message
      end

  Subscribe to all session lifecycle events:

      :ok = Jidoka.Client.subscribe_to_all_sessions()

      # Receive session_created and session_terminated events
      receive do
        {:session_created, %{session_id: id}} -> # New session created
        {:session_terminated, %{session_id: id}} -> # Session terminated
      end

  Unsubscribe from a session:

      :ok = Jidoka.Client.unsubscribe_from_session(session_id)

  ## Events

  ### Global Events (via subscribe_to_all_sessions/0)

  Broadcast to `"jido.client.events"`:

  * `{:session_created, %{session_id: ..., metadata: ...}}` - New session created
  * `{:session_terminated, %{session_id: ...}}` - Session terminated

  ### Session-Specific Events (via subscribe_to_session/1)

  Broadcast to `"jido.session.{session_id}"`:

  * `{:conversation_added, %{session_id: ..., role: ..., content: ..., timestamp: ...}}` - New message
  * `{:conversation_cleared, %{session_id: ...}}` - Conversation cleared
  * `{:file_added, %{session_id: ..., file_path: ...}}` - File added to context
  * `{:file_removed, %{session_id: ..., file_path: ...}}` - File removed from context
  * `{:context_updated, %{session_id: ...}}` - Context updated

  """

  alias Jidoka.PubSub
  alias Jidoka.Messaging
  alias Jidoka.Agents.SessionManager

  # Session Lifecycle Functions

  @doc """
  Creates a new session.

  ## Options

  * `:metadata` - Optional metadata map for the session
  * `:llm_config` - Optional LLM configuration for the session

  ## Returns

  * `{:ok, session_id}` - Session was created successfully
  * `{:error, reason}` - Session creation failed

  ## Examples

      {:ok, session_id} = Client.create_session()
      {:ok, session_id} = Client.create_session(metadata: %{project: "my-project"})
      {:ok, session_id} = Client.create_session(llm_config: %{model: "gpt-4"})

  """
  @spec create_session(keyword()) :: {:ok, String.t()} | {:error, term()}
  def create_session(opts \\ []) do
    SessionManager.create_session(opts)
  end

  @doc """
  Terminates a session.

  Stops the session and all its associated processes. The session will be
  cleaned up after termination.

  ## Parameters

  * `session_id` - The session ID to terminate

  ## Returns

  * `:ok` - Session was terminated successfully
  * `{:error, :not_found}` - Session does not exist
  * `{:error, reason}` - Other error

  ## Examples

      :ok = Client.terminate_session(session_id)

  """
  @spec terminate_session(String.t()) :: :ok | {:error, term()}
  def terminate_session(session_id) when is_binary(session_id) do
    SessionManager.terminate_session(session_id)
  end

  @doc """
  Lists all active sessions.

  Returns a list of session maps containing session information.

  ## Returns

  List of session maps with keys:
  * `:session_id` - The session UUID
  * `:status` - Current session status
  * `:created_at` - Creation timestamp
  * `:updated_at` - Last update timestamp
  * `:metadata` - Session metadata
  * `:pid` - SessionSupervisor PID (if running)

  ## Examples

      sessions = Client.list_sessions()
      # => [
      #   %{
      #     session_id: "session-abc123",
      #     status: :active,
      #     created_at: ~U[2025-01-24 10:00:00Z],
      #     updated_at: ~U[2025-01-24 10:00:00Z],
      #     metadata: %{project: "my-project"},
      #     pid: #PID<0.123.0>
      #   },
      #   ...
      # ]

  """
  @spec list_sessions() :: [map()]
  def list_sessions do
    SessionManager.list_sessions()
  end

  @doc """
  Gets detailed information about a session.

  ## Parameters

  * `session_id` - The session ID to look up

  ## Returns

  * `{:ok, session_info}` - Session information map
  * `{:error, :not_found}` - Session does not exist

  ## Examples

      {:ok, info} = Client.get_session_info(session_id)
      info.session_id
      info.status
      info.created_at

  """
  @spec get_session_info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_session_info(session_id) when is_binary(session_id) do
    SessionManager.get_session_info(session_id)
  end

  # Message Functions

  @doc """
  Sends a message to a session's conversation.

  The message is persisted in `Jidoka.Messaging` and a
  `{:conversation_added, payload}` event is broadcast to the session topic.

  ## Parameters

  * `session_id` - The session ID
  * `role` - Message role (:user, :assistant, :system)
  * `content` - Message content (string)

  ## Returns

  * `:ok` - Message was added
  * `{:error, :context_manager_not_found}` - Session not found or inactive
  * `{:error, reason}` - Other error

  ## Examples

      :ok = Client.send_message(session_id, :user, "Hello, world!")
      :ok = Client.send_message(session_id, :assistant, "Hi there!")

  """
  @spec send_message(String.t(), :user | :assistant | :system, String.t()) ::
          :ok | {:error, term()}
  def send_message(session_id, role, content)
      when is_binary(session_id) and role in [:user, :assistant, :system] and is_binary(content) do
    with :ok <- ensure_active_session(session_id),
         {:ok, message} <- Messaging.append_session_message(session_id, role, content) do
      PubSub.broadcast_session(
        session_id,
        {:conversation_added,
         %{
           session_id: session_id,
           role: role,
           content: content,
           timestamp: message.inserted_at || DateTime.utc_now()
         }}
      )

      :ok
    else
      {:error, :not_found} ->
        {:error, :context_manager_not_found}

      {:error, :session_not_active} ->
        {:error, :context_manager_not_found}

      {:error, _reason} = error ->
        error
    end
  end

  defp ensure_active_session(session_id) do
    case SessionManager.get_session_info(session_id) do
      {:ok, %{status: status}} when status in [:active, :idle] -> :ok
      {:ok, _session} -> {:error, :session_not_active}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Event Subscription Functions

  @doc """
  Subscribes the current process to events for a specific session.

  After subscribing, the calling process will receive session-specific events
  such as:
  * `{:conversation_added, %{session_id: ..., role: ..., content: ...}}`
  * `{:conversation_cleared, %{session_id: ...}}`
  * `{:file_added, %{session_id: ..., file_path: ...}}`
  * `{:file_removed, %{session_id: ..., file_path: ...}}`
  * `{:context_updated, %{session_id: ...}}`

  Events are delivered as normal Elixir messages to the calling process.

  ## Parameters

  * `session_id` - The session ID to subscribe to

  ## Returns

  * `:ok` - Successfully subscribed

  ## Examples

      # Subscribe in your process
      :ok = Client.subscribe_to_session(session_id)

      # Handle events
      handle_info({:conversation_added, %{session_id: id, role: :user, content: content}}, state) do
        # Handle new user message
      end

  """
  @spec subscribe_to_session(String.t()) :: :ok
  def subscribe_to_session(session_id) when is_binary(session_id) do
    topic = PubSub.session_topic(session_id)
    PubSub.subscribe(self(), topic)
  end

  @doc """
  Subscribes the current process to all session lifecycle events.

  After subscribing, the calling process will receive global session events:
  * `{:session_created, %{session_id: ..., metadata: ...}}` - New session created
  * `{:session_terminated, %{session_id: ...}}` - Session terminated

  These events are useful for tracking the overall session lifecycle across
  all sessions in the system.

  ## Returns

  * `:ok` - Successfully subscribed

  ## Examples

      # Subscribe in your process
      :ok = Client.subscribe_to_all_sessions()

      # Handle events
      handle_info({:session_created, %{session_id: id}}, state) do
        # Update UI to show new session
      end

      handle_info({:session_terminated, %{session_id: id}}, state) do
        # Remove session from UI
      end

  """
  @spec subscribe_to_all_sessions() :: :ok
  def subscribe_to_all_sessions do
    PubSub.subscribe_client_events()
  end

  @doc """
  Unsubscribes the current process from events for a specific session.

  ## Parameters

  * `session_id` - The session ID to unsubscribe from

  ## Returns

  * `:ok` - Successfully unsubscribed

  ## Examples

      :ok = Client.unsubscribe_from_session(session_id)

  """
  @spec unsubscribe_from_session(String.t()) :: :ok
  def unsubscribe_from_session(session_id) when is_binary(session_id) do
    topic = PubSub.session_topic(session_id)
    PubSub.unsubscribe(topic)
  end

  # Session Persistence Functions

  @doc """
  Saves a session to disk.

  The session's current state is persisted to disk and can be restored later.

  ## Parameters

  * `session_id` - The session ID to save

  ## Returns

  * `:ok` - Session saved successfully
  * `{:error, :not_found}` - Session doesn't exist
  * `{:error, reason}` - Save failed

  ## Examples

      :ok = Client.save_session(session_id)

  """
  @spec save_session(String.t()) :: :ok | {:error, term()}
  def save_session(session_id) when is_binary(session_id) do
    with {:ok, session_info} <- SessionManager.get_session_info(session_id) do
      Jidoka.Session.Persistence.save(session_id, %{state: session_info})
    end
  end

  @doc """
  Restores a session from disk.

  Loads a previously saved session and creates a new session with the saved state.

  ## Parameters

  * `session_id` - The session ID to restore

  ## Returns

  * `{:ok, session_id}` - Session restored successfully
  * `{:error, :not_found}` - Saved session doesn't exist
  * `{:error, reason}` - Restore failed

  ## Examples

      {:ok, session_id} = Client.restore_session("session_abc123")

  """
  @spec restore_session(String.t()) :: {:ok, String.t()} | {:error, term()}
  def restore_session(session_id) when is_binary(session_id) do
    with {:ok, session_state} <- Jidoka.Session.Persistence.load(session_id) do
      # Create a new session with the restored state's configuration
      create_session(
        metadata: Map.put(session_state.metadata || %{}, :restored_from, session_id),
        llm_config: session_state.llm_config || %{}
      )
    end
  end

  @doc """
  Lists all saved sessions on disk.

  ## Returns

  List of session IDs that have been saved

  ## Examples

      saved_sessions = Client.list_saved_sessions()

  """
  @spec list_saved_sessions() :: [String.t()]
  def list_saved_sessions do
    Jidoka.Session.Persistence.list_saved()
  end

  @doc """
  Deletes a saved session from disk.

  ## Parameters

  * `session_id` - The session ID to delete

  ## Returns

  * `:ok` - Saved session deleted
  * `{:error, :not_found}` - Saved session doesn't exist
  * `{:error, reason}` - Delete failed

  ## Examples

      :ok = Client.delete_saved_session("session_abc123")

  """
  @spec delete_saved_session(String.t()) :: :ok | {:error, term()}
  def delete_saved_session(session_id) when is_binary(session_id) do
    Jidoka.Session.Persistence.delete(session_id)
  end
end
