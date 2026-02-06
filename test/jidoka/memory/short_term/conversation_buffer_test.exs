defmodule Jidoka.Memory.ShortTerm.ConversationBufferTest do
  use ExUnit.Case, async: true

  alias Jidoka.Memory.ShortTerm.ConversationBuffer

  describe "new/1" do
    test "creates buffer with defaults" do
      buffer = ConversationBuffer.new()

      assert buffer.messages == []
      assert buffer.max_messages == 100
      assert buffer.current_tokens == 0
      assert buffer.token_budget.max_tokens == 4000
    end

    test "creates buffer with custom options" do
      buffer = ConversationBuffer.new(max_messages: 50)

      assert buffer.max_messages == 50
    end
  end

  describe "add/2" do
    test "adds message to buffer" do
      buffer = ConversationBuffer.new()
      message = %{role: :user, content: "Hello"}

      assert {:ok, buffer} = ConversationBuffer.add(buffer, message)
      assert ConversationBuffer.count(buffer) == 1
      assert hd(buffer.messages).content == "Hello"
    end

    test "returns evicted messages when budget exceeded" do
      # Create buffer with small token budget
      budget = %Jidoka.Memory.TokenBudget{
        max_tokens: 100,
        reserve_percentage: 0.1,
        overhead_threshold: 0.9
      }

      buffer = %ConversationBuffer{ConversationBuffer.new() | token_budget: budget}

      # Add messages until eviction
      buffer =
        Enum.reduce(1..15, buffer, fn _, acc ->
          {:ok, b} =
            ConversationBuffer.add(acc, %{
              role: :user,
              content: "Test message #{Enum.random(1..100)}"
            })

          b
        end)

      # Next add should trigger eviction
      large_message = %{role: :user, content: String.duplicate("word ", 50)}
      {:ok, buffer, evicted} = ConversationBuffer.add(buffer, large_message)

      assert is_list(evicted)
      assert length(evicted) > 0
    end

    test "validates message has required fields" do
      buffer = ConversationBuffer.new()

      assert {:error, {:missing_field, :role}} = ConversationBuffer.add(buffer, %{content: "Hi"})
      assert {:error, {:missing_field, :content}} = ConversationBuffer.add(buffer, %{role: :user})
    end
  end

  describe "recent/2" do
    test "returns messages in reverse order" do
      buffer = ConversationBuffer.new()
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "First"})
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :assistant, content: "Second"})
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "Third"})

      recent = ConversationBuffer.recent(buffer, 2)

      assert length(recent) == 2
      assert hd(recent).content == "Third"
      assert Enum.at(recent, 1).content == "Second"
    end

    test "returns all messages when count not specified" do
      buffer = ConversationBuffer.new()
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "First"})
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :assistant, content: "Second"})

      recent = ConversationBuffer.recent(buffer)

      assert length(recent) == 2
    end
  end

  describe "all/1" do
    test "returns all messages in chronological order" do
      buffer = ConversationBuffer.new()
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "First"})
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :assistant, content: "Second"})

      all = ConversationBuffer.all(buffer)

      assert length(all) == 2
      assert hd(all).content == "First"
      assert Enum.at(all, 1).content == "Second"
    end
  end

  describe "count/1" do
    test "returns message count" do
      buffer = ConversationBuffer.new()
      assert ConversationBuffer.count(buffer) == 0

      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "Hi"})
      assert ConversationBuffer.count(buffer) == 1
    end
  end

  describe "token_count/1" do
    test "returns current token count" do
      buffer = ConversationBuffer.new()
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "Hello"})

      assert ConversationBuffer.token_count(buffer) > 0
    end
  end

  describe "trim/2" do
    test "trims buffer to specified count" do
      buffer = ConversationBuffer.new()
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "1"})
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "2"})
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "3"})

      {:ok, buffer, evicted} = ConversationBuffer.trim(buffer, 2)

      assert ConversationBuffer.count(buffer) == 2
      assert length(evicted) == 1
      assert hd(evicted).content == "1"
    end

    test "returns unchanged when already under count" do
      buffer = ConversationBuffer.new()
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "Hi"})

      assert {:ok, buffer} = ConversationBuffer.trim(buffer, 5)
    end
  end

  describe "clear/1" do
    test "clears all messages" do
      buffer = ConversationBuffer.new()
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "Hi"})

      {:ok, buffer} = ConversationBuffer.clear(buffer)

      assert ConversationBuffer.count(buffer) == 0
    end
  end

  describe "find/2" do
    test "finds messages matching criteria" do
      buffer = ConversationBuffer.new()
      {:ok, buffer} = ConversationBuffer.add(buffer, %{role: :user, content: "User message"})

      {:ok, buffer} =
        ConversationBuffer.add(buffer, %{role: :assistant, content: "Assistant message"})

      user_messages = ConversationBuffer.find(buffer, role: :user)

      assert length(user_messages) == 1
      assert hd(user_messages).role == :user
    end
  end
end
