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

  @type status :: :disconnected | :connecting | :connected | :disconnecting

  defstruct [
    :connection_name,
    :joined_channels,
    :pending_pushes,
    :status,
    :reconnect_attempts,
    :max_reconnect_attempts,
    :uri,
    :headers,
    :params,
    :auto_join_channels
  ]

  # Public API will be implemented in Step 2
end
