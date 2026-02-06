defmodule Jidoka.Signals.Memory do
  @moduledoc """
  Memory-related signal types for the memory system.

  This module defines signal types for memory operations including:
  - Promotion from STM to LTM
  - Storage in LTM
  - Retrieval for context enrichment
  - Context enrichment events

  All signals follow the CloudEvents v1.0.2 specification.

  ## Signal Types

  - `jido.memory.promoted` - Item promoted from STM to LTM
  - `jido.memory.stored` - Memory stored in LTM
  - `jido.memory.retrieved` - Memories retrieved for context
  - `jido.context.enriched` - Context enriched with LTM memories

  ## Examples

  ### Memory Promoted Signal

      signal = Jidoka.Signals.Memory.promoted(%{
        session_id: "session-123",
        memory_id: "mem_abc",
        type: :fact,
        confidence: 0.85
      })

  ### Memory Stored Signal

      signal = Jidoka.Signals.Memory.stored(%{
        session_id: "session-123",
        memory_id: "mem_xyz",
        type: :file_context
      })

  ### Memory Retrieved Signal

      signal = Jidoka.Signals.Memory.retrieved(%{
        session_id: "session-123",
        count: 5,
        keywords: ["file", "elixir"]
      })

  ### Context Enriched Signal

      signal = Jidoka.Signals.Memory.context_enriched(%{
        session_id: "session-123",
        memory_count: 3,
        summary: "Found 3 related memories"
      })

  """

  @doc """
  Creates a memory promoted signal.

  Emitted when an item is successfully promoted from STM to LTM.

  ## Fields

  - `:session_id` - The session ID (required)
  - `:memory_id` - The promoted memory ID (required)
  - `:type` - Memory type (:fact, :file_context, :analysis, etc.) (required)
  - `:confidence` - Promotion confidence score (optional)

  """
  def promoted(attrs) when is_map(attrs) do
    data = Map.take(attrs, [:session_id, :memory_id, :type, :confidence])
    Jido.Signal.new!("jido.memory.promoted", data, source: "/jido_coder/memory/promotion")
  end

  @doc """
  Creates a memory stored signal.

  Emitted when a memory is stored in LTM.

  ## Fields

  - `:session_id` - The session ID (required)
  - `:memory_id` - The stored memory ID (required)
  - `:type` - Memory type (required)
  - `:importance` - Memory importance score (optional)

  """
  def stored(attrs) when is_map(attrs) do
    data = Map.take(attrs, [:session_id, :memory_id, :type, :importance])
    Jido.Signal.new!("jido.memory.stored", data, source: "/jido_coder/memory/storage")
  end

  @doc """
  Creates a memory retrieved signal.

  Emitted when memories are retrieved from LTM for context.

  ## Fields

  - `:session_id` - The session ID (required)
  - `:count` - Number of memories retrieved (required)
  - `:keywords` - Keywords used for retrieval (optional)
  - `:max_relevance` - Highest relevance score in results (optional)

  """
  def retrieved(attrs) when is_map(attrs) do
    data = Map.take(attrs, [:session_id, :count, :keywords, :max_relevance])
    Jido.Signal.new!("jido.memory.retrieved", data, source: "/jido_coder/memory/retrieval")
  end

  @doc """
  Creates a context enriched signal.

  Emitted when context is enriched with LTM memories.

  ## Fields

  - `:session_id` - The session ID (required)
  - `:memory_count` - Number of memories added to context (required)
  - `:summary` - Human-readable summary of enrichment (required)
  - `:total_relevance` - Sum of all relevance scores (optional)

  """
  def context_enriched(attrs) when is_map(attrs) do
    data = Map.take(attrs, [:session_id, :memory_count, :summary, :total_relevance])
    Jido.Signal.new!("jido.context.enriched", data, source: "/jido_coder/memory/context")
  end
end
