defmodule Jidoka.Memory.LongTerm.SessionAdapterTest do
  use ExUnit.Case, async: false

  alias Jidoka.Memory.LongTerm.SessionAdapter

  @valid_memory %{
    id: "mem_1",
    type: :fact,
    data: %{key: "value"},
    importance: 0.8
  }

  describe "new/1" do
    test "creates adapter with session_id" do
      session_id = "test_session_#{System.unique_integer()}"

      assert {:ok, adapter} = SessionAdapter.new(session_id)
      assert adapter.session_id == session_id
      assert is_atom(adapter.table_name)
      assert :ets.whereis(adapter.table_name) != :undefined
    end

    test "reuses existing table for same session_id" do
      session_id = "test_session_#{System.unique_integer()}"

      {:ok, adapter1} = SessionAdapter.new(session_id)
      {:ok, adapter2} = SessionAdapter.new(session_id)

      # Both should point to the same table
      assert adapter1.table_name == adapter2.table_name
    end

    test "creates separate tables for different sessions" do
      session_id1 = "test_session_#{System.unique_integer()}"
      session_id2 = "test_session_#{System.unique_integer()}"

      {:ok, adapter1} = SessionAdapter.new(session_id1)
      {:ok, adapter2} = SessionAdapter.new(session_id2)

      # Different table names
      assert adapter1.table_name != adapter2.table_name
    end
  end

  describe "persist_memory/2" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      %{adapter: adapter, session_id: session_id}
    end

    test "stores memory with added timestamps and session_id", %{adapter: adapter} do
      assert {:ok, memory} = SessionAdapter.persist_memory(adapter, @valid_memory)

      assert memory.id == "mem_1"
      assert memory.session_id == adapter.session_id
      assert Map.has_key?(memory, :created_at)
      assert Map.has_key?(memory, :updated_at)
      assert %DateTime{} = memory.created_at
    end

    test "returns error for missing required fields", %{adapter: adapter} do
      incomplete_memory = %{
        id: "mem_1",
        type: :fact
        # Missing :data and :importance
      }

      assert {:error, {:missing_fields, fields}} =
               SessionAdapter.persist_memory(adapter, incomplete_memory)

      assert :data in fields
      assert :importance in fields
    end
  end

  describe "get_memory/2" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)
      {:ok, _memory} = SessionAdapter.persist_memory(adapter, @valid_memory)

      %{adapter: adapter}
    end

    test "retrieves stored memory by ID", %{adapter: adapter} do
      assert {:ok, memory} = SessionAdapter.get_memory(adapter, "mem_1")
      assert memory.id == "mem_1"
      assert memory.type == :fact
    end

    test "returns error for non-existent memory", %{adapter: adapter} do
      assert {:error, :not_found} = SessionAdapter.get_memory(adapter, "nonexistent")
    end
  end

  describe "query_memories/2" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      # Add test memories
      {:ok, _} =
        SessionAdapter.persist_memory(adapter, %{
          id: "mem_1",
          type: :fact,
          data: %{key: "value1"},
          importance: 0.5
        })

      {:ok, _} =
        SessionAdapter.persist_memory(adapter, %{
          id: "mem_2",
          type: :analysis,
          data: %{key: "value2"},
          importance: 0.8
        })

      {:ok, _} =
        SessionAdapter.persist_memory(adapter, %{
          id: "mem_3",
          type: :fact,
          data: %{key: "value3"},
          importance: 0.9
        })

      %{adapter: adapter}
    end

    test "returns all memories when no filters provided", %{adapter: adapter} do
      assert {:ok, memories} = SessionAdapter.query_memories(adapter)
      assert length(memories) == 3
    end

    test "filters by type", %{adapter: adapter} do
      assert {:ok, facts} = SessionAdapter.query_memories(adapter, type: :fact)
      assert length(facts) == 2
      assert Enum.all?(facts, fn m -> m.type == :fact end)
    end

    test "filters by min_importance", %{adapter: adapter} do
      assert {:ok, important} = SessionAdapter.query_memories(adapter, min_importance: 0.7)
      assert length(important) == 2
      assert Enum.all?(important, fn m -> m.importance >= 0.7 end)
    end

    test "combines multiple filters", %{adapter: adapter} do
      assert {:ok, results} =
               SessionAdapter.query_memories(adapter,
                 type: :fact,
                 min_importance: 0.8
               )

      assert length(results) == 1
      assert hd(results).id == "mem_3"
    end

    test "applies limit", %{adapter: adapter} do
      assert {:ok, results} = SessionAdapter.query_memories(adapter, limit: 2)
      assert length(results) == 2
    end

    test "returns empty list for empty table" do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      assert {:ok, memories} = SessionAdapter.query_memories(adapter)
      assert memories == []
    end
  end

  describe "update_memory/3" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)
      {:ok, _} = SessionAdapter.persist_memory(adapter, @valid_memory)

      %{adapter: adapter}
    end

    test "updates existing memory fields", %{adapter: adapter} do
      assert {:ok, updated} =
               SessionAdapter.update_memory(adapter, "mem_1", %{
                 importance: 0.9,
                 data: %{new: "data"}
               })

      assert updated.importance == 0.9
      assert updated.data == %{new: "data"}
      # ID preserved
      assert updated.id == "mem_1"
      # session_id preserved
      assert updated.session_id == adapter.session_id
    end

    test "updates updated_at timestamp", %{adapter: adapter} do
      {:ok, original} = SessionAdapter.get_memory(adapter, "mem_1")
      # Ensure time passes
      Process.sleep(10)

      assert {:ok, updated} =
               SessionAdapter.update_memory(adapter, "mem_1", %{
                 importance: 0.9
               })

      assert DateTime.compare(updated.updated_at, original.updated_at) == :gt
    end

    test "preserves created_at timestamp", %{adapter: adapter} do
      {:ok, original} = SessionAdapter.get_memory(adapter, "mem_1")

      assert {:ok, updated} =
               SessionAdapter.update_memory(adapter, "mem_1", %{
                 importance: 0.9
               })

      assert DateTime.compare(updated.created_at, original.created_at) == :eq
    end

    test "returns error for non-existent memory", %{adapter: adapter} do
      assert {:error, :not_found} =
               SessionAdapter.update_memory(adapter, "nonexistent", %{
                 importance: 0.9
               })
    end
  end

  describe "delete_memory/2" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)
      {:ok, _} = SessionAdapter.persist_memory(adapter, @valid_memory)

      %{adapter: adapter}
    end

    test "deletes existing memory", %{adapter: adapter} do
      assert {:ok, adapter} = SessionAdapter.delete_memory(adapter, "mem_1")

      # Memory is gone
      assert {:error, :not_found} = SessionAdapter.get_memory(adapter, "mem_1")
    end

    test "returns error for non-existent memory", %{adapter: adapter} do
      assert {:error, :not_found} = SessionAdapter.delete_memory(adapter, "nonexistent")
    end
  end

  describe "count/1" do
    test "returns zero for empty adapter" do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      assert SessionAdapter.count(adapter) == 0
    end

    test "returns correct count after adding memories" do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      assert SessionAdapter.count(adapter) == 0

      {:ok, _} = SessionAdapter.persist_memory(adapter, @valid_memory)
      assert SessionAdapter.count(adapter) == 1

      {:ok, _} =
        SessionAdapter.persist_memory(adapter, %{
          id: "mem_2",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      assert SessionAdapter.count(adapter) == 2
    end
  end

  describe "clear/1" do
    test "clears all memories from session" do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      {:ok, _} = SessionAdapter.persist_memory(adapter, @valid_memory)
      assert SessionAdapter.count(adapter) == 1

      assert {:ok, adapter} = SessionAdapter.clear(adapter)
      assert SessionAdapter.count(adapter) == 0
    end
  end

  describe "session_id/1" do
    test "returns the session_id" do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      assert SessionAdapter.session_id(adapter) == session_id
    end
  end

  describe "drop_table/1" do
    test "deletes the ETS table for the session" do
      session_id = "test_session_#{System.unique_integer()}"
      {:ok, adapter} = SessionAdapter.new(session_id)

      table_name = adapter.table_name
      assert :ets.whereis(table_name) != :undefined

      assert :ok = SessionAdapter.drop_table(adapter)
      assert :ets.whereis(table_name) == :undefined
    end
  end

  describe "session isolation" do
    test "separates memories between sessions" do
      session_id1 = "test_session_#{System.unique_integer()}"
      session_id2 = "test_session_#{System.unique_integer()}"

      {:ok, adapter1} = SessionAdapter.new(session_id1)
      {:ok, adapter2} = SessionAdapter.new(session_id2)

      {:ok, _} = SessionAdapter.persist_memory(adapter1, @valid_memory)

      # adapter2 should not see adapter1's memories
      assert {:ok, memories2} = SessionAdapter.query_memories(adapter2)
      assert memories2 == []

      # adapter1 should see its memory
      assert {:ok, memories1} = SessionAdapter.query_memories(adapter1)
      assert length(memories1) == 1
    end
  end

  describe "new!/1" do
    test "creates adapter or raises" do
      session_id = "test_session_#{System.unique_integer()}"

      adapter = SessionAdapter.new!(session_id)
      assert adapter.session_id == session_id
    end
  end
end
