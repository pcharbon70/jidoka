defmodule JidoCoderLib.Memory.ShortTerm.PendingMemories do
  @moduledoc """
  A FIFO queue for items pending promotion to long-term memory.

  The PendingMemories queue stores items that have been identified as
  candidates for promotion to long-term memory. Items are enqueued
  during session processing and dequeued by the promotion engine.

  ## Fields

  * `:queue` - :queue.queue() of memory items
  * `:max_size` - Maximum queue size

  ## Memory Item Structure

  Each item in the queue is a map with:
  * `:id` - Unique identifier (required)
  * `:type` - :fact | :conversation | :analysis | :file_context (optional, can be inferred)
  * `:data` - The actual data to promote (required)
  * `:importance` - Float 0.0-1.0 for priority scoring (optional, defaults to 0.5)
  * `:timestamp` - When the item was enqueued (optional, defaults to DateTime.utc_now())

  ## Examples

      pending = PendingMemories.new()

      {:ok, pending} = PendingMemories.enqueue(pending, %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8,
        timestamp: DateTime.utc_now()
      })

      {:ok, item, pending} = PendingMemories.dequeue(pending)

      count = PendingMemories.size(pending)

  """

  defstruct [:queue, :max_size]

  @type t :: %__MODULE__{
          queue: :queue.queue(),
          max_size: pos_integer()
        }

  @default_max_size 20

  @doc """
  Creates a new pending memories queue.

  ## Options

  * `:max_size` - Maximum queue size (default: 20)

  ## Returns

  A new PendingMemories struct

  ## Examples

      pending = PendingMemories.new()
      pending = PendingMemories.new(max_size: 50)

  """
  def new(opts \\ []) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)

    %__MODULE__{
      queue: :queue.new(),
      max_size: max_size
    }
  end

  @doc """
  Enqueues a memory item for promotion.

  ## Parameters

  * `pending` - The PendingMemories struct
  * `item` - Map with id, type, data, importance, timestamp

  ## Returns

  * `{:ok, updated_pending}` - Item enqueued
  * `{:error, :at_capacity}` - Queue is full
  * `{:error, :invalid_item}` - Item missing required fields

  ## Examples

      {:ok, pending} = PendingMemories.enqueue(pending, memory_item)

  """
  def enqueue(%__MODULE__{} = pending, item) when is_map(item) do
    case validate_item(item) do
      :ok ->
        if :queue.len(pending.queue) >= pending.max_size do
          {:error, :at_capacity}
        else
          updated_queue = :queue.in(item, pending.queue)
          {:ok, %{pending | queue: updated_queue}}
        end

      error ->
        error
    end
  end

  @doc """
  Dequeues the next memory item for promotion.

  ## Returns

  * `{:ok, item, updated_pending}` - Item dequeued
  * `{:error, :empty}` - Queue is empty

  ## Examples

      {:ok, item, pending} = PendingMemories.dequeue(pending)

  """
  def dequeue(%__MODULE__{queue: queue} = pending) do
    case :queue.out(queue) do
      {{:value, item}, updated_queue} ->
        {:ok, item, %{pending | queue: updated_queue}}

      {:empty, _} ->
        {:error, :empty}
    end
  end

  @doc """
  Peeks at the next item without removing it.

  ## Returns

  * `{:ok, item}` - Next item in queue
  * `{:error, :empty}` - Queue is empty

  ## Examples

      {:ok, item} = PendingMemories.peek(pending)

  """
  def peek(%__MODULE__{queue: queue}) do
    case :queue.peek(queue) do
      {:value, item} -> {:ok, item}
      :empty -> {:error, :empty}
    end
  end

  @doc """
  Returns the number of items in the queue.

  ## Examples

      count = PendingMemories.size(pending)

  """
  def size(%__MODULE__{queue: queue}) do
    :queue.len(queue)
  end

  @doc """
  Checks if the queue is empty.

  ## Examples

      PendingMemories.empty?(pending)
      #=> true

  """
  def empty?(%__MODULE__{queue: queue}) do
    :queue.is_empty(queue)
  end

  @doc """
  Checks if the queue is full.

  ## Examples

      PendingMemories.full?(pending)
      #=> false

  """
  def full?(%__MODULE__{} = pending) do
    size(pending) >= pending.max_size
  end

  @doc """
  Returns all items as a list (in queue order).

  ## Examples

      items = PendingMemories.to_list(pending)

  """
  def to_list(%__MODULE__{queue: queue}) do
    :queue.to_list(queue)
  end

  @doc """
  Clears all items from the queue.

  ## Examples

      {:ok, pending} = PendingMemories.clear(pending)

  """
  def clear(%__MODULE__{} = pending) do
    {:ok, %{pending | queue: :queue.new()}}
  end

  @doc """
  Filters items by type.

  ## Parameters

  * `pending` - The PendingMemories struct
  * `type` - The type to filter by (:fact, :conversation, :analysis, :file_context)

  ## Returns

  List of items matching the type

  ## Examples

      facts = PendingMemories.filter_by_type(pending, :fact)

  """
  def filter_by_type(%__MODULE__{queue: queue}, type) when is_atom(type) do
    queue
    |> :queue.to_list()
    |> Enum.filter(fn item -> Map.get(item, :type) == type end)
  end

  @doc """
  Finds items by importance threshold.

  ## Parameters

  * `pending` - The PendingMemories struct
  * `min_importance` - Minimum importance score (0.0-1.0)

  ## Returns

  List of items with importance >= threshold

  ## Examples

      important = PendingMemories.filter_by_importance(pending, 0.7)

  """
  def filter_by_importance(%__MODULE__{queue: queue}, min_importance)
      when is_float(min_importance) do
    queue
    |> :queue.to_list()
    |> Enum.filter(fn item -> Map.get(item, :importance, 0.0) >= min_importance end)
  end

  @doc """
  Removes items that match the given criteria.

  ## Parameters

  * `pending` - The PendingMemories struct
  * `criteria` - Keyword list of match criteria

  ## Returns

  * `{:ok, updated_pending, removed_count}` - Items removed

  ## Examples

      {:ok, pending, count} = PendingMemories.remove_where(pending, type: :fact)

  """
  def remove_where(%__MODULE__{queue: queue} = pending, criteria) when is_list(criteria) do
    {to_keep, removed} =
      :queue.to_list(queue)
      |> Enum.reduce({[], []}, fn item, {keep_acc, remove_acc} ->
        if matches_criteria?(item, criteria) do
          {keep_acc, [item | remove_acc]}
        else
          {[item | keep_acc], remove_acc}
        end
      end)

    new_queue = Enum.reverse(to_keep) |> :queue.from_list()
    removed_count = length(removed)

    {:ok, %{pending | queue: new_queue}, removed_count}
  end

  @doc """
  Gets the priority (highest importance) item.

  ## Returns

  * `{:ok, item}` - Highest importance item
  * `{:error, :empty}` - Queue is empty

  ## Examples

      {:ok, item} = PendingMemories.peek_priority(pending)

  """
  def peek_priority(%__MODULE__{} = pending) do
    if empty?(pending) do
      {:error, :empty}
    else
      item =
        pending
        |> to_list()
        |> Enum.max_by(fn item -> Map.get(item, :importance, 0.0) end)

      {:ok, item}
    end
  end

  @doc """
  Returns items ready for promotion to long-term memory.

  Filters items based on importance threshold and optionally age.
  Items with importance >= threshold are considered ready.

  ## Parameters

  * `pending` - The PendingMemories struct
  * `opts` - Keyword list of options:
    * `:min_importance` - Minimum importance score (default: 0.7)
    * `:max_age_seconds` - Maximum age in seconds (optional)

  ## Returns

  List of items ready for promotion

  ## Examples

      ready = PendingMemories.ready_for_promotion(pending, min_importance: 0.8)
      ready = PendingMemories.ready_for_promotion(pending, max_age_seconds: 3600)

  """
  def ready_for_promotion(%__MODULE__{} = pending, opts \\ []) do
    min_importance = Keyword.get(opts, :min_importance, 0.7)
    max_age_seconds = Keyword.get(opts, :max_age_seconds)

    pending
    |> to_list()
    |> Enum.filter(fn item ->
      importance = Map.get(item, :importance, 0.0)
      importance >= min_importance
    end)
    |> filter_by_age(max_age_seconds)
  end

  @doc """
  Calculates an importance score for a memory item.

  Scores are based on:
  * Base score from item type
  * Age decay (older items lose importance)

  Returns a float between 0.0 and 1.0.

  ## Base Importance by Type

  * `:analysis` - 0.8 (analysis results are high value)
  * `:fact` - 0.5 (facts are moderately important)
  * `:file_context` - 0.6 (file context is useful)
  * `:conversation` - 0.4 (conversation excerpts are lower priority)

  ## Age Decay

  Items lose 10% importance per hour (up to 50% max decay).

  ## Examples

      0.8 = PendingMemories.calculate_importance(%{type: :analysis, timestamp: DateTime.utc_now()})

  """
  def calculate_importance(item) when is_map(item) do
    # Base importance by type
    base = base_importance(Map.get(item, :type, :fact))

    # Apply age decay if timestamp exists
    item
    |> apply_age_decay(base)
    |> Float.round(2)
  end

  @doc """
  Removes items that were successfully promoted to long-term memory.

  ## Parameters

  * `pending` - The PendingMemories struct
  * `promoted_ids` - List of item IDs that were promoted

  ## Returns

  * `{:ok, updated_pending, cleared_count}` - Items removed

  ## Examples

      {:ok, pending, 3} = PendingMemories.clear_promoted(pending, ["mem_1", "mem_2", "mem_3"])

  """
  def clear_promoted(%__MODULE__{} = pending, promoted_ids) when is_list(promoted_ids) do
    if promoted_ids == [] do
      {:ok, pending, 0}
    else
      # Convert promoted_ids to a set for efficient lookup
      id_set = MapSet.new(promoted_ids)

      {to_keep, cleared} =
        pending
        |> to_list()
        |> Enum.reduce({[], []}, fn item, {keep_acc, clear_acc} ->
          item_id = Map.get(item, :id)

          if MapSet.member?(id_set, item_id) do
            {keep_acc, [item | clear_acc]}
          else
            {[item | keep_acc], clear_acc}
          end
        end)

      new_queue = Enum.reverse(to_keep) |> :queue.from_list()
      cleared_count = length(cleared)

      {:ok, %{pending | queue: new_queue}, cleared_count}
    end
  end

  # Private Helpers

  defp validate_item(item) do
    id_result = validate_field(item, :id)
    data_result = validate_field(item, :data)

    with :ok <- id_result,
         :ok <- data_result do
      :ok
    end
  end

  defp validate_field(item, field) do
    if Map.has_key?(item, field) do
      :ok
    else
      {:error, {:missing_field, field}}
    end
  end

  defp matches_criteria?(item, criteria) when is_list(criteria) do
    Enum.all?(criteria, fn {key, value} ->
      Map.get(item, key) == value
    end)
  end

  # Helper functions for importance calculation

  defp base_importance(:analysis), do: 0.8
  defp base_importance(:file_context), do: 0.6
  defp base_importance(:fact), do: 0.5
  defp base_importance(:conversation), do: 0.4
  defp base_importance(_), do: 0.5

  defp apply_age_decay(item, base) do
    case Map.get(item, :timestamp) do
      nil ->
        base

      timestamp ->
        now = DateTime.utc_now()
        seconds_diff = DateTime.diff(now, timestamp, :second)
        hours_diff = seconds_diff / 3600

        # Decay: 10% per hour, max 50% decay
        decay_factor = min(hours_diff * 0.1, 0.5)
        base * (1.0 - decay_factor)
    end
  end

  defp filter_by_age(items, nil), do: items

  defp filter_by_age(items, max_age_seconds) when is_number(max_age_seconds) do
    now = DateTime.utc_now()

    Enum.filter(items, fn item ->
      case Map.get(item, :timestamp) do
        nil ->
          true

        timestamp ->
          age_seconds = DateTime.diff(now, timestamp, :second)
          age_seconds <= max_age_seconds
      end
    end)
  end
end
