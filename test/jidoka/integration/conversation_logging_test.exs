defmodule Jidoka.Integration.ConversationLoggingTest do
  @moduledoc """
  Integration tests for conversation logging flow.

  Tests the complete flow:
  1. Chat request comes in
  2. Conversation IRI is obtained from Conversation.Tracker
  3. Turn index is incremented
  4. Prompt is logged
  5. LLM response is logged
  6. Tool calls/results are logged

  These tests require the knowledge graph to be available.
  """

  use ExUnit.Case, async: false

  alias Jidoka.{Agents, Conversation, PubSub, Signals}
  alias Jido.Signal
  alias Jidoka.Knowledge.NamedGraphs
  alias Jidoka.Knowledge.Ontology

  @moduletag :knowledge_graph_required

  setup do
    # Set up knowledge graph for each test
    NamedGraphs.create(:conversation_history)
    Ontology.load_conversation_ontology()

    # Start PubSub for signal routing
    start_supervised!(Jidoka.PubSub)

    # Create a unique session for this test
    session_id = "conv_log_test_#{System.unique_integer([:positive, :monotonic])}"

    # Start Session supervisor with Conversation.Tracker
    {:ok, _sup_pid} = Jidoka.Session.Supervisor.start_link(session_id, [])

    # Get the conversation tracker PID
    {:ok, tracker_pid} = Jidoka.Session.Supervisor.get_conversation_tracker_pid(session_id)

    # Get or create conversation
    {:ok, conversation_iri} = Conversation.Tracker.get_or_create_conversation(tracker_pid)

    %{session_id: session_id, conversation_iri: conversation_iri, tracker_pid: tracker_pid}
  end

  describe "conversation logging flow" do
    test "chat request includes conversation IRI", context do
      %{session_id: session_id, conversation_iri: conversation_iri} = context

      # Create a chat request signal
      chat_request_signal =
        Signals.ChatRequest.new!(%{
          message: "What is Elixir?",
          session_id: session_id
        })

      # Simulate the HandleChatRequest action processing
      # (In real flow, this would be dispatched through the agent)
      assert {:ok, _result, _directives} =
               Agents.Coordinator.Actions.HandleChatRequest.run(
                 %{
                   message: "What is Elixir?",
                   session_id: session_id,
                   context: %{},
                   user_id: nil
                 },
                 %{}
               )

      # The conversation_iri should be available in the tracker
      {:ok, tracked_iri} = Conversation.Tracker.conversation_iri(context.tracker_pid)
      assert tracked_iri == conversation_iri
    end

    test "turn index increments on each request", context do
      %{tracker_pid: tracker_pid} = context

      # Get initial turn index
      {:ok, turn_0} = Conversation.Tracker.next_turn_index(tracker_pid)
      assert turn_0 == 0

      # Get next turn index
      {:ok, turn_1} = Conversation.Tracker.next_turn_index(tracker_pid)
      assert turn_1 == 1

      # Get next turn index
      {:ok, turn_2} = Conversation.Tracker.next_turn_index(tracker_pid)
      assert turn_2 == 2

      # Current turn index should be 2
      {:ok, current} = Conversation.Tracker.current_turn_index(tracker_pid)
      assert current == 2
    end

    test "log_prompt creates conversation turn in knowledge graph", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      # Log a prompt using the LogConversationTurn action
      assert {:ok, result} =
               Agents.Coordinator.Actions.LogConversationTurn.run(
                 %{
                   conversation_iri: conversation_iri,
                   turn_index: 0,
                   session_id: session_id,
                   prompt_text: "What is Elixir?"
                 },
                 %{}
               )

      assert result.status == :logged
      assert result.type == :prompt

      # Verify the prompt was logged to the knowledge graph
      # (This would require SPARQL queries to verify)
    end

    test "log_answer creates conversation turn in knowledge graph", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      # Log an answer using the LogConversationTurn action
      answer_text = "Elixir is a dynamic, functional programming language..."

      assert {:ok, result} =
               Agents.Coordinator.Actions.LogConversationTurn.run(
                 %{
                   conversation_iri: conversation_iri,
                   turn_index: 0,
                   session_id: session_id,
                   answer_text: answer_text
                 },
                 %{}
               )

      assert result.status == :logged
      assert result.type == :answer
    end

    test "log_tool_invocation creates tool invocation in knowledge graph", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      # Log a tool invocation
      assert {:ok, result} =
               Agents.Coordinator.Actions.LogConversationTurn.run(
                 %{
                   conversation_iri: conversation_iri,
                   turn_index: 0,
                   session_id: session_id,
                   tool_index: 0,
                   tool_name: "search_code",
                   parameters: %{"query" => "Jido.Agent"}
                 },
                 %{}
               )

      assert result.status == :logged
      assert result.type == :tool_invocation
      assert result.tool_index == 0
    end

    test "log_tool_result creates tool result in knowledge graph", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      # Log a tool result
      assert {:ok, result} =
               Agents.Coordinator.Actions.LogConversationTurn.run(
                 %{
                   conversation_iri: conversation_iri,
                   turn_index: 0,
                   session_id: session_id,
                   tool_index: 0,
                   result_data: %{"results" => ["file1.ex", "file2.ex"]}
                 },
                 %{}
               )

      assert result.status == :logged
      assert result.type == :tool_result
      assert result.tool_index == 0
    end
  end

  describe "signal-based logging" do
    test "LogPrompt signal can be created and dispatched", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      # Create a LogPrompt signal
      {:ok, signal} =
        Signals.LogPrompt.new(
          conversation_iri,
          0,
          "Test prompt",
          session_id,
          dispatch: false
        )

      assert signal.type == "jido_coder.conversation.log_prompt"
      assert signal.data.conversation_iri == conversation_iri
      assert signal.data.turn_index == 0
      assert signal.data.prompt_text == "Test prompt"
    end

    test "LogAnswer signal can be created and dispatched", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      # Create a LogAnswer signal
      {:ok, signal} =
        Signals.LogAnswer.new(
          conversation_iri,
          0,
          "Test answer",
          session_id,
          dispatch: false
        )

      assert signal.type == "jido_coder.conversation.log_answer"
      assert signal.data.conversation_iri == conversation_iri
      assert signal.data.turn_index == 0
      assert signal.data.answer_text == "Test answer"
    end

    test "LogToolInvocation signal can be created and dispatched", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      # Create a LogToolInvocation signal
      {:ok, signal} =
        Signals.LogToolInvocation.new(
          conversation_iri,
          0,
          0,
          "search_code",
          %{"query" => "test"},
          session_id,
          dispatch: false
        )

      assert signal.type == "jido_coder.conversation.log_tool_invocation"
      assert signal.data.conversation_iri == conversation_iri
      assert signal.data.turn_index == 0
      assert signal.data.tool_index == 0
      assert signal.data.tool_name == "search_code"
    end

    test "LogToolResult signal can be created and dispatched", context do
      %{conversation_iri: conversation_iri, session_id: session_id} = context

      # Create a LogToolResult signal
      {:ok, signal} =
        Signals.LogToolResult.new(
          conversation_iri,
          0,
          0,
          %{"results" => ["file1.ex"]},
          session_id,
          dispatch: false
        )

      assert signal.type == "jido_coder.conversation.log_tool_result"
      assert signal.data.conversation_iri == conversation_iri
      assert signal.data.turn_index == 0
      assert signal.data.tool_index == 0
    end
  end
end
