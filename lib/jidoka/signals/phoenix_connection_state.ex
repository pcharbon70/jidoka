defmodule Jidoka.Signals.PhoenixConnectionState do
  @moduledoc """
  Signal emitted when a Phoenix Channels connection state changes.

  This signal follows the CloudEvents v1.0.2 specification and is used
  to notify agents about Phoenix connection lifecycle events.

  ## Fields

  - `:connection_name` - Name of the connection (required)
  - `:state` - Connection state: `:connected`, `:disconnected`, `:connecting` (required)
  - `:reason` - Optional reason for state change (e.g., disconnect reason)
  - `:reconnect_attempts` - Number of reconnect attempts (if applicable)
  - `:session_id` - Optional session ID for context

  ## Examples

      iex> {:ok, signal} = Jidoka.Signals.PhoenixConnectionState.new(%{
      ...>   connection_name: :my_connection,
      ...>   state: :connected
      ...> })
      iex> signal.type
      "jido_coder.phoenix.connection.state"

      iex> {:ok, signal} = Jidoka.Signals.PhoenixConnectionState.new(%{
      ...>   connection_name: :my_connection,
      ...>   state: :disconnected,
      ...>   reason: :closed,
      ...>   reconnect_attempts: 1
      ...> })

  """

  use Jido.Signal,
    type: "jido_coder.phoenix.connection.state",
    default_source: "/jido_coder/phoenix",
    schema: [
      connection_name: [
        type: :atom,
        required: true,
        doc: "Name of the connection"
      ],
      state: [
        type: :atom,
        required: true,
        doc: "Connection state: :connected, :disconnected, :connecting"
      ],
      reason: [
        type: :any,
        required: false,
        doc: "Reason for state change (e.g., disconnect reason)"
      ],
      reconnect_attempts: [
        type: :integer,
        required: false,
        doc: "Number of reconnect attempts"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Session ID for context"
      ]
    ]
end
