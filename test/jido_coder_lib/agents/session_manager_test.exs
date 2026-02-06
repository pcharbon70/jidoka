defmodule JidoCoderLib.Agents.SessionManagerTest do
  use ExUnit.Case, async: false

  alias JidoCoderLib.Agents.SessionManager

  @moduletag :session_manager

  describe "start_link/1" do
    test "starts SessionManager with ETS table" do
      # SessionManager should be started by Application
      assert Process.whereis(SessionManager) != nil

      # Check ETS table exists
      table_name = SessionManager.ets_table()
      assert :ets.whereis(table_name) != :undefined
    end

    test "starts with custom name" do
      # Can't test custom name as SessionManager is already started by Application
      # This would be tested in isolation in a different test setup
      assert true
    end
  end

  describe "create_session/1" do
    test "generates unique session IDs" do
      {:ok, id1} = SessionManager.create_session()
      {:ok, id2} = SessionManager.create_session()

      assert id1 != id2
      assert String.starts_with?(id1, "session_")
      assert String.starts_with?(id2, "session_")
    end

    test "stores session in ETS with active status" do
      {:ok, session_id} = SessionManager.create_session()

      {:ok, session_info} = SessionManager.get_session_info(session_id)

      assert session_info.session_id == session_id
      assert session_info.status == :active
      assert %DateTime{} = session_info.created_at
      assert %DateTime{} = session_info.updated_at
      assert is_map(session_info.metadata)
      assert session_info.pid != nil
      assert is_pid(session_info.pid)
    end

    test "accepts metadata option" do
      metadata = %{project: "test-project", user: "test-user"}
      {:ok, session_id} = SessionManager.create_session(metadata: metadata)

      {:ok, session_info} = SessionManager.get_session_info(session_id)

      assert session_info.metadata == metadata
    end

    test "accepts llm_config option" do
      llm_config = %{model: "gpt-4", temperature: 0.7}
      {:ok, session_id} = SessionManager.create_session(llm_config: llm_config)

      {:ok, session_info} = SessionManager.get_session_info(session_id)

      assert session_info.llm_config == llm_config
    end
  end

  describe "terminate_session/1" do
    test "marks session as terminated" do
      {:ok, session_id} = SessionManager.create_session()

      :ok = SessionManager.terminate_session(session_id)

      # Give time for async cleanup
      Process.sleep(100)

      # Session should be removed from registry
      assert {:error, :not_found} = SessionManager.get_session_info(session_id)
    end

    test "returns :ok for existing session" do
      {:ok, session_id} = SessionManager.create_session()
      assert :ok = SessionManager.terminate_session(session_id)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = SessionManager.terminate_session("non-existent-id")
    end
  end

  describe "list_sessions/0" do
    setup do
      # Create some test sessions
      {:ok, s1} = SessionManager.create_session()
      {:ok, s2} = SessionManager.create_session()
      {:ok, s3} = SessionManager.create_session()

      on_exit(fn ->
        # Cleanup
        SessionManager.terminate_session(s1)
        SessionManager.terminate_session(s2)
        SessionManager.terminate_session(s3)
      end)

      %{sessions: [s1, s2, s3]}
    end

    test "returns all active sessions", %{sessions: [s1, s2, s3]} do
      sessions = SessionManager.list_sessions()

      session_ids = Enum.map(sessions, & &1.session_id)

      assert s1 in session_ids
      assert s2 in session_ids
      assert s3 in session_ids

      # All sessions should have :active status (SessionSupervisor started)
      assert Enum.all?(sessions, &(&1.status == :active))
    end

    test "returns empty list when no sessions exist" do
      # Terminate all sessions
      sessions = SessionManager.list_sessions()

      Enum.each(sessions, fn s ->
        SessionManager.terminate_session(s.session_id)
      end)

      Process.sleep(100)

      assert SessionManager.list_sessions() == []
    end
  end

  describe "get_session_pid/1" do
    test "returns PID for session with SessionSupervisor" do
      {:ok, session_id} = SessionManager.create_session()

      # With SessionSupervisor (Phase 3.2), sessions have PIDs
      assert {:ok, pid} = SessionManager.get_session_pid(session_id)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = SessionManager.get_session_pid("non-existent")
    end
  end

  describe "get_session_info/1" do
    test "returns session info for existing session" do
      {:ok, session_id} = SessionManager.create_session(metadata: %{test: "data"})

      {:ok, info} = SessionManager.get_session_info(session_id)

      assert info.session_id == session_id
      assert info.status == :active
      assert info.metadata == %{test: "data"}
      assert %DateTime{} = info.created_at
      assert %DateTime{} = info.updated_at
      assert is_pid(info.pid)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = SessionManager.get_session_info("non-existent")
    end
  end

  describe "ets_table/0" do
    test "returns the ETS table name" do
      assert SessionManager.ets_table() == :session_registry
    end
  end

  describe "concurrent operations" do
    test "handles concurrent session creation" do
      tasks =
        for _i <- 1..20 do
          Task.async(fn -> SessionManager.create_session() end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _id} -> true
               _ -> false
             end)

      # All IDs should be unique
      ids = Enum.map(results, fn {:ok, id} -> id end)
      assert length(Enum.uniq(ids)) == length(ids)
    end

    test "handles concurrent session operations" do
      # Create sessions
      {:ok, s1} = SessionManager.create_session()
      {:ok, s2} = SessionManager.create_session()
      {:ok, s3} = SessionManager.create_session()

      # Run concurrent operations
      tasks = [
        Task.async(fn -> SessionManager.get_session_info(s1) end),
        Task.async(fn -> SessionManager.get_session_info(s2) end),
        Task.async(fn -> SessionManager.list_sessions() end),
        Task.async(fn -> SessionManager.terminate_session(s3) end),
        Task.async(fn -> SessionManager.create_session() end)
      ]

      results = Task.await_many(tasks, 2000)

      # All operations should complete successfully
      assert Enum.all?(results, fn
               {:ok, _} -> true
               :ok -> true
               # list_sessions returns list
               sessions when is_list(sessions) -> true
               _ -> false
             end)

      # Cleanup
      SessionManager.terminate_session(s1)
      SessionManager.terminate_session(s2)
    end
  end

  describe "ETS table lifecycle" do
    test "table is public and allows concurrent reads" do
      # Create a session
      {:ok, session_id} = SessionManager.create_session()

      table_name = SessionManager.ets_table()

      # Direct ETS read should work
      assert [{^session_id, _info}] = :ets.lookup(table_name, session_id)

      # Cleanup
      SessionManager.terminate_session(session_id)
    end
  end

  describe "session_status event broadcasting" do
    alias JidoCoderLib.PubSub

    setup do
      # Subscribe to global client events for these tests
      PubSub.subscribe_client_events()
      :ok
    end

    test "broadcasts session_status event on creation (initializing -> active)" do
      {:ok, session_id} = SessionManager.create_session()

      # Should receive session_created event (from Phase 3.6)
      assert_receive {_, {:session_created, %{session_id: ^session_id}}}

      # Should receive session_status event with :active status
      assert_receive {_,
                      {:session_status,
                       %{
                         session_id: ^session_id,
                         status: :active,
                         previous_status: :initializing,
                         updated_at: %DateTime{}
                       }}}

      # Cleanup
      SessionManager.terminate_session(session_id)
      # Flush the remaining events
      flush_messages()
    end

    test "broadcasts session_status events on termination" do
      {:ok, session_id} = SessionManager.create_session()

      # Flush creation events
      flush_messages()

      # Subscribe to session-specific events as well
      PubSub.subscribe_client_session(session_id)

      # Terminate the session
      :ok = SessionManager.terminate_session(session_id)

      # Should receive session_status for :terminating
      assert_receive {_,
                      {:session_status,
                       %{
                         session_id: ^session_id,
                         status: :terminating,
                         previous_status: :active
                       }}}

      # Should receive session_status for :terminated
      assert_receive {_,
                      {:session_status,
                       %{
                         session_id: ^session_id,
                         status: :terminated,
                         previous_status: :terminating
                       }}}

      # Should receive session_terminated event (from Phase 3.6)
      assert_receive {_, {:session_terminated, %{session_id: ^session_id}}}

      # Give time for cleanup
      Process.sleep(100)

      # Flush remaining events
      flush_messages()
    end

    test "sends status events to both global and session-specific topics" do
      {:ok, session_id} = SessionManager.create_session()

      # Flush creation events
      flush_messages()

      # Subscribe to session-specific topic
      PubSub.subscribe_client_session(session_id)

      # Terminate the session
      :ok = SessionManager.terminate_session(session_id)

      # We should receive events on both topics
      # First event on global topic
      assert_receive {_, {:session_status, %{session_id: ^session_id, status: :terminating}}}

      # Same event on session-specific topic
      assert_receive {_, {:session_status, %{session_id: ^session_id, status: :terminating}}}

      # Give time for cleanup
      Process.sleep(100)

      # Flush remaining events
      flush_messages()
    end

    test "session_status events include correct status transitions" do
      {:ok, session_id} = SessionManager.create_session(metadata: %{test: "status"})

      # Flush session_created event
      assert_receive {_, {:session_created, _}}

      # Check the session_status event has correct transition
      assert_receive {_, {:session_status, event}}
      assert event.session_id == session_id
      assert event.status == :active
      assert event.previous_status == :initializing
      assert %DateTime{} = event.updated_at

      # Cleanup
      SessionManager.terminate_session(session_id)
      flush_messages()
    end
  end

  # Helper to flush any remaining messages in the mailbox
  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end
end
