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
  alias Jidoka.Messaging
  alias Jidoka.{PubSub, Tools}
  alias Jidoka.Signals.BroadcastEvent

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

    with {:ok, session_messages} <- Messaging.list_session_messages(session_id, limit: 50) do
      # Generate unique request ID
      request_id = "llm_#{session_id}_#{System.unique_integer([:positive, :monotonic])}"

      # Get available tools
      tool_schemas = get_tool_schemas(tool_names)

      # Build LLM messages from canonical session history
      llm_messages = build_messages(session_messages, context_data)

      # Build LLM parameters
      llm_params = %{
        prompt: message,
        system_prompt: build_system_prompt(),
        messages: llm_messages,
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

      # Build LLM process signal data
      llm_process_data = %{
        request_id: request_id,
        message: message,
        session_id: session_id,
        user_id: user_id,
        context: context_data,
        stream: stream,
        tools: tool_names,
        llm_params: llm_params
      }

      # Create LLM processing signal
      llm_signal =
        Signal.new!(
          "jido_coder.llm.process",
          llm_process_data,
          %{source: "/llm_orchestrator"}
        )

      directives = [
        # State operation: track as active request
        %SetState{attrs: state_updates},
        # Broadcast to client that request was received
        %Emit{
          signal:
            BroadcastEvent.new!(%{
              event_type: "llm_request_received",
              payload: %{
                request_id: request_id,
                session_id: session_id,
                message: message,
                tools_available: length(tool_schemas)
              },
              session_id: session_id
            }),
          dispatch: {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
        },
        # Emit signal for actual LLM processing
        %Emit{
          signal: llm_signal,
          dispatch:
            {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.session_topic(session_id)]}
        }
      ]

      {:ok, %{status: :processing, request_id: request_id}, directives}
    end
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

  defp build_messages(session_messages, context_data) when is_list(session_messages) do
    context_messages =
      if is_map(context_data) and map_size(context_data) > 0 do
        [%{role: :system, content: format_context(context_data)}]
      else
        []
      end

    history_messages =
      session_messages
      |> Enum.flat_map(&message_to_llm_messages/1)

    context_messages ++ history_messages
  end

  defp message_to_llm_messages(%{role: role, content: content_blocks}) do
    text =
      content_blocks
      |> Enum.map(&content_block_to_text/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
      |> String.trim()

    if text == "" do
      []
    else
      [%{role: role, content: text}]
    end
  end

  defp message_to_llm_messages(_message), do: []

  defp content_block_to_text(%{type: :text, text: text}) when is_binary(text), do: text

  defp content_block_to_text(%{type: "text", text: text}) when is_binary(text), do: text

  defp content_block_to_text(%{type: :tool_use, name: name, input: input}) do
    "[tool_use] #{name}: #{inspect(input)}"
  end

  defp content_block_to_text(%{type: "tool_use", name: name, input: input}) do
    "[tool_use] #{name}: #{inspect(input)}"
  end

  defp content_block_to_text(%{type: :tool_result, content: content, is_error: is_error}) do
    "[tool_result#{if is_error, do: " error", else: ""}] #{inspect(content)}"
  end

  defp content_block_to_text(%{type: "tool_result", content: content, is_error: is_error}) do
    "[tool_result#{if is_error, do: " error", else: ""}] #{inspect(content)}"
  end

  defp content_block_to_text(block) when is_map(block), do: inspect(block)
  defp content_block_to_text(_block), do: ""

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
