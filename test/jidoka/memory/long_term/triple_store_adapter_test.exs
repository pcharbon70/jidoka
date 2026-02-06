defmodule Jidoka.Memory.LongTerm.TripleStoreAdapterTest do
  use ExUnit.Case, async: false

  alias Jidoka.Memory.LongTerm.TripleStoreAdapter
  alias Jidoka.Knowledge.{Engine, NamedGraphs, Ontology, Context}
  alias TripleStore.SPARQL.Query

  @moduletag :triple_store_adapter
  @moduletag :external
  @engine_name :test_knowledge_engine
  @data_dir "./test/data/kg_adapter_test"

  # Note: These tests use the test engine which is started/stopped per test

  setup do
    # Create a unique data directory for each test
    test_name = :erlang.phash2(make_ref())
    data_dir = Path.join(@data_dir, to_string(test_name))
    File.mkdir_p!(data_dir)

    # Set the application config to use our test engine
    Application.put_env(:jidoka, :knowledge_engine_name, @engine_name)

    # Start the knowledge engine
    {:ok, pid} =
      Engine.start_link(
        name: @engine_name,
        data_dir: data_dir,
        create_standard_graphs: true
      )

    # Ensure the ontology is loaded for class IRIs
    Ontology.load_jido_ontology()

    # Note: We don't stop the engine in on_exit because it's tied to the test process
    # The file cleanup still happens
    on_exit(fn ->
      Application.delete_env(:jidoka, :knowledge_engine_name)
      File.rm_rf!(data_dir)
    end)

    {:ok, %{engine: pid, data_dir: data_dir}}
  end

  describe "new/2" do
    test "creates adapter for valid session_id", %{engine: _pid} do
      assert {:ok, adapter} = TripleStoreAdapter.new("session_test_123")

      assert adapter.session_id == "session_test_123"
      assert adapter.engine_name == @engine_name
      assert adapter.graph_name == :long_term_context
    end

    test "creates adapter with custom options", %{engine: _pid} do
      assert {:ok, adapter} =
               TripleStoreAdapter.new("session_test_456",
                 engine_name: @engine_name,
                 graph_name: :long_term_context
               )

      assert adapter.session_id == "session_test_456"
      assert adapter.engine_name == @engine_name
    end

    test "rejects empty session_id", %{engine: _pid} do
      assert {:error, :invalid_session_id} = TripleStoreAdapter.new("")
    end

    test "rejects non-binary session_id", %{engine: _pid} do
      assert {:error, :invalid_session_id} = TripleStoreAdapter.new(123)
      assert {:error, :invalid_session_id} = TripleStoreAdapter.new(nil)
    end

    test "new! raises on error", %{engine: _pid} do
      assert_raise ArgumentError, ~r/Failed to create adapter/, fn ->
        TripleStoreAdapter.new!("")
      end
    end
  end

  describe "persist_memory/2" do
    test "persists fact memory successfully", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_persist_1")

      memory_item = %{
        id: "mem_1",
        type: :fact,
        data: %{"key" => "value", "number" => 42},
        importance: 0.8
      }

      assert {:ok, memory} = TripleStoreAdapter.persist_memory(adapter, memory_item)

      assert memory.id == "mem_1"
      assert memory.session_id == "session_persist_1"
      assert memory.type == :fact
      assert memory.importance == 0.8
      assert Map.has_key?(memory, :created_at)
      assert Map.has_key?(memory, :updated_at)
    end

    test "persists decision memory successfully", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_persist_2")

      memory_item = %{
        id: "mem_2",
        type: :decision,
        data: %{"decision" => "use SPARQL"},
        importance: 0.9
      }

      assert {:ok, memory} = TripleStoreAdapter.persist_memory(adapter, memory_item)
      assert memory.type == :decision
    end

    test "persists lesson_learned memory successfully", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_persist_3")

      memory_item = %{
        id: "mem_3",
        type: :lesson_learned,
        data: %{"lesson" => "test early and often"},
        importance: 0.95
      }

      assert {:ok, memory} = TripleStoreAdapter.persist_memory(adapter, memory_item)
      assert memory.type == :lesson_learned
    end

    test "validates required fields", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_persist_validate")

      assert {:error, {:missing_fields, _}} =
               TripleStoreAdapter.persist_memory(adapter, %{})

      assert {:error, {:missing_fields, _}} =
               TripleStoreAdapter.persist_memory(adapter, %{id: "mem_1"})
    end

    test "validates importance range", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_persist_importance")

      assert {:error, {:invalid_importance, _}} =
               TripleStoreAdapter.persist_memory(adapter, %{
                 id: "mem_1",
                 type: :fact,
                 data: %{},
                 importance: 1.5
               })

      assert {:error, {:invalid_importance, _}} =
               TripleStoreAdapter.persist_memory(adapter, %{
                 id: "mem_1",
                 type: :fact,
                 data: %{},
                 importance: -0.1
               })
    end

    test "validates memory size", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_persist_size")

      large_data = String.duplicate("x", 200_000)

      assert {:error, {:data_too_large, _, _}} =
               TripleStoreAdapter.persist_memory(adapter, %{
                 id: "mem_1",
                 type: :fact,
                 data: %{"large" => large_data},
                 importance: 0.5
               })
    end

    test "maps analysis type to decision", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_persist_analysis")

      assert {:ok, memory} =
               TripleStoreAdapter.persist_memory(adapter, %{
                 id: "mem_1",
                 type: :analysis,
                 data: %{"analysis" => "use map"},
                 importance: 0.7
               })

      # Analysis maps to Decision in Jido ontology
      assert memory.jido_type == :decision
    end
  end

  describe "query_memories/2" do
    setup %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_query_test")

      # Insert test memories
      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_fact_1",
          type: :fact,
          data: %{"fact" => "fact one"},
          importance: 0.9
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_fact_2",
          type: :fact,
          data: %{"fact" => "fact two"},
          importance: 0.7
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_decision_1",
          type: :decision,
          data: %{"decision" => "decision one"},
          importance: 0.85
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_lesson_1",
          type: :lesson_learned,
          data: %{"lesson" => "lesson one"},
          importance: 0.6
        })

      {:ok, adapter: adapter}
    end

    test "returns all memories for the session", %{adapter: adapter} do
      assert {:ok, memories} = TripleStoreAdapter.query_memories(adapter)
      assert length(memories) == 4
    end

    test "filters by type - fact", %{adapter: adapter} do
      assert {:ok, memories} = TripleStoreAdapter.query_memories(adapter, type: :fact)
      assert length(memories) == 2

      Enum.each(memories, fn m ->
        assert m.type == :fact
      end)
    end

    test "filters by type - decision", %{adapter: adapter} do
      assert {:ok, memories} = TripleStoreAdapter.query_memories(adapter, type: :decision)
      assert length(memories) == 1

      assert hd(memories).type == :decision
    end

    test "filters by type - lesson_learned", %{adapter: adapter} do
      assert {:ok, memories} = TripleStoreAdapter.query_memories(adapter, type: :lesson_learned)
      assert length(memories) == 1

      assert hd(memories).type == :lesson_learned
    end

    test "filters by min_importance", %{adapter: adapter} do
      assert {:ok, memories} = TripleStoreAdapter.query_memories(adapter, min_importance: 0.8)
      assert length(memories) == 2

      Enum.each(memories, fn m ->
        assert m.importance >= 0.8
      end)
    end

    test "filters by both type and min_importance", %{adapter: adapter} do
      assert {:ok, memories} =
               TripleStoreAdapter.query_memories(adapter,
                 type: :fact,
                 min_importance: 0.8
               )

      assert length(memories) == 1
      assert hd(memories).type == :fact
      assert hd(memories).importance >= 0.8
    end

    test "applies limit", %{adapter: adapter} do
      assert {:ok, memories} = TripleStoreAdapter.query_memories(adapter, limit: 2)
      assert length(memories) == 2
    end

    test "returns empty list when no memories match", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_empty_query")

      assert {:ok, memories} = TripleStoreAdapter.query_memories(adapter)
      assert memories == []
    end

    test "maintains session isolation", %{engine: _pid} do
      {:ok, adapter1} = TripleStoreAdapter.new("session_isolated_1")
      {:ok, adapter2} = TripleStoreAdapter.new("session_isolated_2")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter1, %{
          id: "mem_1",
          type: :fact,
          data: %{"session" => "1"},
          importance: 0.5
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter2, %{
          id: "mem_2",
          type: :fact,
          data: %{"session" => "2"},
          importance: 0.5
        })

      assert {:ok, memories1} = TripleStoreAdapter.query_memories(adapter1)
      assert {:ok, memories2} = TripleStoreAdapter.query_memories(adapter2)

      assert length(memories1) == 1
      assert length(memories2) == 1

      assert hd(memories1).id == "mem_1"
      assert hd(memories2).id == "mem_2"
    end
  end

  describe "get_memory/2" do
    setup %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_get_test")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_get_1",
          type: :fact,
          data: %{"key" => "get_test"},
          importance: 0.8
        })

      {:ok, adapter: adapter}
    end

    test "retrieves existing memory by id", %{adapter: adapter} do
      assert {:ok, memory} = TripleStoreAdapter.get_memory(adapter, "mem_get_1")

      assert memory.id == "mem_get_1"
      assert memory.type == :fact
      assert memory.data == %{"key" => "get_test"}
      assert memory.importance == 0.8
      assert Map.has_key?(memory, :created_at)
    end

    test "returns not found for non-existent memory", %{adapter: adapter} do
      assert {:error, :not_found} = TripleStoreAdapter.get_memory(adapter, "nonexistent")
    end

    test "retrieves memory with complex data", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_get_complex")

      complex_data = %{
        "string" => "value",
        "number" => 42,
        "float" => 3.14,
        "bool" => true,
        "nested" => %{"key" => "nested_value"},
        "list" => [1, 2, 3]
      }

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_complex",
          type: :fact,
          data: complex_data,
          importance: 0.7
        })

      assert {:ok, memory} = TripleStoreAdapter.get_memory(adapter, "mem_complex")
      assert memory.data == complex_data
    end
  end

  describe "update_memory/3" do
    setup %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_update_test")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_update_1",
          type: :fact,
          data: %{"original" => "data"},
          importance: 0.5
        })

      {:ok, adapter: adapter}
    end

    test "updates memory data", %{adapter: adapter} do
      assert {:ok, updated} =
               TripleStoreAdapter.update_memory(adapter, "mem_update_1", %{
                 data: %{"updated" => "data"}
               })

      assert updated.data == %{"updated" => "data"}
      # unchanged
      assert updated.importance == 0.5
    end

    test "updates memory importance", %{adapter: adapter} do
      assert {:ok, updated} =
               TripleStoreAdapter.update_memory(adapter, "mem_update_1", %{importance: 0.95})

      assert updated.importance == 0.95
      # unchanged
      assert updated.data == %{"original" => "data"}
    end

    test "updates multiple fields", %{adapter: adapter} do
      assert {:ok, updated} =
               TripleStoreAdapter.update_memory(adapter, "mem_update_1", %{
                 data: %{"new" => "data"},
                 importance: 0.85
               })

      assert updated.data == %{"new" => "data"}
      assert updated.importance == 0.85
    end

    test "updates timestamp", %{adapter: adapter} do
      {:ok, original} = TripleStoreAdapter.get_memory(adapter, "mem_update_1")
      original_timestamp = original.updated_at

      # Ensure time passes
      Process.sleep(10)

      assert {:ok, updated} =
               TripleStoreAdapter.update_memory(adapter, "mem_update_1", %{
                 data: %{"new" => "data"}
               })

      assert DateTime.compare(updated.updated_at, original_timestamp) == :gt
    end

    test "returns not found for non-existent memory", %{adapter: adapter} do
      assert {:error, :not_found} =
               TripleStoreAdapter.update_memory(adapter, "nonexistent", %{data: %{}})
    end

    test "rejects invalid update fields", %{adapter: adapter} do
      assert {:error, {:invalid_update_fields, _}} =
               TripleStoreAdapter.update_memory(adapter, "mem_update_1", %{id: "new_id"})
    end
  end

  describe "delete_memory/2" do
    setup %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_delete_test")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_delete_1",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      {:ok, adapter: adapter}
    end

    test "deletes existing memory", %{adapter: adapter} do
      assert {:ok, :deleted} = TripleStoreAdapter.delete_memory(adapter, "mem_delete_1")
      assert {:error, :not_found} = TripleStoreAdapter.get_memory(adapter, "mem_delete_1")
    end

    test "returns not found for non-existent memory", %{adapter: adapter} do
      assert {:error, :not_found} =
               TripleStoreAdapter.delete_memory(adapter, "nonexistent")
    end

    test "other memories remain after deletion", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_delete_multi")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_1",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_2",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      assert {:ok, :deleted} = TripleStoreAdapter.delete_memory(adapter, "mem_1")

      assert {:error, :not_found} = TripleStoreAdapter.get_memory(adapter, "mem_1")
      assert {:ok, _} = TripleStoreAdapter.get_memory(adapter, "mem_2")
    end
  end

  describe "count/1" do
    test "returns 0 for empty session", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_count_empty")

      assert TripleStoreAdapter.count(adapter) == 0
    end

    test "returns count of memories in session", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_count_test")

      assert TripleStoreAdapter.count(adapter) == 0

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_1",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      assert TripleStoreAdapter.count(adapter) == 1

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_2",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_3",
          type: :decision,
          data: %{},
          importance: 0.5
        })

      assert TripleStoreAdapter.count(adapter) == 3
    end

    test "maintains session isolation for count", %{engine: _pid} do
      {:ok, adapter1} = TripleStoreAdapter.new("session_count_1")
      {:ok, adapter2} = TripleStoreAdapter.new("session_count_2")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter1, %{
          id: "mem_1",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter2, %{
          id: "mem_2",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter2, %{
          id: "mem_3",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      assert TripleStoreAdapter.count(adapter1) == 1
      assert TripleStoreAdapter.count(adapter2) == 2
    end
  end

  describe "clear/1" do
    test "clears all memories from session", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_clear_test")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_1",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_2",
          type: :decision,
          data: %{},
          importance: 0.5
        })

      assert TripleStoreAdapter.count(adapter) == 2

      assert {:ok, :cleared} = TripleStoreAdapter.clear(adapter)

      assert TripleStoreAdapter.count(adapter) == 0
    end

    test "clear returns ok for already empty session", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_clear_empty")

      assert {:ok, :cleared} = TripleStoreAdapter.clear(adapter)
    end

    test "clear does not affect other sessions", %{engine: _pid} do
      {:ok, adapter1} = TripleStoreAdapter.new("session_clear_1")
      {:ok, adapter2} = TripleStoreAdapter.new("session_clear_2")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter1, %{
          id: "mem_1",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter2, %{
          id: "mem_2",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      assert {:ok, :cleared} = TripleStoreAdapter.clear(adapter1)

      assert TripleStoreAdapter.count(adapter1) == 0
      assert TripleStoreAdapter.count(adapter2) == 1
    end
  end

  describe "session_id/1" do
    test "returns the session_id", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_id_test_123")

      assert TripleStoreAdapter.session_id(adapter) == "session_id_test_123"
    end
  end

  describe "WorkSession linking" do
    test "creates WorkSession individual on first memory", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_worksession_test")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_1",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      # Query for the WorkSession individual
      ctx = Engine.context(@engine_name) |> Context.with_permit_all()
      session_iri = "https://jido.ai/sessions#session_worksession_test"

      query = """
      ASK {
        GRAPH <https://jido.ai/graphs/long-term-context> {
          <#{session_iri}> a <https://jido.ai/ontologies/core#WorkSession> .
        }
      }
      """

      assert {:ok, true} = Query.query(ctx, query, [])
    end

    test "links memory to WorkSession", %{engine: _pid} do
      {:ok, adapter} = TripleStoreAdapter.new("session_link_test")

      {:ok, _} =
        TripleStoreAdapter.persist_memory(adapter, %{
          id: "mem_link_1",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      # Query for the sourceSession relationship
      ctx = Engine.context(@engine_name) |> Context.with_permit_all()
      memory_iri = "https://jido.ai/memories#session_link_test_mem_link_1"
      session_iri = "https://jido.ai/sessions#session_link_test"

      query = """
      ASK {
        GRAPH <https://jido.ai/graphs/long-term-context> {
          <#{memory_iri}> <https://jido.ai/ontologies/core#sourceSession> <#{session_iri}> .
        }
      }
      """

      assert {:ok, true} = Query.query(ctx, query, [])
    end
  end
end
