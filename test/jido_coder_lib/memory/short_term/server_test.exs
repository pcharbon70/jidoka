defmodule JidoCoderLib.Memory.ShortTerm.ServerTest do
  @moduledoc """
  Tests for the STM.Server GenServer.
  """

  use ExUnit.Case, async: false
  alias JidoCoderLib.Memory.ShortTerm.Server

  setup do
    # Start the application to ensure Registry is available
    Application.ensure_all_started(:jido_coder_lib)

    # Use unique session IDs for each test
    session_id = "test_stm_session_#{System.unique_integer([:positive, :monotonic])}"
    {:ok, pid} = Server.start_link(session_id)

    %{pid: pid, session_id: session_id}
  end

  describe "start_link/1" do
    test "starts a new Server for valid session_id" do
      session_id = "test_stm_start_#{System.unique_integer()}"
      assert {:ok, pid} = Server.start_link(session_id)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "fails to start for invalid session_id" do
      assert {:error, _} = Server.start_link("")
    end

    test "fails to start for very long session_id" do
      long_id = String.duplicate("a", 257)
      assert {:error, _} = Server.start_link(long_id)
    end

    test "fails to start for non-binary session_id" do
      assert {:error, _} = Server.start_link(nil)
      assert {:error, _} = Server.start_link(123)
    end

    test "accepts options for ShortTerm configuration" do
      session_id = "test_stm_opts_#{System.unique_integer()}"
      assert {:ok, pid} = Server.start_link(session_id, max_tokens: 8000, max_messages: 200)

      # Verify the options were applied
      assert {:ok, _stm} = Server.get_stm(pid)
      assert Server.token_count(pid) == 0
      assert Server.message_count(pid) == 0

      GenServer.stop(pid)
    end
  end

  describe "Conversation Buffer Operations" do
    test "add_message/2 stores a message", context do
      %{pid: pid} = context

      message = %{role: :user, content: "Hello, world!"}
      assert {:ok, _stm} = Server.add_message(pid, message)
      assert Server.message_count(pid) == 1
    end

    test "add_message/2 returns evicted messages when limit exceeded", _context do
      # Create server with small message limit
      session_id = "test_evict_#{System.unique_integer()}"
      {:ok, pid} = Server.start_link(session_id, max_messages: 3)

      # Add 4 messages (should evict 1)
      for i <- 1..4 do
        Server.add_message(pid, %{role: :user, content: "Message #{i}"})
      end

      # Should have 3 messages (max limit)
      assert Server.message_count(pid) == 3

      GenServer.stop(pid)
    end

    test "recent_messages/2 returns recent messages", context do
      %{pid: pid} = context

      Server.add_message(pid, %{role: :user, content: "First"})
      Server.add_message(pid, %{role: :assistant, content: "Second"})
      Server.add_message(pid, %{role: :user, content: "Third"})

      messages = Server.recent_messages(pid, 2)
      assert length(messages) == 2
      assert Enum.at(messages, 0).content == "Third"
      assert Enum.at(messages, 1).content == "Second"
    end

    test "recent_messages/1 with no count returns all messages", context do
      %{pid: pid} = context

      Server.add_message(pid, %{role: :user, content: "First"})
      Server.add_message(pid, %{role: :assistant, content: "Second"})

      messages = Server.recent_messages(pid)
      assert length(messages) == 2
    end

    test "all_messages/1 returns all messages in chronological order", context do
      %{pid: pid} = context

      Server.add_message(pid, %{role: :user, content: "First"})
      Server.add_message(pid, %{role: :assistant, content: "Second"})

      messages = Server.all_messages(pid)
      assert length(messages) == 2
      assert Enum.at(messages, 0).content == "First"
      assert Enum.at(messages, 1).content == "Second"
    end

    test "message_count/1 returns the count", context do
      %{pid: pid} = context

      assert Server.message_count(pid) == 0

      Server.add_message(pid, %{role: :user, content: "Test"})
      assert Server.message_count(pid) == 1
    end

    test "token_count/1 returns token count", context do
      %{pid: pid} = context

      assert Server.token_count(pid) == 0

      Server.add_message(pid, %{role: :user, content: "This is a test message"})
      assert Server.token_count(pid) > 0
    end
  end

  describe "Working Context Operations" do
    test "put_context/3 stores a value", context do
      %{pid: pid} = context

      assert {:ok, _stm} = Server.put_context(pid, "current_file", "/path/to/file.ex")
      assert {:ok, value} = Server.get_context(pid, "current_file")
      assert value == "/path/to/file.ex"
    end

    test "get_context/2 returns error for missing key", context do
      %{pid: pid} = context

      assert {:error, _} = Server.get_context(pid, "nonexistent")
    end

    test "get_context/3 returns default for missing key", context do
      %{pid: pid} = context

      assert Server.get_context(pid, "nonexistent", "default") == "default"
    end

    test "delete_context/2 removes a key", context do
      %{pid: pid} = context

      Server.put_context(pid, "temp_key", "temp_value")
      assert {:ok, _} = Server.get_context(pid, "temp_key")

      assert {:ok, _stm} = Server.delete_context(pid, "temp_key")
      assert {:error, _} = Server.get_context(pid, "temp_key")
    end

    test "context_keys/1 returns all keys", context do
      %{pid: pid} = context

      Server.put_context(pid, "key1", "value1")
      Server.put_context(pid, "key2", "value2")

      keys = Server.context_keys(pid)
      assert length(keys) == 2
      assert "key1" in keys
      assert "key2" in keys
    end

    test "put_context_many/2 stores multiple values", context do
      %{pid: pid} = context

      updates = %{
        "key1" => "value1",
        "key2" => "value2",
        "key3" => "value3"
      }

      assert {:ok, _stm} = Server.put_context_many(pid, updates)

      assert {:ok, "value1"} = Server.get_context(pid, "key1")
      assert {:ok, "value2"} = Server.get_context(pid, "key2")
      assert {:ok, "value3"} = Server.get_context(pid, "key3")
    end
  end

  describe "Pending Memories Operations" do
    test "enqueue_memory/2 stores a memory item", context do
      %{pid: pid} = context

      item = %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8
      }

      assert {:ok, _stm} = Server.enqueue_memory(pid, item)
      assert Server.pending_count(pid) == 1
    end

    test "dequeue_memory/1 removes and returns the next item", context do
      %{pid: pid} = context

      item = %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8
      }

      Server.enqueue_memory(pid, item)

      assert {:ok, retrieved, _stm} = Server.dequeue_memory(pid)
      assert retrieved.id == "mem_1"
      assert Server.pending_count(pid) == 0
    end

    test "dequeue_memory/1 returns error when empty", context do
      %{pid: pid} = context

      assert {:error, _} = Server.dequeue_memory(pid)
    end

    test "peek_pending_memory/1 returns item without removing", context do
      %{pid: pid} = context

      item = %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8
      }

      Server.enqueue_memory(pid, item)

      assert {:ok, peeked} = Server.peek_pending_memory(pid)
      assert peeked.id == "mem_1"
      # Still there
      assert Server.pending_count(pid) == 1
    end

    test "pending_count/1 returns the count", context do
      %{pid: pid} = context

      assert Server.pending_count(pid) == 0

      for i <- 1..5 do
        Server.enqueue_memory(pid, %{
          id: "mem_#{i}",
          type: :fact,
          data: %{},
          importance: 0.5
        })
      end

      assert Server.pending_count(pid) == 5
    end
  end

  describe "Utility Functions" do
    test "record_access/1 updates access log", context do
      %{pid: pid} = context

      initial_log = Server.access_log(pid)
      initial_count = length(initial_log)

      Server.record_access(pid)

      new_log = Server.access_log(pid)
      assert length(new_log) == initial_count + 1
    end

    test "access_log/1 returns the access log", context do
      %{pid: pid} = context

      log = Server.access_log(pid)
      assert is_list(log)
      # At least the initial access
      assert length(log) >= 1
    end

    test "access_stats/1 returns access statistics", context do
      %{pid: pid} = context

      stats = Server.access_stats(pid)

      assert is_map(stats)
      assert is_integer(stats.total_accesses)
      assert stats.total_accesses >= 1
      assert stats.last_access != nil
    end

    test "summary/1 returns STM state summary", context do
      %{pid: pid} = context

      summary = Server.summary(pid)

      assert is_map(summary)
      assert summary.session_id != nil
      assert summary.conversation.message_count >= 0
      assert summary.conversation.token_count >= 0
      assert summary.context.item_count >= 0
      assert summary.pending.count >= 0
    end

    test "session_id/1 returns the session_id", context do
      %{pid: pid, session_id: session_id} = context

      assert session_id == Server.session_id(pid)
    end

    test "get_stm/1 returns the STM struct", context do
      %{pid: pid} = context

      assert {:ok, stm} = Server.get_stm(pid)
      assert is_map(stm)
      assert stm.session_id != nil
    end
  end

  describe "Process Isolation" do
    test "concurrent access is safe", context do
      %{pid: pid} = context

      # Spawn multiple tasks that access the same server
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Server.put_context(pid, "key_#{i}", "value_#{i}")
            Server.get_context(pid, "key_#{i}")
          end)
        end

      # All tasks should complete successfully
      results = Task.await_many(tasks, 5000)
      assert length(results) == 10

      assert Enum.all?(results, fn
               {:ok, value} when is_binary(value) -> String.starts_with?(value, "value_")
               _ -> false
             end)
    end
  end

  describe "Integration" do
    test "full workflow: messages, context, and pending memories", context do
      %{pid: pid} = context

      # Add conversation messages
      {:ok, _} = Server.add_message(pid, %{role: :user, content: "What is Elixir?"})

      {:ok, _} =
        Server.add_message(pid, %{role: :assistant, content: "Elixir is a functional language."})

      # Store context
      {:ok, _} = Server.put_context(pid, "topic", "Elixir")
      {:ok, _} = Server.put_context(pid, "language_type", "functional")

      # Enqueue a memory for LTM
      {:ok, _} =
        Server.enqueue_memory(pid, %{
          id: "learn_about_elixir",
          type: :fact,
          data: %{topic: "Elixir is a functional language"},
          importance: 0.8
        })

      # Verify state
      assert Server.message_count(pid) == 2
      assert {:ok, "Elixir"} = Server.get_context(pid, "topic")
      assert Server.pending_count(pid) == 1

      # Get summary
      summary = Server.summary(pid)
      assert summary.conversation.message_count == 2
      assert summary.context.item_count == 2
      assert summary.pending.count == 1
    end
  end
end
