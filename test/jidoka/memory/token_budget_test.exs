defmodule Jidoka.Memory.TokenBudgetTest do
  use ExUnit.Case, async: true

  alias Jidoka.Memory.TokenBudget

  describe "new/1" do
    test "creates budget with defaults" do
      budget = TokenBudget.new()

      assert budget.max_tokens == 4000
      assert budget.reserve_percentage == 0.1
      assert budget.overhead_threshold == 0.9
    end

    test "creates budget with custom values" do
      budget = TokenBudget.new(max_tokens: 8000, reserve_percentage: 0.05)

      assert budget.max_tokens == 8000
      assert budget.reserve_percentage == 0.05
      assert budget.overhead_threshold == 0.9
    end
  end

  describe "available/1" do
    test "calculates available tokens (max - reserve)" do
      budget = TokenBudget.new(max_tokens: 4000, reserve_percentage: 0.1)

      assert TokenBudget.available(budget) == 3600
    end

    test "handles zero reserve" do
      budget = TokenBudget.new(max_tokens: 4000, reserve_percentage: 0.0)

      assert TokenBudget.available(budget) == 4000
    end
  end

  describe "overhead_limit/1" do
    test "calculates overhead threshold" do
      budget = TokenBudget.new(max_tokens: 4000, overhead_threshold: 0.9)

      assert TokenBudget.overhead_limit(budget) == 3600
    end
  end

  describe "should_evict?/2" do
    test "returns true when tokens exceed threshold" do
      budget = TokenBudget.new(max_tokens: 4000, overhead_threshold: 0.9)

      assert TokenBudget.should_evict?(budget, 3700)
    end

    test "returns false when tokens under threshold" do
      budget = TokenBudget.new(max_tokens: 4000, overhead_threshold: 0.9)

      refute TokenBudget.should_evict?(budget, 3000)
    end

    test "returns true when tokens equal threshold" do
      budget = TokenBudget.new(max_tokens: 4000, overhead_threshold: 0.9)

      assert TokenBudget.should_evict?(budget, 3600)
    end
  end

  describe "eviction_needed/2" do
    test "calculates tokens to evict" do
      budget = TokenBudget.new(max_tokens: 4000, overhead_threshold: 0.9)

      assert TokenBudget.eviction_needed(budget, 3800) == 200
    end

    test "returns zero when under threshold" do
      budget = TokenBudget.new(max_tokens: 4000, overhead_threshold: 0.9)

      assert TokenBudget.eviction_needed(budget, 3000) == 0
    end
  end

  describe "would_exceed?/3" do
    test "returns true when adding would exceed budget" do
      budget = TokenBudget.new(max_tokens: 4000, reserve_percentage: 0.1)

      assert TokenBudget.would_exceed?(budget, 3500, 200)
    end

    test "returns false when adding is within budget" do
      budget = TokenBudget.new(max_tokens: 4000, reserve_percentage: 0.1)

      refute TokenBudget.would_exceed?(budget, 3000, 200)
    end
  end

  describe "estimate_tokens/1" do
    test "estimates tokens for text" do
      # "Hello, world!" is 13 characters, ~3 tokens
      tokens = TokenBudget.estimate_tokens("Hello, world!")
      assert tokens >= 2 and tokens <= 5
    end

    test "returns at least 1 token for non-empty text" do
      assert TokenBudget.estimate_tokens("Hi") >= 1
    end
  end

  describe "estimate_message_tokens/1" do
    test "estimates tokens for message map" do
      tokens = TokenBudget.estimate_message_tokens(%{role: :user, content: "Hello, world!"})
      assert tokens >= 2
    end

    test "estimates tokens for message with content key" do
      tokens = TokenBudget.estimate_message_tokens(%{content: "This is a test message"})
      assert tokens >= 2
    end
  end
end
