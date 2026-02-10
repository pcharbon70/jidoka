defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleLLMResponse do
  @moduledoc """
  Action to handle LLM response signals.

  This action processes `jido_coder.llm.response` signals and:
  - Extracts conversation tracking data (conversation_iri, turn_index)
  - Emits log_answer signal for conversation logging
  - Broadcasts completion to client
  - Updates active request state

  ## Signal Data

  * `:request_id` - Unique request identifier (optional, for state tracking)
  * `:content` - LLM response text content
  * `:session_id` - Associated session ID (required)
  * `:conversation_iri` - Optional conversation IRI for logging
  * `:turn_index` - Optional turn index for logging
  * `:model` - Model used (optional)
  * `:tokens_used` - Total tokens used (optional)

  ## Directives

  Emits signals for:
  - Broadcasting response to client
  - Logging answer to knowledge graph (if conversation tracking available)
  - Updating active request state
  """

  use Jido.Action,
    name: "handle_llm_response",
    description: "Process LLM responses with conversation logging",
    category: "llm_orchestrator",
    tags: ["llm", "response", "logging"],
    vsn: "1.0.0",
    schema: [
      request_id: [
        type: :string,
        required: false,
        doc: "Unique request identifier for state tracking"
      ],
      content: [
        type: :string,
        required: true,
        doc: "LLM response text content"
      ],
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
      model: [
        type: :string,
        required: false,
        doc: "Model used for this response"
      ],
      tokens_used: [
        type: :integer,
        required: false,
        doc: "Total tokens used for this request"
      ]
    ]

  alias Jido.Agent.{Directive, StateOp}
  alias Jidoka.PubSub
  alias Jidoka.Signals.BroadcastEvent
  alias Jidoka.Signals.ConversationTurn

  alias Directive.Emit
  alias StateOp.SetState
  alias StateOp.DeletePath

  @impl true
  def run(params, _context) do
    # Extract signal data
    request_id = params[:request_id]
    content = params[:content]
    session_id = params[:session_id]
    conversation_iri = params[:conversation_iri]
    turn_index = params[:turn_index]
    model = params[:model]
    tokens_used = params[:tokens_used]

    # Build state updates
    state_updates =
      if request_id do
        %{
          # Remove from active_requests
          delete_active_requests: [request_id]
        }
      else
        %{}
      end

    # Build response payload for client broadcast
    response_payload = %{
      content: content,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Add optional fields if present
    response_payload =
      if model, do: Map.put(response_payload, :model, model), else: response_payload

    response_payload =
      if tokens_used, do: Map.put(response_payload, :tokens_used, tokens_used),
      else: response_payload

    # Create broadcast event for client
    response_signal =
      BroadcastEvent.new!(%{
        event_type: "llm_response",
        payload: response_payload,
        session_id: session_id
      })

    # Start building directives
    directives = [
      # Broadcast to client events topic
      %Emit{
        signal: response_signal,
        dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
      }
    ]

    # Add state operation directives
    directives =
      if request_id do
        [
          %DeletePath{path: [:active_requests, request_id]} | directives
        ]
      else
        directives
      end

    # Add log_answer directive if we have conversation tracking
    directives =
      if conversation_iri != nil and turn_index != nil do
        [
          ConversationTurn.LogAnswer.new!(%{
            conversation_iri: conversation_iri,
            turn_index: turn_index,
            answer_text: content,
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

    {:ok, %{status: :completed, session_id: session_id},
     directives}
  end
end
