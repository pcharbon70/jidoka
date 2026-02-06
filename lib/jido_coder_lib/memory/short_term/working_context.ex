defmodule JidoCoderLib.Memory.ShortTerm.WorkingContext do
  @moduledoc """
  A semantic scratchpad for session-level understanding and state.

  The WorkingContext provides key-value storage for extracted understanding
  during a session. Unlike the conversation buffer which stores raw messages,
  the WorkingContext stores semantic data like "current_file", "active_task",
  "analysis_results", etc.

  ## Fields

  * `:data` - Map of key-value pairs
  * `:max_items` - Maximum number of items
  * `:access_log` - List of {key, timestamp} for access tracking

  ## Examples

      ctx = WorkingContext.new()

      {:ok, ctx} = WorkingContext.put(ctx, "current_file", "/path/to/file.ex")
      {:ok, value} = WorkingContext.get(ctx, "current_file")

      {:ok, ctx} = WorkingContext.delete(ctx, "current_file")

      keys = WorkingContext.keys(ctx)

  """

  defstruct [:data, :max_items, :access_log]

  @type t :: %__MODULE__{
          data: map(),
          max_items: pos_integer(),
          access_log: [{String.t(), DateTime.t()}]
        }

  @default_max_items 50
  @max_access_log 100

  @doc """
  Creates a new working context.

  ## Options

  * `:max_items` - Maximum number of items (default: 50)

  ## Returns

  A new WorkingContext struct

  ## Examples

      ctx = WorkingContext.new()
      ctx = WorkingContext.new(max_items: 100)

  """
  def new(opts \\ []) do
    max_items = Keyword.get(opts, :max_items, @default_max_items)

    %__MODULE__{
      data: %{},
      max_items: max_items,
      access_log: []
    }
  end

  @doc """
  Stores a value in the working context.

  ## Parameters

  * `ctx` - The WorkingContext struct
  * `key` - String key
  * `value` - Any value to store

  ## Returns

  * `{:ok, updated_ctx}` - Value stored
  * `{:error, :at_capacity}` - Max items reached

  ## Examples

      {:ok, ctx} = WorkingContext.put(ctx, "current_file", "/path/to/file.ex")

  """
  def put(%__MODULE__{} = ctx, key, value) when is_binary(key) do
    if map_size(ctx.data) >= ctx.max_items and not Map.has_key?(ctx.data, key) do
      {:error, :at_capacity}
    else
      now = DateTime.utc_now()
      data = Map.put(ctx.data, key, value)

      # Update access log
      access_log = log_access(ctx.access_log, key, now)

      {:ok, %{ctx | data: data, access_log: access_log}}
    end
  end

  @doc """
  Retrieves a value from the working context.

  ## Parameters

  * `ctx` - The WorkingContext struct
  * `key` - String key

  ## Returns

  * `{:ok, value}` - Value found
  * `{:error, :not_found}` - Key not found

  ## Examples

      {:ok, value} = WorkingContext.get(ctx, "current_file")
      {:error, :not_found} = WorkingContext.get(ctx, "missing_key")

  """
  def get(%__MODULE__{data: data}, key) when is_binary(key) do
    case Map.get(data, key) do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  @doc """
  Gets a value or returns a default if not found.

  ## Examples

      value = WorkingContext.get(ctx, "current_file", "default.ex")

  """
  def get(%__MODULE__{} = ctx, key, default) when is_binary(key) do
    case get(ctx, key) do
      {:ok, value} -> value
      {:error, :not_found} -> default
    end
  end

  @doc """
  Checks if a key exists in the working context.

  ## Examples

      WorkingContext.has_key?(ctx, "current_file")
      #=> true

  """
  def has_key?(%__MODULE__{data: data}, key) when is_binary(key) do
    Map.has_key?(data, key)
  end

  @doc """
  Deletes a value from the working context.

  ## Parameters

  * `ctx` - The WorkingContext struct
  * `key` - String key

  ## Returns

  * `{:ok, updated_ctx}` - Key deleted
  * `{:error, :not_found}` - Key not found

  ## Examples

      {:ok, ctx} = WorkingContext.delete(ctx, "current_file")

  """
  def delete(%__MODULE__{} = ctx, key) when is_binary(key) do
    if Map.has_key?(ctx.data, key) do
      data = Map.delete(ctx.data, key)
      {:ok, %{ctx | data: data}}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Returns all keys in the working context.

  ## Examples

      keys = WorkingContext.keys(ctx)

  """
  def keys(%__MODULE__{data: data}) do
    Map.keys(data)
  end

  @doc """
  Returns the number of items in the working context.

  ## Examples

      count = WorkingContext.count(ctx)

  """
  def count(%__MODULE__{data: data}) do
    map_size(data)
  end

  @doc """
  Clears all data from the working context.

  ## Examples

      {:ok, ctx} = WorkingContext.clear(ctx)

  """
  def clear(%__MODULE__{} = ctx) do
    {:ok, %{ctx | data: %{}, access_log: []}}
  end

  @doc """
  Gets all data as a map.

  ## Examples

      data = WorkingContext.to_map(ctx)

  """
  def to_map(%__MODULE__{data: data}) do
    data
  end

  @doc """
  Returns the access log for the working context.

  The access log tracks when keys were last accessed, useful for
  importance scoring and LRU eviction.

  ## Examples

      log = WorkingContext.access_log(ctx)

  """
  def access_log(%__MODULE__{access_log: log}) do
    log
  end

  @doc """
  Returns all items in the working context as a list of {key, value} tuples.

  Useful for inspection, serialization, or passing context to other systems.

  ## Examples

      items = WorkingContext.list(ctx)
      #=> [{"current_file", "/path/to/file.ex"}, {"active_task", "refactor"}]

  """
  def list(%__MODULE__{data: data}) do
    Map.to_list(data)
  end

  @doc """
  Suggests a memory type for LTM promotion based on key and value.

  Uses heuristics to determine what type of memory this item should be
  promoted to in the long-term memory system.

  ## Memory Types

  * `:fact` - Simple factual information (default)
  * `:analysis` - Analysis results or decisions
  * `:file_context` - File-related information
  * `:conversation` - Conversation-related content

  ## Parameters

  * `ctx` - The WorkingContext struct (for future context-aware suggestions)
  * `key` - The key being stored
  * `value` - The value being stored (for future value-based heuristics)

  ## Returns

  An atom representing the suggested memory type

  ## Examples

      :fact = WorkingContext.suggest_type(ctx, "user_name", "Alice")
      :file_context = WorkingContext.suggest_type(ctx, "current_file", "/path/to/file.ex")
      :analysis = WorkingContext.suggest_type(ctx, "analysis_result", %{...})

  """
  def suggest_type(%__MODULE__{}, key, _value) when is_binary(key) do
    downcase_key = String.downcase(key)

    cond do
      # File-related keys
      String.contains?(downcase_key, ["file", "path", "directory", "folder"]) ->
        :file_context

      # Analysis-related keys
      String.contains?(downcase_key, [
        "analysis",
        "result",
        "conclusion",
        "decision",
        "recommendation"
      ]) ->
        :analysis

      # Conversation-related keys
      String.contains?(downcase_key, ["message", "chat", "dialog", "conversation"]) ->
        :conversation

      # Task-related keys (treat as analysis - represents work done)
      String.contains?(downcase_key, ["task", "todo", "action", "step"]) ->
        :analysis

      # Default to fact for simple key-value pairs
      true ->
        :fact
    end
  end

  @doc """
  Gets the most recently accessed keys.

  ## Parameters

  * `ctx` - The WorkingContext struct
  * `count` - Number of keys to return (default: 10)

  ## Examples

      recent = WorkingContext.recent_keys(ctx, 5)

  """
  def recent_keys(%__MODULE__{access_log: log}, count \\ 10) do
    log
    |> Enum.reverse()
    |> Enum.map(fn {key, _time} -> key end)
    |> Enum.uniq()
    |> Enum.take(count)
  end

  @doc """
  Gets the last access time for a key.

  ## Examples

      {:ok, time} = WorkingContext.last_accessed(ctx, "current_file")

  """
  def last_accessed(%__MODULE__{access_log: log}, key) when is_binary(key) do
    case Enum.find(log, fn {k, _} -> k == key end) do
      {^key, time} -> {:ok, time}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Updates multiple values at once.

  ## Parameters

  * `ctx` - The WorkingContext struct
  * `updates` - Map of key-value pairs to update

  ## Returns

  * `{:ok, updated_ctx}` - Values updated
  * `{:error, :at_capacity}` - Would exceed max items

  ## Examples

      {:ok, ctx} = WorkingContext.put_many(ctx, %{"key1" => "val1", "key2" => "val2"})

  """
  def put_many(%__MODULE__{} = ctx, updates) when is_map(updates) do
    # Check if we have room for all new keys
    new_keys = Map.keys(updates) -- Map.keys(ctx.data)

    if map_size(ctx.data) + length(new_keys) > ctx.max_items do
      {:error, :at_capacity}
    else
      now = DateTime.utc_now()

      # Add all updates
      data =
        Enum.reduce(updates, ctx.data, fn {key, value}, acc ->
          Map.put(acc, key, value)
        end)

      # Log access for all keys
      access_log =
        Enum.reduce(Map.keys(updates), ctx.access_log, fn key, acc ->
          log_access(acc, key, now)
        end)

      {:ok, %{ctx | data: data, access_log: access_log}}
    end
  end

  # Private Helpers

  defp log_access(access_log, key, timestamp) do
    [{key, timestamp} | access_log]
    |> Enum.take(@max_access_log)
  end
end
