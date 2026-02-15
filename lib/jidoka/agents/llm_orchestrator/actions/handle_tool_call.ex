defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleToolCall do
  @moduledoc """
  Action to handle tool call signals for logging.

  This action processes `jido_coder.tool.call` signals and:
  - Persists tool invocations to `Jidoka.Messaging`
  - Broadcasts tool call events to clients

  ## Signal Data

  * `:session_id` - Associated session ID (required)
  * `:tool_index` - Index of the tool within this turn (optional)
  * `:tool_name` - Name of the tool being invoked (required)
  * `:parameters` - Tool parameters map (optional)

  ## Directives

  Emits signals for:
  - Broadcasting tool call to client
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
  alias Jidoka.Messaging
  alias Jidoka.PubSub
  alias Jidoka.Signals.BroadcastEvent

  alias Directive.Emit

  @impl true
  def run(params, _context) do
    # Extract signal data
    session_id = params[:session_id]
    tool_index = params[:tool_index]
    tool_name = params[:tool_name]
    parameters = params[:parameters] || %{}

    with {:ok, _stored_message} <-
           Messaging.append_session_message(
             session_id,
             :tool,
             tool_call_content(tool_name, parameters, tool_index),
             sender_id: "tool:#{tool_name}",
             metadata: %{
               event_type: :tool_call,
               tool_name: tool_name,
               parameters: parameters,
               tool_index: tool_index
             }
           ) do
      # Build tool call payload for client broadcast
      tool_call_payload = %{
        tool_name: tool_name,
        parameters: parameters,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      # Add optional fields if present
      tool_call_payload =
        if tool_index != nil,
          do: Map.put(tool_call_payload, :tool_index, tool_index),
          else: tool_call_payload

      # Create broadcast event for client
      tool_call_signal =
        BroadcastEvent.new!(%{
          event_type: "tool_call",
          payload: tool_call_payload,
          session_id: session_id
        })

      directives = [
        # Broadcast to client events topic
        %Emit{
          signal: tool_call_signal,
          dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
        }
      ]

      {:ok, %{status: :logged, session_id: session_id, tool_name: tool_name}, directives}
    end
  end

  defp tool_call_content(tool_name, parameters, tool_index) do
    prefix =
      if is_integer(tool_index) do
        "[tool_call ##{tool_index}]"
      else
        "[tool_call]"
      end

    "#{prefix} #{tool_name} #{inspect(parameters)}"
  end
end
