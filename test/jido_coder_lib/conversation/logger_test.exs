defmodule JidoCoderLib.Conversation.LoggerTest do
  use ExUnit.Case, async: false

  alias JidoCoderLib.Conversation.Logger
  alias JidoCoderLib.Knowledge.{Ontology, NamedGraphs}

  @moduletag :conversation_logger
  @moduletag :external

  setup do
    NamedGraphs.create(:conversation_history)
    Ontology.load_conversation_ontology()
    session_id = "test_session_#{System.unique_integer()}"
    %{session_id: session_id}
  end

  # ==============================================================================
  # ensure_conversation/2 Tests
  # ==============================================================================

  describe "ensure_conversation/2" do
    test "creates a new conversation", %{session_id: session_id} do
      assert {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      assert is_binary(conversation_iri)
      assert String.contains?(conversation_iri, session_id)
    end

    test "is idempotent - returns same IRI on second call", %{session_id: session_id} do
      assert {:ok, iri1} = Logger.ensure_conversation(session_id)
      assert {:ok, iri2} = Logger.ensure_conversation(session_id)
      assert iri1 == iri2
    end
  end

  # ==============================================================================
  # log_turn/3 Tests
  # ==============================================================================

  describe "log_turn/3" do
    test "creates a conversation turn", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      assert {:ok, turn_iri} = Logger.log_turn(conversation_iri, 0)
      assert String.contains?(turn_iri, "turn-0")
    end
  end

  # ==============================================================================
  # log_prompt/3 Tests
  # ==============================================================================

  describe "log_prompt/3" do
    test "creates a prompt with text", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      assert {:ok, prompt_iri} = Logger.log_prompt(conversation_iri, 0, "Hello, world!")
      assert String.contains?(prompt_iri, "prompt")
    end

    test "handles special characters in prompt", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      special_text = "Test with 'quotes' and \"double quotes\" and newlines\n"
      assert {:ok, _} = Logger.log_prompt(conversation_iri, 0, special_text)
    end
  end

  # ==============================================================================
  # log_answer/3 Tests
  # ==============================================================================

  describe "log_answer/3" do
    test "creates an answer with text", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      assert {:ok, answer_iri} = Logger.log_answer(conversation_iri, 0, "Hi there!")
      assert String.contains?(answer_iri, "answer")
    end
  end

  # ==============================================================================
  # log_tool_invocation/4 Tests
  # ==============================================================================

  describe "log_tool_invocation/4" do
    test "creates tool invocation with parameters", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      params = %{"query" => "SELECT *", "limit" => 10}

      assert {:ok, invocation_iri} =
               Logger.log_tool_invocation(conversation_iri, 0, 0, "sparql_query", params)

      assert String.contains?(invocation_iri, "tool-0")
    end

    test "handles nil parameters gracefully", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      assert {:ok, _} = Logger.log_tool_invocation(conversation_iri, 0, 0, "test_tool", nil)
    end

    test "handles empty parameters gracefully", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      assert {:ok, _} = Logger.log_tool_invocation(conversation_iri, 0, 0, "test_tool", %{})
    end
  end

  # ==============================================================================
  # log_tool_result/4 Tests
  # ==============================================================================

  describe "log_tool_result/4" do
    test "creates tool result with data", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      result_data = %{"status" => "success", "rows" => 5}

      assert {:ok, result_iri} = Logger.log_tool_result(conversation_iri, 0, 0, result_data)
      assert String.contains?(result_iri, "result")
    end

    test "handles nil result data gracefully", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)
      assert {:ok, _} = Logger.log_tool_result(conversation_iri, 0, 0, nil)
    end
  end

  # ==============================================================================
  # Integration Tests
  # ==============================================================================

  describe "integration: full conversation logging" do
    test "logs a complete conversation turn", %{session_id: session_id} do
      {:ok, conversation_iri} = Logger.ensure_conversation(session_id)

      {:ok, turn_iri} = Logger.log_turn(conversation_iri, 0)
      {:ok, prompt_iri} = Logger.log_prompt(conversation_iri, 0, "What is Elixir?")
      {:ok, invocation_iri} =
        Logger.log_tool_invocation(conversation_iri, 0, 0, "search", %{"query" => "Elixir"})

      {:ok, result_iri} = Logger.log_tool_result(conversation_iri, 0, 0, %{"results" => []})
      {:ok, answer_iri} = Logger.log_answer(conversation_iri, 0, "Elixir is a programming language.")

      # All IRIs should be returned
      assert turn_iri != nil
      assert prompt_iri != nil
      assert invocation_iri != nil
      assert result_iri != nil
      assert answer_iri != nil
    end
  end
end
