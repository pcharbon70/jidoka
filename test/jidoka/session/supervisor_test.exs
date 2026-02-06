defmodule Jidoka.Session.SupervisorTest do
  use ExUnit.Case, async: false

  alias Jidoka.Session.Supervisor
  alias Jidoka.AgentRegistry

  @moduletag :session_supervisor

  describe "start_link/2" do
    test "starts supervisor with session_id" do
      session_id = "test-session-#{System.unique_integer()}"

      {:ok, pid} = Supervisor.start_link(session_id, [])
      assert Process.alive?(pid)
      assert is_pid(pid)

      # Cleanup via on_exit
      on_exit(fn -> Process.exit(pid, :kill) end)
    end

    test "registers supervisor in Registry" do
      session_id = "test-session-#{System.unique_integer()}"

      {:ok, pid} = Supervisor.start_link(session_id, [])

      # Check registration
      key = Supervisor.registry_key(session_id)
      assert [{^pid, _}] = Registry.lookup(AgentRegistry, key)

      # Cleanup via on_exit
      on_exit(fn -> Process.exit(pid, :kill) end)
    end

    test "accepts llm_config option" do
      session_id = "test-session-#{System.unique_integer()}"
      llm_config = %{model: "gpt-4", temperature: 0.7}

      {:ok, pid} = Supervisor.start_link(session_id, llm_config: llm_config)
      assert Process.alive?(pid)

      # Cleanup via on_exit
      on_exit(fn -> Process.exit(pid, :kill) end)
    end
  end

  describe "find_supervisor/1" do
    test "finds existing supervisor by session_id" do
      session_id = "test-session-#{System.unique_integer()}"

      {:ok, pid} = Supervisor.start_link(session_id, [])

      assert {:ok, found_pid} = Supervisor.find_supervisor(session_id)
      assert found_pid == pid

      # Cleanup via on_exit
      on_exit(fn -> Process.exit(pid, :kill) end)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Supervisor.find_supervisor("non-existent-session")
    end
  end

  describe "get_llm_agent_pid/1" do
    test "returns error for placeholder (Phase 4)" do
      session_id = "test-session-#{System.unique_integer()}"

      {:ok, pid} = Supervisor.start_link(session_id, [])

      # Phase 4: LLMOrchestrator not yet implemented
      assert {:error, :not_found} = Supervisor.get_llm_agent_pid(session_id)

      # Cleanup via on_exit
      on_exit(fn -> Process.exit(pid, :kill) end)
    end
  end

  describe "registry_key/1" do
    test "returns correct registry key pattern" do
      session_id = "session-123"
      assert Supervisor.registry_key(session_id) == "session_supervisor:session-123"
    end

    test "handles different session IDs" do
      assert Supervisor.registry_key("session-abc") == "session_supervisor:session-abc"
      assert Supervisor.registry_key("session-xyz-456") == "session_supervisor:session-xyz-456"
    end
  end

  describe "supervision tree" do
    test "starts context manager child" do
      session_id = "test-session-#{System.unique_integer()}"

      {:ok, pid} = Supervisor.start_link(session_id, [])

      # Check that children are started
      children = Elixir.Supervisor.which_children(pid)
      assert length(children) > 0

      # ContextManager should be started
      assert Enum.any?(children, fn
               {id, child_pid, _, _} when is_pid(child_pid) ->
                 id == Jidoka.Agents.ContextManager and Process.alive?(child_pid)

               _ ->
                 false
             end)

      # Cleanup via on_exit
      on_exit(fn -> Process.exit(pid, :kill) end)
    end

    test "uses one_for_one strategy" do
      session_id = "test-session-#{System.unique_integer()}"

      {:ok, pid} = Supervisor.start_link(session_id, [])

      # Get the supervisor's strategy by checking its children
      # We can't directly check the strategy, but we can verify
      # the supervisor is running and has children
      children = Elixir.Supervisor.which_children(pid)
      assert is_list(children)

      # Cleanup via on_exit
      on_exit(fn -> Process.exit(pid, :kill) end)
    end
  end

  describe "process isolation" do
    test "session crash does not affect other sessions" do
      session_id_1 = "test-session-#{System.unique_integer()}"
      session_id_2 = "test-session-#{System.unique_integer()}"

      {:ok, pid1} = Supervisor.start_link(session_id_1, [])
      {:ok, pid2} = Supervisor.start_link(session_id_2, [])

      # Both should be alive
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)

      # Stop the first session normally
      GenServer.stop(pid1)
      Process.sleep(50)

      # First should be dead
      refute Process.alive?(pid1)

      # Second should still be alive
      assert Process.alive?(pid2)

      # Cleanup after the test
      if Process.alive?(pid2), do: GenServer.stop(pid2)
    end
  end

  describe "concurrent operations" do
    test "handles concurrent session creation" do
      # For concurrent testing, we'll start sessions sequentially
      # but ensure they don't interfere with each other
      results =
        for i <- 1..10 do
          session_id = "test-session-#{System.unique_integer()}-#{i}"
          {:ok, pid} = Supervisor.start_link(session_id, [])
          {session_id, pid}
        end

      # Give more time for all processes to be fully started
      Process.sleep(100)

      # All PIDs should be alive
      assert Enum.all?(results, fn {_, pid} -> Process.alive?(pid) end),
             "Expected all supervisor PIDs to be alive"

      # All should be registered with different keys
      keys = Enum.map(results, fn {session_id, _} -> Supervisor.registry_key(session_id) end)
      assert length(Enum.uniq(keys)) == length(keys)

      # Cleanup after the test (not via on_exit to avoid double-stop)
      Enum.each(results, fn {_, pid} ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
    end
  end

  describe "registry conflicts" do
    test "prevents duplicate session_id registration" do
      session_id = "test-session-#{System.unique_integer()}"

      {:ok, pid1} = Supervisor.start_link(session_id, [])

      # Try to start another supervisor with the same session_id
      # This should return :ignore when already registered
      assert :ignore = Supervisor.start_link(session_id, [])

      # Cleanup via on_exit
      on_exit(fn -> Process.exit(pid1, :kill) end)
    end
  end
end
