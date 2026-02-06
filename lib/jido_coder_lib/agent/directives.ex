defmodule JidoCoderLib.Agent.Directives do
  @moduledoc """
  Common directive helpers for JidoCoderLib agents.

  This module provides helper functions for creating commonly used directives
  in jido_coder_lib agents. Since Jido 2.0 uses directives for side effects,
  these helpers standardize directive creation across all agents.

  ## Client Broadcasts

  Create standardized client broadcast directives:

      # Global broadcast
      directive = Directives.client_broadcast("analysis_complete", %{files: 5})

      # Session-specific broadcast
      directive = Directives.session_broadcast("session-123", "chat_received", %{message: "hello"})

  ## Signal Emission

  Create signal emission directives:

      signal = Jido.Signal.new!("jido_coder.event.name", %{data: %{}})
      directive = Directives.emit_signal(signal, :pubsub)

  ## Usage in Actions

  Use these helpers in action return values:

      def run(params, context) do
        broadcast_directive = Directives.client_broadcast("status", %{state: :ready})

        {:ok, %{status: :broadcasted}, [broadcast_directive]}
      end

  """

  alias Jido.Agent.{Directive, StateOp}
  alias Jido.Signal
  alias JidoCoderLib.{Agent, PubSub, Signals}

  @type directive :: Directive.Emit.t() | StateOp.SetState.t()

  @doc """
  Creates a client broadcast directive for global client events.

  The broadcast is sent to the `jido.client.events` topic which all
  connected clients subscribe to.

  ## Parameters

  * `event_type` - The type of event (e.g., "analysis_complete", "status")
  * `payload` - The event payload data
  * `opts` - Additional options

  ## Options

  * `:timestamp` - Custom timestamp (defaults to current UTC time)
  * `:include_source` - Whether to include source in signal (default: true)

  ## Examples

      # Simple broadcast
      Directives.client_broadcast("status", %{state: :ready})

      # Broadcast with custom timestamp
      Directives.client_broadcast("analysis_complete", %{files: 5},
        timestamp: DateTime.utc_now()
      )

  """
  @spec client_broadcast(String.t(), map(), Keyword.t()) :: Directive.Emit.t()
  def client_broadcast(event_type, payload, opts \\ [])
      when is_binary(event_type) and is_map(payload) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
    include_source = Keyword.get(opts, :include_source, true)

    broadcast_payload = Map.put(payload, :timestamp, timestamp)

    broadcast_params = %{
      event_type: event_type,
      payload: broadcast_payload
    }

    broadcast_signal = Signals.BroadcastEvent.new!(broadcast_params)

    # Add source if requested
    broadcast_signal =
      if include_source do
        %Signal{broadcast_signal | source: "/jido_coder/agent"}
      else
        broadcast_signal
      end

    %Directive.Emit{
      signal: broadcast_signal,
      dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
    }
  end

  @doc """
  Creates a session-specific client broadcast directive.

  The broadcast is sent to a session-specific topic that only clients
  for that session subscribe to.

  ## Parameters

  * `session_id` - The session ID
  * `event_type` - The type of event
  * `payload` - The event payload data
  * `opts` - Additional options

  ## Options

  * `:timestamp` - Custom timestamp (defaults to current UTC time)
  * `:include_source` - Whether to include source in signal (default: true)

  ## Examples

      Directives.session_broadcast("session-123", "chat_received", %{message: "hello"})

  """
  @spec session_broadcast(String.t(), String.t(), map(), Keyword.t()) :: Directive.Emit.t()
  def session_broadcast(session_id, event_type, payload, opts \\ [])
      when is_binary(session_id) and is_binary(event_type) and is_map(payload) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
    include_source = Keyword.get(opts, :include_source, true)

    broadcast_payload = Map.put(payload, :timestamp, timestamp)

    broadcast_params = %{
      event_type: event_type,
      payload: broadcast_payload,
      session_id: session_id
    }

    broadcast_signal = Signals.BroadcastEvent.new!(broadcast_params)

    # Add source if requested
    broadcast_signal =
      if include_source do
        %Signal{broadcast_signal | source: "/jido_coder/agent"}
      else
        broadcast_signal
      end

    %Directive.Emit{
      signal: broadcast_signal,
      dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.session_topic(session_id)]}
    }
  end

  @doc """
  Creates a signal emission directive for the specified dispatch type.

  ## Parameters

  * `signal` - The signal to emit
  * `dispatch_type` - The dispatch type (:pubsub, :pid, etc.)
  * `opts` - Additional options for the dispatch type

  ## Examples

      signal = Jido.Signal.new!("jido_coder.custom.event", %{data: "value"})
      Directives.emit_signal(signal, :pubsub, topic: "custom.topic")

      # Emit directly to a process
      Directives.emit_signal(signal, :pid, target: some_pid)

  """
  @spec emit_signal(Signal.t(), atom(), Keyword.t()) :: Directive.Emit.t()
  def emit_signal(%Signal{} = signal, dispatch_type, opts \\ [])
      when is_atom(dispatch_type) and is_list(opts) do
    dispatch_config = {dispatch_type, opts}

    %Directive.Emit{
      signal: signal,
      dispatch: dispatch_config
    }
  end

  @doc """
  Creates a PubSub broadcast directive for a given topic.

  ## Parameters

  * `signal` - The signal to broadcast
  * `topic` - The PubSub topic to broadcast to
  * `opts` - Additional options (defaults to using jido_coder_pubsub)

  ## Options

  * `:target` - PubSub server name (defaults to jido_coder_pubsub)

  ## Examples

      signal = Jido.Signal.new!("custom.event", %{data: "value"})
      Directives.pubsub_broadcast(signal, "jido.custom.topic")

      # With custom target
      Directives.pubsub_broadcast(signal, "jido.custom.topic",
        target: :custom_pubsub
      )

  """
  @spec pubsub_broadcast(Signal.t(), String.t(), Keyword.t()) :: Directive.Emit.t()
  def pubsub_broadcast(%Signal{} = signal, topic, opts \\ [])
      when is_binary(topic) and is_list(opts) do
    target = Keyword.get(opts, :target, PubSub.pubsub_name())

    %Directive.Emit{
      signal: signal,
      dispatch: {:pubsub, [target: target, topic: topic]}
    }
  end

  @doc """
  Creates a state update directive.

  ## Parameters

  * `attrs` - The attributes to merge into agent state

  ## Examples

      Directives.set_state(%{status: :processing, count: 1})

  """
  @spec set_state(map()) :: StateOp.SetState.t()
  def set_state(attrs) when is_map(attrs) do
    %StateOp.SetState{attrs: attrs}
  end

  @doc """
  Creates multiple directives combined into a list.

  This helper is useful when you need to return multiple directives
  from an action.

  ## Examples

      state_directive = Directives.set_state(%{count: 1})
      broadcast_directive = Directives.client_broadcast("status", %{state: :ready})

      Directives.combine([state_directive, broadcast_directive])

  """
  @spec combine([directive()]) :: [directive()]
  def combine(directives) when is_list(directives), do: directives

  @doc """
  Creates both a state update and a client broadcast directive.

  This is a common pattern in agent actions.

  ## Parameters

  * `state_attrs` - The attributes to merge into agent state
  * `event_type` - The client event type
  * `payload` - The client event payload
  * `opts` - Additional options passed to client_broadcast/3

  ## Examples

      Directives.state_and_broadcast(
        %{status: :ready},
        "status_update",
        %{message: "Agent is ready"}
      )

  """
  @spec state_and_broadcast(map(), String.t(), map(), Keyword.t()) :: [directive()]
  def state_and_broadcast(state_attrs, event_type, payload, opts \\ []) do
    [
      set_state(state_attrs),
      client_broadcast(event_type, payload, opts)
    ]
  end

  @doc """
  Creates both a state update and a session-specific broadcast directive.

  ## Parameters

  * `state_attrs` - The attributes to merge into agent state
  * `session_id` - The session ID
  * `event_type` - The client event type
  * `payload` - The client event payload
  * `opts` - Additional options passed to session_broadcast/4

  ## Examples

      Directives.state_and_session_broadcast(
        %{active_tasks: %{"task_1" => %{status: :processing}}},
        "session-123",
        "task_started",
        %{task_id: "task_1"}
      )

  """
  @spec state_and_session_broadcast(map(), String.t(), String.t(), map(), Keyword.t()) ::
          [directive()]
  def state_and_session_broadcast(state_attrs, session_id, event_type, payload, opts \\ []) do
    [
      set_state(state_attrs),
      session_broadcast(session_id, event_type, payload, opts)
    ]
  end
end
