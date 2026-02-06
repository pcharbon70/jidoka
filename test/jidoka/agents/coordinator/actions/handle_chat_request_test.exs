defmodule Jidoka.Agents.Coordinator.Actions.HandleChatRequestTest do
  use ExUnit.Case, async: true

  alias Jidoka.Agents.Coordinator.Actions.HandleChatRequest

  describe "run/2" do
    test "processes chat request and returns emit directives" do
      params = %{
        message: "Help me debug this function",
        session_id: "session-456",
        user_id: "user-789",
        context: %{language: "elixir"}
      }

      context = %{
        agent_id: "coordinator-test",
        agent: %{state: %{active_tasks: %{}, event_aggregation: %{}}}
      }

      assert {:ok, result, directives} = HandleChatRequest.run(params, context)

      # Check result
      assert result.status == :routed
      assert result.session_id == "session-456"
      assert result.task_id != nil

      # Action returns SetState + 2 Emit directives (chat received + llm request)
      assert length(directives) == 3

      # First directive should be SetState
      state_directive =
        Enum.find(directives, fn
          %Jido.Agent.StateOp.SetState{} -> true
          _ -> false
        end)

      assert state_directive != nil

      # Find the chat_received Emit directive
      chat_directive =
        Enum.find(directives, fn
          %Jido.Agent.Directive.Emit{signal: %{data: %{event_type: "chat_received"}}} -> true
          _ -> false
        end)

      assert chat_directive != nil
      assert chat_directive.signal.data.payload.message == "Help me debug this function"

      # Find the LLM request Emit directive
      llm_directive =
        Enum.find(directives, fn
          %Jido.Agent.Directive.Emit{signal: %{type: "jido_coder.llm.request"}} -> true
          _ -> false
        end)

      assert llm_directive != nil
    end

    test "generates unique task IDs for each request" do
      params1 = %{message: "Test 1", session_id: "session-1"}
      params2 = %{message: "Test 2", session_id: "session-1"}

      context = %{
        agent_id: "coordinator-test",
        agent: %{state: %{active_tasks: %{}, event_aggregation: %{}}}
      }

      {:ok, result1, _} = HandleChatRequest.run(params1, context)
      {:ok, result2, _} = HandleChatRequest.run(params2, context)

      assert result1.task_id != result2.task_id
    end

    test "handles missing optional fields" do
      params = %{
        message: "Simple request",
        session_id: "session-abc"
      }

      context = %{
        agent_id: "coordinator-test",
        agent: %{state: %{active_tasks: %{}, event_aggregation: %{}}}
      }

      assert {:ok, result, directives} = HandleChatRequest.run(params, context)

      assert result.status == :routed

      # Action returns SetState + 2 Emit directives
      # Find the chat_received Emit directive
      chat_directive =
        Enum.find(directives, fn
          %Jido.Agent.Directive.Emit{signal: %{data: %{event_type: "chat_received"}}} -> true
          _ -> false
        end)

      assert chat_directive != nil
      # user_id is not in payload when not provided
      refute Map.has_key?(chat_directive.signal.data.payload, :user_id)
    end
  end
end
