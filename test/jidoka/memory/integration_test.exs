defmodule Jidoka.Memory.IntegrationTest do
  use ExUnit.Case, async: false

  alias Jidoka.Memory.{Integration, ShortTerm}
  alias Jidoka.Memory.LongTerm.SessionAdapter
  alias Jidoka.Agents.ContextManager
  alias Jidoka.Signals.Memory

  @session_id "test_session_#{System.unique_integer()}"

  describe "initialize_stm/2" do
    test "creates STM with default options" do
      assert {:ok, stm} = Integration.initialize_stm(@session_id)

      assert stm.session_id == @session_id
      assert %ShortTerm.ConversationBuffer{} = stm.conversation_buffer
      assert %ShortTerm.WorkingContext{} = stm.working_context
      assert %ShortTerm.PendingMemories{} = stm.pending_memories
      assert stm.created_at != nil
    end

    test "creates STM with custom options" do
      assert {:ok, stm} =
               Integration.initialize_stm(@session_id,
                 max_buffer_size: 50,
                 max_working_context: 25
               )

      assert stm.conversation_buffer.max_messages == 50
      assert stm.working_context.max_items == 25
    end
  end

  describe "initialize_ltm/2" do
    test "creates LTM adapter for session" do
      assert {:ok, ltm} = Integration.initialize_ltm(@session_id)

      assert ltm.session_id == @session_id
      assert is_atom(ltm.table_name)
    end

    test "LTM persists and retrieves memories" do
      {:ok, ltm} = Integration.initialize_ltm(@session_id)

      memory = %{
        id: "mem_1",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.8
      }

      assert {:ok, stored} = SessionAdapter.persist_memory(ltm, memory)
      assert {:ok, retrieved} = SessionAdapter.get_memory(ltm, "mem_1")
      assert retrieved.id == "mem_1"
    end
  end

  describe "promote_memories/3" do
    setup do
      session_id = "test_promotion_#{System.unique_integer()}"
      {:ok, stm} = Integration.initialize_stm(session_id)
      {:ok, ltm} = Integration.initialize_ltm(session_id)

      # Add a high importance memory that should be promoted
      memory = %{
        id: "mem_promote",
        type: :fact,
        data: %{"important" => "fact"},
        importance: 0.9,
        timestamp: DateTime.utc_now()
      }

      {:ok, stm} = ShortTerm.enqueue_memory(stm, memory)

      %{stm: stm, ltm: ltm, session_id: session_id}
    end

    test "promotes items meeting criteria", %{stm: stm, ltm: ltm} do
      assert {:ok, _updated_stm, results} =
               Integration.promote_memories(stm, ltm, min_importance: 0.5)

      assert length(results.promoted) == 1
      assert hd(results.promoted).id == "mem_promote"
    end

    test "skips items below importance threshold", %{stm: stm, ltm: ltm} do
      low_importance_memory = %{
        id: "mem_low",
        type: :fact,
        data: %{"low" => "importance"},
        importance: 0.3,
        timestamp: DateTime.utc_now()
      }

      {:ok, stm} = ShortTerm.enqueue_memory(stm, low_importance_memory)

      assert {:ok, _stm, results} = Integration.promote_memories(stm, ltm, min_importance: 0.5)

      # The high importance item should still be promoted
      assert length(results.promoted) == 1
    end

    test "promoted items are stored in LTM", %{stm: stm, ltm: ltm, session_id: session_id} do
      assert {:ok, _stm, _results} = Integration.promote_memories(stm, ltm, min_importance: 0.5)

      # Verify item was stored in LTM
      assert {:ok, memory} = SessionAdapter.get_memory(ltm, "mem_promote")
      assert memory.session_id == session_id
      assert memory.type == :fact
    end
  end

  describe "store_memory/3" do
    setup do
      session_id = "test_store_#{System.unique_integer()}"
      {:ok, ltm} = Integration.initialize_ltm(session_id)
      %{ltm: ltm, session_id: session_id}
    end

    test "stores memory in LTM", %{ltm: ltm} do
      memory = %{
        id: "mem_store",
        type: :analysis,
        data: %{"result" => "complete"},
        importance: 0.7
      }

      assert {:ok, stored} = Integration.store_memory(ltm, memory)
      assert stored.id == "mem_store"

      # Verify memory was stored
      assert {:ok, retrieved} = SessionAdapter.get_memory(ltm, "mem_store")
      assert retrieved.type == :analysis
    end
  end

  describe "retrieve_memories/3" do
    setup do
      session_id = "test_retrieve_#{System.unique_integer()}"
      {:ok, ltm} = Integration.initialize_ltm(session_id)

      # Store some test memories
      memories = [
        %{id: "mem_1", type: :fact, data: %{"keyword" => "test"}, importance: 0.5},
        %{
          id: "mem_2",
          type: :analysis,
          data: %{"keyword" => "test", "conclusion" => "result"},
          importance: 0.7
        },
        %{id: "mem_3", type: :fact, data: %{"other" => "data"}, importance: 0.6}
      ]

      Enum.each(memories, fn m ->
        {:ok, _} = SessionAdapter.persist_memory(ltm, m)
      end)

      # Subscribe to signals
      Jidoka.PubSub.subscribe("signals")

      %{ltm: ltm, session_id: session_id}
    end

    test "retrieves memories by keyword", %{ltm: ltm} do
      assert {:ok, memories} = Integration.retrieve_memories(ltm, %{keywords: ["test"]})

      assert length(memories) >= 2
      # Verify both test memories are included
      ids = Enum.map(memories, & &1.id)
      assert "mem_1" in ids
      assert "mem_2" in ids
    end

    test "retrieves memories by type", %{ltm: ltm} do
      assert {:ok, memories} = Integration.retrieve_memories(ltm, %{type: :analysis})

      assert length(memories) == 1
      assert hd(memories).id == "mem_2"
    end
  end

  describe "ContextManager STM integration" do
    test "starts with STM enabled" do
      session_id = "test_ctx_stm_#{System.unique_integer()}"

      assert {:ok, pid} = ContextManager.start_link(session_id: session_id, stm_enabled: true)

      # Verify STM is accessible
      assert {:ok, stm} = ContextManager.get_stm(session_id)
      assert stm.session_id == session_id

      # Stop the process
      GenServer.stop(pid)
    end

    test "starts with STM disabled" do
      session_id = "test_ctx_no_stm_#{System.unique_integer()}"

      assert {:ok, pid} = ContextManager.start_link(session_id: session_id, stm_enabled: false)

      # STM should not be available
      assert {:error, :stm_not_enabled} = ContextManager.get_stm(session_id)

      # Stop the process
      GenServer.stop(pid)
    end

    test "stores messages in STM ConversationBuffer" do
      session_id = "test_ctx_buffer_#{System.unique_integer()}"

      assert {:ok, pid} = ContextManager.start_link(session_id: session_id)

      # Add a message
      :ok = ContextManager.add_message(session_id, :user, "Hello")

      # Get conversation history
      assert {:ok, messages} = ContextManager.get_conversation_history(session_id)
      assert length(messages) == 1
      assert hd(messages).role == :user
      assert hd(messages).content == "Hello"

      # Stop the process
      GenServer.stop(pid)
    end

    test "manages working context in STM" do
      session_id = "test_ctx_wc_#{System.unique_integer()}"

      assert {:ok, pid} = ContextManager.start_link(session_id: session_id)

      # Put working context
      :ok = ContextManager.put_working_context(session_id, "current_file", "/path/to/file.ex")

      # Get working context
      assert {:ok, "/path/to/file.ex"} =
               ContextManager.get_working_context(session_id, "current_file")

      # Get all keys
      assert {:ok, keys} = ContextManager.working_context_keys(session_id)
      assert "current_file" in keys

      # Delete working context
      :ok = ContextManager.delete_working_context(session_id, "current_file")
      assert {:error, _} = ContextManager.get_working_context(session_id, "current_file")

      # Stop the process
      GenServer.stop(pid)
    end

    test "build_context includes working_context when requested" do
      session_id = "test_ctx_build_#{System.unique_integer()}"

      assert {:ok, pid} = ContextManager.start_link(session_id: session_id)

      # Add some context
      :ok = ContextManager.put_working_context(session_id, "key1", "value1")

      # Build context with working_context
      assert {:ok, context} =
               ContextManager.build_context(
                 session_id,
                 [:working_context],
                 []
               )

      assert Map.has_key?(context, :working_context)
      assert context.working_context["key1"] == "value1"

      # Stop the process
      GenServer.stop(pid)
    end
  end

  describe "Memory Signals" do
    alias Jido.Signal

    test "creates promoted signal" do
      attrs = %{
        session_id: "session_123",
        memory_id: "mem_abc",
        type: :fact,
        confidence: 0.85
      }

      signal = Memory.promoted(attrs)

      assert signal.type == "jido.memory.promoted"
      assert signal.data.session_id == "session_123"
      assert signal.data.memory_id == "mem_abc"
      assert signal.data.type == :fact
      assert signal.data.confidence == 0.85
    end

    test "creates stored signal" do
      attrs = %{
        session_id: "session_123",
        memory_id: "mem_xyz",
        type: :file_context,
        importance: 0.7
      }

      signal = Memory.stored(attrs)

      assert signal.type == "jido.memory.stored"
      assert signal.data.session_id == "session_123"
      assert signal.data.memory_id == "mem_xyz"
      assert signal.data.type == :file_context
      assert signal.data.importance == 0.7
    end

    test "creates retrieved signal" do
      attrs = %{
        session_id: "session_123",
        count: 5,
        keywords: ["file", "elixir"],
        max_relevance: 0.9
      }

      signal = Memory.retrieved(attrs)

      assert signal.type == "jido.memory.retrieved"
      assert signal.data.session_id == "session_123"
      assert signal.data.count == 5
      assert signal.data.keywords == ["file", "elixir"]
      assert signal.data.max_relevance == 0.9
    end

    test "creates context_enriched signal" do
      attrs = %{
        session_id: "session_123",
        memory_count: 3,
        summary: "Found 3 related memories"
      }

      signal = Memory.context_enriched(attrs)

      assert signal.type == "jido.context.enriched"
      assert signal.data.session_id == "session_123"
      assert signal.data.memory_count == 3
      assert signal.data.summary == "Found 3 related memories"
    end
  end
end
