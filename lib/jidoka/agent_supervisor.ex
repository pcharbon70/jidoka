defmodule Jidoka.AgentSupervisor do
  @moduledoc """
  Supervisor for global Jido agents.

  This supervisor manages the lifecycle of global agents including
  the Coordinator and future agents (CodeAnalyzer, IssueDetector).

  Uses `:rest_for_one` strategy to ensure that if a child terminates,
  all children started after it are also terminated and restarted.

  ## Children

  * `Jidoka.Agents.Coordinator` - The central coordinator agent
  * (Future) CodeAnalyzer - Agent for code analysis
  * (Future) IssueDetector - Agent for issue detection

  ## Examples

  The supervisor is typically started as part of the application supervision tree:

      children = [
        Jidoka.AgentSupervisor
      ]

  """

  use Supervisor

  @doc """
  Starts the agent supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Coordinator agent - must be started first as other agents may depend on it
      {Jido.AgentServer,
       [
         agent: Jidoka.Agents.Coordinator,
         id: "coordinator-main",
         name: :coordinator,
         jido: Jidoka.Jido
       ]}
    ]

    # Use :rest_for_one strategy - if a child dies, all children
    # started after it are also terminated and restarted
    opts = [strategy: :rest_for_one, max_restarts: 5, max_seconds: 60]

    Supervisor.init(children, opts)
  end
end
