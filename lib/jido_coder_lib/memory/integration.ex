defmodule JidoCoderLib.Memory.Integration do
  @moduledoc """
  Memory integration helpers for connecting the memory system to agents.

  This module provides helper functions for:
  - Initializing STM (Short-Term Memory) for a session
  - Initializing LTM (Long-Term Memory) for a session
  - Triggering promotion from STM to LTM
  - Broadcasting memory-related signals

  ## Architecture

  The memory system is integrated into sessions through the Session.Supervisor:

  ```
  Session.Supervisor
    ├── ContextManager (uses STM: ConversationBuffer, WorkingContext)
    ├── SessionAdapter (LTM storage per session)
    └── Memory operations (promotion, retrieval)
  ```

  ## Examples

  ### Initialize STM for a session

      {:ok, stm} = Integration.initialize_stm("session_123", %{
        max_buffer_size: 100,
        max_working_context: 50
      })

  ### Initialize LTM for a session

      {:ok, ltm} = Integration.initialize_ltm("session_123")

  ### Promote pending memories

      {:ok, stm, results} = Integration.promote_memories(stm, ltm, %{
        min_importance: 0.5,
        batch_size: 10
      })

  ### Broadcast promotion signal

      Integration.broadcast_promotion("session_123", %{
        memory_id: "mem_abc",
        type: :fact,
        confidence: 0.85
      })

  """

  alias JidoCoderLib.Memory.ShortTerm
  alias JidoCoderLib.Memory.LongTerm.SessionAdapter
  alias JidoCoderLib.Memory.PromotionEngine
  alias JidoCoderLib.{PubSub, Signals}
  require Logger

  @type stm :: %{
          conversation_buffer: term(),
          working_context: term(),
          pending_memories: term()
        }

  @type ltm :: SessionAdapter.t()

  @type promotion_results :: %{
          promoted: [map()],
          skipped: [map()],
          failed: [map()]
        }

  # Configuration defaults

  @default_max_buffer_size 100
  @default_max_working_context 50
  @default_promotion_min_importance 0.5
  @default_promotion_batch_size 10

  # Client API

  @doc """
  Initializes Short-Term Memory (STM) for a session.

  Creates ConversationBuffer, WorkingContext, and PendingMemories structures.

  ## Parameters

  * `session_id` - Unique session identifier
  * `opts` - Configuration options
    * `:max_buffer_size` - Max messages in ConversationBuffer (default: 100)
    * `:max_working_context` - Max items in WorkingContext (default: 50)

  ## Returns

  * `{:ok, stm}` - STM initialized successfully
  * `{:error, reason}` - Initialization failed

  ## Examples

      {:ok, stm} = Integration.initialize_stm("session_123")
      {:ok, stm} = Integration.initialize_stm("session_123", max_buffer_size: 200)

  """
  @spec initialize_stm(String.t(), keyword()) :: {:ok, stm()} | {:error, term()}
  def initialize_stm(session_id, opts \\ []) do
    max_buffer_size = Keyword.get(opts, :max_buffer_size, @default_max_buffer_size)
    max_working_context = Keyword.get(opts, :max_working_context, @default_max_working_context)

    # Create ShortTerm memory structures
    # Map integration options to ShortTerm options
    stm =
      ShortTerm.new(session_id,
        max_messages: max_buffer_size,
        max_context_items: max_working_context
      )

    {:ok, stm}
  end

  @doc """
  Initializes Long-Term Memory (LTM) for a session.

  Creates a SessionAdapter for the session.

  ## Parameters

  * `session_id` - Unique session identifier
  * `opts` - Configuration options (passed to SessionAdapter)

  ## Returns

  * `{:ok, ltm}` - LTM adapter initialized successfully
  * `{:error, reason}` - Initialization failed

  ## Examples

      {:ok, ltm} = Integration.initialize_ltm("session_123")

  """
  @spec initialize_ltm(String.t(), keyword()) :: {:ok, ltm()} | {:error, term()}
  def initialize_ltm(session_id, _opts \\ []) do
    case SessionAdapter.new(session_id) do
      {:ok, adapter} ->
        Logger.debug("Initialized LTM adapter for session: #{session_id}")
        {:ok, adapter}

      {:error, reason} ->
        Logger.error("Failed to initialize LTM for session #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Promotes pending memories from STM to LTM.

  Evaluates items in PendingMemories and promotes those meeting criteria.

  ## Parameters

  * `stm` - ShortTerm memory structure
  * `ltm` - SessionAdapter for LTM
  * `opts` - Promotion options
    * `:min_importance` - Minimum importance for promotion (default: 0.5)
    * `:max_age_seconds` - Max age before forced promotion (default: 300)
    * `:batch_size` - Max items to process (default: 10)

  ## Returns

  * `{:ok, stm, results}` - Promotion completed with updated STM and results
  * `{:error, reason}` - Promotion failed

  ## Results Structure

  ```elixir
  %{
    promoted: [%{id: ..., confidence: ..., reason: ...}],
    skipped: [%{id: ..., reason: ...}],
    failed: [%{id: ..., error: ...}]
  }
  ```

  ## Examples

      {:ok, stm, results} = Integration.promote_memories(stm, ltm, %{
        min_importance: 0.6,
        batch_size: 5
      })

      IO.inspect(length(results.promoted))  # Number of items promoted

  """
  @spec promote_memories(stm(), ltm(), keyword()) ::
          {:ok, stm(), promotion_results()} | {:error, term()}
  def promote_memories(stm, ltm, opts \\ []) do
    min_importance = Keyword.get(opts, :min_importance, @default_promotion_min_importance)
    max_age_seconds = Keyword.get(opts, :max_age_seconds, 300)
    batch_size = Keyword.get(opts, :batch_size, @default_promotion_batch_size)

    promotion_opts = [
      min_importance: min_importance,
      max_age_seconds: max_age_seconds,
      min_confidence: 0.3,
      infer_types: true,
      batch_size: batch_size
    ]

    case PromotionEngine.evaluate_and_promote(stm, ltm, promotion_opts) do
      {:ok, updated_stm, results} ->
        # Broadcast promotion signals for each promoted item
        Enum.each(results.promoted, fn promoted ->
          broadcast_promotion(stm.session_id, promoted)
        end)

        Logger.debug("Promoted #{length(results.promoted)} items for session: #{stm.session_id}")
        {:ok, updated_stm, results}

      {:error, reason} ->
        Logger.error("Promotion failed for session #{stm.session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Promotes all pending memories from STM to LTM regardless of criteria.

  Use this for explicit promotion (e.g., session shutdown).

  ## Parameters

  * `stm` - ShortTerm memory structure
  * `ltm` - SessionAdapter for LTM

  ## Returns

  * `{:ok, stm, results}` - All items promoted with updated STM and results
  * `{:error, reason}` - Promotion failed

  ## Examples

      {:ok, stm, results} = Integration.promote_all_memories(stm, ltm)

  """
  @spec promote_all_memories(stm(), ltm()) :: {:ok, stm(), promotion_results()} | {:error, term()}
  def promote_all_memories(stm, ltm) do
    case PromotionEngine.promote_all(stm, ltm) do
      {:ok, updated_stm, results} ->
        # Broadcast promotion signals for each promoted item
        Enum.each(results.promoted, fn promoted ->
          broadcast_promotion(stm.session_id, promoted)
        end)

        Logger.info(
          "Promoted all #{length(results.promoted)} items for session: #{stm.session_id}"
        )

        {:ok, updated_stm, results}

      {:error, reason} ->
        Logger.error("Promote all failed for session #{stm.session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stores a memory directly in LTM with signal emission.

  ## Parameters

  * `ltm` - SessionAdapter for LTM
  * `memory` - Memory map to store
  * `opts` - Options

  ## Returns

  * `{:ok, memory}` - Memory stored successfully
  * `{:error, reason}` - Storage failed

  ## Examples

      {:ok, memory} = Integration.store_memory(ltm, %{
        id: "mem_abc",
        type: :fact,
        data: %{"key" => "value"},
        importance: 0.8
      })

  """
  @spec store_memory(ltm(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def store_memory(ltm, memory, opts \\ []) do
    case SessionAdapter.persist_memory(ltm, memory) do
      {:ok, stored_memory} ->
        # Broadcast stored signal
        broadcast_storage(ltm.session_id, stored_memory)

        Logger.debug("Stored memory #{stored_memory.id} for session: #{ltm.session_id}")
        {:ok, stored_memory}

      {:error, reason} = error ->
        Logger.error("Failed to store memory for session #{ltm.session_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Retrieves memories from LTM with signal emission.

  ## Parameters

  * `ltm` - SessionAdapter for LTM
  * `query` - Query map (keywords, type, min_importance, limit)
  * `opts` - Options

  ## Returns

  * `{:ok, results}` - Memories retrieved successfully
  * `{:error, reason}` - Retrieval failed

  ## Examples

      {:ok, results} = Integration.retrieve_memories(ltm, %{
        keywords: ["file", "elixir"],
        limit: 5
      })

  """
  @spec retrieve_memories(ltm(), map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def retrieve_memories(ltm, query, opts \\ []) do
    alias JidoCoderLib.Memory.Retrieval

    case Retrieval.search(ltm, query) do
      {:ok, results} when is_list(results) ->
        memories = Enum.map(results, fn r -> r.memory end)

        # Broadcast retrieved signal
        broadcast_retrieval(ltm.session_id, length(memories), query, results)

        Logger.debug("Retrieved #{length(memories)} memories for session: #{ltm.session_id}")
        {:ok, memories}

      {:error, reason} = error ->
        Logger.error(
          "Failed to retrieve memories for session #{ltm.session_id}: #{inspect(reason)}"
        )

        error
    end
  end

  # Signal Broadcasting Functions

  @doc """
  Broadcasts a memory promoted signal.

  """
  def broadcast_promotion(session_id, promoted_item) do
    signal =
      Signals.Memory.promoted(%{
        session_id: session_id,
        memory_id: Map.get(promoted_item, :id),
        type: Map.get(promoted_item, :type),
        confidence: Map.get(promoted_item, :confidence)
      })

    PubSub.broadcast_signal(signal.type, signal)
  end

  @doc """
  Broadcasts a memory stored signal.

  """
  def broadcast_storage(session_id, memory) do
    signal =
      Signals.Memory.stored(%{
        session_id: session_id,
        memory_id: Map.get(memory, :id),
        type: Map.get(memory, :type),
        importance: Map.get(memory, :importance)
      })

    PubSub.broadcast_signal(signal.type, signal)
  end

  @doc """
  Broadcasts a memory retrieved signal.

  """
  def broadcast_retrieval(session_id, count, query, results) do
    keywords = Map.get(query, :keywords, [])

    max_relevance =
      if length(results) > 0 do
        hd(results).score
      else
        nil
      end

    signal =
      Signals.Memory.retrieved(%{
        session_id: session_id,
        count: count,
        keywords: keywords,
        max_relevance: max_relevance
      })

    PubSub.broadcast_signal(signal.type, signal)
  end

  @doc """
  Broadcasts a context enriched signal.

  """
  def broadcast_context_enriched(session_id, context) do
    signal =
      Signals.Memory.context_enriched(%{
        session_id: session_id,
        memory_count: Map.get(context, :count, 0),
        summary: Map.get(context, :summary, "")
      })

    PubSub.broadcast_signal(signal.type, signal)
  end
end
