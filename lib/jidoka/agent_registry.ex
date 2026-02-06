defmodule Jidoka.AgentRegistry do
  @moduledoc """
  Wrapper module for the unique Agent Registry with access controls.

  This registry manages processes with unique keys - each key can only be
  associated with one process at a time. This is ideal for single-instance
  processes like agents, supervisors, and named services.

  ## Key Naming Conventions

  Agent keys follow the pattern: `"agent:<name>"` or `"session:<id>"`

  * `"agent:coordinator"` - The main coordinator agent
  * `"agent:llm"` - The LLM agent
  * `"agent:analyzer"` - The code analyzer agent
  * `"session:<uuid>"` - A user session

  ## Access Controls

  Keys must match the pattern: `^[a-z][a-z0-9_]*:[a-z0-9_-]+$`

  Valid examples:
  - `"agent:coordinator"`
  - `"session:abc-123"`
  - `"agent:llm_gpt4"`

  Invalid examples:
  - `"coordinator"` (missing type prefix)
  - `"Agent:foo"` (uppercase not allowed)
  - `"agent:foo bar"` (spaces not allowed)

  Reserved key prefixes (restricted):
  - `"system:*"` - System processes (requires special authorization)

  ## Ownership

  Only the process that registered a key can unregister it. This prevents
  processes from accidentally removing each other's registrations.

  ## Examples

  Register the current process:

      iex> Jidoka.AgentRegistry.register("agent:coordinator")
      {:ok, "agent:coordinator"}

  Look up a process by key:

      iex> Jidoka.AgentRegistry.lookup("agent:coordinator")
      {:ok, pid}

  Dispatch a message to the registered process:

      iex> Jidoka.AgentRegistry.dispatch("agent:coordinator", {:process, data})
      :ok

  Unregister the current process:

      iex> Jidoka.AgentRegistry.unregister("agent:coordinator")
      :ok

  """

  @registry_name __MODULE__
  @key_pattern ~r/^[a-z][a-z0-9_]*:[a-z0-9_-]+$/
  @reserved_prefixes ["system"]

  @type key :: String.t()
  @type registration_result ::
          {:ok, key} | {:error, :invalid_key | :already_registered | :reserved_key}
  @type lookup_result :: {:ok, pid} | :error

  @doc """
  Returns the Registry process name.
  """
  @spec registry_name() :: atom()
  def registry_name, do: @registry_name

  @doc """
  Validates a key against the allowed pattern.

  ## Examples

      iex> Jidoka.AgentRegistry.valid_key?("agent:coordinator")
      true

      iex> Jidoka.AgentRegistry.valid_key?("invalid")
      false

  """
  @spec valid_key?(String.t()) :: boolean()
  def valid_key?(key) when is_binary(key) do
    Regex.match?(@key_pattern, key) and not reserved_key?(key)
  end

  def valid_key?(_), do: false

  @doc """
  Registers the current process under the given key.

  The key must be unique - if another process is already registered
  under this key, the function returns `{:error, reason}`.

  ## Access Control

  Keys must match the pattern `^[a-z][a-z0-9_]*:[a-z0-9_-]+$` and cannot
  use reserved prefixes like "system".

  ## Options

  * `:key` - The registration key (defaults to the provided key argument)

  ## Examples

      iex> Jidoka.AgentRegistry.register("agent:coordinator")
      {:ok, "agent:coordinator"}

      iex> Jidoka.AgentRegistry.register("invalid-key")
      {:error, :invalid_key}

  """
  @spec register(key(), Keyword.t()) :: registration_result()
  def register(key, opts \\ []) when is_binary(key) do
    actual_key = Keyword.get(opts, :key, key)

    with true <- valid_key?(actual_key),
         {:ok, _} <- Registry.register(@registry_name, actual_key, []) do
      {:ok, actual_key}
    else
      false -> {:error, :invalid_key}
      {:error, {:already_registered, _}} -> {:error, :already_registered}
      {:error, _} = error -> error
    end
  end

  @doc """
  Looks up a process by key.

  Returns `{:ok, pid}` if a process is registered under the key,
  or `:error` if not found.

  ## Examples

      iex> Jidoka.AgentRegistry.lookup("agent:coordinator")
      {:ok, #PID<0.123.0>}

  """
  @spec lookup(key()) :: lookup_result()
  def lookup(key) when is_binary(key) do
    case Registry.lookup(@registry_name, key) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Unregisters the current process from the given key.

  ## Ownership

  Only the process that registered the key can unregister it. This prevents
  processes from accidentally removing each other's registrations.

  ## Examples

      iex> Jidoka.AgentRegistry.unregister("agent:coordinator")
      :ok

  """
  @spec unregister(key()) :: :ok
  def unregister(key) when is_binary(key) do
    Registry.unregister(@registry_name, key)
  end

  @doc """
  Dispatches a message to the process registered under the given key.

  The message is sent as `{sender, message}` where sender is the PID
  of the calling process.

  ## Options

  * `:from` - The sender PID (defaults to self())

  ## Examples

      iex> Jidoka.AgentRegistry.dispatch("agent:coordinator", {:process, data})
      :ok

  """
  @spec dispatch(key(), term(), Keyword.t()) :: :ok | :error
  def dispatch(key, message, opts \\ []) when is_binary(key) do
    from = Keyword.get(opts, :from, self())

    # Check if key is registered first
    case Registry.lookup(@registry_name, key) do
      [] ->
        :error

      _entries ->
        Registry.dispatch(@registry_name, key, fn entries ->
          for {pid, _} <- entries do
            send(pid, {from, message})
          end
        end)

        :ok
    end
  end

  @doc """
  Returns the number of processes registered under the given key.

  ## Examples

      iex> Jidoka.AgentRegistry.count("agent:coordinator")
      1

  """
  @spec count(key()) :: non_neg_integer()
  def count(key) when is_binary(key) do
    case Registry.select(@registry_name, [
           {{:"$1", :"$2", :"$3"}, [{:==, :"$1", key}], [{{:"$2"}}]}
         ]) do
      [] -> 0
      pids -> length(pids)
    end
  end

  @doc """
  Returns all registered keys.

  ## Examples

      iex> Jidoka.AgentRegistry.list_keys()
      ["agent:coordinator", "agent:llm"]

  """
  @spec list_keys() :: [key()]
  def list_keys do
    Registry.select(@registry_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Checks if a process is registered under the given key.

  ## Examples

      iex> Jidoka.AgentRegistry.registered?("agent:coordinator")
      true

  """
  @spec registered?(key()) :: boolean()
  def registered?(key) when is_binary(key) do
    case lookup(key) do
      {:ok, _pid} -> true
      :error -> false
    end
  end

  # Private Functions

  defp reserved_key?(key) do
    prefix = key |> String.split(":", parts: 2) |> List.first()
    prefix in @reserved_prefixes
  end
end
