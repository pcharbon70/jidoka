defmodule JidoCoderLib.AgentTest do
  use ExUnit.Case, async: true

  alias JidoCoderLib.Agent
  alias JidoCoderLib.AgentRegistry

  describe "generate_task_id/2" do
    test "generates unique task IDs with prefix only" do
      task_id_1 = Agent.generate_task_id("analysis")
      task_id_2 = Agent.generate_task_id("analysis")

      assert String.starts_with?(task_id_1, "analysis_")
      assert String.starts_with?(task_id_2, "analysis_")
      assert task_id_1 != task_id_2
    end

    test "generates task IDs with session ID" do
      task_id = Agent.generate_task_id("chat", session_id: "session-123")

      assert String.starts_with?(task_id, "chat_session-123_")
      assert String.contains?(task_id, "session-123")
    end

    test "generates unique task IDs with same session" do
      task_id_1 = Agent.generate_task_id("analysis", session_id: "session-123")
      task_id_2 = Agent.generate_task_id("analysis", session_id: "session-123")

      assert task_id_1 != task_id_2
    end
  end

  describe "valid_session_id?/1" do
    test "returns true for valid session IDs" do
      assert Agent.valid_session_id?("session-abc-123")
      assert Agent.valid_session_id?("session_123")
      assert Agent.valid_session_id?("user-session-456")
    end

    test "returns false for nil" do
      refute Agent.valid_session_id?(nil)
    end

    test "returns false for empty string" do
      refute Agent.valid_session_id?("")
    end

    test "returns false for whitespace-only strings" do
      refute Agent.valid_session_id?("   ")
      refute Agent.valid_session_id?("\t\n")
    end

    test "returns false for non-strings" do
      refute Agent.valid_session_id?(123)
      refute Agent.valid_session_id?(%{})
      refute Agent.valid_session_id?([])
    end
  end

  describe "validate_session_data/1" do
    test "returns ok for valid session data" do
      assert {:ok, %{session_id: "session-123"}} =
               Agent.validate_session_data(%{session_id: "session-123"})
    end

    test "returns error for missing session_id" do
      assert {:error, :missing_session_id} = Agent.validate_session_data(%{})

      assert {:error, :missing_session_id} =
               Agent.validate_session_data(%{other_field: "value"})
    end

    test "returns error for nil session_id" do
      assert {:error, :invalid_session_id} =
               Agent.validate_session_data(%{session_id: nil})
    end

    test "returns error for invalid session_id" do
      assert {:error, :invalid_session_id} =
               Agent.validate_session_data(%{session_id: ""})

      assert {:error, :invalid_session_id} =
               Agent.validate_session_data(%{session_id: "   "})
    end
  end

  describe "error_response/2" do
    test "creates standardized error response" do
      assert {:error, %{type: :validation_failed, details: %{}}} ==
               Agent.error_response(:validation_failed)

      assert {:error, %{type: :not_found, details: %{resource: :agent}}} ==
               Agent.error_response(:not_found, %{resource: :agent})
    end
  end

  describe "ok_response/1" do
    test "creates standardized ok response" do
      assert {:ok, %{status: :processed}} == Agent.ok_response(%{status: :processed})
      assert {:ok, %{count: 5}} == Agent.ok_response(%{count: 5})
    end
  end

  describe "client_events_topic/0" do
    test "returns the client events topic" do
      assert "jido.client.events" = Agent.client_events_topic()
    end
  end

  describe "session_topic/1" do
    test "returns the session topic for a session ID" do
      assert "jido.session.session-123" = Agent.session_topic("session-123")
      assert "jido.session.user-456" = Agent.session_topic("user-456")
    end
  end

  describe "pubsub_name/0" do
    test "returns the PubSub name" do
      assert :jido_coder_pubsub = Agent.pubsub_name()
    end
  end

  # ============================================================================
  # Agent Registry and Discovery Tests
  # ============================================================================

  describe "jido_instance/0" do
    test "returns the Jido instance" do
      assert JidoCoderLib.Jido = Agent.jido_instance()
    end
  end

  describe "find_agent_by_id/1" do
    test "returns error for non-existent agent" do
      assert :error = Agent.find_agent_by_id("nonexistent-agent")
    end

    test "returns error for nil input" do
      assert :error = Agent.find_agent_by_id(nil)
    end
  end

  describe "find_agent_by_name/1" do
    test "returns error for non-existent agent" do
      assert :error = Agent.find_agent_by_name("nonexistent")
    end

    test "returns error for non-existent agent with prefix" do
      assert :error = Agent.find_agent_by_name("agent:nonexistent")
    end

    test "handles agent: prefix correctly" do
      # Both forms should work the same way
      assert :error = Agent.find_agent_by_name("test-agent")
      assert :error = Agent.find_agent_by_name("agent:test-agent")
    end
  end

  describe "find_agent/1" do
    test "returns error for non-existent agent" do
      assert :error = Agent.find_agent("nonexistent")
      assert :error = Agent.find_agent("agent:nonexistent")
    end

    test "checks both registries" do
      # For agents that don't exist in either registry
      assert :error = Agent.find_agent("definitely-not-real")
    end
  end

  describe "list_jido_agents/0" do
    test "returns a list of agent tuples" do
      agents = Agent.list_jido_agents()

      assert is_list(agents)
      # Each entry should be a tuple with {id, pid}
      Enum.each(agents, fn agent ->
        case agent do
          {id, pid} when is_binary(id) or id == "unknown" ->
            assert is_pid(pid) or pid == nil

          _ ->
            flunk("Expected {id, pid} tuple")
        end
      end)
    end
  end

  describe "list_registered_agents/0" do
    test "returns a list of agent tuples from AgentRegistry" do
      # Need to test with an actual running agent that registers itself
      # Since we can't easily create one here, just verify the function works
      agents = Agent.list_registered_agents()

      assert is_list(agents)
      # Each entry should be a tuple with {name, pid}
      Enum.each(agents, fn agent ->
        assert {_name, _pid} = agent
      end)
    end

    test "filters out non-agent keys" do
      # The list_registered_agents should only return agent: prefixed keys
      agents = Agent.list_registered_agents()

      # All names should not have the agent: prefix (it's stripped)
      Enum.each(agents, fn {name, _pid} ->
        refute String.starts_with?(name, "agent:")
      end)
    end
  end

  describe "list_agents/0" do
    test "returns a combined list from both registries" do
      agents = Agent.list_agents()

      assert is_list(agents)

      # Each entry should be a tuple with {id, pid}
      Enum.each(agents, fn agent ->
        assert {_id, _pid} = agent
      end)
    end

    test "deduplicates agents by PID" do
      # If an agent is in both registries, it should only appear once
      agents = Agent.list_agents()

      pids = Enum.map(agents, fn {_id, pid} -> pid end)
      assert length(pids) == length(Enum.uniq(pids))
    end
  end

  describe "agent_active?/1" do
    test "returns false for non-existent agent" do
      refute Agent.agent_active?("nonexistent")
      refute Agent.agent_active?("agent:nonexistent")
    end

    test "returns false for nil input" do
      refute Agent.agent_active?(nil)
    end
  end

  describe "agent_responsive?/1" do
    test "returns false for non-existent agent" do
      refute Agent.agent_responsive?("nonexistent")
    end

    test "accepts timeout parameter" do
      # Should not error even with custom timeout
      refute Agent.agent_responsive?("nonexistent", 100)
    end
  end

  describe "coordinator/0" do
    test "returns result tuple regardless of whether coordinator is running" do
      result = Agent.coordinator()

      case result do
        {:ok, _pid} -> :ok
        :error -> :ok
        _ -> flunk("Expected {:ok, pid} or :error")
      end
    end
  end

  describe "coordinator_active?/0" do
    test "returns boolean for coordinator status" do
      is_boolean(Agent.coordinator_active?())
    end
  end

  describe "registry integration" do
    test "can register and find the current process" do
      # Register the current process (Registry.register must be called from the process itself)
      {:ok, "agent:test_process"} =
        AgentRegistry.register("agent:test_process", key: "agent:test_process")

      # Should be able to find it
      assert {:ok, test_pid} = Agent.find_agent_by_name("test_process")
      assert test_pid == self()
      assert {:ok, test_pid2} = Agent.find_agent_by_name("agent:test_process")
      assert test_pid2 == self()

      # Should be active
      assert Agent.agent_active?("test_process")

      # Clean up
      AgentRegistry.unregister("agent:test_process")
    end

    test "correctly strips agent: prefix from list_registered_agents" do
      # Register the current process
      AgentRegistry.register("agent:prefix_test", key: "agent:prefix_test")

      agents = Agent.list_registered_agents()

      # Find our test agent
      found = Enum.find(agents, fn {name, _pid} -> name == "prefix_test" end)
      assert {_, pid} = found
      assert pid == self()

      # Should NOT have the prefix in the name
      refute Enum.any?(agents, fn {name, _pid} -> name == "agent:prefix_test" end)

      # Clean up
      AgentRegistry.unregister("agent:prefix_test")
    end
  end
end
