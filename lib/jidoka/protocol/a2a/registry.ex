defmodule Jidoka.Protocol.A2A.Registry do
  @moduledoc """
  Registry for tracking local agents that accept external A2A messages.

  This registry maintains a mapping between agent IDs and process PIDs,
  allowing the A2A Gateway to route incoming messages to the correct
  local agents.

  ## Registration

  Agents must explicitly register to receive external A2A messages.

  ## Examples

      # Register an agent to receive A2A messages
      Registry.register(:my_agent, self())

      # Lookup an agent's PID
      {:ok, pid} = Registry.lookup(:my_agent)

      # Route a message to an agent
      Registry.send_message(:my_agent, {:a2a_message, %{...}})

      # Unregister when done
      Registry.unregister(:my_agent)

  """

  use GenServer
  require Logger

  @table_name :a2a_agent_registry
  @type agent_id :: atom() | String.t()

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts the A2A Agent Registry.

  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an agent to receive external A2A messages.

  ## Parameters

  - `agent_id` - Unique identifier for the agent (atom or string)
  - `pid` - The process PID that will handle messages

  ## Returns

  - `:ok` - Successfully registered
  - `{:error, :already_registered}` - Agent ID already in use

  ## Examples

      :ok = Registry.register(:coordinator, self())
      :ok = Registry.register("custom_agent", some_pid)

  """
  @spec register(agent_id(), pid()) :: :ok | {:error, term()}
  def register(agent_id, pid \\ self()) when is_atom(agent_id) or is_binary(agent_id) do
    GenServer.call(__MODULE__, {:register, agent_id, pid})
  end

  @doc """
  Unregisters an agent from receiving A2A messages.

  ## Parameters

  - `agent_id` - The agent ID to unregister

  ## Returns

  - `:ok` - Successfully unregistered (or not registered)
  - `{:error, reason}` - Failed to unregister

  ## Examples

      :ok = Registry.unregister(:coordinator)

  """
  @spec unregister(agent_id()) :: :ok | {:error, term()}
  def unregister(agent_id) when is_atom(agent_id) or is_binary(agent_id) do
    GenServer.call(__MODULE__, {:unregister, agent_id})
  end

  @doc """
  Looks up an agent's PID by agent ID.

  ## Parameters

  - `agent_id` - The agent ID to look up

  ## Returns

  - `{:ok, pid}` - Agent found
  - `{:error, :not_found}` - Agent not registered

  ## Examples

      {:ok, pid} = Registry.lookup(:coordinator)
      {:error, :not_found} = Registry.lookup(:unknown_agent)

  """
  @spec lookup(agent_id()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(agent_id) when is_atom(agent_id) or is_binary(agent_id) do
    GenServer.call(__MODULE__, {:lookup, agent_id})
  end

  @doc """
  Lists all registered agents.

  ## Returns

  - List of `{agent_id, pid}` tuples

  ## Examples

      agents = Registry.list_agents()
      # => [{:coordinator, #PID<0.123.0>}, {"agent:external:456", #PID<0.124.0>}]

  """
  @spec list_agents() :: [{agent_id(), pid()}]
  def list_agents do
    GenServer.call(__MODULE__, :list_agents)
  end

  @doc """
  Checks if an agent is registered.

  ## Examples

      true = Registry.registered?(:coordinator)
      false = Registry.registered?(:unknown)

  """
  @spec registered?(agent_id()) :: boolean()
  def registered?(agent_id) when is_atom(agent_id) or is_binary(agent_id) do
    GenServer.call(__MODULE__, {:registered?, agent_id})
  end

  @doc """
  Sends a message to a registered agent.

  ## Parameters

  - `agent_id` - The agent to send to
  - `message` - The message to send

  ## Returns

  - `:ok` - Message sent
  - `{:error, :not_found}` - Agent not registered

  ## Examples

      :ok = Registry.send_message(:coordinator, {:a2a_request, request})

  """
  @spec send_message(agent_id(), term()) :: :ok | {:error, :not_found}
  def send_message(agent_id, message) when is_atom(agent_id) or is_binary(agent_id) do
    GenServer.call(__MODULE__, {:send_message, agent_id, message})
  end

  @doc """
  Gets the count of registered agents.

  ## Examples

      count = Registry.count()
      # => 3

  """
  @spec count() :: non_neg_integer()
  def count do
    GenServer.call(__MODULE__, :count)
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================

  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    table =
      :ets.new(@table_name, [
        :named_table,
        :set,
        :public,
        read_concurrency: true
      ])

    Logger.debug("A2A Agent Registry started with table: #{inspect(table)}")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, agent_id, pid}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [] ->
        # Register the agent and monitor the process
        ref = Process.monitor(pid)
        :ets.insert(state.table, {agent_id, pid, ref})
        Logger.debug("Registered A2A agent: #{agent_id} -> #{inspect(pid)}")
        {:reply, :ok, state}

      [{^agent_id, _pid, _ref}] ->
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl true
  def handle_call({:unregister, agent_id}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [{^agent_id, _pid, ref}] ->
        :ets.delete(state.table, agent_id)
        Process.demonitor(ref)
        Logger.debug("Unregistered A2A agent: #{agent_id}")
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:lookup, agent_id}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [{^agent_id, pid, _ref}] ->
        {:reply, {:ok, pid}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    agents =
      :ets.tab2list(state.table)
      |> Enum.map(fn {agent_id, pid, _ref} -> {agent_id, pid} end)

    {:reply, agents, state}
  end

  @impl true
  def handle_call({:registered?, agent_id}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [{_agent_id, _pid, _ref}] -> {:reply, true, state}
      [] -> {:reply, false, state}
    end
  end

  @impl true
  def handle_call({:send_message, agent_id, message}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [{^agent_id, pid, _ref}] ->
        send(pid, message)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:count, _from, state) do
    count = :ets.info(state.table, :size)
    {:reply, count, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Find and remove the dead process
    entries = :ets.tab2list(state.table)

    Enum.each(entries, fn
      {agent_id, _pid, ^ref} ->
        :ets.delete(state.table, agent_id)
        Logger.debug("Auto-unregistered dead A2A agent: #{agent_id}")

      _ ->
        :ok
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
