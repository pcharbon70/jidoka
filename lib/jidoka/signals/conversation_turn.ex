defmodule Jidoka.Signals.ConversationTurn do
  @moduledoc """
  Signals for conversation logging events.

  These signals follow the CloudEvents v1.0.2 specification and are used
  to track conversation logging events throughout the system.

  ## Signal Types

  - `LogPrompt` - Signal to log a user prompt
  - `LogAnswer` - Signal to log an assistant answer
  - `LogToolInvocation` - Signal to log a tool invocation
  - `LogToolResult` - Signal to log a tool result

  ## Fields (LogPrompt)

  - `:conversation_iri` - IRI of the conversation (required)
  - `:turn_index` - Turn index within the conversation (required)
  - `:prompt_text` - Text content of the prompt (required)
  - `:session_id` - Associated session ID (required)
  - `:timestamp` - When the prompt was created (optional)

  ## Fields (LogAnswer)

  - `:conversation_iri` - IRI of the conversation (required)
  - `:turn_index` - Turn index within the conversation (required)
  - `:answer_text` - Text content of the answer (required)
  - `:session_id` - Associated session ID (required)
  - `:timestamp` - When the answer was created (optional)

  ## Fields (LogToolInvocation)

  - `:conversation_iri` - IRI of the conversation (required)
  - `:turn_index` - Turn index within the conversation (required)
  - `:tool_index` - Index of the tool within this turn (required)
  - `:tool_name` - Name of the tool being invoked (required)
  - `:parameters` - Tool parameters (required)
  - `:session_id` - Associated session ID (required)
  - `:timestamp` - When the tool was invoked (optional)

  ## Fields (LogToolResult)

  - `:conversation_iri` - IRI of the conversation (required)
  - `:turn_index` - Turn index within the conversation (required)
  - `:tool_index` - Index of the tool within this turn (required)
  - `:result_data` - Result data from the tool (required)
  - `:session_id` - Associated session ID (required)
  - `:timestamp` - When the result was received (optional)

  ## Examples

      iex> {:ok, signal} = Jidoka.Signals.ConversationTurn.LogPrompt.new(%{
      ...>   conversation_iri: "https://jido.ai/conversations#session_123",
      ...>   turn_index: 0,
      ...>   prompt_text: "What files use Jido.Agent?",
      ...>   session_id: "session_123"
      ...> })

      iex> {:ok, signal} = Jidoka.Signals.ConversationTurn.LogAnswer.new(%{
      ...>   conversation_iri: "https://jido.ai/conversations#session_123",
      ...>   turn_index: 0,
      ...>   answer_text: "The Jido.Agent module is used in...",
      ...>   session_id: "session_123"
      ...> })

  """

  # LogPrompt Signal
  defmodule LogPrompt do
    @moduledoc """
    Signal representing a user prompt to be logged.
    """

    use Jido.Signal,
      type: "jido_coder.conversation.log_prompt",
      default_source: "/jido_coder/conversation",
      schema: [
        conversation_iri: [
          type: :string,
          required: true,
          doc: "IRI of the conversation"
        ],
        turn_index: [
          type: :integer,
          required: true,
          doc: "Turn index within the conversation"
        ],
        prompt_text: [
          type: :string,
          required: true,
          doc: "Text content of the prompt"
        ],
        session_id: [
          type: :string,
          required: true,
          doc: "Associated session ID"
        ],
        timestamp: [
          type: :string,
          required: false,
          doc: "ISO8601 timestamp"
        ]
      ]
  end

  # LogAnswer Signal
  defmodule LogAnswer do
    @moduledoc """
    Signal representing an assistant answer to be logged.
    """

    use Jido.Signal,
      type: "jido_coder.conversation.log_answer",
      default_source: "/jido_coder/conversation",
      schema: [
        conversation_iri: [
          type: :string,
          required: true,
          doc: "IRI of the conversation"
        ],
        turn_index: [
          type: :integer,
          required: true,
          doc: "Turn index within the conversation"
        ],
        answer_text: [
          type: :string,
          required: true,
          doc: "Text content of the answer"
        ],
        session_id: [
          type: :string,
          required: true,
          doc: "Associated session ID"
        ],
        timestamp: [
          type: :string,
          required: false,
          doc: "ISO8601 timestamp"
        ]
      ]
  end

  # LogToolInvocation Signal
  defmodule LogToolInvocation do
    @moduledoc """
    Signal representing a tool invocation to be logged.
    """

    use Jido.Signal,
      type: "jido_coder.conversation.log_tool_invocation",
      default_source: "/jido_coder/conversation",
      schema: [
        conversation_iri: [
          type: :string,
          required: true,
          doc: "IRI of the conversation"
        ],
        turn_index: [
          type: :integer,
          required: true,
          doc: "Turn index within the conversation"
        ],
        tool_index: [
          type: :integer,
          required: true,
          doc: "Index of the tool within this turn"
        ],
        tool_name: [
          type: :string,
          required: true,
          doc: "Name of the tool being invoked"
        ],
        parameters: [
          type: :map,
          required: true,
          doc: "Tool parameters"
        ],
        session_id: [
          type: :string,
          required: true,
          doc: "Associated session ID"
        ],
        timestamp: [
          type: :string,
          required: false,
          doc: "ISO8601 timestamp"
        ]
      ]
  end

  # LogToolResult Signal
  defmodule LogToolResult do
    @moduledoc """
    Signal representing a tool result to be logged.
    """

    use Jido.Signal,
      type: "jido_coder.conversation.log_tool_result",
      default_source: "/jido_coder/conversation",
      schema: [
        conversation_iri: [
          type: :string,
          required: true,
          doc: "IRI of the conversation"
        ],
        turn_index: [
          type: :integer,
          required: true,
          doc: "Turn index within the conversation"
        ],
        tool_index: [
          type: :integer,
          required: true,
          doc: "Index of the tool within this turn"
        ],
        result_data: [
          type: :map,
          required: true,
          doc: "Result data from the tool"
        ],
        session_id: [
          type: :string,
          required: true,
          doc: "Associated session ID"
        ],
        timestamp: [
          type: :string,
          required: false,
          doc: "ISO8601 timestamp"
        ]
      ]
  end
end
