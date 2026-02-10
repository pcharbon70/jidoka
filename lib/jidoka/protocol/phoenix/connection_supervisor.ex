defmodule Jidoka.Protocol.Phoenix.ConnectionSupervisor do
  @moduledoc """
  Dynamic supervisor for Phoenix Channels connections.

  This supervisor manages multiple Phoenix client connections,
  allowing for dynamic addition and removal of connections.

  ## Configuration

  Add Phoenix connections to your config:

      config :jidoka, :phoenix_connections,
        backend_service: [
          name: :phoenix_backend,
          uri: "ws://localhost:4000/socket/websocket",
          headers: [{"X-API-Key", "your-api-key"}],
          params: %{token: "auth-token"},
          auto_join_channels: [{"room:lobby", %{}}]
        ]

  ## Example

      # Start a connection manually
      {:ok, pid} = Jidoka.Protocol.Phoenix.ConnectionSupervisor.start_connection(
        name: :my_connection,
        uri: "ws://localhost:4000/socket/websocket"
      )

      # Stop a connection
      :ok = Jidoka.Protocol.Phoenix.ConnectionSupervisor.stop_connection(:my_connection)

      # List active connections
      connections = Jidoka.Protocol.Phoenix.ConnectionSupervisor.list_connections()
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
  Start a Phoenix connection with the given configuration.

  ## Options

  * `:name` - Name to register the connection (required, atom)
  * `:uri` - WebSocket endpoint URL (required, e.g., `"ws://localhost:4000/socket/websocket"`)
  * `:headers` - List of `{header_name, value}` tuples (optional, default: `[]`)
  * `:params` - Map of connection parameters (optional, default: `%{}`)
  * `:auto_join_channels` - List of `{topic, params}` tuples to join on connect (optional)
  * `:max_retries` - Maximum reconnection attempts (optional, default: 10)
  """
  def start_connection(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    _uri = Keyword.fetch!(opts, :uri)

    child_spec = %{
      id: name,
      start: {Jidoka.Protocol.Phoenix.Client, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started Phoenix connection: #{name}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Phoenix connection #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop a Phoenix connection by name.
  """
  def stop_connection(name) when is_atom(name) do
    case Process.whereis(name) do
      nil ->
        {:error, :not_found}

      pid ->
        case DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok ->
            Logger.info("Stopped Phoenix connection: #{name}")
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  List all active Phoenix connections.
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
      pid -> GenServer.call(pid, :status)
    end
  end

  @doc """
  Start all configured Phoenix connections from application config.
  """
  def start_configured_connections do
    case Application.get_env(:jidoka, :phoenix_connections) do
      nil ->
        :ok

      connections when is_map(connections) ->
        Enum.each(connections, fn {_key, opts} ->
          start_connection(opts)
        end)

      _ ->
        Logger.warning("Invalid :phoenix_connections configuration")
    end
  end

  ## Supervisor Callbacks

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
