defmodule Jidoka.Signals.BroadcastEvent do
  @moduledoc """
  Signal for broadcasting events to connected clients.

  This signal follows the CloudEvents v1.0.2 specification and is used
  by the Coordinator agent to broadcast events to all connected clients
  via the client events PubSub topic.

  ## Fields

  - `:event_type` - Type of client event (e.g., "llm_stream_chunk", "agent_status") (required)
  - `:payload` - Event payload data (required)
  - `:session_id` - Optional session ID for targeted broadcasts

  ## Examples

      iex> {:ok, signal} = Jidoka.Signals.BroadcastEvent.new(%{
      ...>   event_type: "llm_stream_chunk",
      ...>   payload: %{content: "Hello"}
      ...> })
      iex> signal.type
      "jido_coder.client.broadcast"

      iex> {:ok, signal} = Jidoka.Signals.BroadcastEvent.new(%{
      ...>   event_type: "agent_status",
      ...>   payload: %{status: :ready},
      ...>   session_id: "session-123"
      ...> })

  """

  use Jido.Signal,
    type: "jido_coder.client.broadcast",
    default_source: "/jido_coder/coordinator",
    schema: [
      event_type: [
        type: :string,
        required: true,
        doc: "Event type identifier (e.g., llm_stream_chunk, agent_status)"
      ],
      payload: [
        type: :map,
        required: true,
        doc: "Event payload data"
      ],
      session_id: [
        type: :string,
        required: false,
        doc: "Target session ID for targeted broadcasts"
      ]
    ]
end
