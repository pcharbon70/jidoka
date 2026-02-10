defmodule Jidoka.Agents.LLMOrchestrator do
  @moduledoc """
  The LLM Orchestrator agent manages LLM interactions with tool calling support.

  This agent:
  - Receives LLM request signals from the Coordinator
  - Selects and invokes tools from the Jidoka.Tools registry
  - Handles tool results and feeds them back to the LLM
  - Supports multi-step tool calling
  - Streams responses to clients via PubSub
  - Logs all interactions to conversation history

  ## Signal Routes

  | Signal Type | Action | Purpose |
  |-------------|--------|---------|
  | `jido_coder.llm.request` | `HandleLLMRequest` | User chat/messages for LLM |

  ## Agent State

  * `:active_requests` - Map of currently running LLM requests
  * `:tool_call_history` - History of tool calls for the session
  * `:llm_config` - Default LLM configuration

  ## Examples

      {:ok, pid} = Jidoka.Agents.LLMOrchestrator.start_link()

      # Send a request via signal
      signal = Jido.Signal.new!(
        "jido_coder.llm.request",
        %{message: "List files in lib/jidoka", session_id: "session_123"}
      )
      Jido.Signal.Dispatch.dispatch(signal, {:pid, target: pid})

  """

  use Jido.Agent,
    name: "llm_orchestrator",
    description: "Manages LLM interactions with tool calling support",
    category: "orchestration",
    tags: ["llm", "orchestrator", "tool-calling", "agent"],
    vsn: "1.0.0",
    schema: [
      active_requests: [
        type: :map,
        default: %{},
        doc: "Map of currently running LLM requests by request_id"
      ],
      tool_call_history: [
        type: :map,
        default: %{},
        doc: "History of tool calls by session_id"
      ],
      llm_config: [
        type: :map,
        default: %{
          model: "anthropic:claude-haiku-4-5",
          max_tokens: 4096,
          temperature: 0.7,
          auto_execute: true,
          max_turns: 10
        },
        doc: "Default LLM configuration"
      ]
    ]

  alias Jidoka.Agents.LLMOrchestrator.Actions

  alias Jido.AgentServer
  alias Jido.Signal

  @doc """
  Starts the LLMOrchestrator agent.

  ## Options

  * `:id` - Unique identifier for this agent instance (default: "llm_orchestrator-main")
  * `:name` - Optional name for the agent process
  * `:initial_state` - Optional initial state overrides
  * `:jido` - Jido instance module (default: `Jidoka.Jido`)

  ## Examples

      {:ok, pid} = LLMOrchestrator.start_link()
      {:ok, pid} = LLMOrchestrator.start_link(id: "llm_orchestrator-test")

  """
  def start_link(opts \\ []) do
    id = Keyword.get(opts, :id, "llm_orchestrator-main")
    name = Keyword.get(opts, :name)
    initial_state = Keyword.get(opts, :initial_state, %{})
    jido_instance = Keyword.get(opts, :jido, Jidoka.Jido)

    start_opts =
      [
        agent: __MODULE__,
        id: id,
        jido: jido_instance
      ]
      |> maybe_add_name(name)
      |> Keyword.put(:initial_state, initial_state)

    Jido.AgentServer.start_link(start_opts)
  end

  def signal_routes do
    [
      # Route LLM request signals
      {"jido_coder.llm.request", Actions.HandleLLMRequest},
      # Route LLM response signals
      {"jido_coder.llm.response", Actions.HandleLLMResponse},
      # Route tool call signals
      {"jido_coder.tool.call", Actions.HandleToolCall},
      # Route tool result signals
      {"jido_coder.tool.result", Actions.HandleToolResult}
    ]
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Get the current tool call history for a session.
  """
  def get_tool_history(session_id) do
    case Jido.whereis(Jidoka.Jido, "llm_orchestrator-main") do
      pid when is_pid(pid) ->
        case AgentServer.state(pid) do
          {:ok, agent_state} ->
            {:ok, Map.get(agent_state.agent.state.tool_call_history, session_id, [])}

          {:error, _} = error ->
            error
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Clear tool call history for a session.
  """
  def clear_tool_history(session_id) do
    case Jido.whereis(Jidoka.Jido, "llm_orchestrator-main") do
      pid when is_pid(pid) ->
        # Send a signal to update state
        signal = Signal.new!(
          "llm_orchestrator.clear_history",
          %{session_id: session_id}
        )
        AgentServer.cast(pid, signal)

      nil ->
        {:error, :not_found}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp maybe_add_name(opts, nil), do: opts
  defp maybe_add_name(opts, name), do: Keyword.put(opts, :name, name)
end
