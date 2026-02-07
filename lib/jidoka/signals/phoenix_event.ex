defmodule Jidoka.Signals.PhoenixEvent do
  @moduledoc """
  Signal emitted when a Phoenix Channels message is received.

  This signal follows the CloudEvents v1.0.2 specification and is used
  to notify agents about incoming Phoenix Channel events.

  ## Fields

  - `:connection_name` - Name of the connection that received the event (required)
  - `:topic` - Phoenix channel topic (required)
  - `:event` - Event name (required)
  - `:payload` - Event payload map (required)
  - `:session_id` - Optional session ID for context

  ## Examples

      iex> {:ok, signal} = Jidoka.Signals.PhoenixEvent.new(%{
      ...>   connection_name: :my_connection,
      ...>   topic: "room:lobby",
      ...>   event: "new_msg",
      ...>   payload: %{body: "Hello!"}
      ...> })
      iex> signal.type
      "jido_coder.phoenix.event"

  """

  use Jido.Signal,
    type: "jido_coder.phoenix.event",
    default_source: "/jido_coder/phoenix",
    schema: [
      connection_name: [
        type: :atom,
        required: true,
        doc: "Name of the connection that received the event"
      ],
      topic: [
        type: :string,
        required: true,
        doc: "Phoenix channel topic"
      ],
      event: [
        type: :string,
        required: true,
        doc: "Event name"
      ],
      payload: [
        type: :map,
        required: true,
        doc: "Event payload data"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Session ID for context"
      ]
    ]
end
