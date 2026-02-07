defmodule Jidoka.Protocol.A2A.ConnectionSupervisor do
  @moduledoc """
  Dynamic supervisor for A2A Gateway connections.

  This supervisor manages multiple A2A Gateway instances,
  allowing for dynamic addition and removal of gateway connections.

  ## Configuration

  Add A2A gateways to your config:

      config :jidoka, :a2a_gateways,
        default_gateway: [
          name: :a2a_gateway,
          agent_card: %{type: ["Coordinator"]}
        ]

  ## Example

      # Start a gateway manually
      {:ok, pid} = ConnectionSupervisor.start_gateway(
        name: :my_gateway,
        agent_card: %{type: ["CustomAgent"]}
      )

      # Stop a gateway
      :ok = ConnectionSupervisor.stop_gateway(:my_gateway)

      # List active gateways
      gateways = ConnectionSupervisor.list_gateways()

  """

  use DynamicSupervisor
  require Logger

  @doc """
  Starts the connection supervisor.
  """
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts an A2A Gateway with the given configuration.

  ## Options

  * `:name` - Name to register the gateway (required)
  * `:agent_card` - Agent card configuration (optional)
  * `:directory_url` - Agent directory URL (optional)
  * `:known_agents` - Static agent configuration (optional)
  * `:allowed_agents` - Local agents allowed to receive messages (optional)

  """
  def start_gateway(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    child_spec = %{
      id: name,
      start: {Jidoka.Protocol.A2A.Gateway, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started A2A Gateway: #{name}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start A2A Gateway #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops an A2A Gateway by name.
  """
  def stop_gateway(name) when is_atom(name) do
    case Process.whereis(name) do
      nil ->
        {:error, :not_found}

      pid ->
        case DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok ->
            Logger.info("Stopped A2A Gateway: #{name}")
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Lists all active A2A Gateways.
  """
  def list_gateways do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {id, pid, _type, _modules} -> {id, pid} end)
  end

  @doc """
  Gets the status of a gateway by name.
  """
  def gateway_status(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> {:error, :not_found}
      pid -> Jidoka.Protocol.A2A.Gateway.status(pid)
    end
  end

  @doc """
  Starts all configured A2A gateways from application config.
  """
  def start_configured_gateways do
    case Application.get_env(:jidoka, :a2a_gateways) do
      nil ->
        :ok

      gateways when is_map(gateways) ->
        Enum.each(gateways, fn {_key, opts} ->
          start_gateway(opts)
        end)

      _ ->
        Logger.warning("Invalid :a2a_gateways configuration")
    end
  end

  ## Supervisor Callbacks

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
