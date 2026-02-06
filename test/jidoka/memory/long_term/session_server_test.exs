defmodule Jidoka.Memory.LongTerm.SessionServerTest do
  @moduledoc """
  Tests for the SessionServer GenServer.
  """

  use ExUnit.Case, async: false
  alias Jidoka.Memory.LongTerm.SessionServer
  alias Jidoka.Memory.Validation

  setup do
    # Start the application to ensure Registry is available
    Application.ensure_all_started(:jidoka)

    # Use unique session IDs for each test
    session_id = "test_session_#{System.unique_integer([:positive, :monotonic])}"
    {:ok, pid} = SessionServer.start_link(session_id)

    %{pid: pid, session_id: session_id}
  end

  describe "start_link/1" do
    test "starts a new SessionServer for valid session_id" do
      session_id = "test_start_#{System.unique_integer()}"
      assert {:ok, pid} = SessionServer.start_link(session_id)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "fails to start for invalid session_id" do
      assert {:error, _} = SessionServer.start_link("")
    end

    test "fails to start for very long session_id" do
      long_id = String.duplicate("a", 257)
      assert {:error, _} = SessionServer.start_link(long_id)
    end

    test "fails to start for non-binary session_id" do
      assert {:error, _} = SessionServer.start_link(nil)
      assert {:error, _} = SessionServer.start_link(123)
    end
  end

  describe "persist_memory/2" do
    test "stores memory with required fields", context do
      %{pid: pid} = context

      item = %{
        id: "mem_1",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.8
      }

      assert {:ok, memory} = SessionServer.persist_memory(pid, item)
      assert memory.id == "mem_1"
      assert memory.session_id != nil
      assert memory.created_at != nil
      assert memory.updated_at != nil
    end

    test "validates memory using Validation module", context do
      %{pid: pid} = context

      # Missing required fields
      item = %{id: "mem_1"}

      assert {:error, {:missing_fields, _}} = SessionServer.persist_memory(pid, item)
    end

    test "validates memory size", context do
      %{pid: pid} = context

      # Create data larger than 100KB
      large_data =
        for i <- 1..2000, into: %{} do
          {"key_#{i}", String.duplicate("x", 100)}
        end

      item = %{
        id: "mem_large",
        type: :fact,
        data: large_data,
        importance: 0.8
      }

      assert {:error, {:data_too_large, _, _}} = SessionServer.persist_memory(pid, item)
    end

    test "validates importance range", context do
      %{pid: pid} = context

      item = %{
        id: "mem_imp",
        type: :fact,
        data: %{},
        importance: 1.5
      }

      assert {:error, {:invalid_importance, 1.5}} = SessionServer.persist_memory(pid, item)
    end

    test "validates memory type", context do
      %{pid: pid} = context

      item = %{
        id: "mem_type",
        type: :invalid_type,
        data: %{},
        importance: 0.8
      }

      assert {:error, {:invalid_type, :invalid_type}} = SessionServer.persist_memory(pid, item)
    end
  end

  describe "get_memory/2" do
    test "retrieves stored memory by ID", context do
      %{pid: pid} = context

      item = %{
        id: "mem_get",
        type: :fact,
        data: %{"test" => "data"},
        importance: 0.7
      }

      {:ok, stored} = SessionServer.persist_memory(pid, item)
      {:ok, retrieved} = SessionServer.get_memory(pid, "mem_get")

      assert retrieved.id == stored.id
      assert retrieved.data == %{"test" => "data"}
    end

    test "returns error for non-existent memory", context do
      %{pid: pid} = context

      assert {:error, :not_found} = SessionServer.get_memory(pid, "nonexistent")
    end
  end

  describe "query_memories/2" do
    setup context do
      %{pid: pid} = context

      # Store test memories
      memories = [
        %{id: "q1", type: :fact, data: %{"k" => "a"}, importance: 0.5},
        %{id: "q2", type: :fact, data: %{"k" => "b"}, importance: 0.8},
        %{id: "q3", type: :analysis, data: %{"k" => "c"}, importance: 0.6},
        %{id: "q4", type: :file_context, data: %{"k" => "d"}, importance: 0.9}
      ]

      Enum.each(memories, fn m ->
        {:ok, _} = SessionServer.persist_memory(pid, m)
      end)

      :ok
    end

    test "returns all memories", context do
      %{pid: pid} = context
      {:ok, memories} = SessionServer.query_memories(pid)
      assert length(memories) == 4
    end

    test "filters by type", context do
      %{pid: pid} = context
      {:ok, memories} = SessionServer.query_memories(pid, type: :fact)
      assert length(memories) == 2
      assert Enum.all?(memories, &(&1.type == :fact))
    end

    test "filters by minimum importance", context do
      %{pid: pid} = context
      {:ok, memories} = SessionServer.query_memories(pid, min_importance: 0.7)
      assert length(memories) == 2
      assert Enum.all?(memories, &(&1.importance >= 0.7))
    end

    test "applies limit", context do
      %{pid: pid} = context
      {:ok, memories} = SessionServer.query_memories(pid, limit: 2)
      assert length(memories) == 2
    end

    test "combines multiple filters", context do
      %{pid: pid} = context
      {:ok, memories} = SessionServer.query_memories(pid, type: :fact, min_importance: 0.7)
      assert length(memories) == 1
      assert hd(memories).id == "q2"
    end
  end

  describe "update_memory/3" do
    test "updates existing memory", context do
      %{pid: pid} = context

      item = %{
        id: "mem_update",
        type: :fact,
        data: %{"old" => "data"},
        importance: 0.5
      }

      {:ok, _} = SessionServer.persist_memory(pid, item)

      {:ok, updated} =
        SessionServer.update_memory(pid, "mem_update", %{
          data: %{"new" => "data"},
          importance: 0.9
        })

      assert updated.data == %{"new" => "data"}
      assert updated.importance == 0.9
      assert updated.id == "mem_update"
      assert updated.updated_at != nil
    end

    test "returns error for non-existent memory", context do
      %{pid: pid} = context

      assert {:error, :not_found} =
               SessionServer.update_memory(pid, "nonexistent", %{data: %{}})
    end
  end

  describe "delete_memory/2" do
    test "deletes existing memory", context do
      %{pid: pid} = context

      item = %{
        id: "mem_delete",
        type: :fact,
        data: %{},
        importance: 0.5
      }

      {:ok, _} = SessionServer.persist_memory(pid, item)
      assert :ok = SessionServer.delete_memory(pid, "mem_delete")

      assert {:error, :not_found} = SessionServer.get_memory(pid, "mem_delete")
    end

    test "returns error for non-existent memory", context do
      %{pid: pid} = context

      assert {:error, :not_found} = SessionServer.delete_memory(pid, "nonexistent")
    end
  end

  describe "count/1" do
    test "returns zero for empty session", context do
      %{pid: pid} = context
      assert SessionServer.count(pid) == 0
    end

    test "returns count of stored memories", context do
      %{pid: pid} = context

      for i <- 1..5 do
        {:ok, _} =
          SessionServer.persist_memory(pid, %{
            id: "count_#{i}",
            type: :fact,
            data: %{},
            importance: 0.5
          })
      end

      assert SessionServer.count(pid) == 5
    end

    test "updates after delete", context do
      %{pid: pid} = context

      {:ok, _} =
        SessionServer.persist_memory(pid, %{
          id: "count_del",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      assert SessionServer.count(pid) == 1
      :ok = SessionServer.delete_memory(pid, "count_del")
      assert SessionServer.count(pid) == 0
    end
  end

  describe "clear/1" do
    test "clears all memories", context do
      %{pid: pid} = context

      for i <- 1..5 do
        {:ok, _} =
          SessionServer.persist_memory(pid, %{
            id: "clear_#{i}",
            type: :fact,
            data: %{},
            importance: 0.5
          })
      end

      assert SessionServer.count(pid) == 5
      assert :ok = SessionServer.clear(pid)
      assert SessionServer.count(pid) == 0
    end
  end

  describe "session_id/1" do
    test "returns the session_id", context do
      %{pid: pid, session_id: session_id} = context
      assert session_id == SessionServer.session_id(pid)
    end
  end

  describe "table_id/1" do
    test "returns the table reference", context do
      %{pid: pid} = context
      table_id = SessionServer.table_id(pid)
      assert is_reference(table_id)
    end

    test "table reference is usable for direct read operations", context do
      %{pid: pid} = context

      table_id = SessionServer.table_id(pid)

      # Insert a memory
      {:ok, _} =
        SessionServer.persist_memory(pid, %{
          id: "direct_read",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      # Can read directly using table reference (ETS table is :protected, but owner can read)
      # Note: Other processes cannot write to :protected tables
      [{_id, memory}] = :ets.lookup(table_id, "direct_read")
      assert memory.id == "direct_read"
    end
  end

  describe "cleanup on termination" do
    test "deletes ETS table when process terminates" do
      session_id = "cleanup_test_#{System.unique_integer()}"
      {:ok, pid} = SessionServer.start_link(session_id)

      table_id = SessionServer.table_id(pid)
      assert is_reference(table_id)

      # Store a memory
      {:ok, _} =
        SessionServer.persist_memory(pid, %{
          id: "cleanup_mem",
          type: :fact,
          data: %{},
          importance: 0.5
        })

      # Verify memory exists
      assert {:ok, _} = SessionServer.get_memory(pid, "cleanup_mem")

      # Stop the server
      GenServer.stop(pid)

      # Give it a moment to clean up
      Process.sleep(10)

      # Table should be deleted
      assert :ets.info(table_id) == :undefined
    end
  end

  describe "security improvements" do
    test "uses protected ETS table (not public)", context do
      %{pid: pid} = context

      table_id = SessionServer.table_id(pid)

      # Get ETS table info
      info = :ets.info(table_id)
      {_, access} = List.keyfind(info, :protection, 0)

      # :protected means only owner can write
      assert access == :protected
    end

    test "does not create atoms from user input" do
      # No named tables means no atom creation from session_id
      session_id = "no_atom_creation_#{System.unique_integer()}"

      {:ok, pid} = SessionServer.start_link(session_id)

      # Table reference is a reference, not an atom
      table_id = SessionServer.table_id(pid)
      assert is_reference(table_id)
      refute is_atom(table_id)

      GenServer.stop(pid)
    end

    test "session_id is validated before table creation" do
      # Long session_id should fail before any ETS operations
      long_id = String.duplicate("a", 257)

      assert {:error, _} = SessionServer.start_link(long_id)
    end
  end
end
