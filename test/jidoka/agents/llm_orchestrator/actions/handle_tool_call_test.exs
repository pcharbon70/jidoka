defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleToolCallTest do
  @moduledoc """
  Tests for HandleToolCall action.
  """

  use ExUnit.Case, async: true

  alias Jidoka.Agents.LLMOrchestrator.Actions.HandleToolCall
  alias Jidoka.Messaging

  describe "run/2" do
    test "broadcasts tool_call to client" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        session_id: session_id,
        tool_name: "search_code",
        parameters: %{query: "Jido.Agent"}
      }

      assert {:ok, result, directives} = HandleToolCall.run(params, %{})
      assert result.status == :logged
      assert result.session_id == session_id
      assert result.tool_name == "search_code"

      # Should have a broadcast directive
      broadcast_directive =
        Enum.find(directives, fn
          %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
            signal.type == "jido_coder.client.broadcast"

          _ ->
            false
        end)

      assert broadcast_directive != nil
      assert broadcast_directive.signal.data.event_type == "tool_call"
    end

    test "includes tool_index when provided" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        session_id: session_id,
        tool_name: "search_code",
        tool_index: 0,
        parameters: %{}
      }

      assert {:ok, _result, directives} = HandleToolCall.run(params, %{})

      broadcast_directive =
        Enum.find(directives, fn
          %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
            signal.type == "jido_coder.client.broadcast"

          _ ->
            false
        end)

      assert broadcast_directive != nil
      assert broadcast_directive.signal.data.event_type == "tool_call"
      assert broadcast_directive.signal.data.payload.tool_index == 0
    end

    test "persists tool invocation in messaging history" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        session_id: session_id,
        tool_index: 0,
        tool_name: "search_code",
        parameters: %{query: "test"}
      }

      assert {:ok, _result, directives} = HandleToolCall.run(params, %{})
      assert is_list(directives)

      assert {:ok, messages} = Messaging.list_session_messages(session_id)

      assert Enum.any?(messages, fn message ->
               message.role == :tool and
                 Enum.any?(message.content, fn block ->
                   text = Map.get(block, :text, "")
                   String.contains?(text, "[tool_call") and String.contains?(text, "search_code")
                 end)
             end)
    end
  end
end
