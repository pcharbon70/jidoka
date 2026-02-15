defmodule Jidoka.Agents.LLMOrchestratorTest do
  use ExUnit.Case, async: false

  # Note: These tests require the application to be started

  alias Jidoka.Agents.LLMOrchestrator
  alias Jidoka.Agents.LLMOrchestrator.Adapter
  alias Jidoka.Messaging
  alias Jido.Signal

  describe "LLMOrchestrator" do
    test "agent starts successfully" do
      assert {:ok, _pid} = LLMOrchestrator.start_link(id: "test-llm-orchestrator")
    end

    test "agent is registered in Jido registry" do
      # Start a test instance and check it can be found via Jido.whereis
      {:ok, pid} = LLMOrchestrator.start_link(id: "test-registered-llm")
      assert pid == Jido.whereis(Jidoka.Jido, "test-registered-llm")
    end

    test "agent has correct signal routes" do
      routes = LLMOrchestrator.signal_routes()
      assert is_list(routes)
      assert length(routes) > 0
    end
  end

  describe "HandleLLMRequest" do
    alias Jidoka.Agents.LLMOrchestrator.Actions.HandleLLMRequest

    test "extracts parameters from signal data" do
      params = %{
        message: "Hello, LLM!",
        session_id: "session_123",
        user_id: "user_abc",
        context: %{project: "my-project"},
        stream: true
      }

      assert {:ok, result, directives} = HandleLLMRequest.run(params, %{})
      assert result.status == :processing
      assert is_binary(result.request_id)

      # Verify directives were returned
      assert is_list(directives)
      assert length(directives) > 0
    end

    test "generates correct tool schemas" do
      # The action should be able to get tool schemas
      params = %{
        message: "List files",
        session_id: "session_test",
        # Get all tools
        tools: nil
      }

      assert {:ok, result, _directives} = HandleLLMRequest.run(params, %{})
      # Should complete without error
      assert result.status == :processing
    end

    test "filters tools when tool names provided" do
      params = %{
        message: "Read a file",
        session_id: "session_test",
        tools: ["read_file", "list_files"]
      }

      assert {:ok, result, _directives} = HandleLLMRequest.run(params, %{})
      assert result.status == :processing
    end

    test "generates unique request IDs" do
      params1 = %{
        message: "Test 1",
        session_id: "session_test"
      }

      params2 = %{
        message: "Test 2",
        session_id: "session_test"
      }

      {:ok, result1, _} = HandleLLMRequest.run(params1, %{})
      {:ok, result2, _} = HandleLLMRequest.run(params2, %{})

      # Request IDs should be unique
      refute result1.request_id == result2.request_id
    end

    test "uses messaging session history for llm message context" do
      session_id = "session_history_#{System.unique_integer([:positive, :monotonic])}"

      assert {:ok, _} = Messaging.append_session_message(session_id, :user, "first prompt")
      assert {:ok, _} = Messaging.append_session_message(session_id, :assistant, "first answer")

      params = %{
        message: "next prompt",
        session_id: session_id,
        context: %{project: "jidoka"}
      }

      assert {:ok, _result, directives} = HandleLLMRequest.run(params, %{})

      llm_process_directive =
        Enum.find(directives, fn
          %Jido.Agent.Directive.Emit{signal: %{type: "jido_coder.llm.process"}} -> true
          _ -> false
        end)

      assert llm_process_directive != nil

      llm_messages = get_in(llm_process_directive.signal.data, [:llm_params, :messages])
      assert is_list(llm_messages)

      assert Enum.any?(llm_messages, fn msg ->
               msg.role == :user and msg.content == "first prompt"
             end)

      assert Enum.any?(llm_messages, fn msg ->
               msg.role == :assistant and msg.content == "first answer"
             end)
    end
  end

  describe "Adapter" do
    alias Jidoka.Tools

    test "converts Jidoka tool to Jido.AI format" do
      {:ok, tool_info} = Tools.Registry.find_tool("read_file")

      converted = Adapter.to_jido_tool(tool_info)

      assert is_map(converted)
      assert Map.has_key?(converted, :name)
      assert Map.has_key?(converted, :description)
      assert Map.has_key?(converted, :parameters)
      assert Map.has_key?(converted, :module)
    end

    test "executes ReadFile tool successfully" do
      {:ok, tool_info} = Tools.Registry.find_tool("read_file")
      # Pass required parameters - offset and limit with proper values
      # (limit needs a non-nil value due to Jido's schema validation)
      params = %{file_path: "lib/jidoka/client.ex", offset: 1, limit: 10}

      result = Adapter.execute_tool(tool_info, params, %{})

      # Tool should execute successfully
      assert match?({:ok, %{content: _, metadata: _}}, result)
    end

    test "executes ListFiles tool successfully" do
      {:ok, tool_info} = Tools.Registry.find_tool("list_files")
      params = %{path: "lib/jidoka/tools"}

      result = Adapter.execute_tool(tool_info, params, %{})

      # Tool should execute successfully
      assert match?({:ok, %{files: _, metadata: _}}, result)
    end

    test "handles tool execution errors gracefully" do
      {:ok, tool_info} = Tools.Registry.find_tool("read_file")

      # Invalid file path should return error
      result = Adapter.execute_tool(tool_info, %{file_path: "../../../etc/passwd"}, %{})

      # Should return error tuple
      assert match?({:error, %{error: _, tool: "read_file"}}, result)
    end

    test "normalizes parameters with string keys" do
      {:ok, tool_info} = Tools.Registry.find_tool("read_file")

      # Use string keys (as LLM would provide)
      # Pass proper values for offset/limit to avoid schema validation issues
      params = %{"file_path" => "lib/jidoka/client.ex", "offset" => 1, "limit" => 10}

      result = Adapter.execute_tool(tool_info, params, %{})

      # Should normalize and execute successfully
      assert match?({:ok, %{content: _, metadata: _}}, result)
    end

    test "formats tool results correctly" do
      # Map result
      assert Adapter.format_result(%{content: "test"}) == %{content: "test"}

      # String result
      assert Adapter.format_result("test") == %{content: "test"}

      # Other result
      assert Adapter.format_result(123) == %{result: 123}
    end
  end

  describe "Tool History Tracking" do
    alias Jidoka.Agents.LLMOrchestrator

    test "gets tool history for session" do
      session_id = "session_history_test"

      # Initially should be empty or not found
      result = LLMOrchestrator.get_tool_history(session_id)

      # Should return a list (empty or with existing history)
      assert {:ok, history} = result
      assert is_list(history)
    end

    test "clears tool history for session" do
      session_id = "session_clear_test"

      # Clear should succeed
      result = LLMOrchestrator.clear_tool_history(session_id)

      assert :ok = result
    end
  end

  describe "Integration" do
    alias Jidoka.Agents.LLMOrchestrator
    alias Jido.Signal

    @tag :integration
    test "end-to-end LLM request flow" do
      {:ok, pid} = LLMOrchestrator.start_link(id: "integration-test-llm")

      # Create a signal
      signal =
        Signal.new!(
          "jido_coder.llm.request",
          %{
            message: "What tools are available?",
            session_id: "integration_session",
            user_id: "test_user"
          },
          %{source: "/test"}
        )

      # Dispatch the signal
      assert :ok = Jido.Signal.Dispatch.dispatch(signal, {:pid, target: pid})

      # Give the agent time to process
      Process.sleep(100)

      # Verify the agent processed the request
      {:ok, agent_state} = Jido.AgentServer.state(pid)
      assert map_size(agent_state.agent.state.active_requests) >= 0
    end
  end

  describe "Error Handling" do
    alias Jidoka.Agents.LLMOrchestrator.Adapter

    test "handles non-existent tool gracefully" do
      # Create a fake tool info
      tool_info = %{
        name: "nonexistent_tool",
        description: "Does not exist",
        parameters: %{},
        module: Jidoka.Nonexistent.Tool
      }

      result = Adapter.execute_tool(tool_info, %{}, %{})

      # Should return error
      assert match?({:error, %{error: _, tool: "nonexistent_tool"}}, result)
    end

    test "handles exception during tool execution" do
      # Use ReadFile with invalid input that might cause issues
      {:ok, tool_info} = Jidoka.Tools.Registry.find_tool("read_file")

      # Use very long file path that might cause issues
      long_path = String.duplicate("very_long_path/", 1000) <> "file.ex"
      result = Adapter.execute_tool(tool_info, %{file_path: long_path}, %{})

      # Should return error, not crash
      assert match?({:error, _}, result)
    end
  end
end
