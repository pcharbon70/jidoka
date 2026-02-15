defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleToolResultTest do
  @moduledoc """
  Tests for HandleToolResult action.
  """

  use ExUnit.Case, async: true

  alias Jidoka.Agents.LLMOrchestrator.Actions.HandleToolResult
  alias Jidoka.Messaging

  describe "run/2" do
    test "broadcasts tool_result to client" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        session_id: session_id,
        result_data: %{results: ["file1.ex", "file2.ex"]}
      }

      assert {:ok, result, directives} = HandleToolResult.run(params, %{})
      assert result.status == :logged
      assert result.session_id == session_id

      # Should have a broadcast directive
      broadcast_directive =
        Enum.find(directives, fn
          %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
            signal.type == "jido_coder.client.broadcast"

          _ ->
            false
        end)

      assert broadcast_directive != nil
      assert broadcast_directive.signal.data.event_type == "tool_result"

      assert broadcast_directive.signal.data.payload.result == %{
               results: ["file1.ex", "file2.ex"]
             }
    end

    test "includes tool_index when provided" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        session_id: session_id,
        tool_index: 0,
        result_data: %{}
      }

      assert {:ok, _result, directives} = HandleToolResult.run(params, %{})

      broadcast_directive =
        Enum.find(directives, fn
          %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
            signal.type == "jido_coder.client.broadcast"

          _ ->
            false
        end)

      assert broadcast_directive != nil
      assert broadcast_directive.signal.data.payload.tool_index == 0
    end

    test "persists tool result in messaging history" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        session_id: session_id,
        tool_index: 0,
        result_data: %{results: ["file1.ex"]}
      }

      assert {:ok, _result, directives} = HandleToolResult.run(params, %{})
      assert is_list(directives)

      assert {:ok, messages} = Messaging.list_session_messages(session_id)

      assert Enum.any?(messages, fn message ->
               message.role == :tool and
                 Enum.any?(message.content, fn block ->
                   text = Map.get(block, :text, "")
                   String.contains?(text, "[tool_result") and String.contains?(text, "file1.ex")
                 end)
             end)
    end
  end
end
