defmodule Jidoka.Signals.A2AMessage do
  @moduledoc """
  Signal emitted when an A2A message is sent or received.

  This signal follows the CloudEvents v1.0.2 specification and is used
  to track communication between agents across frameworks.

  ## Fields

  - `:gateway_name` - Name of the A2A gateway (optional)
  - `:direction` - `:outgoing` or `:incoming`
  - `:from_agent` - Source agent ID
  - `:to_agent` - Target agent ID
  - `:method` - JSON-RPC method invoked
  - `:message` - Message content map
  - `:response` - Response (for completed requests, optional)
  - `:status` - Request status: `:pending`, `:success`, `:error`
  - `:session_id` - Optional session ID for context

  ## Examples

      iex> {:ok, signal} = A2AMessage.new(%{
      ...>   direction: :outgoing,
      ...>   from_agent: "agent:jidoka:coordinator",
      ...>   to_agent: "agent:external:assistant",
      ...>   method: "agent.send_message",
      ...>   message: %{type: "text", content: "Hello!"},
      ...>   status: :pending
      ...> })
      iex> signal.type
      "jido_coder.a2a.message"

  """

  use Jido.Signal,
    type: "jido_coder.a2a.message",
    default_source: "/jido_coder/a2a",
    schema: [
      gateway_name: [
        type: :atom,
        required: false,
        doc: "Name of the A2A gateway"
      ],
      direction: [
        type: :atom,
        required: true,
        doc: "Message direction: :outgoing or :incoming"
      ],
      from_agent: [
        type: :string,
        required: true,
        doc: "Source agent ID"
      ],
      to_agent: [
        type: :string,
        required: true,
        doc: "Target agent ID"
      ],
      method: [
        type: :string,
        required: true,
        doc: "JSON-RPC method invoked"
      ],
      message: [
        type: :map,
        required: true,
        doc: "Message content"
      ],
      response: [
        type: :any,
        required: false,
        doc: "Response (for completed requests)"
      ],
      status: [
        type: :atom,
        required: true,
        doc: "Request status: :pending, :success, :error"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Session ID for context"
      ]
    ]
end
