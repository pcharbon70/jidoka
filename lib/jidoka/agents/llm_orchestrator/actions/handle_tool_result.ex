defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleToolResult do
  @moduledoc """
  Action to handle tool result signals for logging.

  This action processes `jido_coder.tool.result` signals and:
  - Logs tool results to the knowledge graph
  - Broadcasts tool result events to clients

  ## Signal Data

  * `:session_id` - Associated session ID (required)
  * `:conversation_iri` - Conversation IRI for logging (optional)
  * `:turn_index` - Turn index for logging (optional)
  * `:tool_index` - Index of the tool within this turn (optional)
  * `:result_data` - Result data from the tool (required)

  ## Directives

  Emits signals for:
  - Broadcasting tool result to client
  - Logging tool result to knowledge graph (if conversation tracking available)
  """

  use Jido.Action,
    name: "handle_tool_result",
    description: "Process tool results with logging",
    category: "llm_orchestrator",
    tags: ["tool", "logging"],
    vsn: "1.0.0",
    schema: [
      session_id: [
        type: :string,
        required: true,
        doc: "Associated session ID"
      ],
      conversation_iri: [
        type: :string,
        required: false,
        doc: "Conversation IRI for logging to knowledge graph"
      ],
      turn_index: [
        type: :integer,
        required: false,
        doc: "Turn index for logging to knowledge graph"
      ],
      tool_index: [
        type: :integer,
        required: false,
        doc: "Index of the tool within this turn"
      ],
      result_data: [
        type: :map,
        required: true,
        doc: "Result data from the tool"
      ]
    ]

  alias Jido.Agent.Directive
  alias Jidoka.PubSub
  alias Jidoka.Signals.BroadcastEvent
  alias Jidoka.Signals.ConversationTurn

  alias Directive.Emit

  @impl true
  def run(params, _context) do
    # Extract signal data
    session_id = params[:session_id]
    conversation_iri = params[:conversation_iri]
    turn_index = params[:turn_index]
    tool_index = params[:tool_index]
    result_data = params[:result_data]

    # Build tool result payload for client broadcast
    tool_result_payload = %{
      result: result_data,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Add optional fields if present
    tool_result_payload =
      if tool_index != nil, do: Map.put(tool_result_payload, :tool_index, tool_index),
      else: tool_result_payload

    # Create broadcast event for client
    tool_result_signal =
      BroadcastEvent.new!(%{
        event_type: "tool_result",
        payload: tool_result_payload,
        session_id: session_id
      })

    # Start building directives
    directives = [
      # Broadcast to client events topic
      %Emit{
        signal: tool_result_signal,
        dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
      }
    ]

    # Add log_tool_result directive if we have conversation tracking
    directives =
      if conversation_iri != nil and turn_index != nil and tool_index != nil do
        [
          ConversationTurn.LogToolResult.new!(%{
            conversation_iri: conversation_iri,
            turn_index: turn_index,
            tool_index: tool_index,
            result_data: result_data,
            session_id: session_id
          })
          |> then(&%Emit{
            signal: &1,
            dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.session_topic(session_id)]}
          })
        | directives
        ]
      else
        directives
      end

    {:ok, %{status: :logged, session_id: session_id},
     directives}
  end
end
