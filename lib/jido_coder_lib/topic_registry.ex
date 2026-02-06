defmodule JidoCoderLib.TopicRegistry do
  @moduledoc """
  Wrapper module for the duplicate Topic Registry with access controls.

  This registry manages processes with duplicate keys - multiple processes
  can register under the same key. This is ideal for pub/sub patterns where
  multiple subscribers want to receive messages for the same topic.

  ## Key Naming Conventions

  Topic keys follow the pattern: `"topic:<category>:<name>"`

  * `"topic:signal:file_changed"` - File system change events
  * `"topic:session:abc123"` - Session-specific events
  * `"topic:agent:llm"` - LLM agent events
  * `"topic:client:events"` - Client event broadcasts

  ## Access Controls

  Keys must match the pattern: `^topic:[a-z][a-z0-9_]*:[a-z0-9_-]+$`

  Valid examples:
  - `"topic:signal:file_changed"`
  - `"topic:session:abc-123"`
  - `"topic:client:events"`

  Invalid examples:
  - `"signal:file_changed"` (missing topic prefix)
  - `"topic:Signal:foo"` (uppercase not allowed)
  - `"topic:foo bar"` (spaces not allowed)

  ## Ownership

  Only the process that registered a key can unregister it.

  ## Examples

  Register the current process under a topic:

      iex> JidoCoderLib.TopicRegistry.register("topic:signal:file_changed")
      {:ok, "topic:signal:file_changed"}

  Look up all processes subscribed to a topic:

      iex> JidoCoderLib.TopicRegistry.lookup("topic:signal:file_changed")
      {:ok, [{pid1, _}, {pid2, _}]}

  Dispatch a message to all processes under the topic:

      iex> JidoCoderLib.TopicRegistry.dispatch("topic:signal:file_changed", {:changed, "/path/to/file"})
      {:ok, 2}

  Unregister the current process from a topic:

      iex> JidoCoderLib.TopicRegistry.unregister("topic:signal:file_changed")
      :ok

  """

  @registry_name __MODULE__
  @key_pattern ~r/^topic:[a-z][a-z0-9_]*:[a-z0-9_-]+$/

  @type key :: String.t()
  @type registration_result :: {:ok, key} | {:error, :invalid_key | term()}
  @type lookup_result :: {:ok, [{pid, term()}]} | :error
  @type dispatch_result :: {:ok, non_neg_integer()} | :error

  @doc """
  Returns the Registry process name.
  """
  @spec registry_name() :: atom()
  def registry_name, do: @registry_name

  @doc """
  Validates a key against the allowed pattern.

  ## Examples

      iex> JidoCoderLib.TopicRegistry.valid_key?("topic:signal:file_changed")
      true

      iex> JidoCoderLib.TopicRegistry.valid_key?("signal:file_changed")
      false

  """
  @spec valid_key?(String.t()) :: boolean()
  def valid_key?(key) when is_binary(key) do
    Regex.match?(@key_pattern, key)
  end

  def valid_key?(_), do: false

  @doc """
  Registers the current process under the given key.

  Multiple processes can register under the same key (duplicate keys).

  ## Access Control

  Keys must match the pattern `^topic:[a-z][a-z0-9_]*:[a-z0-9_-]+$`.

  ## Options

  * `:key` - The registration key (defaults to the provided key argument)

  ## Examples

      iex> JidoCoderLib.TopicRegistry.register("topic:signal:file_changed")
      {:ok, "topic:signal:file_changed"}

      iex> JidoCoderLib.TopicRegistry.register("invalid-key")
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
      {:error, _} = error -> error
    end
  end

  @doc """
  Looks up all processes registered under the given key.

  Returns `{:ok, [{pid, value}]}` if processes are found, or `:error` if none.

  ## Examples

      iex> JidoCoderLib.TopicRegistry.lookup("topic:signal:file_changed")
      {:ok, [{#PID<0.123.0>, nil}, {#PID<0.124.0>, nil}]}

  """
  @spec lookup(key()) :: lookup_result()
  def lookup(key) when is_binary(key) do
    case Registry.lookup(@registry_name, key) do
      [] -> :error
      entries -> {:ok, entries}
    end
  end

  @doc """
  Unregisters the current process from the given key.

  ## Ownership

  Only the process that registered the key can unregister it.

  ## Examples

      iex> JidoCoderLib.TopicRegistry.unregister("topic:signal:file_changed")
      :ok

  """
  @spec unregister(key()) :: :ok
  def unregister(key) when is_binary(key) do
    Registry.unregister(@registry_name, key)
  end

  @doc """
  Dispatches a message to all processes registered under the given key.

  Returns `{:ok, count}` where count is the number of processes that
  received the message, or `:error` if no processes were found.

  The message is sent as `{sender, message}` where sender is the PID
  of the calling process.

  ## Options

  * `:from` - The sender PID (defaults to self())

  ## Examples

      iex> JidoCoderLib.TopicRegistry.dispatch("topic:signal:file_changed", {:changed, path})
      {:ok, 2}

  """
  @spec dispatch(key(), term(), Keyword.t()) :: dispatch_result()
  def dispatch(key, message, opts \\ []) when is_binary(key) do
    from = Keyword.get(opts, :from, self())

    # We need to count before dispatching
    count =
      case Registry.lookup(@registry_name, key) do
        [] -> 0
        entries when is_list(entries) -> length(entries)
      end

    if count > 0 do
      Registry.dispatch(@registry_name, key, fn entries ->
        for {pid, _} <- entries, do: send(pid, {from, message})
      end)

      {:ok, count}
    else
      :error
    end
  end

  @doc """
  Returns the number of processes registered under the given key.

  ## Examples

      iex> JidoCoderLib.TopicRegistry.count("topic:signal:file_changed")
      3

  """
  @spec count(key()) :: non_neg_integer()
  def count(key) when is_binary(key) do
    case Registry.lookup(@registry_name, key) do
      [] -> 0
      entries when is_list(entries) -> length(entries)
    end
  end

  @doc """
  Returns all registered keys.

  ## Examples

      iex> JidoCoderLib.TopicRegistry.list_keys()
      ["topic:signal:file_changed", "topic:session:abc123"]

  """
  @spec list_keys() :: [key()]
  def list_keys do
    # Registry.select doesn't return duplicates for duplicate registries
    # Each key appears once in the selection result
    @registry_name
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Checks if any processes are registered under the given key.

  ## Examples

      iex> JidoCoderLib.TopicRegistry.registered?("topic:signal:file_changed")
      true

  """
  @spec registered?(key()) :: boolean()
  def registered?(key) when is_binary(key) do
    case lookup(key) do
      :error -> false
      {:ok, entries} when is_list(entries) -> length(entries) > 0
    end
  end

  @doc """
  Registers the current process under a pattern of keys.

  This allows a process to receive messages for multiple related keys.

  Returns `{:ok, keys}` if all registrations succeeded, or `{:error, results}`
  with partial results if any failed.

  ## Examples

      iex> JidoCoderLib.TopicRegistry.register_multi(["topic:file:txt", "topic:file:ex"])
      {:ok, ["topic:file:txt", "topic:file:ex"]}

  """
  @spec register_multi([key()]) :: {:ok, [key()]} | {:error, [registration_result()]}
  def register_multi(keys) when is_list(keys) do
    results =
      Enum.map(keys, fn key ->
        case register(key) do
          {:ok, ^key} -> {:ok, key}
          error -> error
        end
      end)

    case Enum.all?(results, fn
           {:ok, _} -> true
           _ -> false
         end) do
      true -> {:ok, Enum.map(results, fn {:ok, key} -> key end)}
      false -> {:error, results}
    end
  end
end
