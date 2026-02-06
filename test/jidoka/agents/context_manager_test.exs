defmodule Jidoka.Agents.ContextManagerTest do
  use ExUnit.Case, async: false

  alias Jidoka.Agents.ContextManager
  alias Jidoka.AgentRegistry
  alias Jidoka.PubSub

  @moduletag :context_manager

  setup do
    # Subscribe to session topic for event testing
    session_id = "test-session-#{System.unique_integer()}"

    # Ensure PubSub is available
    pubsub_available? = Process.whereis(Jidoka.PubSub.pubsub_name()) != nil

    if pubsub_available? do
      PubSub.subscribe(PubSub.session_topic(session_id))
    end

    {:ok, session_id: session_id, pubsub_available?: pubsub_available?}
  end

  describe "start_link/1" do
    test "starts ContextManager with session_id" do
      session_id = "test-session-#{System.unique_integer()}"

      assert {:ok, pid} = ContextManager.start_link(session_id: session_id)
      assert Process.alive?(pid)
      assert is_pid(pid)

      # Cleanup
      Process.exit(pid, :kill)
    end

    test "accepts max_history option" do
      session_id = "test-session-#{System.unique_integer()}"

      assert {:ok, pid} = ContextManager.start_link(session_id: session_id, max_history: 50)
      assert Process.alive?(pid)

      # Cleanup
      Process.exit(pid, :kill)
    end

    test "accepts max_files option" do
      session_id = "test-session-#{System.unique_integer()}"

      assert {:ok, pid} = ContextManager.start_link(session_id: session_id, max_files: 25)
      assert Process.alive?(pid)

      # Cleanup
      Process.exit(pid, :kill)
    end

    test "registers in Registry with correct key" do
      session_id = "test-session-#{System.unique_integer()}"

      assert {:ok, pid} = ContextManager.start_link(session_id: session_id)

      key = ContextManager.registry_key(session_id)
      assert [{^pid, _}] = Registry.lookup(AgentRegistry, key)

      # Cleanup
      Process.exit(pid, :kill)
    end

    test "prevents duplicate session_id registration" do
      session_id = "test-session-#{System.unique_integer()}"

      assert {:ok, pid1} = ContextManager.start_link(session_id: session_id)

      # Try to start another with same session_id - returns :ignore
      assert :ignore = ContextManager.start_link(session_id: session_id)

      # Cleanup
      Process.exit(pid1, :kill)
    end
  end

  describe "find_context_manager/1" do
    test "finds existing ContextManager by session_id" do
      session_id = "test-session-#{System.unique_integer()}"

      {:ok, pid} = ContextManager.start_link(session_id: session_id)

      assert {:ok, found_pid} = ContextManager.find_context_manager(session_id)
      assert found_pid == pid

      # Cleanup
      Process.exit(pid, :kill)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = ContextManager.find_context_manager("non-existent-session")
    end
  end

  describe "add_message/3" do
    setup %{session_id: session_id} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)
      {:ok, pid: pid}
    end

    test "adds user message to conversation history", %{session_id: session_id} do
      assert :ok = ContextManager.add_message(session_id, :user, "Hello, world!")

      {:ok, history} = ContextManager.get_conversation_history(session_id)

      assert length(history) == 1
      assert [%{role: :user, content: "Hello, world!", timestamp: ts}] = history
      assert is_struct(ts, DateTime)
    end

    test "adds assistant message to conversation history", %{session_id: session_id} do
      assert :ok = ContextManager.add_message(session_id, :assistant, "Hi there!")

      {:ok, history} = ContextManager.get_conversation_history(session_id)

      assert length(history) == 1
      assert [%{role: :assistant, content: "Hi there!", timestamp: _}] = history
    end

    test "adds multiple messages in order", %{session_id: session_id} do
      assert :ok = ContextManager.add_message(session_id, :user, "First")
      assert :ok = ContextManager.add_message(session_id, :assistant, "Second")
      assert :ok = ContextManager.add_message(session_id, :user, "Third")

      {:ok, history} = ContextManager.get_conversation_history(session_id)

      assert length(history) == 3
      assert Enum.at(history, 0).content == "First"
      assert Enum.at(history, 1).content == "Second"
      assert Enum.at(history, 2).content == "Third"
    end

    test "enforces max_history limit" do
      limit_session_id = "limit-history-#{System.unique_integer()}"
      max_history = 5

      {:ok, _pid} =
        ContextManager.start_link(session_id: limit_session_id, max_history: max_history)

      # Add more messages than max_history
      for i <- 1..10 do
        ContextManager.add_message(limit_session_id, :user, "Message #{i}")
      end

      {:ok, history} = ContextManager.get_conversation_history(limit_session_id)

      # Should only have max_history messages
      assert length(history) == max_history
      # Should have the last max_history messages
      assert Enum.at(history, 0).content == "Message 6"
      assert Enum.at(history, -1).content == "Message 10"
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} =
               ContextManager.add_message("non-existent", :user, "Hello")
    end
  end

  describe "get_conversation_history/1" do
    setup %{session_id: session_id} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)
      {:ok, pid: pid}
    end

    test "returns empty list initially", %{session_id: session_id} do
      {:ok, history} = ContextManager.get_conversation_history(session_id)
      assert history == []
    end

    test "returns all messages in history", %{session_id: session_id} do
      :ok = ContextManager.add_message(session_id, :user, "Message 1")
      :ok = ContextManager.add_message(session_id, :assistant, "Message 2")

      {:ok, history} = ContextManager.get_conversation_history(session_id)

      assert length(history) == 2
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} =
               ContextManager.get_conversation_history("non-existent")
    end
  end

  describe "clear_conversation/1" do
    setup %{session_id: session_id} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)
      {:ok, pid: pid}
    end

    test "clears conversation history", %{session_id: session_id} do
      :ok = ContextManager.add_message(session_id, :user, "Message 1")
      :ok = ContextManager.add_message(session_id, :assistant, "Message 2")

      {:ok, history} = ContextManager.get_conversation_history(session_id)
      assert length(history) == 2

      :ok = ContextManager.clear_conversation(session_id)

      {:ok, history} = ContextManager.get_conversation_history(session_id)
      assert history == []
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} =
               ContextManager.clear_conversation("non-existent")
    end
  end

  describe "add_file/2" do
    setup %{session_id: session_id} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)
      {:ok, pid: pid}
    end

    test "adds file to active files", %{session_id: session_id} do
      :ok = ContextManager.add_file(session_id, "/path/to/file.ex")

      {:ok, files} = ContextManager.get_active_files(session_id)

      assert length(files) == 1
      assert [%{path: "/path/to/file.ex", added_at: ts}] = files
      assert is_struct(ts, DateTime)
    end

    test "adds multiple files", %{session_id: session_id} do
      :ok = ContextManager.add_file(session_id, "/path/to/file1.ex")
      :ok = ContextManager.add_file(session_id, "/path/to/file2.ex")
      :ok = ContextManager.add_file(session_id, "/path/to/file3.ex")

      {:ok, files} = ContextManager.get_active_files(session_id)

      assert length(files) == 3
    end

    test "does not duplicate existing file", %{session_id: session_id} do
      :ok = ContextManager.add_file(session_id, "/path/to/file.ex")
      :ok = ContextManager.add_file(session_id, "/path/to/file.ex")

      {:ok, files} = ContextManager.get_active_files(session_id)

      assert length(files) == 1
    end

    test "enforces max_files limit" do
      limit_session_id = "limit-session-#{System.unique_integer()}"
      max_files = 3
      {:ok, _pid} = ContextManager.start_link(session_id: limit_session_id, max_files: max_files)

      # Add more files than max_files
      for i <- 1..5 do
        ContextManager.add_file(limit_session_id, "/path/to/file#{i}.ex")
      end

      {:ok, files} = ContextManager.get_active_files(limit_session_id)

      # Should only have max_files files
      assert length(files) == max_files

      # Cleanup
      {:ok, pid} = ContextManager.find_context_manager(limit_session_id)
      Process.exit(pid, :kill)
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} =
               ContextManager.add_file("non-existent", "/path/to/file.ex")
    end
  end

  describe "remove_file/2" do
    setup %{session_id: session_id} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)
      {:ok, pid: pid}
    end

    test "removes file from active files", %{session_id: session_id} do
      :ok = ContextManager.add_file(session_id, "/path/to/file.ex")
      :ok = ContextManager.add_file(session_id, "/path/to/file2.ex")

      {:ok, files} = ContextManager.get_active_files(session_id)
      assert length(files) == 2

      :ok = ContextManager.remove_file(session_id, "/path/to/file.ex")

      {:ok, files} = ContextManager.get_active_files(session_id)
      assert length(files) == 1
      assert Enum.all?(files, fn f -> f.path != "/path/to/file.ex" end)
    end

    test "removes file from file index", %{session_id: session_id} do
      :ok = ContextManager.add_file(session_id, "/path/to/file.ex")

      :ok =
        ContextManager.update_file_index(session_id, "/path/to/file.ex", %{
          language: :elixir
        })

      {:ok, index} = ContextManager.get_file_index(session_id)
      assert Map.has_key?(index, "/path/to/file.ex")

      :ok = ContextManager.remove_file(session_id, "/path/to/file.ex")

      {:ok, index} = ContextManager.get_file_index(session_id)
      refute Map.has_key?(index, "/path/to/file.ex")
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} =
               ContextManager.remove_file("non-existent", "/path/to/file.ex")
    end
  end

  describe "get_active_files/1" do
    setup %{session_id: session_id} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)
      {:ok, pid: pid}
    end

    test "returns empty list initially", %{session_id: session_id} do
      {:ok, files} = ContextManager.get_active_files(session_id)
      assert files == []
    end

    test "returns all active files", %{session_id: session_id} do
      :ok = ContextManager.add_file(session_id, "/path/to/file1.ex")
      :ok = ContextManager.add_file(session_id, "/path/to/file2.ex")

      {:ok, files} = ContextManager.get_active_files(session_id)

      assert length(files) == 2
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} =
               ContextManager.get_active_files("non-existent")
    end
  end

  describe "update_file_index/3" do
    setup %{session_id: session_id} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)
      {:ok, pid: pid}
    end

    test "updates file index with metadata", %{session_id: session_id} do
      metadata = %{language: :elixir, line_count: 42}

      :ok = ContextManager.update_file_index(session_id, "/path/to/file.ex", metadata)

      {:ok, index} = ContextManager.get_file_index(session_id)

      assert Map.has_key?(index, "/path/to/file.ex")
      assert index["/path/to/file.ex"].language == :elixir
      assert index["/path/to/file.ex"].line_count == 42
      assert is_struct(index["/path/to/file.ex"].last_accessed, DateTime)
    end

    test "merges metadata for existing file", %{session_id: session_id} do
      :ok = ContextManager.update_file_index(session_id, "/path/to/file.ex", %{language: :elixir})

      :ok =
        ContextManager.update_file_index(session_id, "/path/to/file.ex", %{line_count: 42})

      {:ok, index} = ContextManager.get_file_index(session_id)

      assert index["/path/to/file.ex"].language == :elixir
      assert index["/path/to/file.ex"].line_count == 42
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} =
               ContextManager.update_file_index("non-existent", "/path/to/file.ex", %{})
    end
  end

  describe "get_file_index/1" do
    setup %{session_id: session_id} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)
      {:ok, pid: pid}
    end

    test "returns empty map initially", %{session_id: session_id} do
      {:ok, index} = ContextManager.get_file_index(session_id)
      assert index == %{}
    end

    test "returns all file metadata", %{session_id: session_id} do
      :ok =
        ContextManager.update_file_index(session_id, "/path/to/file1.ex", %{language: :elixir})

      :ok =
        ContextManager.update_file_index(session_id, "/path/to/file2.ex", %{language: :erlang})

      {:ok, index} = ContextManager.get_file_index(session_id)

      assert map_size(index) == 2
      assert index["/path/to/file1.ex"].language == :elixir
      assert index["/path/to/file2.ex"].language == :erlang
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} = ContextManager.get_file_index("non-existent")
    end
  end

  describe "build_context/3" do
    setup %{session_id: session_id} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)
      {:ok, pid: pid}
    end

    test "builds context with conversation", %{session_id: session_id} do
      :ok = ContextManager.add_message(session_id, :user, "Hello")

      {:ok, context} = ContextManager.build_context(session_id, [:conversation], [])

      assert context.session_id == session_id
      assert Map.has_key?(context, :conversation)
      assert length(context.conversation) == 1
      assert Enum.at(context.conversation, 0).content == "Hello"
    end

    test "builds context with files", %{session_id: session_id} do
      :ok = ContextManager.add_file(session_id, "/path/to/file.ex")

      {:ok, context} = ContextManager.build_context(session_id, [:files], [])

      assert Map.has_key?(context, :files)
      assert length(context.files) == 1
      assert Enum.at(context.files, 0).path == "/path/to/file.ex"
    end

    test "builds context with file_index", %{session_id: session_id} do
      :ok =
        ContextManager.update_file_index(session_id, "/path/to/file.ex", %{language: :elixir})

      {:ok, context} = ContextManager.build_context(session_id, [:file_index], [])

      assert Map.has_key?(context, :file_index)
      assert context.file_index["/path/to/file.ex"].language == :elixir
    end

    test "builds full context with all includes", %{session_id: session_id} do
      :ok = ContextManager.add_message(session_id, :user, "Hello")
      :ok = ContextManager.add_file(session_id, "/path/to/file.ex")

      :ok =
        ContextManager.update_file_index(session_id, "/path/to/file.ex", %{language: :elixir})

      {:ok, context} =
        ContextManager.build_context(session_id, [:conversation, :files, :file_index], [])

      assert Map.has_key?(context, :conversation)
      assert Map.has_key?(context, :files)
      assert Map.has_key?(context, :file_index)
    end

    test "includes metadata in context", %{session_id: session_id} do
      :ok = ContextManager.add_message(session_id, :user, "Hello")
      :ok = ContextManager.add_file(session_id, "/path/to/file.ex")

      {:ok, context} = ContextManager.build_context(session_id, [:conversation, :files], [])

      assert Map.has_key?(context, :metadata)
      assert context.metadata.conversation_count == 1
      assert context.metadata.active_file_count == 1
      assert is_struct(context.metadata.timestamp, DateTime)
    end

    test "respects max_messages option", %{session_id: session_id} do
      for i <- 1..10 do
        ContextManager.add_message(session_id, :user, "Message #{i}")
      end

      {:ok, context} = ContextManager.build_context(session_id, [:conversation], max_messages: 3)

      assert length(context.conversation) == 3
      assert Enum.at(context.conversation, 0).content == "Message 8"
    end

    test "respects max_files option", %{session_id: session_id} do
      for i <- 1..10 do
        ContextManager.add_file(session_id, "/path/to/file#{i}.ex")
      end

      {:ok, context} = ContextManager.build_context(session_id, [:files], max_files: 3)

      assert length(context.files) == 3
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} =
               ContextManager.build_context("non-existent", [:conversation], [])
    end
  end

  describe "session isolation" do
    test "conversation history is isolated per session" do
      session_id_1 = "session-iso-1-#{System.unique_integer()}"
      session_id_2 = "session-iso-2-#{System.unique_integer()}"

      {:ok, pid1} = ContextManager.start_link(session_id: session_id_1)
      {:ok, pid2} = ContextManager.start_link(session_id: session_id_2)

      :ok = ContextManager.add_message(session_id_1, :user, "Session 1 message")
      :ok = ContextManager.add_message(session_id_2, :user, "Session 2 message")

      {:ok, history1} = ContextManager.get_conversation_history(session_id_1)
      {:ok, history2} = ContextManager.get_conversation_history(session_id_2)

      assert length(history1) == 1
      assert length(history2) == 1
      assert Enum.at(history1, 0).content == "Session 1 message"
      assert Enum.at(history2, 0).content == "Session 2 message"

      # Cleanup
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "active files are isolated per session" do
      session_id_1 = "session-iso-3-#{System.unique_integer()}"
      session_id_2 = "session-iso-4-#{System.unique_integer()}"

      {:ok, pid1} = ContextManager.start_link(session_id: session_id_1)
      {:ok, pid2} = ContextManager.start_link(session_id: session_id_2)

      :ok = ContextManager.add_file(session_id_1, "/path/to/file1.ex")
      :ok = ContextManager.add_file(session_id_2, "/path/to/file2.ex")

      {:ok, files1} = ContextManager.get_active_files(session_id_1)
      {:ok, files2} = ContextManager.get_active_files(session_id_2)

      assert length(files1) == 1
      assert length(files2) == 1
      assert Enum.at(files1, 0).path == "/path/to/file1.ex"
      assert Enum.at(files2, 0).path == "/path/to/file2.ex"

      # Cleanup
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "file index is isolated per session" do
      session_id_1 = "session-iso-5-#{System.unique_integer()}"
      session_id_2 = "session-iso-6-#{System.unique_integer()}"

      {:ok, pid1} = ContextManager.start_link(session_id: session_id_1)
      {:ok, pid2} = ContextManager.start_link(session_id: session_id_2)

      :ok =
        ContextManager.update_file_index(session_id_1, "/path/to/file.ex", %{session: 1})

      :ok =
        ContextManager.update_file_index(session_id_2, "/path/to/file.ex", %{session: 2})

      {:ok, index1} = ContextManager.get_file_index(session_id_1)
      {:ok, index2} = ContextManager.get_file_index(session_id_2)

      assert index1["/path/to/file.ex"].session == 1
      assert index2["/path/to/file.ex"].session == 2

      # Cleanup
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  describe "PubSub events" do
    test "broadcasts conversation_added event", %{session_id: session_id, pubsub_available?: true} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)

      :ok = ContextManager.add_message(session_id, :user, "Hello")

      assert_receive {_pid, {:conversation_added, event}}, 100
      assert event.session_id == session_id
      assert event.role == :user
      assert event.content == "Hello"
    end

    test "broadcasts file_added event", %{session_id: session_id, pubsub_available?: true} do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)

      :ok = ContextManager.add_file(session_id, "/path/to/file.ex")

      assert_receive {_pid, {:file_added, event}}, 100
      assert event.session_id == session_id
      assert event.file_path == "/path/to/file.ex"
    end

    test "broadcasts conversation_cleared event", %{
      session_id: session_id,
      pubsub_available?: true
    } do
      {:ok, pid} = ContextManager.start_link(session_id: session_id)
      on_exit(fn -> Process.exit(pid, :kill) end)

      :ok = ContextManager.add_message(session_id, :user, "Hello")
      :ok = ContextManager.clear_conversation(session_id)

      assert_receive {_pid, {:conversation_cleared, event}}, 100
      assert event.session_id == session_id
    end
  end
end
