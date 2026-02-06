defmodule JidoCoderLib.ClientTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for the JidoCoderLib.Client API.
  """

  # Ensure the application is running for these tests
  setup_all do
    Application.ensure_all_started(:jido_coder_lib)
    :ok
  end

  # Clean up sessions after each test
  setup do
    # Clear any existing sessions
    for session <- JidoCoderLib.Client.list_sessions() do
      JidoCoderLib.Client.terminate_session(session.session_id)
    end

    :ok
  end

  describe "create_session/1" do
    test "creates a new session with default options" do
      assert {:ok, session_id} = JidoCoderLib.Client.create_session()
      assert is_binary(session_id)
      assert String.starts_with?(session_id, "session_")
    end

    test "creates a new session with metadata" do
      metadata = %{project: "test-project", user: "tester"}

      assert {:ok, session_id} = JidoCoderLib.Client.create_session(metadata: metadata)

      # Verify session was created with metadata
      assert {:ok, info} = JidoCoderLib.Client.get_session_info(session_id)
      assert info.metadata == metadata
    end

    test "creates a new session with llm_config" do
      llm_config = %{model: "gpt-4", temperature: 0.7}

      assert {:ok, session_id} = JidoCoderLib.Client.create_session(llm_config: llm_config)

      # Verify session was created with config
      assert {:ok, info} = JidoCoderLib.Client.get_session_info(session_id)
      assert info.llm_config == llm_config
    end

    test "broadcasts session_created event" do
      # Subscribe to global client events
      JidoCoderLib.Client.subscribe_to_all_sessions()

      # Create a session
      assert {:ok, session_id} = JidoCoderLib.Client.create_session(metadata: %{test: true})

      # Should receive the event (wrapped in {pid, message} tuple by PubSub)
      assert_receive {_, {:session_created, %{session_id: ^session_id, metadata: %{test: true}}}}
    end
  end

  describe "terminate_session/1" do
    test "terminates an existing session" do
      {:ok, session_id} = JidoCoderLib.Client.create_session()

      assert :ok = JidoCoderLib.Client.terminate_session(session_id)

      # Session should no longer be in list
      sessions = JidoCoderLib.Client.list_sessions()
      refute Enum.any?(sessions, fn s -> s.session_id == session_id end)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = JidoCoderLib.Client.terminate_session("non-existent-session")
    end

    test "broadcasts session_terminated event" do
      # Subscribe to global client events
      JidoCoderLib.Client.subscribe_to_all_sessions()

      # Create and then terminate a session
      {:ok, session_id} = JidoCoderLib.Client.create_session()
      :ok = JidoCoderLib.Client.terminate_session(session_id)

      # Should receive the event (wrapped in {pid, message} tuple by PubSub)
      assert_receive {_, {:session_terminated, %{session_id: ^session_id}}}
    end
  end

  describe "list_sessions/0" do
    test "returns empty list when no sessions exist" do
      assert [] = JidoCoderLib.Client.list_sessions()
    end

    test "returns list of active sessions" do
      {:ok, session_id1} = JidoCoderLib.Client.create_session(metadata: %{name: "Session 1"})
      {:ok, session_id2} = JidoCoderLib.Client.create_session(metadata: %{name: "Session 2"})

      sessions = JidoCoderLib.Client.list_sessions()

      assert length(sessions) == 2

      # Check session IDs are in the list
      session_ids = Enum.map(sessions, fn s -> s.session_id end)
      assert session_id1 in session_ids
      assert session_id2 in session_ids

      # Check that sessions have expected fields
      session = Enum.find(sessions, fn s -> s.session_id == session_id1 end)
      assert session.session_id == session_id1
      assert session.status == :active
      assert is_struct(session.created_at, DateTime)
      assert is_struct(session.updated_at, DateTime)
      assert session.metadata == %{name: "Session 1"}
      assert is_pid(session.pid)
    end

    test "does not include terminated sessions" do
      {:ok, session_id1} = JidoCoderLib.Client.create_session()
      {:ok, session_id2} = JidoCoderLib.Client.create_session()

      # Terminate one session
      :ok = JidoCoderLib.Client.terminate_session(session_id1)

      # Only one session should be listed
      sessions = JidoCoderLib.Client.list_sessions()
      assert length(sessions) == 1
      assert hd(sessions).session_id == session_id2
    end
  end

  describe "get_session_info/1" do
    test "returns session info for existing session" do
      metadata = %{project: "test"}
      llm_config = %{model: "gpt-4"}

      {:ok, session_id} =
        JidoCoderLib.Client.create_session(metadata: metadata, llm_config: llm_config)

      assert {:ok, info} = JidoCoderLib.Client.get_session_info(session_id)

      # Verify all fields
      assert info.session_id == session_id
      assert info.status == :active
      assert info.metadata == metadata
      assert info.llm_config == llm_config
      assert is_struct(info.created_at, DateTime)
      assert is_struct(info.updated_at, DateTime)
      assert is_pid(info.pid)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = JidoCoderLib.Client.get_session_info("non-existent")
    end
  end

  describe "send_message/3" do
    test "adds user message to session" do
      {:ok, session_id} = JidoCoderLib.Client.create_session()

      assert :ok = JidoCoderLib.Client.send_message(session_id, :user, "Hello, world!")

      # Verify message was added via ContextManager
      {:ok, history} = JidoCoderLib.Agents.ContextManager.get_conversation_history(session_id)
      assert length(history) == 1
      assert hd(history).role == :user
      assert hd(history).content == "Hello, world!"
    end

    test "adds assistant message to session" do
      {:ok, session_id} = JidoCoderLib.Client.create_session()

      assert :ok = JidoCoderLib.Client.send_message(session_id, :assistant, "Hi there!")

      {:ok, history} = JidoCoderLib.Agents.ContextManager.get_conversation_history(session_id)
      assert length(history) == 1
      assert hd(history).role == :assistant
      assert hd(history).content == "Hi there!"
    end

    test "adds multiple messages to session" do
      {:ok, session_id} = JidoCoderLib.Client.create_session()

      :ok = JidoCoderLib.Client.send_message(session_id, :user, "First message")
      :ok = JidoCoderLib.Client.send_message(session_id, :assistant, "First response")
      :ok = JidoCoderLib.Client.send_message(session_id, :user, "Second message")

      {:ok, history} = JidoCoderLib.Agents.ContextManager.get_conversation_history(session_id)
      assert length(history) == 3

      assert Enum.at(history, 0).role == :user
      assert Enum.at(history, 0).content == "First message"
      assert Enum.at(history, 1).role == :assistant
      assert Enum.at(history, 1).content == "First response"
      assert Enum.at(history, 2).role == :user
      assert Enum.at(history, 2).content == "Second message"
    end

    test "returns error for non-existent session" do
      assert {:error, :context_manager_not_found} =
               JidoCoderLib.Client.send_message("non-existent", :user, "test")
    end
  end

  describe "subscribe_to_session/1" do
    test "subscribes to session events" do
      {:ok, session_id} = JidoCoderLib.Client.create_session()

      # Subscribe to session events
      assert :ok = JidoCoderLib.Client.subscribe_to_session(session_id)

      # Send a message which triggers an event
      :ok = JidoCoderLib.Client.send_message(session_id, :user, "Test message")

      # Should receive conversation_added event (wrapped in {pid, message} tuple)
      assert_receive {_, {:conversation_added, %{session_id: ^session_id, role: :user}}}
    end

    test "receives file_added events" do
      {:ok, session_id} = JidoCoderLib.Client.create_session()
      JidoCoderLib.Client.subscribe_to_session(session_id)

      # Add a file
      file_path = "/test/file.ex"
      :ok = JidoCoderLib.Agents.ContextManager.add_file(session_id, file_path)

      # Should receive file_added event (wrapped in {pid, message} tuple)
      assert_receive {_, {:file_added, %{session_id: ^session_id, file_path: ^file_path}}}
    end

    test "receives file_removed events" do
      {:ok, session_id} = JidoCoderLib.Client.create_session()
      JidoCoderLib.Client.subscribe_to_session(session_id)

      # Add and then remove a file
      file_path = "/test/file.ex"
      :ok = JidoCoderLib.Agents.ContextManager.add_file(session_id, file_path)
      :ok = JidoCoderLib.Agents.ContextManager.remove_file(session_id, file_path)

      # Should receive file_removed event (wrapped in {pid, message} tuple)
      assert_receive {_, {:file_removed, %{session_id: ^session_id, file_path: ^file_path}}}
    end
  end

  describe "subscribe_to_all_sessions/0" do
    test "subscribes to session_created events" do
      # Subscribe to all session events
      assert :ok = JidoCoderLib.Client.subscribe_to_all_sessions()

      # Create a session
      {:ok, session_id} = JidoCoderLib.Client.create_session(metadata: %{test: true})

      # Should receive session_created event (wrapped in {pid, message} tuple)
      assert_receive {_, {:session_created, %{session_id: ^session_id, metadata: %{test: true}}}}
    end

    test "subscribes to session_terminated events" do
      # Subscribe to all session events
      JidoCoderLib.Client.subscribe_to_all_sessions()

      # Create and terminate a session
      {:ok, session_id} = JidoCoderLib.Client.create_session()
      :ok = JidoCoderLib.Client.terminate_session(session_id)

      # Should receive both events (wrapped in {pid, message} tuple)
      assert_receive {_, {:session_created, %{session_id: ^session_id}}}
      assert_receive {_, {:session_terminated, %{session_id: ^session_id}}}
    end

    test "receives events for multiple sessions" do
      # Subscribe to all session events
      JidoCoderLib.Client.subscribe_to_all_sessions()

      # Create multiple sessions
      {:ok, session_id1} = JidoCoderLib.Client.create_session()
      {:ok, session_id2} = JidoCoderLib.Client.create_session()

      # Should receive session_created events for both
      assert_receive {_, {:session_created, %{session_id: ^session_id1}}}
      assert_receive {_, {:session_created, %{session_id: ^session_id2}}}

      # Terminate both sessions
      :ok = JidoCoderLib.Client.terminate_session(session_id1)
      :ok = JidoCoderLib.Client.terminate_session(session_id2)

      # Should receive session_terminated events for both
      assert_receive {_, {:session_terminated, %{session_id: ^session_id1}}}
      assert_receive {_, {:session_terminated, %{session_id: ^session_id2}}}
    end
  end

  describe "unsubscribe_from_session/1" do
    test "unsubscribes from session events" do
      {:ok, session_id} = JidoCoderLib.Client.create_session()

      # Subscribe to session events
      JidoCoderLib.Client.subscribe_to_session(session_id)

      # Unsubscribe
      assert :ok = JidoCoderLib.Client.unsubscribe_from_session(session_id)

      # Send a message
      :ok = JidoCoderLib.Client.send_message(session_id, :user, "Test message")

      # Should NOT receive the event (flush any messages)
      refute_receive {:conversation_added, %{session_id: ^session_id}}, 100
    end
  end

  describe "integration scenarios" do
    test "full session lifecycle with events" do
      # Subscribe to all events
      JidoCoderLib.Client.subscribe_to_all_sessions()

      # Create a session
      {:ok, session_id} = JidoCoderLib.Client.create_session(metadata: %{name: "Test Session"})
      assert_receive {_, {:session_created, %{session_id: ^session_id}}}

      # Subscribe to session-specific events
      JidoCoderLib.Client.subscribe_to_session(session_id)

      # Send messages
      :ok = JidoCoderLib.Client.send_message(session_id, :user, "Hello")
      assert_receive {_, {:conversation_added, %{session_id: ^session_id, role: :user}}}

      :ok = JidoCoderLib.Client.send_message(session_id, :assistant, "Hi!")
      assert_receive {_, {:conversation_added, %{session_id: ^session_id, role: :assistant}}}

      # List sessions
      sessions = JidoCoderLib.Client.list_sessions()
      assert length(sessions) == 1

      # Get session info
      {:ok, info} = JidoCoderLib.Client.get_session_info(session_id)
      assert info.session_id == session_id
      assert info.status == :active

      # Terminate session
      :ok = JidoCoderLib.Client.terminate_session(session_id)
      assert_receive {_, {:session_terminated, %{session_id: ^session_id}}}

      # Session should be gone
      assert [] = JidoCoderLib.Client.list_sessions()
    end

    test "multiple sessions with independent events" do
      # Parent process subscribes to global events
      JidoCoderLib.Client.subscribe_to_all_sessions()

      # Create two sessions
      {:ok, session_a} = JidoCoderLib.Client.create_session(metadata: %{name: "Session A"})
      {:ok, session_b} = JidoCoderLib.Client.create_session(metadata: %{name: "Session B"})

      # Receive both creation events
      assert_receive {_, {:session_created, %{session_id: ^session_a}}}
      assert_receive {_, {:session_created, %{session_id: ^session_b}}}

      # Subscribe to session A events
      JidoCoderLib.Client.subscribe_to_session(session_a)

      # Send messages to each session
      :ok = JidoCoderLib.Client.send_message(session_a, :user, "Message for A")
      :ok = JidoCoderLib.Client.send_message(session_b, :user, "Message for B")

      # Should only receive event for session A (we subscribed to it)
      assert_receive {_, {:conversation_added, %{session_id: ^session_a}}}
      refute_receive {_, {:conversation_added, %{session_id: ^session_b}}}, 100

      # Terminate session A
      :ok = JidoCoderLib.Client.terminate_session(session_a)
      assert_receive {_, {:session_terminated, %{session_id: ^session_a}}}

      # Only session B should remain
      sessions = JidoCoderLib.Client.list_sessions()
      assert length(sessions) == 1
      assert hd(sessions).session_id == session_b
    end
  end
end
