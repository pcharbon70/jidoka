defmodule Jidoka.Memory.TokenBudget do
  @moduledoc """
  Token budget configuration for short-term memory.

  This struct defines the token limits and thresholds for conversation
  buffer management.

  ## Fields

  * `:max_tokens` - Maximum number of tokens allowed (default: 4000)
  * `:reserve_percentage` - Percentage to keep in reserve (default: 0.1 = 10%)
  * `:overhead_threshold` - Percentage that triggers eviction (default: 0.9 = 90%)

  ## Examples

      budget = TokenBudget.new()
      budget.max_tokens
      #=> 4000

      custom = TokenBudget.new(max_tokens: 8000)
      custom.max_tokens
      #=> 8000

  Calculating available tokens:

      available = TokenBudget.available(budget)
      #=> 3600 (reserves 10%)

  Checking if eviction is needed:

      TokenBudget.should_evict?(budget, 3800)
      #=> true (exceeds 90% threshold)

  """

  defstruct [:max_tokens, :reserve_percentage, :overhead_threshold]

  @type t :: %__MODULE__{
          max_tokens: pos_integer(),
          reserve_percentage: float(),
          overhead_threshold: float()
        }

  @default_max_tokens 4000
  @default_reserve 0.1
  @default_threshold 0.9

  @doc """
  Creates a new token budget with default or custom values.

  ## Options

  * `:max_tokens` - Maximum token limit (default: 4000)
  * `:reserve_percentage` - Reserve percentage 0.0-1.0 (default: 0.1)
  * `:overhead_threshold` - Eviction threshold 0.0-1.0 (default: 0.9)

  ## Returns

  A TokenBudget struct

  ## Examples

      budget = TokenBudget.new()
      budget = TokenBudget.new(max_tokens: 8000, reserve_percentage: 0.05)

  """
  def new(opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    reserve_percentage = Keyword.get(opts, :reserve_percentage, @default_reserve)
    overhead_threshold = Keyword.get(opts, :overhead_threshold, @default_threshold)

    %__MODULE__{
      max_tokens: max_tokens,
      reserve_percentage: reserve_percentage,
      overhead_threshold: overhead_threshold
    }
  end

  @doc """
  Calculates the number of available tokens (max - reserve).

  ## Examples

      TokenBudget.available(%TokenBudget{max_tokens: 4000, reserve_percentage: 0.1})
      #=> 3600

  """
  def available(%__MODULE__{} = budget) do
    reserve = trunc(budget.max_tokens * budget.reserve_percentage)
    budget.max_tokens - reserve
  end

  @doc """
  Calculates the overhead threshold in tokens.

  ## Examples

      TokenBudget.overhead_limit(%TokenBudget{max_tokens: 4000, overhead_threshold: 0.9})
      #=> 3600

  """
  def overhead_limit(%__MODULE__{} = budget) do
    trunc(budget.max_tokens * budget.overhead_threshold)
  end

  @doc """
  Checks if the given current token count should trigger eviction.

  Returns true when current_tokens exceeds the overhead threshold.

  ## Examples

      TokenBudget.should_evict?(budget, 3800)
      #=> true

  """
  def should_evict?(%__MODULE__{} = budget, current_tokens) when is_integer(current_tokens) do
    current_tokens >= overhead_limit(budget)
  end

  @doc """
  Calculates how many tokens need to be evicted to get back to the threshold.

  ## Examples

      TokenBudget.eviction_needed(budget, 3800)
      #=> 200

  """
  def eviction_needed(%__MODULE__{} = budget, current_tokens) when is_integer(current_tokens) do
    limit = overhead_limit(budget)
    max(current_tokens - limit, 0)
  end

  @doc """
  Checks if adding the given number of tokens would exceed the budget.

  ## Examples

      TokenBudget.would_exceed?(budget, 3900, 200)
      #=> true

  """
  def would_exceed?(%__MODULE__{} = budget, current_tokens, to_add)
      when is_integer(current_tokens) and is_integer(to_add) do
    current_tokens + to_add > available(budget)
  end

  @doc """
  Estimates the token count for a given text.

  This is a simple approximation: character count / 4.
  For production, use a proper tokenizer.

  ## Examples

      TokenBudget.estimate_tokens("Hello, world!")
      #=> 3

  """
  def estimate_tokens(text) when is_binary(text) do
    # Rough approximation: ~4 characters per token
    text
    |> String.length()
    |> div(4)
    |> max(1)
  end

  @doc """
  Estimates the token count for a conversation message.

  ## Examples

      TokenBudget.estimate_message_tokens(%{role: :user, content: "Hello"})
      #=> 2

  """
  def estimate_message_tokens(%{content: content}) do
    estimate_tokens(content)
  end

  def estimate_message_tokens(message) when is_map(message) do
    content = Map.get(message, :content, "")
    estimate_tokens(content)
  end
end
