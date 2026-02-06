defmodule Jidoka.Signals.ChatRequest do
  @moduledoc """
  Signal representing a user chat request.

  This signal follows the CloudEvents v1.0.2 specification and is used
  to represent user messages sent to the agent system for processing.

  ## Fields

  - `:message` - User message content (required)
  - `:session_id` - Associated session ID (defaults to empty string)
  - `:user_id` - Optional user identifier
  - `:context` - Additional conversation context map

  ## Examples

      iex> {:ok, signal} = Jidoka.Signals.ChatRequest.new(%{
      ...>   message: "Help me debug this function"
      ...> })
      iex> signal.type
      "jido_coder.chat.request"

      iex> {:ok, signal} = Jidoka.Signals.ChatRequest.new(%{
      ...>   message: "Explain this code",
      ...>   session_id: "session-123",
      ...>   user_id: "user-456",
      ...>   context: %{language: "elixir"}
      ...> })

  """

  use Jido.Signal,
    type: "jido_coder.chat.request",
    default_source: "/jido_coder/client",
    schema: [
      message: [
        type: :string,
        required: true,
        doc: "User message content"
      ],
      session_id: [
        type: :string,
        required: false,
        default: "",
        doc: "Associated session ID"
      ],
      user_id: [
        type: :string,
        required: false,
        doc: "User identifier"
      ],
      context: [
        type: :map,
        default: %{},
        doc: "Additional conversation context"
      ]
    ]
end
