defmodule Jidoka.PubSub do
  @moduledoc """
  Wrapper module for Phoenix PubSub with helper functions and topic conventions.

  This module provides a convenient interface for interacting with the
  Phoenix.PubSub system used throughout Jidoka.

  ## Topic Naming Conventions

  Topics follow a hierarchical naming pattern:

  * `"jido.agent.<agent_name>"` - Agent-specific events
  * `"jido.session.<session_id>"` - Session-specific events
  * `"jido.client.events"` - Global client events
  * `"jido.client.session.<session_id>"` - Session-specific client events
  * `"jido.signal.<signal_type>"` - System signals
  * `"jido.protocol.<protocol>"` - Protocol events

  ## Examples

  ### Subscribe to a topic

      iex> Jidoka.PubSub.subscribe(self(), "jido.agent.coordinator")
      :ok

  ### Broadcast to a topic

      iex> Jidoka.PubSub.broadcast("jido.agent.coordinator", {:status, :ready})
      :ok

      # Or with from option
      iex> Jidoka.PubSub.broadcast("jido.agent.coordinator", {:status, :ready}, from: self())
      :ok

  ### Subscribe to all client events

      iex> Jidoka.PubSub.subscribe_client_events(self())
      :ok

  ### Broadcast to a session

      iex> Jidoka.PubSub.broadcast_session("session-123", {:message, "hello"})
      :ok

  """

  @pubsub_name :jido_coder_pubsub

  @type topic :: String.t()
  @type message :: term()
  @type subscription_result :: :ok | {:ok, term()}
  @type broadcast_result :: :ok

  @doc """
  Returns the PubSub process name.
  """
  @spec pubsub_name() :: atom()
  def pubsub_name, do: @pubsub_name

  # Topic prefixes

  @doc """
  Topic prefix for agent-specific events.
  """
  @spec agent_prefix() :: String.t()
  def agent_prefix, do: "jido.agent"

  @doc """
  Topic prefix for session-specific events.
  """
  @spec session_prefix() :: String.t()
  def session_prefix, do: "jido.session"

  @doc """
  Topic for global client events.
  """
  @spec client_events_topic() :: String.t()
  def client_events_topic, do: "jido.client.events"

  @doc """
  Topic prefix for session-specific client events.
  """
  @spec client_session_prefix() :: String.t()
  def client_session_prefix, do: "jido.client.session"

  @doc """
  Topic prefix for system signals.
  """
  @spec signal_prefix() :: String.t()
  def signal_prefix, do: "jido.signal"

  @doc """
  Topic prefix for protocol events.
  """
  @spec protocol_prefix() :: String.t()
  def protocol_prefix, do: "jido.protocol"

  # Topic builders

  @doc """
  Builds an agent topic for the given agent name.
  """
  @spec agent_topic(String.t()) :: topic()
  def agent_topic(agent_name), do: "#{agent_prefix()}.#{agent_name}"

  @doc """
  Builds a session topic for the given session ID.
  """
  @spec session_topic(String.t()) :: topic()
  def session_topic(session_id), do: "#{session_prefix()}.#{session_id}"

  @doc """
  Builds a client session topic for the given session ID.
  """
  @spec client_session_topic(String.t()) :: topic()
  def client_session_topic(session_id), do: "#{client_session_prefix()}.#{session_id}"

  @doc """
  Builds a signal topic for the given signal type.
  """
  @spec signal_topic(String.t()) :: topic()
  def signal_topic(signal_type), do: "#{signal_prefix()}.#{signal_type}"

  @doc """
  Builds a protocol topic for the given protocol.
  """
  @spec protocol_topic(String.t()) :: topic()
  def protocol_topic(protocol), do: "#{protocol_prefix()}.#{protocol}"

  # Subscribe functions

  @doc """
  Subscribes to a topic.

  When given a PID as first argument, subscribes that process.
  When given a topic as first argument, subscribes the current process.

  ## Options

  * `:metadata` - Optional metadata to attach to the subscription

  ## Examples

  Subscribe the current process:

      iex> Jidoka.PubSub.subscribe("jido.agent.coordinator")
      :ok

  Subscribe a specific process:

      iex> Jidoka.PubSub.subscribe(self(), "jido.agent.coordinator")
      :ok

  Subscribe with options:

      iex> Jidoka.PubSub.subscribe("jido.agent.coordinator", metadata: %{position: 1})
      {:ok, _}

  """
  @spec subscribe(topic()) :: subscription_result()
  def subscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.subscribe(@pubsub_name, topic, [])
  end

  @spec subscribe(topic(), Keyword.t()) :: subscription_result()
  def subscribe(topic, opts) when is_list(opts) and is_binary(topic) do
    Phoenix.PubSub.subscribe(@pubsub_name, topic, opts)
  end

  @spec subscribe(pid(), topic()) :: subscription_result()
  def subscribe(pid, topic) when is_pid(pid) and is_binary(topic) do
    Phoenix.PubSub.subscribe(@pubsub_name, topic, pid: pid)
  end

  @spec subscribe(pid(), topic(), Keyword.t()) :: subscription_result()
  def subscribe(pid, topic, opts) when is_pid(pid) and is_binary(topic) do
    Phoenix.PubSub.subscribe(@pubsub_name, topic, Keyword.put(opts, :pid, pid))
  end

  @doc """
  Subscribes the current process to global client events.
  """
  @spec subscribe_client_events(Keyword.t()) :: subscription_result()
  def subscribe_client_events(opts \\ []) do
    subscribe(client_events_topic(), opts)
  end

  @doc """
  Subscribes the current process to session-specific client events.
  """
  @spec subscribe_client_session(String.t()) :: subscription_result()
  def subscribe_client_session(session_id) when is_binary(session_id) do
    subscribe(client_session_topic(session_id))
  end

  @doc """
  Subscribes the given process to session-specific client events.
  """
  @spec subscribe_client_session(String.t(), pid()) :: subscription_result()
  def subscribe_client_session(session_id, pid) when is_binary(session_id) and is_pid(pid) do
    subscribe(pid, client_session_topic(session_id))
  end

  @doc """
  Subscribes the current process to agent events.
  """
  @spec subscribe_agent(String.t()) :: subscription_result()
  def subscribe_agent(agent_name) when is_binary(agent_name) do
    subscribe(agent_topic(agent_name))
  end

  @doc """
  Subscribes the given process to agent events.
  """
  @spec subscribe_agent(String.t(), pid()) :: subscription_result()
  def subscribe_agent(agent_name, pid) when is_binary(agent_name) and is_pid(pid) do
    subscribe(pid, agent_topic(agent_name))
  end

  # Unsubscribe functions

  @doc """
  Unsubscribes the current process from a topic.
  """
  @spec unsubscribe(topic()) :: :ok
  def unsubscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub_name, topic)
  end

  # Broadcast functions

  @doc """
  Broadcasts a message to a topic.

  ## Options

  * `:from` - The process broadcasting the message (defaults to self())
  * `:metadata` - Optional metadata to attach to the broadcast

  ## Examples

      iex> Jidoka.PubSub.broadcast("jido.agent.coordinator", {:status, :ready})
      :ok

      iex> Jidoka.PubSub.broadcast("jido.agent.coordinator", {:status, :ready}, from: self())
      :ok

  """
  @spec broadcast(topic(), message(), Keyword.t()) :: broadcast_result()
  def broadcast(topic, message, opts \\ []) when is_binary(topic) do
    from = Keyword.get(opts, :from, self())
    Phoenix.PubSub.broadcast(@pubsub_name, topic, {from, message})
  end

  @doc """
  Broadcasts a message to global client events.
  """
  @spec broadcast_client_event(message(), Keyword.t()) :: broadcast_result()
  def broadcast_client_event(message, opts \\ []) do
    broadcast(client_events_topic(), message, opts)
  end

  @doc """
  Broadcasts a message to a session's client events.
  """
  @spec broadcast_client_session(String.t(), message(), Keyword.t()) :: broadcast_result()
  def broadcast_client_session(session_id, message, opts \\ []) do
    broadcast(client_session_topic(session_id), message, opts)
  end

  @doc """
  Broadcasts a message to an agent's topic.
  """
  @spec broadcast_agent(String.t(), message(), Keyword.t()) :: broadcast_result()
  def broadcast_agent(agent_name, message, opts \\ []) do
    broadcast(agent_topic(agent_name), message, opts)
  end

  @doc """
  Broadcasts a message to a session topic.
  """
  @spec broadcast_session(String.t(), message(), Keyword.t()) :: broadcast_result()
  def broadcast_session(session_id, message, opts \\ []) do
    broadcast(session_topic(session_id), message, opts)
  end

  @doc """
  Broadcasts a message to a signal topic.
  """
  @spec broadcast_signal(String.t(), message(), Keyword.t()) :: broadcast_result()
  def broadcast_signal(signal_type, message, opts \\ []) do
    broadcast(signal_topic(signal_type), message, opts)
  end
end
