defmodule Jidoka.Signals do
  @moduledoc """
  Convenience functions for creating and dispatching Jidoka signals.

  This module provides a unified interface for signal creation and dispatch,
  integrating with Phoenix PubSub for signal routing.

  All signals follow the CloudEvents v1.0.2 specification and are built
  on top of Jido's Signal system.

  ## Signal Types

  - `file_changed/3` - File system events
  - `analysis_complete/3` - Analysis results
  - `broadcast_event/3` - Client broadcast events
  - `chat_request/2` - User chat requests
  - `indexing_status/2` - Code indexing status updates
  - `phoenix_event/4` - Phoenix Channels message events
  - `phoenix_connection_state/2` - Phoenix connection state changes
  - `phoenix_channel_state/3` - Phoenix channel state changes
  - `a2a_message/2` - A2A message sent or received
  - `a2a_agent_discovered/2` - A2A agent discovered
  - `a2a_connection_state/1` - A2A gateway connection state changes

  ## Options

  All signal constructors accept the following options:

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override the default source
  - `:subject` - Set a custom subject for the signal

  ## Examples

  Create and dispatch a signal (default behavior):

      {:ok, signal} = Jidoka.Signals.file_changed("/path/to/file.ex", :updated)

  Create a signal without dispatching:

      {:ok, signal} = Jidoka.Signals.file_changed(
        "/path/to/file.ex",
        :updated,
        dispatch: false
      )

  Create with custom source:

      {:ok, signal} = Jidoka.Signals.analysis_complete(
        "custom_type",
        %{result: :ok},
        source: "/custom/source"
      )

  """

  alias Jidoka.PubSub

  alias Jidoka.Signals.{
    FileChanged,
    AnalysisComplete,
    BroadcastEvent,
    ChatRequest,
    IndexingStatus,
    PhoenixEvent,
    PhoenixConnectionState,
    PhoenixChannelState,
    A2AMessage,
    A2AAgentDiscovered,
    A2AConnectionState
  }

  @type signal :: Jido.Signal.t()
  @type signal_result :: {:ok, signal()} | {:error, term()}

  @doc """
  Creates and optionally dispatches a file changed signal.

  ## Parameters

  - `path` - Absolute path to the changed file
  - `action` - Type of change: `:created`, `:updated`, or `:deleted`
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/filesystem`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Session tracking ID
  - `:metadata` - Additional metadata about the file change

  ## Examples

      {:ok, signal} = Signals.file_changed("/path/to/file.ex", :updated)

      {:ok, signal} = Signals.file_changed(
        "/path/to/file.ex",
        :created,
        session_id: "session-123",
        metadata: %{size: 1024}
      )

  """
  @spec file_changed(String.t(), atom(), Keyword.t()) :: signal_result()
  def file_changed(path, action, opts \\ []) when is_binary(path) and is_atom(action) do
    data =
      %{
        path: path,
        action: action,
        metadata: Keyword.get(opts, :metadata, %{})
      }
      |> maybe_put_session_id(opts)

    create_and_dispatch(FileChanged, data, opts)
  end

  @doc """
  Creates and optionally dispatches an analysis complete signal.

  ## Parameters

  - `analysis_type` - Type of analysis performed (e.g., "credo", "dialyzer")
  - `results` - Analysis results map
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/analyzer`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Associated session ID
  - `:duration_ms` - Analysis duration in milliseconds

  ## Examples

      {:ok, signal} = Signals.analysis_complete("credo", %{errors: [], warnings: ["unused var"]})

      {:ok, signal} = Signals.analysis_complete(
        "dialyzer",
        %{warnings: 5},
        session_id: "session-123",
        duration_ms: 150
      )

  """
  @spec analysis_complete(String.t(), map(), Keyword.t()) :: signal_result()
  def analysis_complete(analysis_type, results, opts \\ []) when is_binary(analysis_type) do
    data =
      %{
        analysis_type: analysis_type,
        results: results
      }
      |> maybe_put_session_id(opts)
      |> maybe_put_duration_ms(opts)

    create_and_dispatch(AnalysisComplete, data, opts)
  end

  @doc """
  Creates and optionally dispatches a client broadcast event signal.

  ## Parameters

  - `event_type` - Type of client event (e.g., "llm_stream_chunk", "agent_status")
  - `payload` - Event payload map
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/coordinator`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Target session ID for targeted broadcasts

  ## Examples

      {:ok, signal} = Signals.broadcast_event("llm_stream_chunk", %{content: "Hello"})

      {:ok, signal} = Signals.broadcast_event(
        "agent_status",
        %{status: :ready},
        session_id: "session-123"
      )

  """
  @spec broadcast_event(String.t(), map(), Keyword.t()) :: signal_result()
  def broadcast_event(event_type, payload, opts \\ []) when is_binary(event_type) do
    data =
      %{
        event_type: event_type,
        payload: payload
      }
      |> maybe_put_session_id(opts)

    create_and_dispatch(BroadcastEvent, data, opts)
  end

  @doc """
  Creates and optionally dispatches an indexing status signal.

  ## Parameters

  - `file_path` - Path to the file being indexed
  - `status` - Current indexing status (required)
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/indexing`)
  - `:subject` - Custom subject for the signal
  - `:project_root` - Root directory of the project
  - `:triple_count` - Number of triples generated
  - `:error_message` - Error message (for failed operations)
  - `:duration_ms` - Duration in milliseconds

  ## Examples

      {:ok, signal} = Signals.indexing_status("lib/my_app.ex", :in_progress)

      {:ok, signal} = Signals.indexing_status(
        "lib/my_app.ex",
        :completed,
        triple_count: 42,
        duration_ms: 150
      )

      {:ok, signal} = Signals.indexing_status(
        "lib/invalid.ex",
        :failed,
        error_message: "Syntax error at line 10",
        duration_ms: 50
      )

  """
  @spec indexing_status(String.t(), atom(), Keyword.t()) :: signal_result()
  def indexing_status(file_path, status, opts \\ [])
      when is_binary(file_path) and is_atom(status) do
    data =
      %{
        file_path: file_path,
        status: status
      }
      |> maybe_put_project_root(opts)
      |> maybe_put_triple_count(opts)
      |> maybe_put_error_message(opts)
      |> maybe_put_duration_ms(opts)

    create_and_dispatch(IndexingStatus, data, opts)
  end

  @doc """
  Creates and optionally dispatches a chat request signal.

  ## Parameters

  - `message` - User message content
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/client`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Associated session ID (defaults to empty string)
  - `:user_id` - User identifier
  - `:context` - Additional conversation context map

  ## Examples

      {:ok, signal} = Signals.chat_request("Help me debug this function")

      {:ok, signal} = Signals.chat_request(
        "Explain this code",
        session_id: "session-123",
        user_id: "user-456",
        context: %{language: "elixir"}
      )

  """
  @spec chat_request(String.t(), Keyword.t()) :: signal_result()
  def chat_request(message, opts \\ []) when is_binary(message) do
    data =
      %{
        message: message,
        session_id: Keyword.get(opts, :session_id, ""),
        context: Keyword.get(opts, :context, %{})
      }
      |> maybe_put_user_id(opts)

    create_and_dispatch(ChatRequest, data, opts)
  end

  @doc """
  Creates and optionally dispatches a Phoenix Channels event signal.

  ## Parameters

  - `connection_name` - Name of the connection receiving the event
  - `topic` - Phoenix channel topic
  - `event` - Event name
  - `payload` - Event payload map
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/phoenix`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Associated session ID

  ## Examples

      {:ok, signal} = Signals.phoenix_event(
        :my_connection,
        "room:lobby",
        "new_msg",
        %{body: "Hello!"}
      )

      {:ok, signal} = Signals.phoenix_event(
        :my_connection,
        "user:123",
        "presence_state",
        %{users: ["user1", "user2"]},
        session_id: "session-123"
      )

  """
  @spec phoenix_event(atom(), String.t(), String.t(), map(), Keyword.t()) :: signal_result()
  def phoenix_event(connection_name, topic, event, payload, opts \\ [])
      when is_atom(connection_name) and is_binary(topic) and is_binary(event) and is_map(payload) do
    data =
      %{
        connection_name: connection_name,
        topic: topic,
        event: event,
        payload: payload
      }
      |> maybe_put_session_id(opts)

    create_and_dispatch(PhoenixEvent, data, opts)
  end

  @doc """
  Creates and optionally dispatches a Phoenix connection state signal.

  ## Parameters

  - `connection_name` - Name of the connection
  - `state` - Connection state: `:connected`, `:disconnected`, `:connecting`
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/phoenix`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Associated session ID
  - `:reason` - Reason for state change
  - `:reconnect_attempts` - Number of reconnect attempts

  ## Examples

      {:ok, signal} = Signals.phoenix_connection_state(:my_connection, :connected)

      {:ok, signal} = Signals.phoenix_connection_state(
        :my_connection,
        :disconnected,
        reason: :closed,
        reconnect_attempts: 1
      )

  """
  @spec phoenix_connection_state(atom(), atom(), Keyword.t()) :: signal_result()
  def phoenix_connection_state(connection_name, state, opts \\ [])
      when is_atom(connection_name) and is_atom(state) do
    data =
      %{
        connection_name: connection_name,
        state: state
      }
      |> maybe_put_reason(opts)
      |> maybe_put_reconnect_attempts(opts)
      |> maybe_put_session_id(opts)

    create_and_dispatch(PhoenixConnectionState, data, opts)
  end

  @doc """
  Creates and optionally dispatches a Phoenix channel state signal.

  ## Parameters

  - `connection_name` - Name of the connection
  - `topic` - Channel topic
  - `state` - Channel state: `:joined`, `:left`, `:closed`
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/phoenix`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Associated session ID
  - `:response` - Response from join (if applicable)
  - `:reason` - Reason for state change

  ## Examples

      {:ok, signal} = Signals.phoenix_channel_state(
        :my_connection,
        "room:lobby",
        :joined
      )

      {:ok, signal} = Signals.phoenix_channel_state(
        :my_connection,
        "room:lobby",
        :left,
        reason: :user_leave
      )

  """
  @spec phoenix_channel_state(atom(), String.t(), atom(), Keyword.t()) :: signal_result()
  def phoenix_channel_state(connection_name, topic, state, opts \\ [])
      when is_atom(connection_name) and is_binary(topic) and is_atom(state) do
    data =
      %{
        connection_name: connection_name,
        topic: topic,
        state: state
      }
      |> maybe_put_response(opts)
      |> maybe_put_reason(opts)
      |> maybe_put_session_id(opts)

    create_and_dispatch(PhoenixChannelState, data, opts)
  end

  @doc """
  Creates and optionally dispatches an A2A message signal.

  ## Parameters

  - `direction` - Message direction: `:outgoing` or `:incoming`
  - `from_agent` - Source agent ID
  - `to_agent` - Target agent ID
  - `method` - JSON-RPC method invoked
  - `message` - Message content map
  - `status` - Request status: `:pending`, `:success`, `:error`
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/a2a`)
  - `:subject` - Custom subject for the signal
  - `:gateway_name` - Name of the A2A gateway
  - `:response` - Response for completed requests
  - `:session_id` - Associated session ID

  ## Examples

      {:ok, signal} = Signals.a2a_message(
        :outgoing,
        "agent:jidoka:coordinator",
        "agent:external:assistant",
        "agent.send_message",
        %{type: "text", content: "Hello!"},
        :pending
      )

      {:ok, signal} = Signals.a2a_message(
        :incoming,
        "agent:external:assistant",
        "agent:jidoka:coordinator",
        "agent.send_message",
        %{type: "text", content: "Hi back!"},
        :success,
        gateway_name: :a2a_gateway
      )

  """
  @spec a2a_message(atom(), String.t(), String.t(), String.t(), map(), atom(), Keyword.t()) :: signal_result()
  def a2a_message(direction, from_agent, to_agent, method, message, status, opts \\ [])
      when is_atom(direction) and is_binary(from_agent) and is_binary(to_agent) and
           is_binary(method) and is_map(message) and is_atom(status) do
    data =
      %{
        direction: direction,
        from_agent: from_agent,
        to_agent: to_agent,
        method: method,
        message: message,
        status: status
      }
      |> maybe_put_gateway_name(opts)
      |> maybe_put_response(opts)
      |> maybe_put_session_id(opts)

    create_and_dispatch(A2AMessage, data, opts)
  end

  @doc """
  Creates and optionally dispatches an A2A agent discovered signal.

  ## Parameters

  - `agent_id` - ID of the discovered agent
  - `agent_card` - The agent's card/map
  - `source` - Discovery source: `:directory`, `:static`, `:cache`
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/a2a`)
  - `:subject` - Custom subject for the signal
  - `:gateway_name` - Name of the A2A gateway
  - `:session_id` - Associated session ID

  ## Examples

      {:ok, signal} = Signals.a2a_agent_discovered(
        "agent:external:assistant",
        %{name: "External Assistant", type: ["Assistant"]},
        :directory
      )

  """
  @spec a2a_agent_discovered(String.t(), term(), atom(), Keyword.t()) :: signal_result()
  def a2a_agent_discovered(agent_id, agent_card, source, opts \\ [])
      when is_binary(agent_id) and is_atom(source) do
    data =
      %{
        agent_id: agent_id,
        agent_card: agent_card,
        source: source
      }
      |> maybe_put_gateway_name(opts)
      |> maybe_put_session_id(opts)

    create_and_dispatch(A2AAgentDiscovered, data, opts)
  end

  @doc """
  Creates and optionally dispatches an A2A connection state signal.

  ## Parameters

  - `gateway_name` - Name of the A2A gateway
  - `state` - Connection state: `:initializing`, `:ready`, `:closing`, `:terminated`
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/a2a`)
  - `:subject` - Custom subject for the signal
  - `:reason` - Reason for state change
  - `:session_id` - Associated session ID

  ## Examples

      {:ok, signal} = Signals.a2a_connection_state(:a2a_gateway, :ready)

      {:ok, signal} = Signals.a2a_connection_state(
        :a2a_gateway,
        :closing,
        reason: :shutdown
      )

  """
  @spec a2a_connection_state(atom(), atom(), Keyword.t()) :: signal_result()
  def a2a_connection_state(gateway_name, state, opts \\ [])
      when is_atom(gateway_name) and is_atom(state) do
    data =
      %{
        gateway_name: gateway_name,
        state: state
      }
      |> maybe_put_reason(opts)
      |> maybe_put_session_id(opts)

    create_and_dispatch(A2AConnectionState, data, opts)
  end

  # Private helper for consistent signal creation and dispatch

  defp create_and_dispatch(signal_module, data, opts) do
    # Build signal options
    signal_opts =
      []
      |> maybe_put_source(opts)
      |> maybe_put_subject(opts)

    # Create the signal
    case signal_module.new(data, signal_opts) do
      {:ok, signal} = result ->
        # Dispatch if requested (default: true)
        if Keyword.get(opts, :dispatch, true) do
          dispatch_signal(signal)
        end

        result

      {:error, _reason} = error ->
        error
    end
  end

  defp dispatch_signal(signal) do
    # Broadcast to signal-type-specific topic
    PubSub.broadcast_signal(signal.type, signal)

    # For client-facing signals, also broadcast to client events
    if client_facing_signal?(signal.type) do
      PubSub.broadcast_client_event({:signal, signal})
    end

    :ok
  end

  defp client_facing_signal?("jido_coder.client." <> _), do: true
  defp client_facing_signal?("jido_coder.chat." <> _), do: true
  defp client_facing_signal?(_), do: false

  defp maybe_put_source(signal_opts, opts) do
    case Keyword.get(opts, :source) do
      nil -> signal_opts
      source -> Keyword.put(signal_opts, :source, source)
    end
  end

  defp maybe_put_subject(signal_opts, opts) do
    case Keyword.get(opts, :subject) do
      nil -> signal_opts
      subject -> Keyword.put(signal_opts, :subject, subject)
    end
  end

  # Data field helpers for optional fields

  defp maybe_put_session_id(data, opts) do
    case Keyword.get(opts, :session_id) do
      nil -> data
      session_id -> Map.put(data, :session_id, session_id)
    end
  end

  defp maybe_put_duration_ms(data, opts) do
    case Keyword.get(opts, :duration_ms) do
      nil -> data
      duration_ms -> Map.put(data, :duration_ms, duration_ms)
    end
  end

  defp maybe_put_user_id(data, opts) do
    case Keyword.get(opts, :user_id) do
      nil -> data
      user_id -> Map.put(data, :user_id, user_id)
    end
  end

  defp maybe_put_project_root(data, opts) do
    case Keyword.get(opts, :project_root) do
      nil -> data
      project_root -> Map.put(data, :project_root, project_root)
    end
  end

  defp maybe_put_triple_count(data, opts) do
    case Keyword.get(opts, :triple_count) do
      nil -> data
      triple_count -> Map.put(data, :triple_count, triple_count)
    end
  end

  defp maybe_put_error_message(data, opts) do
    case Keyword.get(opts, :error_message) do
      nil -> data
      error_message -> Map.put(data, :error_message, error_message)
    end
  end

  defp maybe_put_reason(data, opts) do
    case Keyword.get(opts, :reason) do
      nil -> data
      reason -> Map.put(data, :reason, reason)
    end
  end

  defp maybe_put_reconnect_attempts(data, opts) do
    case Keyword.get(opts, :reconnect_attempts) do
      nil -> data
      reconnect_attempts -> Map.put(data, :reconnect_attempts, reconnect_attempts)
    end
  end

  defp maybe_put_response(data, opts) do
    case Keyword.get(opts, :response) do
      nil -> data
      response -> Map.put(data, :response, response)
    end
  end

  defp maybe_put_gateway_name(data, opts) do
    case Keyword.get(opts, :gateway_name) do
      nil -> data
      gateway_name -> Map.put(data, :gateway_name, gateway_name)
    end
  end
end
