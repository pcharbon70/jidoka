defmodule Jidoka.Signals.A2AConnectionState do
  @moduledoc """
  Signal emitted when the A2A Gateway connection state changes.

  This signal follows the CloudEvents v1.0.2 specification.

  ## Fields

  - `:gateway_name` - Name of the A2A gateway
  - `:state` - Connection state: `:initializing`, `:ready`, `:closing`, `:terminated`
  - `:reason` - Optional reason for state change
  - `:session_id` - Optional session ID for context

  ## Examples

      iex> {:ok, signal} = A2AConnectionState.new(%{
      ...>   gateway_name: :a2a_gateway,
      ...>   state: :ready
      ...> })
      iex> signal.type
      "jido_coder.a2a.connection_state"

  """

  use Jido.Signal,
    type: "jido_coder.a2a.connection_state",
    default_source: "/jido_coder/a2a",
    schema: [
      gateway_name: [
        type: :atom,
        required: true,
        doc: "Name of the A2A gateway"
      ],
      state: [
        type: :atom,
        required: true,
        doc: "Connection state: :initializing, :ready, :closing, :terminated"
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
