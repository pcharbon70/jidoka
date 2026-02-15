defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleToolResult do
  @moduledoc """
  Action to handle tool result signals for logging.

  This action processes `jido_coder.tool.result` signals and:
  - Persists tool results to `Jidoka.Messaging`
  - Broadcasts tool result events to clients

  ## Signal Data

  * `:session_id` - Associated session ID (required)
  * `:tool_index` - Index of the tool within this turn (optional)
  * `:result_data` - Result data from the tool (required)

  ## Directives

  Emits signals for:
  - Broadcasting tool result to client
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
  alias Jidoka.Messaging
  alias Jidoka.PubSub
  alias Jidoka.Signals.BroadcastEvent

  alias Directive.Emit

  @impl true
  def run(params, _context) do
    # Extract signal data
    session_id = params[:session_id]
    tool_index = params[:tool_index]
    result_data = params[:result_data]

    with {:ok, _stored_message} <-
           Messaging.append_session_message(
             session_id,
             :tool,
             tool_result_content(result_data, tool_index)
           ) do
      # Build tool result payload for client broadcast
      tool_result_payload = %{
        result: result_data,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      # Add optional fields if present
      tool_result_payload =
        if tool_index != nil,
          do: Map.put(tool_result_payload, :tool_index, tool_index),
          else: tool_result_payload

      # Create broadcast event for client
      tool_result_signal =
        BroadcastEvent.new!(%{
          event_type: "tool_result",
          payload: tool_result_payload,
          session_id: session_id
        })

      directives = [
        # Broadcast to client events topic
        %Emit{
          signal: tool_result_signal,
          dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
        }
      ]

      {:ok, %{status: :logged, session_id: session_id}, directives}
    end
  end

  defp tool_result_content(result_data, tool_index) do
    prefix =
      if is_integer(tool_index) do
        "[tool_result ##{tool_index}]"
      else
        "[tool_result]"
      end

    "#{prefix} #{inspect(result_data)}"
  end
end
