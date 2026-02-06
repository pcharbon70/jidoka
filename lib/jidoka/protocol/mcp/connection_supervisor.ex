defmodule Jidoka.Protocol.MCP.ConnectionSupervisor do
  @moduledoc """
  Dynamic supervisor for MCP server connections.

  This supervisor manages multiple MCP client connections,
  allowing for dynamic addition and removal of servers.

  ## Configuration

  Add MCP servers to your config:

      config :jidoka, :mcp_servers,
        filesystem: [
          transport: {:stdio, command: "npx -y @modelcontextprotocol/server-filesystem /path/to/allowed"},
          name: :mcp_filesystem
        ],
        github: [
          transport: {:stdio, command: "uvx --from mcp-server-github mcp-server-github"},
          name: :mcp_github
        ]

  ## Example

      # Start a connection manually
      {:ok, pid} = ConnectionSupervisor.start_connection(
        name: :my_server,
        transport: {:stdio, command: "mcp-server"}
      )

      # Stop a connection
      :ok = ConnectionSupervisor.stop_connection(:my_server)

      # List active connections
      connections = ConnectionSupervisor.list_connections()
  """

  use DynamicSupervisor
  require Logger

  @doc """
  Start the connection supervisor.
  """
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start an MCP connection with the given configuration.

  ## Options

  * `:name` - Name to register the connection (required)
  * `:transport` - Transport configuration `{type, opts}` (required)
  * `:timeout` - Request timeout in milliseconds (optional, default: 30000)
  """
  def start_connection(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    transport = Keyword.fetch!(opts, :transport)
    timeout = Keyword.get(opts, :timeout, 30_000)

    child_spec = %{
      id: name,
      start: {Jidoka.Protocol.MCP.Client, :start_link, [[transport: transport, name: name, timeout: timeout]]},
      restart: :permanent,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started MCP connection: #{name}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start MCP connection #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop an MCP connection by name.
  """
  def stop_connection(name) when is_atom(name) do
    case Process.whereis(name) do
      nil ->
        {:error, :not_found}

      pid ->
        case DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok ->
            Logger.info("Stopped MCP connection: #{name}")
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  List all active MCP connections.
  """
  def list_connections do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {id, pid, _type, _modules} -> {id, pid} end)
  end

  @doc """
  Get the status of a connection by name.
  """
  def connection_status(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> {:error, :not_found}
      pid -> Jidoka.Protocol.MCP.Client.status(pid)
    end
  end

  @doc """
  Start all configured MCP servers from application config.
  """
  def start_configured_servers do
    case Application.get_env(:jidoka, :mcp_servers) do
      nil ->
        :ok

      servers when is_map(servers) ->
        Enum.each(servers, fn {_key, opts} ->
          start_connection(opts)
        end)

      _ ->
        Logger.warning("Invalid :mcp_servers configuration")
    end
  end

  ## Supervisor Callbacks

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
