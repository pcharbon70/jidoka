defmodule Jidoka.Agents.Coordinator.Actions.LogConversationTurn do
  @moduledoc """
  Action to log conversation turns to the knowledge graph.

  This action handles conversation logging signals and persists them
  to the `:conversation_history` named graph using `Conversation.Logger`.

  ## Signal Types Handled

  - `jido_coder.conversation.log_prompt` - Log user prompts
  - `jido_coder.conversation.log_answer` - Log assistant answers
  - `jido_coder.conversation.log_tool_invocation` - Log tool invocations
  - `jido_coder.conversation.log_tool_result` - Log tool results

  ## Error Handling

  Logging failures do not break the chat flow - errors are logged
  but the action returns success to allow processing to continue.

  ## Schema

  All logging signals share common fields:

  * `:conversation_iri` - IRI of the conversation (required)
  * `:turn_index` - Turn index within the conversation (required)
  * `:session_id` - Associated session ID (required)

  Type-specific fields:

  * `LogPrompt`: `:prompt_text` - Text content of the prompt (required)
  * `LogAnswer`: `:answer_text` - Text content of the answer (required)
  * `LogToolInvocation`: `:tool_index`, `:tool_name`, `:parameters` (required)
  * `LogToolResult`: `:tool_index`, `:result_data` (required)

  """

  use Jido.Action,
    name: "log_conversation_turn",
    description: "Log conversation turns to the knowledge graph",
    category: "conversation",
    tags: ["logging", "conversation", "knowledge_graph"],
    vsn: "1.0.0",
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
      session_id: [
        type: :string,
        required: true,
        doc: "Associated session ID"
      ],
      # LogPrompt fields
      prompt_text: [
        type: :string,
        required: false,
        doc: "Text content of the prompt"
      ],
      # LogAnswer fields
      answer_text: [
        type: :string,
        required: false,
        doc: "Text content of the answer"
      ],
      # LogToolInvocation fields
      tool_index: [
        type: :integer,
        required: false,
        doc: "Index of the tool within this turn"
      ],
      tool_name: [
        type: :string,
        required: false,
        doc: "Name of the tool being invoked"
      ],
      parameters: [
        type: :map,
        required: false,
        doc: "Tool parameters"
      ],
      # LogToolResult fields
      result_data: [
        type: :map,
        required: false,
        doc: "Result data from the tool"
      ]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    conversation_iri = params[:conversation_iri]
    turn_index = params[:turn_index]
    session_id = params[:session_id]

    cond do
      # Log prompt
      prompt_text = params[:prompt_text] ->
        log_prompt(conversation_iri, turn_index, prompt_text, session_id)

      # Log answer
      answer_text = params[:answer_text] ->
        log_answer(conversation_iri, turn_index, answer_text, session_id)

      # Log tool invocation
      tool_name = params[:tool_name] ->
        tool_index = params[:tool_index]
        parameters = params[:parameters]

        log_tool_invocation(
          conversation_iri,
          turn_index,
          tool_index,
          tool_name,
          parameters,
          session_id
        )

      # Log tool result
      result_data = params[:result_data] ->
        tool_index = params[:tool_index]

        log_tool_result(conversation_iri, turn_index, tool_index, result_data, session_id)

      # Unknown signal type
      true ->
        Logger.warning("Unknown conversation logging signal for session #{session_id}")
        {:ok, %{status: :unknown_signal_type}}
    end
  end

  # Private helpers

  defp log_prompt(conversation_iri, turn_index, prompt_text, session_id) do
    case Jidoka.Conversation.Logger.log_prompt(
           conversation_iri,
           turn_index,
           prompt_text
         ) do
      {:ok, _prompt_iri} ->
        {:ok, %{status: :logged, type: :prompt, session_id: session_id, turn_index: turn_index}}

      {:error, reason} ->
        # Log error but don't fail - user preference for silent failure
        Logger.warning(
          "Failed to log prompt for session #{session_id}, turn #{turn_index}: #{inspect(reason)}"
        )

        {:ok, %{status: :log_failed, type: :prompt, session_id: session_id, turn_index: turn_index}}
    end
  end

  defp log_answer(conversation_iri, turn_index, answer_text, session_id) do
    case Jidoka.Conversation.Logger.log_answer(
           conversation_iri,
           turn_index,
           answer_text
         ) do
      {:ok, _answer_iri} ->
        {:ok, %{status: :logged, type: :answer, session_id: session_id, turn_index: turn_index}}

      {:error, reason} ->
        Logger.warning(
          "Failed to log answer for session #{session_id}, turn #{turn_index}: #{inspect(reason)}"
        )

        {:ok, %{status: :log_failed, type: :answer, session_id: session_id, turn_index: turn_index}}
    end
  end

  defp log_tool_invocation(
         conversation_iri,
         turn_index,
         tool_index,
         tool_name,
         parameters,
         session_id
       ) do
    case Jidoka.Conversation.Logger.log_tool_invocation(
           conversation_iri,
           turn_index,
           tool_index,
           tool_name,
           parameters
         ) do
      {:ok, _invocation_iri} ->
        {:ok,
         %{status: :logged, type: :tool_invocation, session_id: session_id, turn_index: turn_index,
           tool_index: tool_index}}

      {:error, reason} ->
        Logger.warning(
          "Failed to log tool invocation for session #{session_id}, turn #{turn_index}, tool #{tool_index}: #{inspect(reason)}"
        )

        {:ok,
         %{status: :log_failed, type: :tool_invocation, session_id: session_id, turn_index: turn_index,
           tool_index: tool_index}}
    end
  end

  defp log_tool_result(conversation_iri, turn_index, tool_index, result_data, session_id) do
    case Jidoka.Conversation.Logger.log_tool_result(
           conversation_iri,
           turn_index,
           tool_index,
           result_data
         ) do
      {:ok, _result_iri} ->
        {:ok,
         %{status: :logged, type: :tool_result, session_id: session_id, turn_index: turn_index,
           tool_index: tool_index}}

      {:error, reason} ->
        Logger.warning(
          "Failed to log tool result for session #{session_id}, turn #{turn_index}, tool #{tool_index}: #{inspect(reason)}"
        )

        {:ok,
         %{status: :log_failed, type: :tool_result, session_id: session_id, turn_index: turn_index,
           tool_index: tool_index}}
    end
  end
end
