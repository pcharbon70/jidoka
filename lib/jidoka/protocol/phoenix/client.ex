defmodule Jidoka.Protocol.Phoenix.Client do
  @moduledoc """
  Phoenix Channels client using Slipstream for WebSocket connections.

  Follows the same pattern as Jidoka.Protocol.MCP.Client for consistency.

  ## Configuration

  The client accepts the following options on `start_link/1`:

  * `:name` - Required. Atom name for process registration.
  * `:uri` - Required. WebSocket endpoint (e.g., `"ws://localhost:4000/socket/websocket"`).
  * `:headers` - Optional. List of `{header_name, value}` tuples for connection headers.
  * `:params` - Optional. Map of connection parameters.
  * `:auto_join_channels` - Optional. List of `{topic, params}` tuples to join on connection.
  * `:max_retries` - Optional. Maximum reconnection attempts (default: 10).

  ## Example

      {:ok, pid} = Jidoka.Protocol.Phoenix.Client.start_link(
        name: :my_connection,
        uri: "ws://localhost:4000/socket/websocket",
        headers: [{"X-API-Key", "secret"}],
        params: %{token: "auth-token"},
        auto_join_channels: [{"room:lobby", %{}}]
      )

  ## Signal Types

  Incoming Phoenix messages are converted to Jidoka signals:

  * `"phoenix.connection.connected"` - Connection established
  * `"phoenix.connection.disconnected"` - Connection lost
  * `"phoenix.channel.joined"` - Channel joined successfully
  * `"phoenix.channel.left"` - Channel left
  * `"phoenix.<connection_name>.<topic>.<event>"` - Incoming messages

  """

  use Slipstream, restart: :temporary
  require Logger
  alias Jidoka.Signals

  @type status :: :disconnected | :connecting | :connected | :disconnecting

  defstruct [
    :connection_name,
    joined_channels: %{},
    pending_pushes: %{},
    status: :disconnected,
    reconnect_attempts: 0,
    max_reconnect_attempts: 10,
    uri: nil,
    headers: [],
    params: %{},
    auto_join_channels: []
  ]

  # ========================================================================
  # Client API
  # ========================================================================

  @doc """
  Start a Phoenix Channels connection.

  ## Options

  * `:name` - Required. Atom name for process registration.
  * `:uri` - Required. WebSocket endpoint (e.g., `"ws://localhost:4000/socket/websocket"`).
  * `:headers` - Optional. List of `{header_name, value}` tuples for connection headers.
  * `:params` - Optional. Map of connection parameters.
  * `:auto_join_channels` - Optional. List of `{topic, params}` tuples to join on connection.
  * `:max_retries` - Optional. Maximum reconnection attempts (default: 10).

  ## Examples

      {:ok, pid} = Jidoka.Protocol.Phoenix.Client.start_link(
        name: :my_connection,
        uri: "ws://localhost:4000/socket/websocket"
      )

      {:ok, pid} = Jidoka.Protocol.Phoenix.Client.start_link(
        name: :my_connection,
        uri: "wss://example.com/socket/websocket",
        headers: [{"X-API-Key", "secret"}],
        params: %{token: "auth-token"},
        auto_join_channels: [{"room:lobby", %{}}]
      )
  """
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    Slipstream.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Join a Phoenix channel.

  ## Parameters

  * `client` - PID or name of the connection process.
  * `topic` - Channel topic (e.g., `"room:lobby"`, `"user:123"`).
  * `params` - Optional map of parameters to send with the join.

  ## Returns

  * `{:ok, ref}` - Successfully requested to join, `ref` is for tracking the reply.
  * `{:error, reason}` - Failed to join (e.g., not connected, invalid topic).

  ## Examples

      {:ok, ref} = Jidoka.Protocol.Phoenix.Client.join_channel(
        :my_connection,
        "room:lobby",
        %{user_id: "123"}
      )
  """
  def join_channel(client, topic, params \\ %{}) do
    GenServer.call(client, {:join_channel, topic, params})
  end

  @doc """
  Leave a Phoenix channel.

  ## Parameters

  * `client` - PID or name of the connection process.
  * `topic` - Channel topic to leave.

  ## Returns

  * `:ok` - Successfully requested to leave.
  * `{:error, reason}` - Failed to leave.

  ## Examples

      :ok = Jidoka.Protocol.Phoenix.Client.leave_channel(
        :my_connection,
        "room:lobby"
      )
  """
  def leave_channel(client, topic) do
    GenServer.call(client, {:leave_channel, topic})
  end

  @doc """
  Push an event to a Phoenix channel.

  ## Parameters

  * `client` - PID or name of the connection process.
  * `topic` - Channel topic to push to.
  * `event` - Event name (e.g., `"new_msg"`).
  * `payload` - Event payload map.

  ## Returns

  * `{:ok, ref}` - Successfully pushed, `ref` is for tracking the reply.
  * `{:error, reason}` - Failed to push (e.g., channel not joined).

  ## Examples

      {:ok, ref} = Jidoka.Protocol.Phoenix.Client.push_event(
        :my_connection,
        "room:lobby",
        "new_msg",
        %{body: "Hello!", from: "user123"}
      )
  """
  def push_event(client, topic, event, payload) do
    GenServer.call(client, {:push_event, topic, event, payload})
  end

  @doc """
  Get the current connection status.

  ## Returns

  * `:disconnected` - Not connected
  * `:connecting` - Connection in progress
  * `:connected` - Connected and ready
  * `:disconnecting` - Disconnection in progress

  ## Examples

      status = Jidoka.Protocol.Phoenix.Client.status(:my_connection)
      # => :connected
  """
  def status(client) do
    GenServer.call(client, :status)
  end

  @doc """
  List all joined channels.

  ## Returns

  * List of channel topics (strings).

  ## Examples

      channels = Jidoka.Protocol.Phoenix.Client.list_channels(:my_connection)
      # => ["room:lobby", "user:123"]
  """
  def list_channels(client) do
    GenServer.call(client, :list_channels)
  end

  # ========================================================================
  # Slipstream Callbacks
  # ========================================================================

  @impl true
  def init(opts) do
    # Extract configuration
    name = Keyword.fetch!(opts, :name)
    uri = Keyword.fetch!(opts, :uri)
    headers = Keyword.get(opts, :headers, [])
    params = Keyword.get(opts, :params, %{})
    auto_join_channels = Keyword.get(opts, :auto_join_channels, [])
    max_retries = Keyword.get(opts, :max_retries, 10)

    # Build Slipstream configuration
    config = [
      uri: uri,
      headers: headers,
      params: params,
      # Exponential backoff for reconnection
      reconnect_after_msec: [100, 500, 1_000, 2_000, 5_000, 10_000, 30_000],
      # Exponential backoff for rejoining
      rejoin_after_msec: [100, 500, 1_000, 2_000, 5_000, 10_000],
      # Heartbeat every 30 seconds (Phoenix closes connections after 60s of inactivity)
      heartbeat_interval_msec: 30_000,
      # Custom assigns for our client state
      assigns: %{
        connection_name: name,
        status: :connecting,
        reconnect_attempts: 0,
        max_reconnect_attempts: max_retries,
        channels: %{},
        pending_pushes: %{},
        auto_join_channels: auto_join_channels
      }
    ]

    # Start connection
    case Slipstream.connect(config) do
      {:ok, socket} ->
        Logger.debug("Phoenix connection initiated: #{name} -> #{uri}")
        {:ok, socket}

      {:error, reason} ->
        Logger.error("Failed to initiate Phoenix connection #{name}: #{inspect(reason)}")
        # Return :ignore to not crash the supervisor
        :ignore
    end
  end

  @impl true
  def handle_connect(socket) do
    connection_name = socket.assigns.connection_name
    Logger.info("Phoenix connection established: #{connection_name}")

    # Dispatch connection state signal
    _ = Signals.phoenix_connection_state(connection_name, :connected, dispatch: true)

    # Update socket assigns with connection state
    socket = assign(socket, :status, :connected)
    socket = assign(socket, :reconnect_attempts, 0)

    # Auto-join configured channels
    socket = Enum.reduce(socket.assigns.auto_join_channels || [], socket, fn
      {topic, params}, acc_socket ->
        join(acc_socket, topic, params)
    end)

    {:ok, socket}
  end

  @impl true
  def handle_join(topic, _response, socket) do
    connection_name = socket.assigns.connection_name
    Logger.info("Joined Phoenix channel: #{connection_name} -> #{topic}")

    # Dispatch channel state signal
    _ = Signals.phoenix_channel_state(connection_name, topic, :joined, dispatch: true)

    # Track joined channel
    channels = Map.put(
      socket.assigns.channels || %{},
      topic,
      %{
        params: %{},
        joined_at: DateTime.utc_now(),
        ref: nil
      }
    )
    socket = assign(socket, :channels, channels)

    {:ok, socket}
  end

  @impl true
  def handle_topic_close(topic, reason, socket) do
    connection_name = socket.assigns.connection_name
    Logger.debug("Phoenix channel closed: #{connection_name} -> #{topic}: #{inspect(reason)}")

    # Dispatch channel state signal
    _ = Signals.phoenix_channel_state(
      connection_name,
      topic,
      :closed,
      reason: reason,
      dispatch: true
    )

    # Remove from tracked channels
    channels = Map.delete(socket.assigns.channels || %{}, topic)
    socket = assign(socket, :channels, channels)

    {:ok, socket}
  end

  @impl true
  def handle_message(topic, event, payload, socket) do
    connection_name = socket.assigns.connection_name
    Logger.debug("Phoenix message: #{connection_name} -> #{topic} | #{event}")

    # Dispatch Phoenix event signal
    _ = Signals.phoenix_event(
      connection_name,
      topic,
      event,
      payload,
      dispatch: true
    )

    {:ok, socket}
  end

  @impl true
  def handle_reply(ref, reply, socket) do
    Logger.debug("Phoenix reply: #{socket.assigns.connection_name} -> ref: #{inspect(reply)}")

    # Clean up from pending pushes if this ref matches
    pending = Map.delete(socket.assigns.pending_pushes || %{}, ref)
    socket = assign(socket, :pending_pushes, pending)

    {:ok, socket}
  end

  @impl true
  def handle_disconnect(reason, socket) do
    connection_name = socket.assigns.connection_name
    Logger.warning("Phoenix connection disconnected: #{connection_name} -> #{inspect(reason)}")

    # Dispatch connection state signal
    _ = Signals.phoenix_connection_state(
      connection_name,
      :disconnected,
      reason: reason,
      dispatch: true
    )

    # Update status
    socket = assign(socket, :status, :disconnected)

    # Track reconnect attempts
    attempts = (socket.assigns.reconnect_attempts || 0) + 1
    socket = assign(socket, :reconnect_attempts, attempts)

    max_attempts = socket.assigns.max_reconnect_attempts

    if attempts <= max_attempts do
      Logger.info("Attempting to reconnect Phoenix connection #{connection_name} (attempt #{attempts}/#{max_attempts})")

      # Dispatch reconnecting signal
      _ = Signals.phoenix_connection_state(
        connection_name,
        :connecting,
        reconnect_attempts: attempts,
        dispatch: true
      )

      # Attempt reconnection
      case Slipstream.reconnect(socket) do
        {:ok, new_socket} ->
          {:ok, new_socket}

        {:error, _reason} ->
          # Stop and let supervisor handle restart
          {:stop, :reconnect_failed, socket}
      end
    else
      Logger.error("Max reconnection attempts reached for Phoenix connection #{connection_name}")
      {:stop, :max_retries_reached, socket}
    end
  end

  # ========================================================================
  # GenServer Callbacks
  # ========================================================================

  @impl true
  def handle_call({:join_channel, topic, params}, _from, socket) do
    if socket.assigns.status != :connected do
      {:reply, {:error, :not_connected}, socket}
    else
      new_socket = join(socket, topic, params)
      {:reply, {:ok, :joining}, new_socket}
    end
  end

  @impl true
  def handle_call({:leave_channel, topic}, _from, socket) do
    if socket.assigns.status != :connected do
      {:reply, {:error, :not_connected}, socket}
    else
      new_socket = leave(socket, topic)
      # Remove from tracked channels
      channels = Map.delete(new_socket.assigns.channels || %{}, topic)
      new_socket = assign(new_socket, :channels, channels)
      {:reply, :ok, new_socket}
    end
  end

  @impl true
  def handle_call({:push_event, topic, event, payload}, _from, socket) do
    if socket.assigns.status != :connected do
      {:reply, {:error, :not_connected}, socket}
    else
      # Check if channel is joined
      unless Map.has_key?(socket.assigns.channels || %{}, topic) do
        {:reply, {:error, :channel_not_joined}, socket}
      else
        case Slipstream.push(socket, topic, event, payload) do
          {:ok, ref, new_socket} ->
            # Track pending push
            pending = Map.put(new_socket.assigns.pending_pushes || %{}, ref, {topic, event, payload})
            new_socket = assign(new_socket, :pending_pushes, pending)
            {:reply, {:ok, ref}, new_socket}

          {:error, reason, new_socket} ->
            {:reply, {:error, reason}, new_socket}
        end
      end
    end
  end

  @impl true
  def handle_call(:status, _from, socket) do
    {:reply, socket.assigns.status, socket}
  end

  @impl true
  def handle_call(:list_channels, _from, socket) do
    channels = Map.keys(socket.assigns.channels || %{})
    {:reply, channels, socket}
  end
end
