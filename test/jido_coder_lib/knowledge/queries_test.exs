defmodule JidoCoderLib.Knowledge.QueriesTest do
  use ExUnit.Case, async: false

  alias JidoCoderLib.Knowledge.{Queries, Engine, Ontology}
  alias JidoCoderLib.Memory.LongTerm.TripleStoreAdapter

  @moduletag :queries
  @moduletag :external
  @engine_name :test_queries_engine
  @data_dir "./test/data/queries_test"

  # Note: async: false due to known SPARQL parser issues in triple_store dependency

  setup do
    # Create a unique data directory for each test
    test_name = :erlang.phash2(make_ref())
    data_dir = Path.join(@data_dir, to_string(test_name))
    File.mkdir_p!(data_dir)

    # Set the application config to use our test engine
    Application.put_env(:jido_coder_lib, :knowledge_engine_name, @engine_name)

    # Start the knowledge engine
    {:ok, pid} =
      Engine.start_link(
        name: @engine_name,
        data_dir: data_dir,
        create_standard_graphs: true
      )

    # Ensure the ontology is loaded for class IRIs
    Ontology.load_jido_ontology()

    on_exit(fn ->
      Application.delete_env(:jido_coder_lib, :knowledge_engine_name)
      File.rm_rf!(data_dir)
    end)

    {:ok, %{engine: pid, data_dir: data_dir}}
  end

  describe "find_facts/1" do
    test "returns empty list when no facts exist", %{engine: _pid} do
      assert {:ok, []} = Queries.find_facts()
    end

    test "returns Fact items when they exist", %{engine: _pid} do
      session_id = "test-session-facts"

      # Insert a fact memory using TripleStoreAdapter
      memory = %{
        id: "mem-fact-1",
        session_id: session_id,
        type: :fact,
        data: %{"content" => "Named graphs segregate triples"},
        importance: 0.9,
        created_at: DateTime.utc_now()
      }

      assert {:ok, _} = persist_memory(memory, @engine_name)

      # Query for facts
      assert {:ok, facts} = Queries.find_facts(session_id: session_id, engine_name: @engine_name)

      assert length(facts) >= 1
      fact = Enum.find(facts, fn f -> f.id == "mem-fact-1" end)
      assert fact
      assert fact.type == :fact
      assert fact.session_id == session_id
      assert fact.data["content"] == "Named graphs segregate triples"
      assert fact.importance == 0.9
    end

    test "filters by min_confidence", %{engine: _pid} do
      session_id = "test-session-confidence"

      # Insert two facts with different confidence
      memory_high = %{
        id: "mem-high-confidence",
        session_id: session_id,
        type: :fact,
        data: %{"content" => "High confidence fact"},
        importance: 0.9,
        created_at: DateTime.utc_now()
      }

      memory_low = %{
        id: "mem-low-confidence",
        session_id: session_id,
        type: :fact,
        data: %{"content" => "Low confidence fact"},
        importance: 0.3,
        created_at: DateTime.utc_now()
      }

      assert {:ok, _} = persist_memory(memory_high, @engine_name)
      assert {:ok, _} = persist_memory(memory_low, @engine_name)

      # Query with min_confidence filter
      assert {:ok, facts} =
               Queries.find_facts(
                 session_id: session_id,
                 min_confidence: 0.8,
                 engine_name: @engine_name
               )

      assert length(facts) >= 1
      refute Enum.any?(facts, fn f -> f.id == "mem-low-confidence" end)
      assert Enum.any?(facts, fn f -> f.id == "mem-high-confidence" end)
    end

    test "respects limit option", %{engine: _pid} do
      session_id = "test-session-limit"

      # Insert multiple facts
      for i <- 1..5 do
        memory = %{
          id: "mem-fact-#{i}",
          session_id: session_id,
          type: :fact,
          data: %{"content" => "Fact #{i}"},
          importance: 0.5,
          created_at: DateTime.utc_now()
        }

        assert {:ok, _} = persist_memory(memory, @engine_name)
      end

      # Query with limit
      assert {:ok, facts} =
               Queries.find_facts(session_id: session_id, limit: 3, engine_name: @engine_name)

      assert length(facts) <= 3
    end
  end

  describe "find_decisions/1" do
    test "returns Decision items when they exist", %{engine: _pid} do
      session_id = "test-session-decisions"

      memory = %{
        id: "mem-decision-1",
        session_id: session_id,
        type: :decision,
        data: %{"content" => "Use named graphs for session isolation"},
        importance: 0.85,
        created_at: DateTime.utc_now()
      }

      assert {:ok, _} = persist_memory(memory, @engine_name)

      assert {:ok, decisions} =
               Queries.find_decisions(session_id: session_id, engine_name: @engine_name)

      assert length(decisions) >= 1
      decision = Enum.find(decisions, fn d -> d.id == "mem-decision-1" end)
      assert decision
      assert decision.type == :decision
    end

    test "returns empty list when no decisions exist", %{engine: _pid} do
      assert {:ok, []} =
               Queries.find_decisions(
                 session_id: "nonexistent-session",
                 engine_name: @engine_name
               )
    end
  end

  describe "find_lessons/1" do
    test "returns LessonLearned items when they exist", %{engine: _pid} do
      session_id = "test-session-lessons"

      memory = %{
        id: "mem-lesson-1",
        session_id: session_id,
        type: :lesson_learned,
        data: %{"content" => "SPARQL parser has issues with concurrent test execution"},
        importance: 0.95,
        created_at: DateTime.utc_now()
      }

      assert {:ok, _} = persist_memory(memory, @engine_name)

      assert {:ok, lessons} =
               Queries.find_lessons(session_id: session_id, engine_name: @engine_name)

      assert length(lessons) >= 1
      lesson = Enum.find(lessons, fn l -> l.id == "mem-lesson-1" end)
      assert lesson
      assert lesson.type == :lesson_learned
    end

    test "returns empty list when no lessons exist", %{engine: _pid} do
      assert {:ok, []} =
               Queries.find_lessons(session_id: "nonexistent-session", engine_name: @engine_name)
    end
  end

  describe "session_memories/2" do
    test "returns all memory types for a session", %{engine: _pid} do
      session_id = "test-session-all-types"

      # Insert different types of memories
      memories = [
        %{
          id: "mem-fact",
          session_id: session_id,
          type: :fact,
          data: %{"content" => "Fact memory"},
          importance: 0.8,
          created_at: DateTime.utc_now()
        },
        %{
          id: "mem-decision",
          session_id: session_id,
          type: :decision,
          data: %{"content" => "Decision memory"},
          importance: 0.7,
          created_at: DateTime.utc_now()
        },
        %{
          id: "mem-lesson",
          session_id: session_id,
          type: :lesson_learned,
          data: %{"content" => "Lesson learned"},
          importance: 0.9,
          created_at: DateTime.utc_now()
        }
      ]

      Enum.each(memories, fn memory ->
        assert {:ok, _} = persist_memory(memory, @engine_name)
      end)

      # Query all memories for session
      assert {:ok, memories} = Queries.session_memories(session_id, engine_name: @engine_name)

      assert length(memories) >= 3
      assert Enum.any?(memories, fn m -> m.id == "mem-fact" end)
      assert Enum.any?(memories, fn m -> m.id == "mem-decision" end)
      assert Enum.any?(memories, fn m -> m.id == "mem-lesson" end)
    end

    test "filters by type when type option is provided", %{engine: _pid} do
      session_id = "test-session-type-filter"

      memories = [
        %{
          id: "mem-fact-1",
          session_id: session_id,
          type: :fact,
          data: %{"content" => "Fact"},
          importance: 0.5,
          created_at: DateTime.utc_now()
        },
        %{
          id: "mem-decision-1",
          session_id: session_id,
          type: :decision,
          data: %{"content" => "Decision"},
          importance: 0.5,
          created_at: DateTime.utc_now()
        }
      ]

      Enum.each(memories, fn memory ->
        assert {:ok, _} = persist_memory(memory, @engine_name)
      end)

      # Query only facts
      assert {:ok, facts} =
               Queries.session_memories(session_id, type: :fact, engine_name: @engine_name)

      assert length(facts) >= 1
      assert Enum.any?(facts, fn f -> f.id == "mem-fact-1" end)
      refute Enum.any?(facts, fn f -> f.id == "mem-decision-1" end)
    end

    test "returns empty list for non-existent session", %{engine: _pid} do
      assert {:ok, []} =
               Queries.session_memories("nonexistent-session", engine_name: @engine_name)
    end
  end

  describe "memories_by_type/2" do
    test "returns memories for valid type", %{engine: _pid} do
      session_id = "test-session-by-type"

      memory = %{
        id: "mem-by-type-1",
        session_id: session_id,
        type: :fact,
        data: %{"content" => "Test content"},
        importance: 0.6,
        created_at: DateTime.utc_now()
      }

      assert {:ok, _} = persist_memory(memory, @engine_name)

      assert {:ok, memories} =
               Queries.memories_by_type(:fact, session_id: session_id, engine_name: @engine_name)

      assert length(memories) >= 1
      assert Enum.any?(memories, fn m -> m.id == "mem-by-type-1" end)
    end

    test "returns error for invalid type", %{engine: _pid} do
      assert {:error, {:invalid_type, :invalid_type}} =
               Queries.memories_by_type(:invalid_type, engine_name: @engine_name)
    end

    test "filters by session_id", %{engine: _pid} do
      session_id_1 = "test-session-by-type-1"
      session_id_2 = "test-session-by-type-2"

      memory1 = %{
        id: "mem-session-1",
        session_id: session_id_1,
        type: :fact,
        data: %{"content" => "Session 1"},
        importance: 0.5,
        created_at: DateTime.utc_now()
      }

      memory2 = %{
        id: "mem-session-2",
        session_id: session_id_2,
        type: :fact,
        data: %{"content" => "Session 2"},
        importance: 0.5,
        created_at: DateTime.utc_now()
      }

      assert {:ok, _} = persist_memory(memory1, @engine_name)
      assert {:ok, _} = persist_memory(memory2, @engine_name)

      # Query for session 1 only
      assert {:ok, memories} =
               Queries.memories_by_type(:fact,
                 session_id: session_id_1,
                 engine_name: @engine_name
               )

      assert Enum.any?(memories, fn m -> m.id == "mem-session-1" end)
      refute Enum.any?(memories, fn m -> m.id == "mem-session-2" end)
    end
  end

  describe "recent_memories/1" do
    test "returns memories ordered by timestamp (newest first)", %{engine: _pid} do
      session_id = "test-session-recent"

      # Insert memories with different timestamps
      now = DateTime.utc_now()

      memories = [
        %{
          id: "mem-old",
          session_id: session_id,
          type: :fact,
          data: %{"content" => "Old memory"},
          importance: 0.5,
          created_at: DateTime.add(now, -3600, :second)
        },
        %{
          id: "mem-new",
          session_id: session_id,
          type: :fact,
          data: %{"content" => "New memory"},
          importance: 0.5,
          created_at: DateTime.add(now, -60, :second)
        },
        %{
          id: "mem-newest",
          session_id: session_id,
          type: :fact,
          data: %{"content" => "Newest memory"},
          importance: 0.5,
          created_at: now
        }
      ]

      Enum.each(memories, fn memory ->
        assert {:ok, _} = persist_memory(memory, @engine_name)
      end)

      # Query recent memories
      assert {:ok, recent} =
               Queries.recent_memories(
                 session_id: session_id,
                 limit: 10,
                 engine_name: @engine_name
               )

      # Verify ordering is newest first (descending)
      timestamps = Enum.map(recent, fn m -> m.created_at end)
      assert timestamps == Enum.sort(timestamps, {:desc, DateTime})
    end

    test "uses default limit of 10", %{engine: _pid} do
      session_id = "test-session-default-limit"

      # Insert 15 memories
      for i <- 1..15 do
        memory = %{
          id: "mem-#{i}",
          session_id: session_id,
          type: :fact,
          data: %{"content" => "Memory #{i}"},
          importance: 0.5,
          created_at: DateTime.utc_now()
        }

        assert {:ok, _} = persist_memory(memory, @engine_name)
      end

      # Query recent memories without specifying limit
      assert {:ok, recent} =
               Queries.recent_memories(session_id: session_id, engine_name: @engine_name)

      # Should return at most 10 (default limit)
      assert length(recent) <= 10
    end

    test "filters by type when type option is provided", %{engine: _pid} do
      session_id = "test-session-recent-type"

      memories = [
        %{
          id: "mem-recent-fact",
          session_id: session_id,
          type: :fact,
          data: %{"content" => "Recent fact"},
          importance: 0.5,
          created_at: DateTime.utc_now()
        },
        %{
          id: "mem-recent-decision",
          session_id: session_id,
          type: :decision,
          data: %{"content" => "Recent decision"},
          importance: 0.5,
          created_at: DateTime.utc_now()
        }
      ]

      Enum.each(memories, fn memory ->
        assert {:ok, _} = persist_memory(memory, @engine_name)
      end)

      # Query only facts
      assert {:ok, facts} =
               Queries.recent_memories(
                 session_id: session_id,
                 type: :fact,
                 engine_name: @engine_name
               )

      assert Enum.any?(facts, fn f -> f.id == "mem-recent-fact" end)
      refute Enum.any?(facts, fn f -> f.id == "mem-recent-decision" end)
    end
  end

  describe "result parsing" do
    test "parses JSON content into data map", %{engine: _pid} do
      session_id = "test-session-json-parse"

      memory = %{
        id: "mem-json",
        session_id: session_id,
        type: :fact,
        data: %{"key" => "value", "nested" => %{"item" => "data"}},
        importance: 0.5,
        created_at: DateTime.utc_now()
      }

      assert {:ok, _} = persist_memory(memory, @engine_name)

      assert {:ok, [parsed_memory]} =
               Queries.find_facts(session_id: session_id, engine_name: @engine_name)

      assert parsed_memory.data["key"] == "value"
      assert parsed_memory.data["nested"]["item"] == "data"
    end

    test "extracts memory_id and session_id from subject IRI", %{engine: _pid} do
      session_id = "test-session-iri-parse"

      memory = %{
        id: "mem-iri-test",
        session_id: session_id,
        type: :fact,
        data: %{"content" => "IRI parsing test"},
        importance: 0.5,
        created_at: DateTime.utc_now()
      }

      assert {:ok, _} = persist_memory(memory, @engine_name)

      assert {:ok, [parsed_memory]} =
               Queries.find_facts(session_id: session_id, engine_name: @engine_name)

      assert parsed_memory.id == "mem-iri-test"
      assert parsed_memory.session_id == session_id
    end
  end

  describe "empty results handling" do
    test "find_facts returns empty list for non-existent session", %{engine: _pid} do
      assert {:ok, []} =
               Queries.find_facts(
                 session_id: "nonexistent-session-xyz",
                 engine_name: @engine_name
               )
    end

    test "find_decisions returns empty list for non-existent session", %{engine: _pid} do
      assert {:ok, []} =
               Queries.find_decisions(
                 session_id: "nonexistent-session-xyz",
                 engine_name: @engine_name
               )
    end

    test "find_lessons returns empty list for non-existent session", %{engine: _pid} do
      assert {:ok, []} =
               Queries.find_lessons(
                 session_id: "nonexistent-session-xyz",
                 engine_name: @engine_name
               )
    end

    test "session_memories returns empty list for non-existent session", %{engine: _pid} do
      assert {:ok, []} =
               Queries.session_memories("nonexistent-session-xyz", engine_name: @engine_name)
    end

    test "recent_memories returns empty list for non-existent session", %{engine: _pid} do
      assert {:ok, []} =
               Queries.recent_memories(
                 session_id: "nonexistent-session-xyz",
                 engine_name: @engine_name
               )
    end
  end

  # Helper functions

  defp persist_memory(memory, engine_name) do
    adapter = TripleStoreAdapter.new!(memory.session_id, engine_name: engine_name)
    TripleStoreAdapter.persist_memory(adapter, memory)
  end
end
