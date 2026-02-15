defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleLLMResponse do
  @moduledoc """
  Action to handle LLM response signals.

  This action processes `jido_coder.llm.response` signals and:
  - Persists assistant responses to `Jidoka.Messaging`
  - Broadcasts completion to client
  - Updates active request state

  ## Signal Data

  * `:request_id` - Unique request identifier (optional, for state tracking)
  * `:content` - LLM response text content
  * `:session_id` - Associated session ID (required)
  * `:model` - Model used (optional)
  * `:tokens_used` - Total tokens used (optional)

  ## Directives

  Emits signals for:
  - Broadcasting response to client
  - Updating active request state
  """

  use Jido.Action,
    name: "handle_llm_response",
    description: "Process LLM responses and persist assistant messages",
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

  alias Jido.Agent.Directive
  alias Jido.Agent.StateOp.DeletePath
  alias Jidoka.Messaging
  alias Jidoka.PubSub
  alias Jidoka.Signals.BroadcastEvent

  alias Directive.Emit

  @impl true
  def run(params, _context) do
    # Extract signal data
    request_id = params[:request_id]
    content = params[:content]
    session_id = params[:session_id]
    model = params[:model]
    tokens_used = params[:tokens_used]

    with {:ok, _stored_message} <-
           Messaging.append_session_message(session_id, :assistant, content) do
      # Build response payload for client broadcast
      response_payload = %{
        content: content,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      # Add optional fields if present
      response_payload =
        if model, do: Map.put(response_payload, :model, model), else: response_payload

      response_payload =
        if tokens_used,
          do: Map.put(response_payload, :tokens_used, tokens_used),
          else: response_payload

      # Create broadcast event for client
      response_signal =
        BroadcastEvent.new!(%{
          event_type: "llm_response",
          payload: response_payload,
          session_id: session_id
        })

      directives = [
        # Broadcast to client events topic
        %Emit{
          signal: response_signal,
          dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
        }
      ]

      directives =
        if request_id do
          [
            %DeletePath{path: [:active_requests, request_id]} | directives
          ]
        else
          directives
        end

      {:ok, %{status: :completed, session_id: session_id}, directives}
    end
  end
end
