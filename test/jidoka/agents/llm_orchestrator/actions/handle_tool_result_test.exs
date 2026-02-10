defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleToolResultTest do
  @moduledoc """
  Tests for HandleToolResult action.
  """

  use ExUnit.Case, async: true

  alias Jidoka.Agents.LLMOrchestrator.Actions.HandleToolResult

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
      broadcast_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.client.broadcast"

        _ ->
          false
      end)

      assert broadcast_directive != nil
      assert broadcast_directive.signal.data.event_type == "tool_result"
      assert broadcast_directive.signal.data.payload.result == %{results: ["file1.ex", "file2.ex"]}
    end

    test "includes tool_index when provided" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        session_id: session_id,
        tool_index: 0,
        result_data: %{}
      }

      assert {:ok, _result, directives} = HandleToolResult.run(params, %{})

      broadcast_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.client.broadcast"

        _ ->
          false
      end)

      assert broadcast_directive != nil
      assert broadcast_directive.signal.data.payload.tool_index == 0
    end

    test "emits log_tool_result signal when conversation tracking available" do
      session_id = "test_session_#{System.unique_integer()}"
      conversation_iri = "https://jido.ai/conversations##{session_id}"

      params = %{
        session_id: session_id,
        conversation_iri: conversation_iri,
        turn_index: 0,
        tool_index: 0,
        result_data: %{results: ["file1.ex"]}
      }

      assert {:ok, _result, directives} = HandleToolResult.run(params, %{})

      # Should have a log_tool_result directive
      log_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.conversation.log_tool_result"

        _ ->
          false
      end)

      assert log_directive != nil
      assert log_directive.signal.data.tool_index == 0
    end

    test "does not emit log_tool_result when conversation tracking unavailable" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        session_id: session_id,
        result_data: %{}
      }

      assert {:ok, _result, directives} = HandleToolResult.run(params, %{})

      # Should NOT have a log_tool_result directive
      log_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.conversation.log_tool_result"

        _ ->
          false
      end)

      assert log_directive == nil
    end
  end
end
