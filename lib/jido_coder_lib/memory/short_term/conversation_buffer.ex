defmodule JidoCoderLib.Memory.ShortTerm.ConversationBuffer do
  @moduledoc """
  A sliding window buffer for conversation messages with token-aware eviction.

  The ConversationBuffer stores recent conversation messages and automatically
  evicts oldest messages when the token budget is exceeded.

  ## Fields

  * `:messages` - List of conversation messages
  * `:max_messages` - Maximum message count (soft limit)
  * `:token_budget` - TokenBudget configuration
  * `:current_tokens` - Current estimated token count

  ## Examples

      buffer = ConversationBuffer.new()

      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "Hello"})
      {:ok, buffer, evicted} = ConversationBuffer.add(buffer, message)

      recent = ConversationBuffer.recent(buffer, 5)

  """

  alias JidoCoderLib.Memory.TokenBudget

  defstruct [:messages, :max_messages, :token_budget, :current_tokens]

  @type t :: %__MODULE__{
          messages: [map()],
          max_messages: pos_integer(),
          token_budget: TokenBudget.t(),
          current_tokens: non_neg_integer()
        }

  @default_max_messages 100

  @doc """
  Creates a new conversation buffer.

  ## Options

  * `:max_messages` - Maximum message count (default: 100)
  * `:token_budget` - TokenBudget configuration (default: TokenBudget.new())

  ## Returns

  A new ConversationBuffer struct

  ## Examples

      buffer = ConversationBuffer.new()
      buffer = ConversationBuffer.new(max_messages: 50)

  """
  def new(opts \\ []) do
    max_messages = Keyword.get(opts, :max_messages, @default_max_messages)
    token_budget = Keyword.get(opts, :token_budget, TokenBudget.new())

    %__MODULE__{
      messages: [],
      max_messages: max_messages,
      token_budget: token_budget,
      current_tokens: 0
    }
  end

  @doc """
  Adds a message to the buffer, evicting oldest messages if needed.

  ## Parameters

  * `buffer` - The ConversationBuffer struct
  * `message` - Map with at least `:role` and `:content` keys

  ## Returns

  * `{:ok, updated_buffer}` - Message added, no eviction needed
  * `{:ok, updated_buffer, evicted}` - Message added, messages evicted

  ## Examples

      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "Hello"})
      {:ok, buffer, [evicted_msg]} = ConversationBuffer.add(buffer, large_message)

  """
  def add(%__MODULE__{} = buffer, message) when is_map(message) do
    # Validate message has required fields
    with :ok <- validate_message(message) do
      tokens = TokenBudget.estimate_message_tokens(message)
      message_with_tokens = Map.put(message, :tokens, tokens)

      messages = buffer.messages ++ [message_with_tokens]
      current_tokens = buffer.current_tokens + tokens

      updated_buffer = %{buffer | messages: messages, current_tokens: current_tokens}

      # Check if we need to evict
      maybe_evict(updated_buffer)
    end
  end

  @doc """
  Gets the most recent N messages from the buffer.

  ## Parameters

  * `buffer` - The ConversationBuffer struct
  * `count` - Number of messages to return (default: all)

  ## Returns

  List of messages (most recent first)

  ## Examples

      recent = ConversationBuffer.recent(buffer, 5)

  """
  def recent(%__MODULE__{messages: messages}, count) when is_integer(count) do
    messages
    |> Enum.reverse()
    |> Enum.take(count)
  end

  def recent(%__MODULE__{messages: messages}) do
    Enum.reverse(messages)
  end

  @doc """
  Gets all messages in chronological order.

  ## Examples

      all = ConversationBuffer.all(buffer)

  """
  def all(%__MODULE__{messages: messages}) do
    messages
  end

  @doc """
  Gets the current message count.

  ## Examples

      count = ConversationBuffer.count(buffer)

  """
  def count(%__MODULE__{messages: messages}) do
    length(messages)
  end

  @doc """
  Gets the current token count.

  ## Examples

      tokens = ConversationBuffer.token_count(buffer)

  """
  def token_count(%__MODULE__{current_tokens: tokens}) do
    tokens
  end

  @doc """
  Trims the buffer to the given number of most recent messages.

  Useful for manual buffer management.

  ## Parameters

  * `buffer` - The ConversationBuffer struct
  * `count` - Target message count

  ## Returns

  * `{:ok, updated_buffer, evicted}` - Buffer trimmed, evicted messages returned
  * `{:ok, buffer}` - No trimming needed (already under count)

  ## Examples

      {:ok, buffer, evicted} = ConversationBuffer.trim(buffer, 50)

  """
  def trim(%__MODULE__{} = buffer, count) when is_integer(count) do
    current_count = length(buffer.messages)

    if current_count > count do
      # Keep the most recent 'count' messages
      to_keep = Enum.take(buffer.messages, -count)
      evicted = Enum.take(buffer.messages, current_count - count)

      # Recalculate token count
      new_tokens =
        Enum.reduce(to_keep, 0, fn msg, acc ->
          acc + Map.get(msg, :tokens, 0)
        end)

      updated = %{buffer | messages: to_keep, current_tokens: new_tokens}
      {:ok, updated, evicted}
    else
      {:ok, buffer}
    end
  end

  @doc """
  Clears all messages from the buffer.

  ## Examples

      {:ok, buffer} = ConversationBuffer.clear(buffer)

  """
  def clear(%__MODULE__{} = buffer) do
    {:ok, %{buffer | messages: [], current_tokens: 0}}
  end

  @doc """
  Finds messages matching the given criteria.

  ## Parameters

  * `buffer` - The ConversationBuffer struct
  * `criteria` - Keyword list of match criteria

  ## Examples

      user_messages = ConversationBuffer.find(buffer, role: :user)

  """
  def find(%__MODULE__{messages: messages}, criteria) when is_list(criteria) do
    Enum.filter(messages, fn message ->
      Enum.all?(criteria, fn {key, value} ->
        Map.get(message, key) == value
      end)
    end)
  end

  # Private Helpers

  defp validate_message(message) do
    with :ok <- validate_field(message, :role),
         :ok <- validate_field(message, :content) do
      :ok
    end
  end

  defp validate_field(message, field) do
    if Map.has_key?(message, field) do
      :ok
    else
      {:error, {:missing_field, field}}
    end
  end

  defp maybe_evict(%__MODULE__{} = buffer) do
    cond do
      # Check token budget
      TokenBudget.should_evict?(buffer.token_budget, buffer.current_tokens) ->
        evict_to_threshold(buffer)

      # Check message count limit (soft limit)
      length(buffer.messages) > buffer.max_messages ->
        trim_to_max(buffer)

      # No eviction needed
      true ->
        {:ok, buffer}
    end
  end

  defp evict_to_threshold(%__MODULE__{} = buffer) do
    # Evict until we're back under the threshold
    target_tokens = TokenBudget.overhead_limit(buffer.token_budget)
    evict_tokens(buffer, target_tokens, false)
  end

  defp trim_to_max(%__MODULE__{} = buffer) do
    case trim(buffer, buffer.max_messages) do
      {:ok, updated, evicted} -> {:ok, updated, evicted}
      {:ok, updated} -> {:ok, updated}
    end
  end

  defp evict_tokens(%__MODULE__{messages: messages} = buffer, target, _force_oldest) do
    # Remove oldest messages until we're under the target
    # Start with 0 tokens in kept list and track running count
    {to_keep, evicted, final_tokens} = evict_until_under(messages, target, [], [], 0)

    updated = %{buffer | messages: Enum.reverse(to_keep), current_tokens: final_tokens}
    {:ok, updated, Enum.reverse(evicted)}
  end

  defp evict_until_under(messages, target, kept, evicted, kept_tokens) do
    if kept_tokens >= target or messages == [] do
      {Enum.reverse(kept) ++ messages, Enum.reverse(evicted), kept_tokens}
    else
      [oldest | rest] = messages
      evicted_tokens = Map.get(oldest, :tokens, 0)
      # Add evicted message's tokens to kept_tokens (moving from messages to kept)
      evict_until_under(
        rest,
        target,
        [oldest | kept],
        [oldest | evicted],
        kept_tokens + evicted_tokens
      )
    end
  end
end
