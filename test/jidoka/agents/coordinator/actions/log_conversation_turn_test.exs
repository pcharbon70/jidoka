defmodule Jidoka.Agents.Coordinator.Actions.LogConversationTurnTest do
  @moduledoc """
  Tests for LogConversationTurn action.
  """

  use ExUnit.Case, async: false

  alias Jidoka.Agents.Coordinator.Actions.LogConversationTurn
  alias Jidoka.Knowledge.{NamedGraphs, Ontology}

  @moduletag :knowledge_graph_required

  setup do
    # Set up knowledge graph for each test
    NamedGraphs.create(:conversation_history)
    Ontology.load_conversation_ontology()

    session_id = "test_log_session_#{System.unique_integer([:positive, :monotonic])}"
    conversation_iri = "https://jido.ai/conversations##{session_id}"

    # Ensure conversation exists
    {:ok, ^conversation_iri} = Jidoka.Conversation.Logger.ensure_conversation(session_id)

    %{session_id: session_id, conversation_iri: conversation_iri}
  end

  describe "run/2" do
    test "logs a prompt successfully", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      params = %{
        conversation_iri: conversation_iri,
        turn_index: 0,
        session_id: session_id,
        prompt_text: "What is Elixir?"
      }

      assert {:ok, result} = LogConversationTurn.run(params, %{})
      assert result.status == :logged
      assert result.type == :prompt
      assert result.session_id == session_id
      assert result.turn_index == 0
    end

    test "logs an answer successfully", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      params = %{
        conversation_iri: conversation_iri,
        turn_index: 0,
        session_id: session_id,
        answer_text: "Elixir is a dynamic, functional language..."
      }

      assert {:ok, result} = LogConversationTurn.run(params, %{})
      assert result.status == :logged
      assert result.type == :answer
    end

    test "logs a tool invocation successfully", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      params = %{
        conversation_iri: conversation_iri,
        turn_index: 0,
        session_id: session_id,
        tool_index: 0,
        tool_name: "search_code",
        parameters: %{"query" => "Jido.Agent"}
      }

      assert {:ok, result} = LogConversationTurn.run(params, %{})
      assert result.status == :logged
      assert result.type == :tool_invocation
      assert result.tool_index == 0
    end

    test "logs a tool result successfully", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      params = %{
        conversation_iri: conversation_iri,
        turn_index: 0,
        session_id: session_id,
        tool_index: 0,
        result_data: %{"results" => ["file1.ex", "file2.ex"]}
      }

      assert {:ok, result} = LogConversationTurn.run(params, %{})
      assert result.status == :logged
      assert result.type == :tool_result
      assert result.tool_index == 0
    end

    test "returns unknown_signal_type for unrecognized signal", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      params = %{
        conversation_iri: conversation_iri,
        turn_index: 0,
        session_id: session_id
        # No type-specific field
      }

      assert {:ok, result} = LogConversationTurn.run(params, %{})
      assert result.status == :unknown_signal_type
    end
  end
end
