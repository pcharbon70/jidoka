defmodule Jidoka.ProtocolSupervisor do
  @moduledoc """
  Supervisor for all protocol connections (MCP, Phoenix, A2A, etc.).

  This supervisor manages protocol-specific connection supervisors,
  providing a unified interface for protocol lifecycle management
  and health monitoring.

  ## Supervision Tree

      Jidoka.Supervisor
        └── Jidoka.ProtocolSupervisor (DynamicSupervisor)
              ├── Jidoka.Protocol.MCP.ConnectionSupervisor
              ├── Jidoka.Protocol.Phoenix.ConnectionSupervisor
              └── Jidoka.Protocol.A2A.ConnectionSupervisor

  ## Examples

      # List all active protocols
      Jidoka.ProtocolSupervisor.list_protocols()
      => [{Jidoka.Protocol.MCP.ConnectionSupervisor, #PID<...>}]

      # Get aggregated health status
      Jidoka.ProtocolSupervisor.health()
      => %{
        mcp: %{status: :healthy, active_connections: 2},
        phoenix: %{status: :healthy, active_connections: 1},
        a2a: %{status: :healthy, active_gateways: 1}
      }

      # Start a protocol dynamically
      {:ok, pid} = Jidoka.ProtocolSupervisor.start_protocol(
        Jidoka.Protocol.MCP.ConnectionSupervisor,
        []
      )

      # Stop a protocol
      :ok = Jidoka.ProtocolSupervisor.stop_protocol(
        Jidoka.Protocol.MCP.ConnectionSupervisor
      )

      # Get individual protocol status
      Jidoka.ProtocolSupervisor.protocol_status(
        Jidoka.Protocol.MCP.ConnectionSupervisor
      )
  """

  use DynamicSupervisor
  require Logger

  @doc """
  Start the protocol supervisor.
  """
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  List all active protocol supervisors.

  Returns a list of `{module, pid}` tuples for each protocol.
  """
  def list_protocols do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn
      {_id, pid, _type, [module]} when is_atom(module) -> {module, pid}
      {_id, pid, _type, modules} when is_list(modules) -> {List.first(modules), pid}
      {id, pid, _type, _modules} -> {id, pid}
    end)
  end

  @doc """
  Get aggregated health status for all protocols.

  Returns a map with protocol types as keys and their health status as values.
  """
  def health do
    protocols = %{
      mcp: Jidoka.Protocol.MCP.ConnectionSupervisor,
      phoenix: Jidoka.Protocol.Phoenix.ConnectionSupervisor,
      a2a: Jidoka.Protocol.A2A.ConnectionSupervisor
    }

    Enum.reduce(protocols, %{}, fn {type, module}, acc ->
      Map.put(acc, type, get_protocol_health(type, module))
    end)
  end

  @doc """
  Get the status of a specific protocol supervisor.

  Returns a status map with connection/activity information.
  """
  def protocol_status(protocol_module) when is_atom(protocol_module) do
    case find_protocol_pid(protocol_module) do
      {:ok, pid} ->
        get_status_from_module(protocol_module, pid)

      {:error, :not_found} ->
        %{status: :not_found, pid: nil}
    end
  end

  @doc """
  Start a protocol supervisor dynamically.

  ## Options

  * `:restart` - Restart strategy (default: :permanent)
  * `:shutdown` - Shutdown timeout (default: 5000)
  * `:timeout` - Start timeout (default: :infinity)

  """
  def start_protocol(protocol_module, opts \\ []) when is_atom(protocol_module) do
    if find_protocol_pid(protocol_module) == {:error, :not_found} do
      child_spec = %{
        id: protocol_module,
        start: {protocol_module, :start_link, [opts]},
        restart: Keyword.get(opts, :restart, :permanent),
        shutdown: Keyword.get(opts, :shutdown, 5000),
        type: :supervisor
      }

      case DynamicSupervisor.start_child(__MODULE__, child_spec) do
        {:ok, pid} ->
          Logger.info("Started protocol: #{protocol_module}")
          {:ok, pid}

        {:error, {:already_started, pid}} ->
          {:ok, pid}

        {:error, reason} = error ->
          Logger.error("Failed to start protocol #{protocol_module}: #{inspect(reason)}")
          error
      end
    else
      {:ok, _pid} = find_protocol_pid(protocol_module)
    end
  end

  @doc """
  Stop a protocol supervisor.

  Returns `:ok` if the protocol was stopped, `{:error, reason}` otherwise.
  """
  def stop_protocol(protocol_module) when is_atom(protocol_module) do
    case find_protocol_pid(protocol_module) do
      {:ok, pid} ->
        case DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok ->
            Logger.info("Stopped protocol: #{protocol_module}")
            :ok

          {:error, reason} = error ->
            Logger.error("Failed to stop protocol #{protocol_module}: #{inspect(reason)}")
            error
        end

      {:error, :not_found} = error ->
        error
    end
  end

  @doc """
  Start all configured protocols from application config.

  This is called automatically on application start.
  """
  def start_configured_protocols do
    # MCP Protocol
    if Application.get_env(:jidoka, :mcp_servers) do
      start_protocol(Jidoka.Protocol.MCP.ConnectionSupervisor)
    end

    # Phoenix Protocol
    if Application.get_env(:jidoka, :phoenix_connections) do
      start_protocol(Jidoka.Protocol.Phoenix.ConnectionSupervisor)
    end

    # A2A Protocol
    if Application.get_env(:jidoka, :a2a_gateway) do
      start_protocol(Jidoka.Protocol.A2A.ConnectionSupervisor)
    end

    :ok
  end

  ## Supervisor Callbacks

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  ## Private Helpers

  defp find_protocol_pid(protocol_module) do
    case Process.whereis(protocol_module) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  defp get_protocol_health(type, module) do
    case find_protocol_pid(module) do
      {:ok, _pid} ->
        get_health_from_module(type, module)

      {:error, :not_found} ->
        %{status: :not_running}
    end
  end

  defp get_health_from_module(:mcp, _module) do
    case Jidoka.Protocol.MCP.ConnectionSupervisor.list_connections() do
      [] -> %{status: :healthy, active_connections: 0}
      connections -> %{status: :healthy, active_connections: length(connections)}
    end
  rescue
    _ -> %{status: :error, error: "Failed to get MCP health"}
  end

  defp get_health_from_module(:phoenix, _module) do
    case Jidoka.Protocol.Phoenix.ConnectionSupervisor.list_connections() do
      [] -> %{status: :healthy, active_connections: 0}
      connections -> %{status: :healthy, active_connections: length(connections)}
    end
  rescue
    _ -> %{status: :error, error: "Failed to get Phoenix health"}
  end

  defp get_health_from_module(:a2a, _module) do
    case Jidoka.Protocol.A2A.ConnectionSupervisor.list_gateways() do
      [] -> %{status: :healthy, active_gateways: 0}
      gateways -> %{status: :healthy, active_gateways: length(gateways)}
    end
  rescue
    _ -> %{status: :error, error: "Failed to get A2A health"}
  end

  defp get_status_from_module(Jidoka.Protocol.MCP.ConnectionSupervisor, _pid) do
    connections = Jidoka.Protocol.MCP.ConnectionSupervisor.list_connections()
    %{
      status: :running,
      type: :mcp,
      active_connections: length(connections),
      connections: Enum.map(connections, fn {id, _pid} -> id end)
    }
  rescue
    _ -> %{status: :error, type: :mcp}
  end

  defp get_status_from_module(Jidoka.Protocol.Phoenix.ConnectionSupervisor, _pid) do
    connections = Jidoka.Protocol.Phoenix.ConnectionSupervisor.list_connections()
    %{
      status: :running,
      type: :phoenix,
      active_connections: length(connections),
      connections: Enum.map(connections, fn {id, _pid} -> id end)
    }
  rescue
    _ -> %{status: :error, type: :phoenix}
  end

  defp get_status_from_module(Jidoka.Protocol.A2A.ConnectionSupervisor, _pid) do
    gateways = Jidoka.Protocol.A2A.ConnectionSupervisor.list_gateways()
    %{
      status: :running,
      type: :a2a,
      active_gateways: length(gateways),
      gateways: Enum.map(gateways, fn {id, _pid} -> id end)
    }
  rescue
    _ -> %{status: :error, type: :a2a}
  end

  defp get_status_from_module(_module, _pid) do
    %{status: :unknown}
  end
end
