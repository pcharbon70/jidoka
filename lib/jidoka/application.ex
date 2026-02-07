defmodule Jidoka.Application do
  @moduledoc """
  The main application module for Jidoka.

  This module defines the supervision tree for the entire application.
  It starts the top-level supervisor and all core infrastructure components.

  ## Supervision Tree

  ```
  Jidoka.Supervisor (one_for_one)
  ├── Jidoka.Knowledge.Engine - added in Phase 5.2
  ├── Jidoka.Indexing.IndexingStatusTracker - added in Phase 6.4.5
  ├── Jidoka.Indexing.CodeIndexer - added in Phase 6.2
  ├── Jidoka.ProtocolSupervisor (DynamicSupervisor)
  │   └── Protocol connections (MCP, Phoenix, A2A) - added in later phases
  ├── Jidoka.Protocol.MCP.ConnectionSupervisor (DynamicSupervisor) - Phase 8.3
  │   └── MCP server connections
  ├── Jidoka.Protocol.Phoenix.ConnectionSupervisor (DynamicSupervisor) - Phase 8.4
  │   └── Phoenix Channels connections
  ├── Jidoka.AgentSupervisor (rest_for_one)
  │   └── Coordinator, CodeAnalyzer, IssueDetector - added in Phase 2.2+
  ├── Jidoka.Agents.SessionManager - added in Phase 3.1
  ├── Phoenix.PubSub - added in Phase 1.3
  ├── AgentRegistry - added in Phase 1.4
  ├── TopicRegistry - added in Phase 1.4
  ├── SessionRegistry - added in Phase 4.11 (review fixes)
  ├── SecureCredentials - added in Phase 1.8 (security fixes)
  ├── ContextStore - added in Phase 1.5
  └── TelemetryHandlers - added in Phase 1.7
  ```

  ## Security Notes

  - SecureCredentials uses a private ETS table that only its GenServer can access
  - ContextStore uses protected ETS tables (write control through GenServer)
  - TelemetryHandlers uses protected ETS tables for metrics
  - SessionRegistry tracks memory session processes for proper cleanup
  - SessionServer uses protected ETS tables (fixes security vulnerability from public access)
  """

  use Application
  import Config

  @doc """
  Starts the application and its supervision tree.

  ## Options

  - `:type` - The type of application (:permanent, :temporary, :transient)
  - `:args` - Application arguments passed from the VM

  ## Returns

  - `{:ok, pid}` - Successfully started
  - `{:error, reason}` - Failed to start
  """
  @impl true
  def start(_type, _args) do
    children = [
      # Knowledge Engine for RDF quad-store (Phase 5.2)
      {Jidoka.Knowledge.Engine,
       [
         name: :knowledge_engine,
         data_dir: knowledge_data_dir(),
         schema: Application.fetch_env!(:jidoka, :knowledge_engine)[:schema],
         health_check_interval:
           Application.fetch_env!(:jidoka, :knowledge_engine)[:health_check_interval]
       ]},
      # IndexingStatusTracker for code indexing operations (Phase 6.4.5)
      {Jidoka.Indexing.IndexingStatusTracker,
       [name: Jidoka.Indexing.IndexingStatusTracker, engine_name: :knowledge_engine]},
      # CodeIndexer for codebase semantic model (Phase 6.2)
      {Jidoka.Indexing.CodeIndexer,
       [
         name: Jidoka.Indexing.CodeIndexer,
         engine_name: :knowledge_engine,
         tracker_name: Jidoka.Indexing.IndexingStatusTracker
       ]},
      # Phoenix PubSub for message passing
      {Phoenix.PubSub, name: :jido_coder_pubsub},
      # Registry for unique process registration (agents, sessions)
      {Registry, keys: :unique, name: Jidoka.AgentRegistry},
      # Registry for duplicate key registration (topics, pub/sub patterns)
      {Registry, keys: :duplicate, name: Jidoka.TopicRegistry},
      # Registry for memory session processes (Phase 4.11 - review fixes)
      {Registry, keys: :unique, name: Jidoka.Memory.SessionRegistry},
      # SecureCredentials for API key storage (private ETS)
      Jidoka.SecureCredentials,
      # ContextStore for ETS table management
      Jidoka.ContextStore,
      # Jido instance for agent management
      Jidoka.Jido,
      # AgentSupervisor for global agents (Coordinator, etc.)
      Jidoka.AgentSupervisor,
      # SessionManager for multi-session management (Phase 3.1)
      Jidoka.Agents.SessionManager,
      # Telemetry event handlers (started manually, not a child process)
      # Jidoka.TelemetryHandlers.attach_all() is called in Application.start
      # Protocol connections (Phase 8)
      {DynamicSupervisor, name: Jidoka.ProtocolSupervisor, strategy: :one_for_one},
      # MCP Connection Supervisor (Phase 8.3)
      {Jidoka.Protocol.MCP.ConnectionSupervisor, []},
      # Phoenix Connection Supervisor (Phase 8.4)
      {Jidoka.Protocol.Phoenix.ConnectionSupervisor, []},
      # A2A Connection Supervisor (Phase 8.5)
      {Jidoka.Protocol.A2A.ConnectionSupervisor, []}
    ]

    # Use one_for_one strategy with restart intensity limits
    # max_restarts: 3, max_seconds: 5 means if 3 children restart within 5 seconds,
    # the supervisor terminates all children and itself
    opts = [
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5,
      name: Jidoka.Supervisor
    ]

    {:ok, _pid} = Supervisor.start_link(children, opts)

    # Attach telemetry handlers after supervisor starts
    # TelemetryHandlers is not a GenServer, so it doesn't go in the supervision tree
    Jidoka.TelemetryHandlers.attach_all()

    {:ok, self()}
  end

  # ========================================================================
  # Private Helpers
  # ========================================================================

  defp knowledge_data_dir do
    case Application.get_env(:jidoka, :env, :dev) do
      :test ->
        Path.join([System.tmp_dir!(), "jido_kg_test"])

      _env ->
        Application.fetch_env!(:jidoka, :knowledge_engine)[:data_dir]
        |> Path.expand()
    end
  end
end
