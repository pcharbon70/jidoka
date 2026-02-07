defmodule Jidoka.Signals.A2AAgentDiscovered do
  @moduledoc """
  Signal emitted when a new agent is discovered via the A2A Gateway.

  This signal follows the CloudEvents v1.0.2 specification.

  ## Fields

  - `:gateway_name` - Name of the A2A gateway (optional)
  - `:agent_id` - ID of the discovered agent
  - `:agent_card` - The agent's card/map
  - `:source` - Discovery source: `:directory`, `:static`, `:cache`
  - `:session_id` - Optional session ID for context

  ## Examples

      iex> {:ok, signal} = A2AAgentDiscovered.new(%{
      ...>   agent_id: "agent:external:assistant",
      ...>   agent_card: %{name: "External Assistant", type: ["Assistant"]},
      ...>   source: :directory
      ...> })
      iex> signal.type
      "jido_coder.a2a.agent_discovered"

  """

  use Jido.Signal,
    type: "jido_coder.a2a.agent_discovered",
    default_source: "/jido_coder/a2a",
    schema: [
      gateway_name: [
        type: :atom,
        required: false,
        doc: "Name of the A2A gateway"
      ],
      agent_id: [
        type: :string,
        required: true,
        doc: "ID of the discovered agent"
      ],
      agent_card: [
        type: :any,
        required: true,
        doc: "The agent's card/map"
      ],
      source: [
        type: :atom,
        required: true,
        doc: "Discovery source: :directory, :static, :cache"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Session ID for context"
      ]
    ]
end
