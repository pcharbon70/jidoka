defmodule JidoCoderLib.Agents.Coordinator do
  @moduledoc """
  The Coordinator agent manages inter-agent communication and broadcasts events to clients.

  This agent serves as the central hub for:
  - Routing signals between agents
  - Aggregating results from multiple agents
  - Broadcasting events to connected clients

  ## Signal Routes

  The Coordinator subscribes to and handles the following signals:

  | Signal Type | Action | Purpose |
  |-------------|--------|---------|
  | `jido_coder.analysis.complete` | `HandleAnalysisComplete` | Analysis results |
  | `jido_coder.analysis.issue.found` | `HandleIssueFound` | Code issues detected |
  | `jido_coder.chat.request` | `HandleChatRequest` | User chat messages |

  ## Agent State

  * `:active_tasks` - Map of currently running tasks by task_id
  * `:pending_broadcasts` - List of pending client broadcasts
  * `:event_aggregation` - Map of aggregated event data

  ## Examples

  Starting the coordinator:

      {:ok, pid} = JidoCoderLib.Agents.Coordinator.start_link()

  Sending a signal to the coordinator:

      signal = Jido.Signal.new!(
        %{analysis_id: "test", results: %{files: 5}},
        type: "jido_coder.analysis.complete"
      )
      Jido.Signal.Dispatch.dispatch(signal, {:pid, target: pid})

  """

  use Jido.Agent,
    name: "coordinator",
    description: "Manages inter-agent communication and client broadcasting",
    category: "orchestration",
    tags: ["coordinator", "signals", "broadcast"],
    vsn: "1.0.0",
    schema: [
      active_tasks: [
        type: :map,
        default: %{},
        doc: "Map of active tasks by task_id"
      ],
      pending_broadcasts: [
        type: :list,
        default: [],
        doc: "List of pending client broadcasts"
      ],
      event_aggregation: [
        type: :map,
        default: %{},
        doc: "Map of aggregated event data"
      ]
    ]

  alias JidoCoderLib.Agents.Coordinator.Actions

  @doc """
  Starts the Coordinator agent.

  ## Options

  * `:id` - Unique identifier for this agent instance (default: "coordinator-main")
  * `:name` - Optional name for the agent process
  * `:initial_state` - Optional initial state overrides
  * `:jido` - Jido instance module (default: `JidoCoderLib.Jido`)

  ## Examples

      {:ok, pid} = Coordinator.start_link()
      {:ok, pid} = Coordinator.start_link(id: "coordinator-test")

  """
  def start_link(opts \\ []) do
    id = Keyword.get(opts, :id, "coordinator-main")
    name = Keyword.get(opts, :name)
    initial_state = Keyword.get(opts, :initial_state, %{})
    jido_instance = Keyword.get(opts, :jido, JidoCoderLib.Jido)

    # Build the start options for Jido.AgentServer
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

  @impl true
  def signal_routes do
    [
      # Route analysis completion signals
      {"jido_coder.analysis.complete", Actions.HandleAnalysisComplete},

      # Route issue found signals
      {"jido_coder.analysis.issue.found", Actions.HandleIssueFound},

      # Route chat request signals
      {"jido_coder.chat.request", Actions.HandleChatRequest}
    ]
  end

  # Private helpers

  defp maybe_add_name(opts, nil), do: opts
  defp maybe_add_name(opts, name), do: Keyword.put(opts, :name, name)
end
