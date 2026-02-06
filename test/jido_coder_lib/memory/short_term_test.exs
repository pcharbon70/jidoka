defmodule JidoCoderLib.Memory.ShortTermTest do
  use ExUnit.Case, async: true

  alias JidoCoderLib.Memory.ShortTerm

  describe "new/2" do
    test "creates STM with defaults" do
      stm = ShortTerm.new("session_123")

      assert stm.session_id == "session_123"
      assert ShortTerm.message_count(stm) == 0
      assert ShortTerm.empty?(stm)
    end

    test "creates STM with custom options" do
      stm = ShortTerm.new("session_123", max_tokens: 8000)

      assert stm.conversation_buffer.token_budget.max_tokens == 8000
    end
  end

  describe "add_message/2" do
    test "adds message to conversation buffer" do
      stm = ShortTerm.new("session_123")
      message = %{role: :user, content: "Hello"}

      assert {:ok, stm} = ShortTerm.add_message(stm, message)
      assert ShortTerm.message_count(stm) == 1
    end

    test "records access in log" do
      stm = ShortTerm.new("session_123")
      message = %{role: :user, content: "Hello"}

      {:ok, stm} = ShortTerm.add_message(stm, message)

      # created_at + add_message
      assert length(stm.access_log) == 2
    end
  end

  describe "recent_messages/2" do
    test "returns recent messages" do
      stm = ShortTerm.new("session_123")
      {:ok, stm} = ShortTerm.add_message(stm, %{role: :user, content: "First"})
      {:ok, stm} = ShortTerm.add_message(stm, %{role: :assistant, content: "Second"})
      {:ok, stm} = ShortTerm.add_message(stm, %{role: :user, content: "Third"})

      recent = ShortTerm.recent_messages(stm, 2)

      assert length(recent) == 2
      assert hd(recent).content == "Third"
    end
  end

  describe "all_messages/1" do
    test "returns all messages in order" do
      stm = ShortTerm.new("session_123")
      {:ok, stm} = ShortTerm.add_message(stm, %{role: :user, content: "First"})

      messages = ShortTerm.all_messages(stm)

      assert length(messages) == 1
      assert hd(messages).content == "First"
    end
  end

  describe "put_context/3" do
    test "stores context value" do
      stm = ShortTerm.new("session_123")

      {:ok, stm} = ShortTerm.put_context(stm, "current_file", "/path/to/file.ex")

      assert {:ok, "/path/to/file.ex"} = ShortTerm.get_context(stm, "current_file")
    end

    test "records access" do
      stm = ShortTerm.new("session_123")

      {:ok, stm} = ShortTerm.put_context(stm, "key", "value")

      assert length(stm.access_log) == 2
    end
  end

  describe "get_context/2" do
    test "retrieves context value" do
      stm = ShortTerm.new("session_123")
      {:ok, stm} = ShortTerm.put_context(stm, "key", "value")

      assert {:ok, "value"} = ShortTerm.get_context(stm, "key")
    end

    test "returns error for missing key" do
      stm = ShortTerm.new("session_123")

      assert {:error, :not_found} = ShortTerm.get_context(stm, "missing")
    end
  end

  describe "get_context/3" do
    test "returns default for missing key" do
      stm = ShortTerm.new("session_123")

      assert ShortTerm.get_context(stm, "missing", "default") == "default"
    end
  end

  describe "delete_context/2" do
    test "deletes context value" do
      stm = ShortTerm.new("session_123")
      {:ok, stm} = ShortTerm.put_context(stm, "key", "value")

      {:ok, stm} = ShortTerm.delete_context(stm, "key")

      assert {:error, :not_found} = ShortTerm.get_context(stm, "key")
    end
  end

  describe "context_keys/1" do
    test "returns all context keys" do
      stm = ShortTerm.new("session_123")
      {:ok, stm} = ShortTerm.put_context(stm, "key1", "val1")
      {:ok, stm} = ShortTerm.put_context(stm, "key2", "val2")

      keys = ShortTerm.context_keys(stm)

      assert "key1" in keys
      assert "key2" in keys
    end
  end

  describe "enqueue_memory/2" do
    test "enqueues memory item" do
      stm = ShortTerm.new("session_123")

      item = %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8,
        timestamp: DateTime.utc_now()
      }

      {:ok, stm} = ShortTerm.enqueue_memory(stm, item)

      assert ShortTerm.pending_count(stm) == 1
    end
  end

  describe "dequeue_memory/1" do
    test "dequeues memory item" do
      stm = ShortTerm.new("session_123")

      item = %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8,
        timestamp: DateTime.utc_now()
      }

      {:ok, stm} = ShortTerm.enqueue_memory(stm, item)

      {:ok, dequeued, stm} = ShortTerm.dequeue_memory(stm)

      assert dequeued.id == "mem_1"
      assert ShortTerm.pending_count(stm) == 0
    end
  end

  describe "summary/1" do
    test "returns STM summary" do
      stm = ShortTerm.new("session_123")
      {:ok, stm} = ShortTerm.add_message(stm, %{role: :user, content: "Hi"})
      {:ok, stm} = ShortTerm.put_context(stm, "key", "value")

      summary = ShortTerm.summary(stm)

      assert summary.session_id == "session_123"
      assert summary.conversation.message_count == 1
      assert summary.context.item_count == 1
    end
  end

  describe "empty?/1" do
    test "returns true when empty" do
      stm = ShortTerm.new("session_123")

      assert ShortTerm.empty?(stm)
    end

    test "returns false when has data" do
      stm = ShortTerm.new("session_123")
      {:ok, stm} = ShortTerm.add_message(stm, %{role: :user, content: "Hi"})

      refute ShortTerm.empty?(stm)
    end
  end

  describe "access_stats/1" do
    test "returns access statistics" do
      stm = ShortTerm.new("session_123")

      stats = ShortTerm.access_stats(stm)

      # created_at
      assert stats.total_accesses == 1
      assert stats.first_access != nil
      assert stats.last_access != nil
    end
  end
end
