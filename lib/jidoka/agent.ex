defmodule Jidoka.Agent do
  @moduledoc """
  Base utilities module for Jidoka agents.

  This module provides common helper functions that complement Jido 2.0's
  agent framework. Since Jido.Agent already provides the behavior definition
  and lifecycle management, this module focuses on jidoka-specific
  utilities for:

  - Task ID generation and tracking
  - Session validation
  - Error handling patterns
  - Agent discovery and registry helpers

  ## Task ID Generation

  Generate unique task IDs for tracking operations across the system:

      iex> task_id = Jidoka.Agent.generate_task_id("analysis")
      iex> String.starts_with?(task_id, "analysis_")
      true

  ## Session Validation

  Validate session IDs and session-related data:

      iex> Jidoka.Agent.valid_session_id?("session-abc-123")
      true

      iex> Jidoka.Agent.valid_session_id?("invalid!")
      false

  ## Error Handling

  Create standardized error responses for agent actions:

      iex> Jidoka.Agent.error_response(:validation_failed, %{field: :session_id})
      {:error, %{type: :validation_failed, details: %{field: :session_id}}}

  ## Agent Discovery

  Find and query agents across both Jido's registry and the custom AgentRegistry:

      iex> {:ok, pid} = Jidoka.Agent.find_agent("coordinator")
      iex> is_pid(pid)
      true

      iex> agents = Jidoka.Agent.list_agents()
      iex> is_list(agents)
      true

  """

  alias Jidoka.PubSub
  alias Jidoka.AgentRegistry

  @type task_id :: String.t()
  @type session_id :: String.t()
  @type error_response :: {:error, %{type: atom(), details: map()}}
  @type agent_id :: String.t()
  @type agent_name :: String.t()
  @type agent_result :: {:ok, pid()} | :error

  @doc """
  Generates a unique task ID for tracking operations.

  Task IDs follow the pattern: `{prefix}_{session_id}_{unique_integer}`
  or `{prefix}_{unique_integer}` if no session_id is provided.

  ## Options

  * `:session_id` - Optional session ID to include in the task ID

  ## Examples

      iex> task_id = Jidoka.Agent.generate_task_id("analysis")
      iex> String.starts_with?(task_id, "analysis_")
      true

      iex> task_id = Jidoka.Agent.generate_task_id("chat", session_id: "session-123")
      iex> String.contains?(task_id, "session-123")
      true

  """
  @spec generate_task_id(String.t(), Keyword.t()) :: task_id()
  def generate_task_id(prefix, opts \\ []) when is_binary(prefix) do
    session_id = Keyword.get(opts, :session_id)
    unique = System.unique_integer([:positive, :monotonic])

    case session_id do
      nil -> "#{prefix}_#{unique}"
      sid -> "#{prefix}_#{sid}_#{unique}"
    end
  end

  @doc """
  Validates a session ID format.

  Session IDs must be non-empty strings and match the basic pattern.

  ## Examples

      iex> Jidoka.Agent.valid_session_id?("session-abc-123")
      true

      iex> Jidoka.Agent.valid_session_id?(nil)
      false

      iex> Jidoka.Agent.valid_session_id?("")
      false

  """
  @spec valid_session_id?(term()) :: boolean()
  def valid_session_id?(nil), do: false
  def valid_session_id?(""), do: false

  def valid_session_id?(session_id) when is_binary(session_id) do
    String.length(session_id) > 0 and String.trim(session_id) == session_id
  end

  def valid_session_id?(_), do: false

  @doc """
  Validates session-related data map.

  Checks that the map contains a valid :session_id field.

  ## Examples

      iex> Jidoka.Agent.validate_session_data(%{session_id: "session-123"})
      {:ok, %{session_id: "session-123"}}

      iex> Jidoka.Agent.validate_session_data(%{session_id: nil})
      {:error, :invalid_session_id}

      iex> Jidoka.Agent.validate_session_data(%{})
      {:error, :missing_session_id}

  """
  @spec validate_session_data(map()) :: {:ok, map()} | {:error, atom()}
  def validate_session_data(data) when is_map(data) do
    case Map.fetch(data, :session_id) do
      :error ->
        {:error, :missing_session_id}

      {:ok, nil} ->
        {:error, :invalid_session_id}

      {:ok, session_id} ->
        if valid_session_id?(session_id) do
          {:ok, data}
        else
          {:error, :invalid_session_id}
        end
    end
  end

  @doc """
  Creates a standardized error response for agent actions.

  ## Examples

      iex> Jidoka.Agent.error_response(:validation_failed, %{field: :session_id})
      {:error, %{type: :validation_failed, details: %{field: :session_id}}}

  """
  @spec error_response(atom(), map()) :: error_response()
  def error_response(type, details \\ %{}) when is_atom(type) and is_map(details) do
    {:error, %{type: type, details: details}}
  end

  @doc """
  Creates a standardized ok response for agent actions.

  ## Examples

      iex> Jidoka.Agent.ok_response(%{status: :processed})
      {:ok, %{status: :processed}}

  """
  @spec ok_response(map()) :: {:ok, map()}
  def ok_response(result) when is_map(result) do
    {:ok, result}
  end

  @doc """
  Returns the client events topic name.

  This is a convenience function that delegates to PubSub.client_events_topic/0.

  ## Examples

      iex> Jidoka.Agent.client_events_topic()
      "jido.client.events"

  """
  @spec client_events_topic() :: String.t()
  def client_events_topic, do: PubSub.client_events_topic()

  @doc """
  Returns a session-specific topic name.

  This is a convenience function that delegates to PubSub.session_topic/1.

  ## Examples

      iex> Jidoka.Agent.session_topic("session-123")
      "jido.session.session-123"

  """
  @spec session_topic(session_id()) :: String.t()
  def session_topic(session_id), do: PubSub.session_topic(session_id)

  @doc """
  Returns the PubSub process name.

  This is a convenience function that delegates to PubSub.pubsub_name/0.

  ## Examples

      iex> Jidoka.Agent.pubsub_name()
      :jido_coder_pubsub

  """
  @spec pubsub_name() :: atom()
  def pubsub_name, do: PubSub.pubsub_name()

  # ============================================================================
  # Agent Discovery and Registry Helpers
  # ============================================================================

  @doc """
  Returns the Jido instance for advanced operations.

  This provides access to the Jido instance for use with Jido's
  built-in functions like `Jido.whereis/2`, `Jido.list_agents/1`, etc.

  ## Examples

      iex> Jidoka.Agent.jido_instance()
      Jidoka.Jido

  """
  @spec jido_instance() :: atom()
  def jido_instance, do: Jidoka.Jido

  @doc """
  Finds an agent by name, checking both Jido's registry and the custom AgentRegistry.

  This function provides a unified lookup that:
  1. First checks Jido's registry using `Jido.whereis/2`
  2. Falls back to the custom AgentRegistry with "agent:" prefix

  ## Parameters

  * `name` - The agent name (with or without "agent:" prefix)

  ## Returns

  * `{:ok, pid}` - If the agent is found
  * `:error` - If the agent is not found

  ## Examples

      # Find by bare name (checks Jido registry first)
      iex> Jidoka.Agent.find_agent("coordinator")
      {:ok, #PID<0.123.0>}

      # Find by full agent registry key
      iex> Jidoka.Agent.find_agent("agent:coordinator")
      {:ok, #PID<0.123.0>}

      # Not found
      iex> Jidoka.Agent.find_agent("nonexistent")
      :error

  """
  @spec find_agent(agent_name()) :: agent_result()
  def find_agent(name) when is_binary(name) do
    # First try Jido's registry (bare name)
    case find_agent_by_id(name) do
      {:ok, _pid} = result ->
        result

      :error ->
        # Fall back to custom registry (with agent: prefix)
        find_agent_by_name(name)
    end
  end

  @doc """
  Finds an agent in Jido's built-in registry by agent ID.

  Uses `Jido.whereis/2` to look up agents registered with Jido.

  ## Parameters

  * `agent_id` - The agent ID in Jido's registry

  ## Returns

  * `{:ok, pid}` - If the agent is found
  * `:error` - If the agent is not found (returns nil)

  ## Examples

      iex> Jidoka.Agent.find_agent_by_id("coordinator-main")
      {:ok, #PID<0.123.0>}

      iex> Jidoka.Agent.find_agent_by_id("nonexistent")
      :error

  """
  @spec find_agent_by_id(agent_id()) :: agent_result()
  def find_agent_by_id(agent_id) when is_binary(agent_id) do
    case Jido.whereis(jido_instance(), agent_id) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> :error
    end
  end

  def find_agent_by_id(_), do: :error

  @doc """
  Finds an agent in the custom AgentRegistry by name.

  Automatically adds the "agent:" prefix if not present.

  ## Parameters

  * `name` - The agent name (with or without "agent:" prefix)

  ## Returns

  * `{:ok, pid}` - If the agent is found
  * `:error` - If the agent is not found

  ## Examples

      iex> Jidoka.Agent.find_agent_by_name("coordinator")
      {:ok, #PID<0.123.0>}

      iex> Jidoka.Agent.find_agent_by_name("agent:coordinator")
      {:ok, #PID<0.123.0>}

      iex> Jidoka.Agent.find_agent_by_name("nonexistent")
      :error

  """
  @spec find_agent_by_name(agent_name()) :: agent_result()
  def find_agent_by_name(name) when is_binary(name) do
    key = if String.starts_with?(name, "agent:"), do: name, else: "agent:#{name}"
    AgentRegistry.lookup(key)
  end

  @doc """
  Lists all registered agents from both registries.

  Returns a combined list of unique agent PIDs from:
  1. Jido's registry (via `Jido.list_agents/1`)
  2. Custom AgentRegistry (keys starting with "agent:")

  ## Returns

  * List of `{agent_id, pid}` tuples where agent_id is the identifier

  ## Examples

      iex> Jidoka.Agent.list_agents()
      [{"coordinator-main", #PID<0.123.0>}, {"llm-main", #PID<0.124.0>}]

  """
  @spec list_agents() :: [{String.t(), pid()}]
  def list_agents do
    jido_agents = list_jido_agents()
    registered_agents = list_registered_agents()

    # Combine and deduplicate by PID
    (jido_agents ++ registered_agents)
    |> Enum.uniq_by(fn {_id, pid} -> pid end)
  end

  @doc """
  Lists all agents from Jido's built-in registry.

  Uses `Jido.list_agents/1` to get all agents registered with Jido.

  ## Returns

  * List of `{agent_id, pid}` tuples

  ## Examples

      iex> Jidoka.Agent.list_jido_agents()
      [{"coordinator-main", #PID<0.123.0>}]

  """
  @spec list_jido_agents() :: [{String.t(), pid()}]
  def list_jido_agents do
    case Jido.list_agents(jido_instance()) do
      agents when is_list(agents) ->
        Enum.map(agents, fn
          # Handle map format (may be returned by some versions)
          agent when is_map(agent) ->
            id = Map.get(agent, :id, "unknown")
            pid = Map.get(agent, :pid)
            {id, pid}

          # Handle tuple format
          {id, pid} when is_binary(id) and is_pid(pid) ->
            {id, pid}

          # Handle tuple with nil pid
          {id, nil} when is_binary(id) ->
            {id, nil}

          # Skip malformed entries
          _ ->
            nil
        end)
        |> Enum.filter(&(&1 != nil))

      _error ->
        []
    end
  end

  @doc """
  Lists all agents from the custom AgentRegistry.

  Returns agents registered with keys starting with "agent:".

  ## Returns

  * List of `{agent_name, pid}` tuples

  ## Examples

      iex> Jidoka.Agent.list_registered_agents()
      [{"coordinator", #PID<0.123.0>}, {"llm", #PID<0.124.0>}]

  """
  @spec list_registered_agents() :: [{String.t(), pid()}]
  def list_registered_agents do
    AgentRegistry.list_keys()
    |> Enum.filter(&String.starts_with?(&1, "agent:"))
    |> Enum.map(fn key ->
      case AgentRegistry.lookup(key) do
        {:ok, pid} ->
          # Remove "agent:" prefix for cleaner output
          name = String.replace_prefix(key, "agent:", "")
          {name, pid}

        :error ->
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

  @doc """
  Checks if an agent is alive (process exists).

  Uses `Process.alive?/1` to check if the agent process is still running.

  ## Parameters

  * `name` - The agent name

  ## Returns

  * `true` - If the agent is alive
  * `false` - If the agent is not found or not alive

  ## Examples

      iex> Jidoka.Agent.agent_active?("coordinator")
      true

      iex> Jidoka.Agent.agent_active?("nonexistent")
      false

  """
  @spec agent_active?(agent_name()) :: boolean()
  def agent_active?(name) when is_binary(name) do
    case find_agent(name) do
      {:ok, pid} -> Process.alive?(pid)
      :error -> false
    end
  end

  def agent_active?(_), do: false

  @doc """
  Checks if an agent is responsive (process exists and responds to ping).

  Uses `Process.alive?/1` to verify the agent process is running.
  For deeper health checks, agents should implement specific health actions.

  ## Parameters

  * `name` - The agent name
  * `timeout` - Unused, kept for API compatibility (default: 1000)

  ## Returns

  * `true` - If the agent is alive
  * `false` - If the agent is not found or not alive

  ## Examples

      iex> Jidoka.Agent.agent_responsive?("coordinator")
      true

      iex> Jidoka.Agent.agent_responsive?("nonexistent")
      false

  """
  @spec agent_responsive?(agent_name(), timeout()) :: boolean()
  def agent_responsive?(name, _timeout \\ 1000) when is_binary(name) do
    agent_active?(name)
  end

  @doc """
  Gets the coordinator agent PID.

  Convenience function to quickly find the coordinator agent.

  ## Returns

  * `{:ok, pid}` - If the coordinator is found
  * `:error` - If the coordinator is not found

  ## Examples

      iex> Jidoka.Agent.coordinator()
      {:ok, #PID<0.123.0>}

  """
  @spec coordinator() :: agent_result()
  def coordinator do
    find_agent("coordinator")
  end

  @doc """
  Checks if the coordinator agent is active.

  Convenience function to check coordinator status.

  ## Returns

  * `true` - If the coordinator is alive
  * `false` - If the coordinator is not found or not alive

  ## Examples

      iex> Jidoka.Agent.coordinator_active?()
      true

  """
  @spec coordinator_active?() :: boolean()
  def coordinator_active? do
    agent_active?("coordinator")
  end
end
