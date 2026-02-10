defmodule Jidoka.Agents.LLMOrchestrator.Actions.HandleLLMResponseTest do
  @moduledoc """
  Tests for HandleLLMResponse action.
  """

  use ExUnit.Case, async: true

  alias Jidoka.Agents.LLMOrchestrator.Actions.HandleLLMResponse
  alias Jidoka.Signals

  describe "run/2" do
    test "broadcasts llm_response to client" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        content: "This is an LLM response",
        session_id: session_id
      }

      assert {:ok, result, directives} = HandleLLMResponse.run(params, %{})
      assert result.status == :completed
      assert result.session_id == session_id

      # Should have a broadcast directive
      broadcast_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.client.broadcast"

        _ ->
          false
      end)

      assert broadcast_directive != nil
    end

    test "includes model in response when provided" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        content: "Response text",
        session_id: session_id,
        model: "gpt-4"
      }

      assert {:ok, _result, directives} = HandleLLMResponse.run(params, %{})

      # Check that model is included in the broadcast
      broadcast_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.client.broadcast"

        _ ->
          false
      end)

      assert broadcast_directive != nil
      assert broadcast_directive.signal.data.payload.model == "gpt-4"
    end

    test "includes tokens_used in response when provided" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        content: "Response text",
        session_id: session_id,
        tokens_used: 150
      }

      assert {:ok, _result, directives} = HandleLLMResponse.run(params, %{})

      # Check that tokens_used is included in the broadcast
      broadcast_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.client.broadcast"

        _ ->
          false
      end)

      assert broadcast_directive != nil
      assert broadcast_directive.signal.data.payload.tokens_used == 150
    end

    test "emits log_answer signal when conversation tracking available" do
      session_id = "test_session_#{System.unique_integer()}"
      conversation_iri = "https://jido.ai/conversations##{session_id}"
      turn_index = 0

      params = %{
        content: "Response to log",
        session_id: session_id,
        conversation_iri: conversation_iri,
        turn_index: turn_index
      }

      assert {:ok, _result, directives} = HandleLLMResponse.run(params, %{})

      # Should have a log_answer directive
      log_answer_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.conversation.log_answer"

        _ ->
          false
      end)

      assert log_answer_directive != nil
      assert log_answer_directive.signal.data.answer_text == "Response to log"
    end

    test "does not emit log_answer when conversation tracking unavailable" do
      session_id = "test_session_#{System.unique_integer()}"

      params = %{
        content: "Response",
        session_id: session_id
        # No conversation_iri or turn_index
      }

      assert {:ok, _result, directives} = HandleLLMResponse.run(params, %{})

      # Should NOT have a log_answer directive
      log_answer_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.Directive.Emit, signal: signal} ->
          signal.type == "jido_coder.conversation.log_answer"

        _ ->
          false
      end)

      assert log_answer_directive == nil
    end

    test "deletes active request when request_id provided" do
      session_id = "test_session_#{System.unique_integer()}"
      request_id = "llm_#{session_id}_#{System.unique_integer()}"

      params = %{
        request_id: request_id,
        content: "Response",
        session_id: session_id
      }

      assert {:ok, _result, directives} = HandleLLMResponse.run(params, %{})

      # Should have a DeletePath directive
      delete_directive = Enum.find(directives, fn
        %{__struct__: Jido.Agent.StateOp.DeletePath} -> true
        _ -> false
      end)

      assert delete_directive != nil
      assert delete_directive.path == [:active_requests, request_id]
    end
  end
end
