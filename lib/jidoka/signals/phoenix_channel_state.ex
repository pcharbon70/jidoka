defmodule Jidoka.Signals.PhoenixChannelState do
  @moduledoc """
  Signal emitted when a Phoenix Channels channel state changes.

  This signal follows the CloudEvents v1.0.2 specification and is used
  to notify agents about Phoenix channel lifecycle events.

  ## Fields

  - `:connection_name` - Name of the connection (required)
  - `:topic` - Channel topic (required)
  - `:state` - Channel state: `:joined`, `:left`, `:closed` (required)
  - `:response` - Optional response from join (if applicable)
  - `:reason` - Optional reason for state change (e.g., close reason)
  - `:session_id` - Optional session ID for context

  ## Examples

      iex> {:ok, signal} = Jidoka.Signals.PhoenixChannelState.new(%{
      ...>   connection_name: :my_connection,
      ...>   topic: "room:lobby",
      ...>   state: :joined
      ...> })
      iex> signal.type
      "jido_coder.phoenix.channel.state"

      iex> {:ok, signal} = Jidoka.Signals.PhoenixChannelState.new(%{
      ...>   connection_name: :my_connection,
      ...>   topic: "room:lobby",
      ...>   state: :left,
      ...>   reason: :user_leave
      ...> })

  """

  use Jido.Signal,
    type: "jido_coder.phoenix.channel.state",
    default_source: "/jido_coder/phoenix",
    schema: [
      connection_name: [
        type: :atom,
        required: true,
        doc: "Name of the connection"
      ],
      topic: [
        type: :string,
        required: true,
        doc: "Channel topic"
      ],
      state: [
        type: :atom,
        required: true,
        doc: "Channel state: :joined, :left, :closed"
      ],
      response: [
        type: :any,
        required: false,
        doc: "Response from join (if applicable)"
      ],
      reason: [
        type: :any,
        required: false,
        doc: "Reason for state change"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Session ID for context"
      ]
    ]
end
