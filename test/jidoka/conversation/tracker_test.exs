defmodule Jidoka.Conversation.TrackerTest do
  @moduledoc """
  Tests for Conversation.Tracker GenServer.
  """

  use ExUnit.Case, async: false

  alias Jidoka.Conversation.Tracker
  alias Jidoka.Knowledge.{NamedGraphs, Ontology}

  @moduletag :knowledge_graph_required

  setup_all do
    # Start registry if not already started
    case Process.whereis(Jidoka.Memory.SessionRegistry) do
      nil ->
        {:ok, _pid} = Registry.start_link(keys: :unique, name: Jidoka.Memory.SessionRegistry)

      _pid ->
        :ok
    end

    :ok
  end

  setup do
    # Set up knowledge graph for each test
    NamedGraphs.create(:conversation_history)
    Ontology.load_conversation_ontology()

    session_id = "test_tracker_session_#{System.unique_integer([:positive, :monotonic])}"

    %{session_id: session_id}
  end

  describe "start_link/1" do
    test "starts a tracker for a valid session_id", context do
      %{session_id: session_id} = context

      assert {:ok, pid} = Tracker.start_link(session_id)
      assert Process.alive?(pid)
      assert is_pid(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "starts with list argument for supervision tree", context do
      %{session_id: session_id} = context

      assert {:ok, pid} = Tracker.start_link([session_id])
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "registers the tracker in SessionRegistry", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      # Check registration using the via tuple
      registry_key = {:conversation_tracker, session_id}

      assert [{^pid, _}] = Registry.lookup(Jidoka.Memory.SessionRegistry, registry_key)

      GenServer.stop(pid)
    end
  end

  describe "get_or_create_conversation/1" do
    test "creates a new conversation on first call", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      assert {:ok, conversation_iri} = Tracker.get_or_create_conversation(pid)
      assert conversation_iri == "https://jido.ai/conversations##{session_id}"

      GenServer.stop(pid)
    end

    test "returns cached conversation on subsequent calls", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      # First call should create conversation
      assert {:ok, conversation_iri} = Tracker.get_or_create_conversation(pid)

      # Second call should return same IRI
      assert {:ok, ^conversation_iri} = Tracker.get_or_create_conversation(pid)

      GenServer.stop(pid)
    end
  end

  describe "next_turn_index/1" do
    test "returns 0 on first call", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      assert {:ok, 0} = Tracker.next_turn_index(pid)

      GenServer.stop(pid)
    end

    test "increments turn index on each call", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      assert {:ok, 0} = Tracker.next_turn_index(pid)
      assert {:ok, 1} = Tracker.next_turn_index(pid)
      assert {:ok, 2} = Tracker.next_turn_index(pid)

      GenServer.stop(pid)
    end

    test "increments atomically (concurrent access)", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      # Spawn multiple tasks to request turn indices concurrently
      tasks =
        for _ <- 1..10 do
          Task.async(fn -> Tracker.next_turn_index(pid) end)
        end

      results = Task.await_many(tasks, 5000)

      # All results should be unique and sequential 0-9
      sorted_results = results |> Enum.sort() |> Enum.map(fn {:ok, v} -> v end)
      assert sorted_results == Enum.to_list(0..9)

      GenServer.stop(pid)
    end
  end

  describe "current_turn_index/1" do
    test "returns current turn without incrementing", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      assert {:ok, 0} = Tracker.current_turn_index(pid)
      assert {:ok, 0} = Tracker.current_turn_index(pid)

      assert {:ok, 0} = Tracker.next_turn_index(pid)
      assert {:ok, 1} = Tracker.current_turn_index(pid)
      assert {:ok, 1} = Tracker.current_turn_index(pid)

      GenServer.stop(pid)
    end
  end

  describe "conversation_iri/1" do
    test "returns :not_found when conversation not created", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      assert {:error, :not_found} = Tracker.conversation_iri(pid)

      GenServer.stop(pid)
    end

    test "returns conversation IRI after creation", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      # Create conversation
      {:ok, conversation_iri} = Tracker.get_or_create_conversation(pid)

      # Get conversation IRI
      assert {:ok, ^conversation_iri} = Tracker.conversation_iri(pid)

      GenServer.stop(pid)
    end
  end

  describe "session_id/1" do
    test "returns the session_id", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      assert ^session_id = Tracker.session_id(pid)

      GenServer.stop(pid)
    end
  end

  describe "summary/1" do
    test "returns a summary of tracker state", context do
      %{session_id: session_id} = context

      {:ok, pid} = Tracker.start_link(session_id)

      # Create conversation
      {:ok, _iri} = Tracker.get_or_create_conversation(pid)

      # Get some turn indices
      {:ok, 0} = Tracker.next_turn_index(pid)
      {:ok, 1} = Tracker.next_turn_index(pid)

      summary = Tracker.summary(pid)

      assert summary.session_id == session_id
      assert summary.conversation_iri == "https://jido.ai/conversations##{session_id}"
      assert summary.turn_index == 2
      assert %DateTime{} = summary.started_at

      GenServer.stop(pid)
    end
  end
end
