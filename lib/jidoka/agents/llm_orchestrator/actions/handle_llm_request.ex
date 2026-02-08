defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleLLMRequest do
  @moduledoc """
  Action to handle LLM request signals.

  This action processes `jido_coder.llm.request` signals and:
  - Extracts message and context from the signal
  - Gets available tools from the Tools registry
  - Converts tools to OpenAI format
  - Calls the LLM with tool calling support
  - Broadcasts responses to the client
  - Handles multi-step tool calling

  ## Signal Data

  * `:message` - User message content
  * `:session_id` - Associated session ID
  * `:user_id` - Optional user identifier
  * `:context` - Additional conversation context map
  * `:stream` - Whether to stream responses (default: true)
  * `:tools` - Optional list of tool names to include (default: all)

  ## Directives

  Emits signals for:
  - Broadcasting LLM responses to client
  - Logging tool usage
  """

  use Jido.Action,
    name: "handle_llm_request",
    description: "Process LLM requests with tool calling support",
    category: "llm_orchestrator",
    tags: ["llm", "tool-calling", "chat"],
    vsn: "1.0.0",
    schema: [
      message: [
        type: :string,
        required: true,
        doc: "User message content"
      ],
      session_id: [
        type: :string,
        required: true,
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
      ],
      stream: [
        type: :boolean,
        default: true,
        doc: "Whether to stream LLM responses"
      ],
      tools: [
        type: {:list, :string},
        required: false,
        doc: "Optional list of tool names to include"
      ]
    ]

  alias Jido.Agent.{Directive, StateOp}
  alias Jido.Signal
  alias Jidoka.{PubSub, Tools}
  alias Jidoka.Signals

  alias Directive.Emit
  alias StateOp.SetState

  @impl true
  def run(params, _context) do
    # Extract signal data
    message = params[:message]
    session_id = params[:session_id]
    user_id = params[:user_id]
    context_data = params[:context]
    stream = params[:stream] != false
    tool_names = params[:tools]

    # Generate unique request ID
    request_id = "llm_#{session_id}_#{System.unique_integer([:positive, :monotonic])}"

    # Get available tools
    tool_schemas = get_tool_schemas(tool_names)

    # Build messages for LLM
    _messages = build_messages(message, context_data)

    # Build LLM parameters
    llm_params = %{
      prompt: message,
      system_prompt: build_system_prompt(),
      tools: tool_names,
      auto_execute: true,
      max_turns: 10
    }

    # State updates: track as active request
    state_updates = %{
      active_requests: %{
        request_id => %{
          type: :llm,
          session_id: session_id,
          user_id: user_id,
          status: :processing,
          started_at: DateTime.utc_now()
        }
      }
    }

    # Create LLM processing signal
    llm_signal =
      Signal.new!(
        "jido_coder.llm.process",
        %{
          request_id: request_id,
          message: message,
          session_id: session_id,
          user_id: user_id,
          context: context_data,
          stream: stream,
          tools: tool_names,
          llm_params: llm_params
        },
        %{source: "/llm_orchestrator"}
      )

    # Broadcast request received event
    received_signal =
      Signals.BroadcastEvent.new!(%{
        event_type: "llm_request_received",
        payload: %{
          request_id: request_id,
          session_id: session_id,
          message: message,
          tools_available: length(tool_schemas)
        },
        session_id: session_id
      })

    {:ok, %{status: :processing, request_id: request_id},
     [
       # State operation: track as active request
       %SetState{attrs: state_updates},
       # Broadcast to client that request was received
       %Emit{
         signal: received_signal,
         dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
       },
       # Emit signal for actual LLM processing
       %Emit{
         signal: llm_signal,
         dispatch:
           {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.session_topic(session_id)]}
       }
     ]}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_tool_schemas(nil) do
    # Get all tools and convert to schema format
    Tools.Registry.list_tools()
    |> Enum.map(fn tool ->
      schema = Tools.Schema.to_openai_schema(tool.module)
      Map.put(schema, :module, tool.module)
    end)
  end

  defp get_tool_schemas(tool_names) when is_list(tool_names) do
    # Get specific tools
    Enum.map(tool_names, fn name ->
      {:ok, tool} = Tools.Registry.find_tool(name)
      schema = Tools.Schema.to_openai_schema(tool.module)
      Map.put(schema, :module, tool.module)
    end)
  end

  defp build_messages(message, context_data) when is_map(context_data) do
    # Build conversation messages from context
    base_messages = [
      %{role: :user, content: message}
    ]

    # Add context as system message if present
    if map_size(context_data) > 0 do
      [
        %{role: :system, content: format_context(context_data)}
      ] ++ base_messages
    else
      base_messages
    end
  end

  defp build_messages(message, _context_data) do
    # No context or nil context, just return user message
    [%{role: :user, content: message}]
  end

  defp build_system_prompt do
    """
    You are Jido, a helpful coding assistant with access to tools for
    interacting with codebases. You can read files, search code, analyze functions,
    and more. Use the available tools to help users with their coding tasks.

    When you need to use a tool, select the appropriate one and provide the
    required parameters. After receiving tool results, incorporate them into
    your response to answer the user's question.
    """
  end

  defp format_context(context_data) do
    context_lines =
      Enum.flat_map(context_data, fn {key, value} ->
        ["#{key}: #{inspect(value)}"]
      end)

    Enum.join(context_lines, "\n")
  end
end
