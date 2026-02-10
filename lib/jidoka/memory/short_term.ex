defmodule Jidoka.Memory.ShortTerm do
  @moduledoc """
  Short-Term Memory (STM) for session-scoped context management.

  The STM provides ephemeral, session-scoped memory with three components:
  - ConversationBuffer: Sliding window for recent messages
  - WorkingContext: Semantic scratchpad for extracted understanding
  - PendingMemories: FIFO queue for LTM promotion candidates

  ## Architecture

  ```
  ShortTerm
  ├── ConversationBuffer (recent messages with token-aware eviction)
  ├── WorkingContext (semantic key-value store)
  └── PendingMemories (promotion queue)
  ```

  ## Fields

  * `:session_id` - Unique session identifier
  * `:conversation_buffer` - ConversationBuffer struct
  * `:working_context` - WorkingContext struct
  * `:pending_memories` - PendingMemories struct
  * `:created_at` - Creation timestamp
  * `:access_log` - List of access timestamps for activity tracking

  ## Examples

  Creating a new STM instance:

      stm = ShortTerm.new("session_123")

  Adding conversation messages:

      {:ok, stm} = ShortTerm.add_message(stm, %{role: :user, content: "Hello"})

  Working with context:

      {:ok, stm} = ShortTerm.put_context(stm, "current_file", "/path/to/file.ex")
      {:ok, value} = ShortTerm.get_context(stm, "current_file")

  Managing pending memories:

      {:ok, stm} = ShortTerm.enqueue_memory(stm, memory_item)
      {:ok, item, stm} = ShortTerm.dequeue_memory(stm)

  Getting conversation history:

      recent = ShortTerm.recent_messages(stm, 10)

  """

  alias Jidoka.Memory.TokenBudget
  alias Jidoka.Memory.ShortTerm.{ConversationBuffer, WorkingContext, PendingMemories}

  @max_access_log 1000

  defstruct [
    :session_id,
    :conversation_buffer,
    :working_context,
    :pending_memories,
    :created_at,
    :access_log
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          conversation_buffer: ConversationBuffer.t(),
          working_context: WorkingContext.t(),
          pending_memories: PendingMemories.t(),
          created_at: DateTime.t(),
          access_log: [DateTime.t()]
        }

  @doc """
  Creates a new short-term memory instance for a session.

  ## Options

  * `:max_messages` - Max messages in conversation buffer (default: 100)
  * `:max_tokens` - Token budget for conversation (default: 4000)
  * `:max_context_items` - Max items in working context (default: 50)
  * `:max_pending` - Max items in pending memories (default: 20)

  ## Returns

  A new ShortTerm struct

  ## Examples

      stm = ShortTerm.new("session_123")
      stm = ShortTerm.new("session_123", max_tokens: 8000)

  """
  def new(session_id, opts \\ []) when is_binary(session_id) do
    max_messages = Keyword.get(opts, :max_messages, 100)
    max_tokens = Keyword.get(opts, :max_tokens, 4000)
    max_context_items = Keyword.get(opts, :max_context_items, 50)
    max_pending = Keyword.get(opts, :max_pending, 20)

    %__MODULE__{
      session_id: session_id,
      conversation_buffer:
        ConversationBuffer.new(
          max_messages: max_messages,
          token_budget: TokenBudget.new(max_tokens: max_tokens)
        ),
      working_context: WorkingContext.new(max_items: max_context_items),
      pending_memories: PendingMemories.new(max_size: max_pending),
      created_at: DateTime.utc_now(),
      access_log: [DateTime.utc_now()]
    }
  end

  # Conversation Buffer Delegates

  @doc """
  Adds a message to the conversation buffer.

  ## Examples

      {:ok, stm} = ShortTerm.add_message(stm, %{role: :user, content: "Hello"})

  """
  def add_message(%__MODULE__{} = stm, message) when is_map(message) do
    case ConversationBuffer.add(stm.conversation_buffer, message) do
      {:ok, buffer} ->
        {:ok, %{stm | conversation_buffer: buffer, access_log: update_access_log(stm)}}

      {:ok, buffer, evicted} ->
        {:ok, %{stm | conversation_buffer: buffer, access_log: update_access_log(stm)}, evicted}
    end
  end

  @doc """
  Gets recent messages from the conversation buffer.

  ## Examples

      messages = ShortTerm.recent_messages(stm, 10)
      messages = ShortTerm.recent_messages(stm)  # all messages

  """
  def recent_messages(%__MODULE__{conversation_buffer: buffer}, count) when is_integer(count) do
    ConversationBuffer.recent(buffer, count)
  end

  def recent_messages(%__MODULE__{conversation_buffer: buffer}) do
    ConversationBuffer.recent(buffer)
  end

  @doc """
  Gets all messages in chronological order.

  ## Examples

      messages = ShortTerm.all_messages(stm)

  """
  def all_messages(%__MODULE__{conversation_buffer: buffer}) do
    ConversationBuffer.all(buffer)
  end

  @doc """
  Gets the message count.

  ## Examples

      count = ShortTerm.message_count(stm)

  """
  def message_count(%__MODULE__{conversation_buffer: buffer}) do
    ConversationBuffer.count(buffer)
  end

  @doc """
  Gets the current token count.

  ## Examples

      tokens = ShortTerm.token_count(stm)

  """
  def token_count(%__MODULE__{conversation_buffer: buffer}) do
    ConversationBuffer.token_count(buffer)
  end

  # Working Context Delegates

  @doc """
  Stores a value in the working context.

  ## Examples

      {:ok, stm} = ShortTerm.put_context(stm, "current_file", "/path/to/file.ex")

  """
  def put_context(%__MODULE__{} = stm, key, value) when is_binary(key) do
    case WorkingContext.put(stm.working_context, key, value) do
      {:ok, ctx} ->
        {:ok, %{stm | working_context: ctx, access_log: update_access_log(stm)}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets a value from the working context.

  ## Examples

      {:ok, value} = ShortTerm.get_context(stm, "current_file")

  """
  def get_context(%__MODULE__{working_context: ctx}, key) when is_binary(key) do
    WorkingContext.get(ctx, key)
  end

  @doc """
  Gets a value or returns default.

  ## Examples

      value = ShortTerm.get_context(stm, "key", "default")

  """
  def get_context(%__MODULE__{working_context: ctx} = _stm, key, default) when is_binary(key) do
    WorkingContext.get(ctx, key, default)
  end

  @doc """
  Deletes a value from the working context.

  ## Examples

      {:ok, stm} = ShortTerm.delete_context(stm, "current_file")

  """
  def delete_context(%__MODULE__{} = stm, key) when is_binary(key) do
    case WorkingContext.delete(stm.working_context, key) do
      {:ok, ctx} -> {:ok, %{stm | working_context: ctx}}
      error -> error
    end
  end

  @doc """
  Returns all context keys.

  ## Examples

      keys = ShortTerm.context_keys(stm)

  """
  def context_keys(%__MODULE__{working_context: ctx}) do
    WorkingContext.keys(ctx)
  end

  @doc """
  Updates multiple context values.

  ## Examples

      {:ok, stm} = ShortTerm.put_context_many(stm, %{"key1" => "val1", "key2" => "val2"})

  """
  def put_context_many(%__MODULE__{} = stm, updates) when is_map(updates) do
    case WorkingContext.put_many(stm.working_context, updates) do
      {:ok, ctx} ->
        {:ok, %{stm | working_context: ctx, access_log: update_access_log(stm)}}

      {:error, _} = error ->
        error
    end
  end

  # Pending Memories Delegates

  @doc """
  Enqueues a memory item for LTM promotion.

  ## Examples

      {:ok, stm} = ShortTerm.enqueue_memory(stm, %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8,
        timestamp: DateTime.utc_now()
      })

  """
  def enqueue_memory(%__MODULE__{} = stm, item) when is_map(item) do
    case PendingMemories.enqueue(stm.pending_memories, item) do
      {:ok, pending} ->
        {:ok, %{stm | pending_memories: pending, access_log: update_access_log(stm)}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Dequeues the next memory item for promotion.

  ## Examples

      {:ok, item, stm} = ShortTerm.dequeue_memory(stm)

  """
  def dequeue_memory(%__MODULE__{} = stm) do
    case PendingMemories.dequeue(stm.pending_memories) do
      {:ok, item, pending} ->
        {:ok, item, %{stm | pending_memories: pending, access_log: update_access_log(stm)}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Peeks at the next pending memory.

  ## Examples

      {:ok, item} = ShortTerm.peek_pending_memory(stm)

  """
  def peek_pending_memory(%__MODULE__{pending_memories: pending}) do
    PendingMemories.peek(pending)
  end

  @doc """
  Gets the pending memory count.

  ## Examples

      count = ShortTerm.pending_count(stm)

  """
  def pending_count(%__MODULE__{pending_memories: pending}) do
    PendingMemories.size(pending)
  end

  # Utility Functions

  @doc """
  Records an access in the access log.

  ## Examples

      stm = ShortTerm.record_access(stm)

  """
  def record_access(%__MODULE__{} = stm) do
    %{stm | access_log: update_access_log(stm)}
  end

  @doc """
  Gets the access log.

  ## Examples

      log = ShortTerm.access_log(stm)

  """
  def access_log(%__MODULE__{access_log: log}) do
    log
  end

  @doc """
  Gets access statistics.

  ## Returns

  Map with:
  * `:total_accesses` - Total number of accesses
  * `:last_access` - Last access timestamp
  * `:first_access` - First access timestamp

  ## Examples

      stats = ShortTerm.access_stats(stm)

  """
  def access_stats(%__MODULE__{access_log: []}) do
    %{
      total_accesses: 0,
      last_access: nil,
      first_access: nil
    }
  end

  def access_stats(%__MODULE__{access_log: log}) do
    %{
      total_accesses: length(log),
      last_access: List.first(log),
      first_access: List.last(log)
    }
  end

  @doc """
  Gets a summary of the STM state.

  ## Returns

  Map with statistics about all STM components

  ## Examples

      summary = ShortTerm.summary(stm)

  """
  def summary(%__MODULE__{} = stm) do
    %{
      session_id: stm.session_id,
      conversation: %{
        message_count: ConversationBuffer.count(stm.conversation_buffer),
        token_count: ConversationBuffer.token_count(stm.conversation_buffer),
        max_tokens: stm.conversation_buffer.token_budget.max_tokens
      },
      context: %{
        item_count: WorkingContext.count(stm.working_context),
        max_items: stm.working_context.max_items
      },
      pending: %{
        count: PendingMemories.size(stm.pending_memories),
        max_size: stm.pending_memories.max_size
      },
      access: access_stats(stm),
      created_at: stm.created_at
    }
  end

  @doc """
  Checks if the STM is empty (no messages, context, or pending items).

  ## Examples

      ShortTerm.empty?(stm)
      #=> false

  """
  def empty?(%__MODULE__{} = stm) do
    ConversationBuffer.count(stm.conversation_buffer) == 0 and
      WorkingContext.count(stm.working_context) == 0 and
      PendingMemories.empty?(stm.pending_memories)
  end

  # Private Helpers

  defp update_access_log(%__MODULE__{access_log: log}) do
    [DateTime.utc_now() | log]
    |> Enum.take(@max_access_log)
  end
end
