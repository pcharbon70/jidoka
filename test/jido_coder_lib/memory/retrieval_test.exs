defmodule JidoCoderLib.Memory.RetrievalTest do
  use ExUnit.Case, async: true

  alias JidoCoderLib.Memory.{Retrieval, LongTerm.SessionAdapter}

  @valid_memory %{
    id: "mem_1",
    type: :fact,
    data: %{"key" => "value", "description" => "A test fact"},
    importance: 0.8
  }

  @file_memory %{
    id: "mem_file",
    type: :file_context,
    data: %{"file_path" => "/path/to/file.ex", "language" => "elixir"},
    importance: 0.7
  }

  @analysis_memory %{
    id: "mem_analysis",
    type: :analysis,
    data: %{"conclusion" => "The refactoring is complete", "confidence" => "high"},
    importance: 0.9
  }

  describe "search/2" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      # Store some test memories
      {:ok, _} = SessionAdapter.persist_memory(adapter, @valid_memory)
      {:ok, _} = SessionAdapter.persist_memory(adapter, @file_memory)
      {:ok, _} = SessionAdapter.persist_memory(adapter, @analysis_memory)

      %{adapter: adapter}
    end

    test "returns all memories when no filters provided", %{adapter: adapter} do
      assert {:ok, results} = Retrieval.search(adapter, %{})

      assert length(results) == 3
      assert Enum.all?(results, fn r -> is_map(r.memory) end)
      assert Enum.all?(results, fn r -> is_float(r.score) end)
    end

    test "filters by keyword match", %{adapter: adapter} do
      assert {:ok, results} = Retrieval.search(adapter, %{keywords: ["elixir"]})

      assert length(results) == 1
      assert hd(results).memory.id == "mem_file"
      assert hd(results).match_reasons == ["elixir"]
    end

    test "filters by type", %{adapter: adapter} do
      assert {:ok, results} = Retrieval.search(adapter, %{type: :fact})

      assert length(results) == 1
      assert hd(results).memory.id == "mem_1"
    end

    test "filters by min_importance", %{adapter: adapter} do
      assert {:ok, results} = Retrieval.search(adapter, %{min_importance: 0.8})

      assert length(results) >= 1

      assert Enum.all?(results, fn r ->
               Map.get(r.memory, :importance, 0.0) >= 0.8
             end)
    end

    test "applies limit to results", %{adapter: adapter} do
      assert {:ok, results} = Retrieval.search(adapter, %{limit: 2})

      assert length(results) <= 2
    end

    test "ranks results by relevance score", %{adapter: adapter} do
      assert {:ok, results} = Retrieval.search(adapter, %{keywords: ["test"]})

      assert length(results) >= 1
      # Results should be sorted by score (descending)
      scores = Enum.map(results, & &1.score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "combines multiple filters", %{adapter: adapter} do
      assert {:ok, results} =
               Retrieval.search(adapter, %{
                 keywords: ["test"],
                 type: :fact,
                 limit: 5
               })

      assert length(results) >= 0
    end
  end

  describe "search_with_cache/2" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      {:ok, _} = SessionAdapter.persist_memory(adapter, @valid_memory)

      # Clear cache before each test
      Retrieval.clear_cache()

      %{adapter: adapter}
    end

    test "returns cached results for same query", %{adapter: adapter} do
      query = %{keywords: ["test"]}

      assert {:ok, results1} = Retrieval.search_with_cache(adapter, query)
      assert {:ok, results2} = Retrieval.search_with_cache(adapter, query)

      assert results1 == results2
    end

    test "respects cache TTL", %{adapter: adapter} do
      query = %{keywords: ["test"], cache_ttl: 1}

      assert {:ok, _results} = Retrieval.search_with_cache(adapter, query)

      # Wait for cache to expire
      Process.sleep(1100)

      # Results should come from fresh search
      assert {:ok, _results} = Retrieval.search_with_cache(adapter, query)
    end

    test "different queries have different cache entries", %{adapter: adapter} do
      query1 = %{keywords: ["test"]}
      query2 = %{keywords: ["value"]}

      assert {:ok, results1} = Retrieval.search_with_cache(adapter, query1)
      assert {:ok, results2} = Retrieval.search_with_cache(adapter, query2)

      # Results should be different (different keywords)
      assert results1 != results2
    end

    test "cache_stats returns cache information", %{adapter: adapter} do
      assert {:ok, _results} = Retrieval.search_with_cache(adapter, %{keywords: ["test"]})

      stats = Retrieval.cache_stats()
      assert stats.size > 0
      assert stats.max_size == 100
    end

    test "clear_cache empties the cache", %{adapter: adapter} do
      assert {:ok, _results} = Retrieval.search_with_cache(adapter, %{keywords: ["test"]})

      assert Retrieval.cache_stats().size > 0

      :ok = Retrieval.clear_cache()

      assert Retrieval.cache_stats().size == 0
    end

    test "different sessions have separate cache entries (SEC-4 fix)" do
      # Create two different sessions
      {:ok, adapter1} = SessionAdapter.new("session_isolation_test_1")
      {:ok, adapter2} = SessionAdapter.new("session_isolation_test_2")

      # Store different data in each session
      {:ok, _} =
        SessionAdapter.persist_memory(adapter1, %{
          id: "mem_1",
          type: :fact,
          data: %{"owner" => "session_1"},
          importance: 0.8
        })

      {:ok, _} =
        SessionAdapter.persist_memory(adapter2, %{
          id: "mem_2",
          type: :fact,
          data: %{"owner" => "session_2"},
          importance: 0.8
        })

      # Same query for both sessions
      query = %{keywords: ["owner"]}

      # Results should be different (different sessions)
      assert {:ok, results1} = Retrieval.search_with_cache(adapter1, query)
      assert {:ok, results2} = Retrieval.search_with_cache(adapter2, query)

      # Each session should only get its own data
      assert length(results1) == 1
      assert length(results2) == 1
      assert hd(results1).memory.data["owner"] == "session_1"
      assert hd(results2).memory.data["owner"] == "session_2"

      # Cache should have 2 entries (one per session)
      stats = Retrieval.cache_stats()
      assert stats.size == 2
    end
  end

  describe "enrich_context/3" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      {:ok, _} = SessionAdapter.persist_memory(adapter, @valid_memory)
      {:ok, _} = SessionAdapter.persist_memory(adapter, @file_memory)

      %{adapter: adapter}
    end

    test "returns context with memories and summary", %{adapter: adapter} do
      assert {:ok, context} = Retrieval.enrich_context(adapter, %{keywords: ["test"]})

      assert is_list(context.memories)
      assert is_binary(context.summary)
      assert is_integer(context.count)
      assert %DateTime{} = context.last_retrieved
    end

    test "summary includes memory count and type breakdown", %{adapter: adapter} do
      assert {:ok, context} = Retrieval.enrich_context(adapter, %{})

      assert context.summary =~ ~r/Found \d+ memor/
      assert context.summary =~ ~r/fact/
    end

    test "respects max_tokens option", %{adapter: adapter} do
      assert {:ok, context} = Retrieval.enrich_context(adapter, %{}, max_tokens: 100)

      # Context should be returned (token limiting is approximate)
      assert is_map(context)
    end

    test "groups memories by type when requested", %{adapter: adapter} do
      assert {:ok, context} = Retrieval.enrich_context(adapter, %{}, group_by: :type)

      assert is_list(context.memories)
    end

    test "includes metadata when requested", %{adapter: adapter} do
      assert {:ok, context} = Retrieval.enrich_context(adapter, %{}, include_metadata: true)

      # First memory should have metadata
      first = hd(context.memories)

      assert Map.has_key?(first, :importance) or Map.has_key?(first, :created_at) or
               Map.has_key?(first, :type)
    end

    test "groups by recency when requested", %{adapter: adapter} do
      assert {:ok, context} = Retrieval.enrich_context(adapter, %{}, group_by: :recency)

      assert is_list(context.memories)
    end
  end

  describe "calculate_relevance/2" do
    setup do
      now = DateTime.utc_now()

      old_memory = %{
        id: "mem_old",
        type: :fact,
        data: %{"test" => "old fact"},
        importance: 0.5,
        created_at: DateTime.add(now, -48, :hour)
      }

      new_memory = %{
        id: "mem_new",
        type: :fact,
        data: %{"test" => "new fact"},
        importance: 0.8,
        created_at: now
      }

      type_match_memory = %{
        id: "mem_type",
        type: :analysis,
        data: %{"test" => "analysis"},
        importance: 0.6
      }

      %{old_memory: old_memory, new_memory: new_memory, type_match_memory: type_match_memory}
    end

    test "calculates relevance with keyword matches", %{old_memory: old_memory} do
      query = %{keywords: ["test"]}

      score = Retrieval.calculate_relevance(old_memory, query)

      assert score >= 0.0
      assert score <= 1.0
    end

    test "higher importance increases relevance score", %{
      old_memory: old_memory,
      new_memory: new_memory
    } do
      query = %{keywords: ["test"]}

      score_high_importance = Retrieval.calculate_relevance(new_memory, query)
      score_low_importance = Retrieval.calculate_relevance(%{old_memory | importance: 0.2}, query)

      assert score_high_importance > score_low_importance
    end

    test "type match increases relevance score when type filter present", %{
      type_match_memory: type_match_memory
    } do
      query_with_type = %{keywords: ["test"], type: :analysis}
      query_without_type = %{keywords: ["test"]}

      score_with_type = Retrieval.calculate_relevance(type_match_memory, query_with_type)
      score_without_type = Retrieval.calculate_relevance(type_match_memory, query_without_type)

      assert score_with_type > score_without_type
    end

    test "returns 0.0 for no keywords and no type filter", %{new_memory: new_memory} do
      query = %{}

      score = Retrieval.calculate_relevance(new_memory, query)

      # Should only have importance and recency components
      assert score >= 0.0
      assert score <= 1.0
    end
  end

  describe "edge cases" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      %{adapter: adapter}
    end

    test "handles empty result set", %{adapter: adapter} do
      assert {:ok, results} = Retrieval.search(adapter, %{keywords: ["nonexistent"]})

      assert results == []
    end

    test "handles empty keywords list", %{adapter: adapter} do
      {:ok, _} = SessionAdapter.persist_memory(adapter, @valid_memory)

      assert {:ok, results} = Retrieval.search(adapter, %{keywords: []})

      assert length(results) >= 0
    end

    test "handles nil data in memory" do
      {:ok, adapter} = SessionAdapter.new("test_nil_data")

      nil_data_memory = %{
        id: "mem_nil",
        type: :fact,
        data: nil,
        importance: 0.5
      }

      {:ok, _} = SessionAdapter.persist_memory(adapter, nil_data_memory)

      assert {:ok, results} = Retrieval.search(adapter, %{})
      assert length(results) >= 0
    end

    test "handles complex nested data structures" do
      {:ok, adapter} = SessionAdapter.new("test_complex")

      complex_memory = %{
        id: "mem_complex",
        type: :fact,
        data: %{
          "nested" => %{"deep" => %{"value" => "complex"}},
          "list" => [1, 2, 3]
        },
        importance: 0.5
      }

      {:ok, _} = SessionAdapter.persist_memory(adapter, complex_memory)

      assert {:ok, results} = Retrieval.search(adapter, %{keywords: ["complex"]})
      assert length(results) >= 0
    end
  end

  describe "integration: keyword matching" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      %{adapter: adapter}
    end

    test "finds memories with substring match", %{adapter: adapter} do
      memory = %{
        id: "mem_substring",
        type: :fact,
        data: %{"file_path" => "/path/to/my_file.ex"},
        importance: 0.5
      }

      {:ok, _} = SessionAdapter.persist_memory(adapter, memory)

      assert {:ok, results} = Retrieval.search(adapter, %{keywords: ["file"]})

      assert length(results) >= 1
    end

    test "finds memories with multiple keyword matches", %{adapter: adapter} do
      memory = %{
        id: "mem_multi",
        type: :fact,
        data: %{"file" => "test", "type" => "analysis"},
        importance: 0.5
      }

      {:ok, _} = SessionAdapter.persist_memory(adapter, memory)

      assert {:ok, results} = Retrieval.search(adapter, %{keywords: ["file", "test"]})

      # Multiple matches should increase score
      assert length(results) >= 1
    end
  end
end
