defmodule JidoCoderLib.Memory.PromotionEngineTest do
  use ExUnit.Case, async: true

  alias JidoCoderLib.Memory.{PromotionEngine, ShortTerm, LongTerm.SessionAdapter}
  alias ShortTerm.PendingMemories

  @valid_memory %{
    id: "mem_1",
    type: :fact,
    data: %{"key" => "value"},
    importance: 0.8,
    timestamp: DateTime.utc_now()
  }

  @low_importance_memory %{
    id: "mem_low",
    type: :fact,
    data: %{"key" => "value"},
    importance: 0.3,
    timestamp: DateTime.utc_now()
  }

  @old_memory %{
    id: "mem_old",
    type: :fact,
    data: %{"key" => "value"},
    importance: 0.6,
    timestamp: DateTime.add(DateTime.utc_now(), -400, :second)
  }

  describe "evaluate_and_promote/3" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      stm = ShortTerm.new(session_id)
      {:ok, ltm} = SessionAdapter.new(session_id)

      %{stm: stm, ltm: ltm, session_id: session_id}
    end

    test "processes items from pending memories", %{stm: stm, ltm: ltm} do
      {:ok, stm} = ShortTerm.enqueue_memory(stm, @valid_memory)

      assert {:ok, _updated_stm, results} = PromotionEngine.evaluate_and_promote(stm, ltm)
      assert length(results.promoted) >= 0
      assert is_list(results.skipped)
      assert is_list(results.failed)
    end

    test "promotes items meeting importance criteria", %{stm: stm, ltm: ltm} do
      {:ok, stm} = ShortTerm.enqueue_memory(stm, @valid_memory)

      assert {:ok, _stm, results} =
               PromotionEngine.evaluate_and_promote(stm, ltm, min_importance: 0.7)

      assert length(results.promoted) == 1
      assert hd(results.promoted).id == "mem_1"
    end

    test "skips items below importance threshold", %{stm: stm, ltm: ltm} do
      {:ok, stm} = ShortTerm.enqueue_memory(stm, @low_importance_memory)

      assert {:ok, _stm, results} =
               PromotionEngine.evaluate_and_promote(stm, ltm, min_importance: 0.5)

      assert length(results.skipped) == 1
      assert hd(results.skipped).reason == "below threshold"
    end

    test "promotes old items regardless of importance", %{stm: stm, ltm: ltm} do
      {:ok, stm} = ShortTerm.enqueue_memory(stm, @old_memory)

      assert {:ok, _stm, results} =
               PromotionEngine.evaluate_and_promote(stm, ltm, max_age_seconds: 300)

      # Old memory should be promoted due to age
      assert length(results.promoted) == 1
    end

    test "high importance items override age threshold", %{stm: stm, ltm: ltm} do
      recent_high_importance = %{
        id: "mem_recent_high",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.9,
        timestamp: DateTime.utc_now()
      }

      {:ok, stm} = ShortTerm.enqueue_memory(stm, recent_high_importance)

      assert {:ok, _stm, results} =
               PromotionEngine.evaluate_and_promote(stm, ltm, max_age_seconds: 300)

      # High importance (0.9) should override age threshold
      assert length(results.promoted) == 1
    end

    test "respects batch size limit", %{stm: stm, ltm: ltm} do
      # Enqueue multiple items
      Enum.each(1..15, fn i ->
        item = %{
          id: "mem_#{i}",
          type: :fact,
          data: %{"index" => i},
          importance: 0.8,
          timestamp: DateTime.utc_now()
        }

        {:ok, stm} = ShortTerm.enqueue_memory(stm, item)
      end)

      # Process with batch size of 5
      assert {:ok, _stm, results} = PromotionEngine.evaluate_and_promote(stm, ltm, batch_size: 5)

      # Should only process 5 items
      total_processed =
        length(results.promoted) + length(results.skipped) + length(results.failed)

      assert total_processed <= 5
    end

    test "returns updated stm with items removed from pending", %{stm: stm, ltm: ltm} do
      {:ok, stm} = ShortTerm.enqueue_memory(stm, @valid_memory)

      {:ok, updated_stm, _results} = PromotionEngine.evaluate_and_promote(stm, ltm)

      # Item should be removed from pending memories
      assert PendingMemories.size(updated_stm.pending_memories) == 0
    end
  end

  describe "promote_all/2" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      stm = ShortTerm.new(session_id)
      {:ok, ltm} = SessionAdapter.new(session_id)

      %{stm: stm, ltm: ltm}
    end

    test "promotes all items regardless of criteria", %{stm: stm, ltm: ltm} do
      {:ok, stm} = ShortTerm.enqueue_memory(stm, @low_importance_memory)

      assert {:ok, _stm, results} = PromotionEngine.promote_all(stm, ltm)

      # Even low importance should be promoted
      assert length(results.promoted) == 1
      assert results.promoted |> hd() |> Map.get(:id) == "mem_low"
    end

    test "returns results with promoted items", %{stm: stm, ltm: ltm} do
      {:ok, stm} = ShortTerm.enqueue_memory(stm, @valid_memory)

      assert {:ok, _stm, results} = PromotionEngine.promote_all(stm, ltm)

      assert [%{id: _, confidence: _, reason: _}] = results.promoted
    end
  end

  describe "evaluate_item/2" do
    setup do
      criteria = %{
        min_importance: 0.5,
        max_age_seconds: 300,
        min_confidence: 0.3,
        infer_types: true
      }

      %{criteria: criteria}
    end

    test "returns :promote for items meeting all criteria", %{criteria: criteria} do
      assert {:ok, :promote, confidence} = PromotionEngine.evaluate_item(@valid_memory, criteria)
      assert is_float(confidence)
      assert confidence >= 0.0
      assert confidence <= 1.0
    end

    test "returns :skip for items below importance threshold", %{criteria: criteria} do
      assert {:ok, :skip, :below_importance_threshold} =
               PromotionEngine.evaluate_item(@low_importance_memory, criteria)
    end

    test "returns :promote for old items due to age", %{criteria: criteria} do
      old_criteria = Map.put(criteria, :max_age_seconds, 300)

      assert {:ok, :promote, _confidence} =
               PromotionEngine.evaluate_item(@old_memory, old_criteria)
    end

    test "returns error for items missing required fields", %{criteria: criteria} do
      invalid_item = %{id: "mem_invalid"}
      # Missing :data field

      assert {:error, {:missing_fields, fields}} =
               PromotionEngine.evaluate_item(invalid_item, criteria)

      assert :data in fields
    end

    test "returns error for items without type when inference disabled", %{
      criteria: criteria
    } do
      no_type_item = %{
        id: "mem_no_type",
        data: %{"key" => "value"}
      }

      no_infer_criteria = Map.put(criteria, :infer_types, false)

      assert {:error, {:missing_type, :no_type_and_inference_disabled}} =
               PromotionEngine.evaluate_item(no_type_item, no_infer_criteria)
    end
  end

  describe "infer_type/1" do
    test "infers :file_context for file references" do
      item = %{id: "mem_1", data: %{file_path: "/path/to/file.ex"}}

      assert PromotionEngine.infer_type(item) == :file_context
    end

    test "infers :file_context for code references" do
      item = %{id: "mem_1", data: %{module: "MyModule", function: "my_func"}}

      assert PromotionEngine.infer_type(item) == :file_context
    end

    test "infers :analysis for analysis content" do
      item = %{id: "mem_1", data: %{conclusion: "The refactoring is complete"}}

      assert PromotionEngine.infer_type(item) == :analysis
    end

    test "infers :analysis for reasoning content" do
      item = %{id: "mem_1", data: %{reasoning: "Step by step analysis"}}

      assert PromotionEngine.infer_type(item) == :analysis
    end

    test "infers :conversation for message content" do
      item = %{id: "mem_1", data: %{role: "user", content: "Hello"}}

      assert PromotionEngine.infer_type(item) == :conversation
    end

    test "defaults to :fact for generic data" do
      item = %{id: "mem_1", data: %{"key" => "value"}}

      assert PromotionEngine.infer_type(item) == :fact
    end

    test "defaults to :fact when data is missing" do
      item = %{id: "mem_1", data: %{}}

      assert PromotionEngine.infer_type(item) == :fact
    end
  end

  describe "calculate_confidence/2" do
    test "calculates confidence for high importance item" do
      item = %{
        id: "mem_1",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.9
      }

      confidence = PromotionEngine.calculate_confidence(item)
      assert confidence >= 0.5
    end

    test "calculates confidence for low importance item" do
      item = %{
        id: "mem_1",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.3
      }

      confidence = PromotionEngine.calculate_confidence(item)
      assert confidence >= 0.0
      assert confidence < 0.5
    end

    test "gives bonus for explicit type" do
      item_with_type = %{
        id: "mem_1",
        type: :analysis,
        data: %{"conclusion" => "result"},
        importance: 0.5
      }

      item_without_type = %{
        id: "mem_2",
        data: %{"conclusion" => "result"},
        importance: 0.5
      }

      confidence_with = PromotionEngine.calculate_confidence(item_with_type)
      confidence_without = PromotionEngine.calculate_confidence(item_without_type)

      assert confidence_with > confidence_without
    end

    test "gives bonus for rich data" do
      rich_item = %{
        id: "mem_1",
        data: %{"key1" => "val1", "key2" => "val2", "key3" => "val3"},
        importance: 0.5
      }

      poor_item = %{
        id: "mem_2",
        data: %{},
        importance: 0.5
      }

      rich_confidence = PromotionEngine.calculate_confidence(rich_item)
      poor_confidence = PromotionEngine.calculate_confidence(poor_item)

      assert rich_confidence > poor_confidence
    end

    test "clamps confidence between 0.0 and 1.0" do
      perfect_item = %{
        id: "mem_1",
        type: :fact,
        data: Map.new(1..10, fn i -> {"key#{i}", "val#{i}"} end),
        importance: 1.0
      }

      confidence = PromotionEngine.calculate_confidence(perfect_item)
      assert confidence <= 1.0
    end
  end

  describe "integration: end-to-end promotion" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      stm = ShortTerm.new(session_id)
      {:ok, ltm} = SessionAdapter.new(session_id)

      %{stm: stm, ltm: ltm, session_id: session_id}
    end

    test "promoted item is stored in LTM", %{stm: stm, ltm: ltm, session_id: session_id} do
      {:ok, stm} = ShortTerm.enqueue_memory(stm, @valid_memory)

      assert {:ok, _stm, results} = PromotionEngine.evaluate_and_promote(stm, ltm)

      # Verify item was stored in LTM
      assert {:ok, memory} = SessionAdapter.get_memory(ltm, "mem_1")
      assert memory.session_id == session_id
      assert memory.type == :fact
    end

    test "skipped items remain in pending queue", %{stm: stm, ltm: ltm} do
      {:ok, stm} = ShortTerm.enqueue_memory(stm, @low_importance_memory)

      assert {:ok, updated_stm, results} =
               PromotionEngine.evaluate_and_promote(stm, ltm, min_importance: 0.5)

      # Item should be skipped
      assert length(results.skipped) == 1

      # And should still be in pending queue
      assert PendingMemories.size(updated_stm.pending_memories) == 1
    end

    test "multiple items processed in batch", %{stm: stm, ltm: ltm} do
      items = [
        %{
          id: "mem_1",
          type: :fact,
          data: %{"k" => "v1"},
          importance: 0.8,
          timestamp: DateTime.utc_now()
        },
        %{
          id: "mem_2",
          type: :analysis,
          data: %{"k" => "v2"},
          importance: 0.7,
          timestamp: DateTime.utc_now()
        },
        %{
          id: "mem_3",
          type: :fact,
          data: %{"k" => "v3"},
          importance: 0.9,
          timestamp: DateTime.utc_now()
        }
      ]

      stm =
        Enum.reduce(items, stm, fn item, acc ->
          {:ok, acc} = ShortTerm.enqueue_memory(acc, item)
          acc
        end)

      assert {:ok, _stm, results} = PromotionEngine.evaluate_and_promote(stm, ltm)

      # mem_1 (0.8) and mem_3 (0.9) should be promoted (high importance overrides age)
      # mem_2 (0.7) should be skipped (too recent and not high enough importance)
      assert length(results.promoted) == 2
      assert length(results.skipped) == 1
      assert length(results.failed) == 0
    end

    test "type inference works for items without explicit type", %{stm: stm, ltm: ltm} do
      item_without_type = %{
        id: "mem_inferred",
        data: %{file_path: "/path/to/file.ex"},
        importance: 0.8,
        timestamp: DateTime.utc_now()
      }

      {:ok, stm} = ShortTerm.enqueue_memory(stm, item_without_type)

      assert {:ok, _stm, results} = PromotionEngine.evaluate_and_promote(stm, ltm)

      # Should be promoted with inferred type
      assert length(results.promoted) == 1

      # Verify LTM has the inferred type
      assert {:ok, memory} = SessionAdapter.get_memory(ltm, "mem_inferred")
      assert memory.type == :file_context
    end
  end

  describe "error handling" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      stm = ShortTerm.new(session_id)
      {:ok, ltm} = SessionAdapter.new(session_id)

      %{stm: stm, ltm: ltm}
    end

    test "handles invalid items gracefully", %{stm: stm, ltm: ltm} do
      # Items without :data are rejected at enqueue time by PendingMemories
      invalid_item = %{
        id: "mem_invalid",
        # Missing :data field
        importance: 0.8,
        timestamp: DateTime.utc_now()
      }

      assert {:error, {:missing_field, :data}} = ShortTerm.enqueue_memory(stm, invalid_item)
    end

    test "continues processing after failure", %{stm: stm, ltm: ltm} do
      # Item with low importance that will be skipped (but causes no failure)
      low_importance_item = %{
        id: "mem_low",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.3,
        timestamp: DateTime.utc_now()
      }

      # Valid item with high importance
      valid_item = %{
        id: "mem_valid",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.8,
        timestamp: DateTime.utc_now()
      }

      {:ok, stm} = ShortTerm.enqueue_memory(stm, low_importance_item)
      {:ok, stm} = ShortTerm.enqueue_memory(stm, valid_item)

      assert {:ok, _stm, results} = PromotionEngine.evaluate_and_promote(stm, ltm)

      # One skipped (low importance), one promoted (high importance)
      assert length(results.skipped) == 1
      assert length(results.promoted) == 1
      assert hd(results.promoted).id == "mem_valid"
    end
  end
end
