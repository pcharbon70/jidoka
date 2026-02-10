defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleToolCall do
  @moduledoc """
  Action to handle tool call signals for logging.

  This action processes `jido_coder.tool.call` signals and:
  - Logs tool invocations to the knowledge graph
  - Broadcasts tool call events to clients

  ## Signal Data

  * `:session_id` - Associated session ID (required)
  * `:conversation_iri` - Conversation IRI for logging (optional)
  * `:turn_index` - Turn index for logging (optional)
  * `:tool_index` - Index of the tool within this turn (optional)
  * `:tool_name` - Name of the tool being invoked (required)
  * `:parameters` - Tool parameters map (optional)

  ## Directives

  Emits signals for:
  - Broadcasting tool call to client
  - Logging tool invocation to knowledge graph (if conversation tracking available)
  """

  use Jido.Action,
    name: "handle_tool_call",
    description: "Process tool calls with logging",
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
      tool_name: [
        type: :string,
        required: true,
        doc: "Name of the tool being invoked"
      ],
      parameters: [
        type: :map,
        required: false,
        doc: "Tool parameters"
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
    tool_name = params[:tool_name]
    parameters = params[:parameters] || %{}

    # Build tool call payload for client broadcast
    tool_call_payload = %{
      tool_name: tool_name,
      parameters: parameters,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Add optional fields if present
    tool_call_payload =
      if tool_index != nil, do: Map.put(tool_call_payload, :tool_index, tool_index),
      else: tool_call_payload

    # Create broadcast event for client
    tool_call_signal =
      BroadcastEvent.new!(%{
        event_type: "tool_call",
        payload: tool_call_payload,
        session_id: session_id
      })

    # Start building directives
    directives = [
      # Broadcast to client events topic
      %Emit{
        signal: tool_call_signal,
        dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
      }
    ]

    # Add log_tool_invocation directive if we have conversation tracking
    directives =
      if conversation_iri != nil and turn_index != nil and tool_index != nil do
        [
          ConversationTurn.LogToolInvocation.new!(%{
            conversation_iri: conversation_iri,
            turn_index: turn_index,
            tool_index: tool_index,
            tool_name: tool_name,
            parameters: parameters,
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

    {:ok, %{status: :logged, session_id: session_id, tool_name: tool_name},
     directives}
  end
end
