defmodule JidoCoderLib.Memory.ShortTerm.PendingMemoriesTest do
  use ExUnit.Case, async: true

  alias JidoCoderLib.Memory.ShortTerm.PendingMemories

  @valid_item %{
    id: "mem_1",
    type: :fact,
    data: %{key: "value"},
    importance: 0.8,
    timestamp: DateTime.utc_now()
  }

  describe "new/1" do
    test "creates queue with defaults" do
      pending = PendingMemories.new()

      assert PendingMemories.size(pending) == 0
      assert pending.max_size == 20
    end

    test "creates queue with custom max_size" do
      pending = PendingMemories.new(max_size: 50)

      assert pending.max_size == 50
    end
  end

  describe "enqueue/2" do
    test "adds item to queue" do
      pending = PendingMemories.new()

      assert {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)
      assert PendingMemories.size(pending) == 1
    end

    test "returns error when queue is full" do
      pending = PendingMemories.new(max_size: 1)

      {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)
      assert {:error, :at_capacity} = PendingMemories.enqueue(pending, @valid_item)
    end

    test "validates item has required fields" do
      pending = PendingMemories.new()

      assert {:error, {:missing_field, :id}} = PendingMemories.enqueue(pending, %{type: :fact})
      assert {:error, {:missing_field, :data}} = PendingMemories.enqueue(pending, %{id: "mem1"})

      assert {:error, {:missing_field, :id}} =
               PendingMemories.enqueue(pending, %{type: :fact, data: %{}})
    end
  end

  describe "dequeue/1" do
    test "removes and returns next item" do
      pending = PendingMemories.new()
      {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)

      assert {:ok, item, pending} = PendingMemories.dequeue(pending)
      assert item.id == "mem_1"
      assert PendingMemories.size(pending) == 0
    end

    test "returns error when empty" do
      pending = PendingMemories.new()

      assert {:error, :empty} = PendingMemories.dequeue(pending)
    end
  end

  describe "peek/1" do
    test "returns next item without removing" do
      pending = PendingMemories.new()
      {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)

      assert {:ok, item} = PendingMemories.peek(pending)
      assert item.id == "mem_1"
      assert PendingMemories.size(pending) == 1
    end

    test "returns error when empty" do
      pending = PendingMemories.new()

      assert {:error, :empty} = PendingMemories.peek(pending)
    end
  end

  describe "size/1" do
    test "returns queue size" do
      pending = PendingMemories.new()

      assert PendingMemories.size(pending) == 0

      {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)
      assert PendingMemories.size(pending) == 1
    end
  end

  describe "empty?/1" do
    test "returns true when empty" do
      pending = PendingMemories.new()

      assert PendingMemories.empty?(pending)
    end

    test "returns false when has items" do
      pending = PendingMemories.new()
      {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)

      refute PendingMemories.empty?(pending)
    end
  end

  describe "full?/1" do
    test "returns true when at capacity" do
      pending = PendingMemories.new(max_size: 1)
      {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)

      assert PendingMemories.full?(pending)
    end

    test "returns false when not full" do
      pending = PendingMemories.new()

      refute PendingMemories.full?(pending)
    end
  end

  describe "to_list/1" do
    test "returns all items as list" do
      pending = PendingMemories.new()
      item1 = %{@valid_item | id: "mem1"}
      item2 = %{@valid_item | id: "mem2"}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)

      items = PendingMemories.to_list(pending)

      assert length(items) == 2
    end
  end

  describe "clear/1" do
    test "removes all items" do
      pending = PendingMemories.new()
      {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)

      {:ok, pending} = PendingMemories.clear(pending)

      assert PendingMemories.empty?(pending)
    end
  end

  describe "filter_by_type/2" do
    test "filters items by type" do
      pending = PendingMemories.new()
      item1 = %{@valid_item | id: "mem1", type: :fact}
      item2 = %{@valid_item | id: "mem2", type: :conversation}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)

      facts = PendingMemories.filter_by_type(pending, :fact)

      assert length(facts) == 1
      assert hd(facts).type == :fact
    end
  end

  describe "filter_by_importance/2" do
    test "filters by minimum importance" do
      pending = PendingMemories.new()
      item1 = %{@valid_item | id: "mem1", importance: 0.5}
      item2 = %{@valid_item | id: "mem2", importance: 0.9}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)

      important = PendingMemories.filter_by_importance(pending, 0.7)

      assert length(important) == 1
      assert hd(important).importance == 0.9
    end
  end

  describe "remove_where/2" do
    test "removes items matching criteria" do
      pending = PendingMemories.new()
      item1 = %{@valid_item | id: "mem1", type: :fact}
      item2 = %{@valid_item | id: "mem2", type: :conversation}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)

      {:ok, pending, count} = PendingMemories.remove_where(pending, type: :fact)

      assert count == 1
      assert PendingMemories.size(pending) == 1
    end
  end

  describe "peek_priority/1" do
    test "returns highest importance item" do
      pending = PendingMemories.new()
      item1 = %{@valid_item | id: "mem1", importance: 0.5}
      item2 = %{@valid_item | id: "mem2", importance: 0.9}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)

      {:ok, item} = PendingMemories.peek_priority(pending)

      assert item.importance == 0.9
    end

    test "returns error when empty" do
      pending = PendingMemories.new()

      assert {:error, :empty} = PendingMemories.peek_priority(pending)
    end
  end

  describe "ready_for_promotion/2" do
    test "filters by min_importance threshold" do
      pending = PendingMemories.new()
      item1 = %{@valid_item | id: "mem1", importance: 0.5}
      item2 = %{@valid_item | id: "mem2", importance: 0.8}
      item3 = %{@valid_item | id: "mem3", importance: 0.9}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)
      {:ok, pending} = PendingMemories.enqueue(pending, item3)

      ready = PendingMemories.ready_for_promotion(pending, min_importance: 0.7)

      assert length(ready) == 2
      assert Enum.all?(ready, fn item -> item.importance >= 0.7 end)
    end

    test "uses default min_importance of 0.7" do
      pending = PendingMemories.new()
      item1 = %{@valid_item | id: "mem1", importance: 0.8}
      item2 = %{@valid_item | id: "mem2", importance: 0.6}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)

      ready = PendingMemories.ready_for_promotion(pending)

      assert length(ready) == 1
      assert hd(ready).importance == 0.8
    end

    test "filters by max_age_seconds when provided" do
      pending = PendingMemories.new()
      old_timestamp = DateTime.utc_now() |> DateTime.add(-7200, :second)
      new_timestamp = DateTime.utc_now() |> DateTime.add(-60, :second)

      item1 = %{@valid_item | id: "mem1", timestamp: old_timestamp, importance: 0.9}
      item2 = %{@valid_item | id: "mem2", timestamp: new_timestamp, importance: 0.8}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)

      ready = PendingMemories.ready_for_promotion(pending, max_age_seconds: 3600)

      # Only item2 (age 60 seconds) should be included, item1 (age 7200 seconds) excluded
      assert length(ready) == 1
      assert hd(ready).id == "mem2"
    end

    test "returns empty list when no items meet criteria" do
      pending = PendingMemories.new()
      item = %{@valid_item | importance: 0.3}

      {:ok, pending} = PendingMemories.enqueue(pending, item)

      ready = PendingMemories.ready_for_promotion(pending, min_importance: 0.7)

      assert ready == []
    end
  end

  describe "calculate_importance/1" do
    test "returns base importance for analysis type" do
      item = %{type: :analysis, timestamp: DateTime.utc_now()}

      assert PendingMemories.calculate_importance(item) == 0.8
    end

    test "returns base importance for file_context type" do
      item = %{type: :file_context, timestamp: DateTime.utc_now()}

      assert PendingMemories.calculate_importance(item) == 0.6
    end

    test "returns base importance for fact type" do
      item = %{type: :fact, timestamp: DateTime.utc_now()}

      assert PendingMemories.calculate_importance(item) == 0.5
    end

    test "returns base importance for conversation type" do
      item = %{type: :conversation, timestamp: DateTime.utc_now()}

      assert PendingMemories.calculate_importance(item) == 0.4
    end

    test "applies age decay to old items" do
      # 2 hours old = 20% decay
      timestamp = DateTime.utc_now() |> DateTime.add(-7200, :second)
      item = %{type: :analysis, timestamp: timestamp}

      importance = PendingMemories.calculate_importance(item)

      # 0.8 base - 20% decay = 0.64
      assert importance < 0.8
      assert importance >= 0.6
    end

    test "caps decay at 50%" do
      # Very old item (10 hours) should still have 50% of base
      timestamp = DateTime.utc_now() |> DateTime.add(-36000, :second)
      item = %{type: :analysis, timestamp: timestamp}

      importance = PendingMemories.calculate_importance(item)

      # 0.8 base - 50% max decay = 0.4
      assert importance == 0.4
    end

    test "handles items without timestamp" do
      item = %{type: :fact}

      assert PendingMemories.calculate_importance(item) == 0.5
    end
  end

  describe "clear_promoted/2" do
    test "removes items by their IDs" do
      pending = PendingMemories.new()
      item1 = %{@valid_item | id: "mem1"}
      item2 = %{@valid_item | id: "mem2"}
      item3 = %{@valid_item | id: "mem3"}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)
      {:ok, pending} = PendingMemories.enqueue(pending, item3)

      {:ok, pending, count} = PendingMemories.clear_promoted(pending, ["mem1", "mem3"])

      assert count == 2
      assert PendingMemories.size(pending) == 1
      {:ok, remaining} = PendingMemories.peek(pending)
      assert remaining.id == "mem2"
    end

    test "returns zero count when no IDs provided" do
      pending = PendingMemories.new()
      {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)

      {:ok, pending, count} = PendingMemories.clear_promoted(pending, [])

      assert count == 0
      assert PendingMemories.size(pending) == 1
    end

    test "handles non-existent IDs gracefully" do
      pending = PendingMemories.new()
      {:ok, pending} = PendingMemories.enqueue(pending, @valid_item)

      {:ok, pending, count} = PendingMemories.clear_promoted(pending, ["nonexistent"])

      # Count is based on promoted_ids that were actually found
      assert count == 0
      assert PendingMemories.size(pending) == 1
    end

    test "clears all items when all IDs are provided" do
      pending = PendingMemories.new()
      item1 = %{@valid_item | id: "mem1"}
      item2 = %{@valid_item | id: "mem2"}

      {:ok, pending} = PendingMemories.enqueue(pending, item1)
      {:ok, pending} = PendingMemories.enqueue(pending, item2)

      {:ok, pending, count} = PendingMemories.clear_promoted(pending, ["mem1", "mem2"])

      assert count == 2
      assert PendingMemories.empty?(pending)
    end
  end
end
