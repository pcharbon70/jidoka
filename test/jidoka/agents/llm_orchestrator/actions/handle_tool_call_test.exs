defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleToolCallTest do
  @moduledoc """
  Tests for HandleToolCall action.
  """

  use ExUnit.Case, async: true

  alias Jidoka.Agents.LLMOrchestrator.Actions.HandleToolCall

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
      broadcast_directive = Enum.find(directives, fn
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

      broadcast_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.client.broadcast"

        _ ->
          false
      end)

      assert broadcast_directive != nil
      assert broadcast_directive.signal.data.event_type == "tool_call"
      assert broadcast_directive.signal.data.payload.tool_index == 0
    end

    test "emits log_tool_invocation signal when conversation tracking available" do
      session_id = "test_session_#{System.unique_integer()}"
      conversation_iri = "https://jido.ai/conversations##{session_id}"

      params = %{
        session_id: session_id,
        conversation_iri: conversation_iri,
        turn_index: 0,
        tool_index: 0,
        tool_name: "search_code",
        parameters: %{query: "test"}
      }

      assert {:ok, _result, directives} = HandleToolCall.run(params, %{})

      # Should have a log_tool_invocation directive
      log_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.conversation.log_tool_invocation"

        _ ->
          false
      end)

      assert log_directive != nil
      assert log_directive.signal.data.tool_name == "search_code"
      assert log_directive.signal.data.tool_index == 0
    end

    test "does not emit log_tool_invocation when conversation tracking unavailable" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        session_id: session_id,
        tool_name: "search_code",
        parameters: %{}
      }

      assert {:ok, _result, directives} = HandleToolCall.run(params, %{})

      # Should NOT have a log_tool_invocation directive
      log_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.conversation.log_tool_invocation"

        _ ->
          false
      end)

      assert log_directive == nil
    end
  end
end
