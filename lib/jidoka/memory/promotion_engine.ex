defmodule Jidoka.Memory.PromotionEngine do
  @moduledoc """
  Evaluates and promotes items from Short-Term Memory (STM) to Long-Term Memory (LTM).

  The promotion engine processes items in the PendingMemories queue, evaluating
  them against promotion criteria and moving qualified items to LTM.

  ## Promotion Flow

  1. Dequeue items from PendingMemories
  2. Evaluate against criteria (importance, age, confidence)
  3. Score each item's promotion confidence
  4. Promote qualified items to LTM via SessionAdapter
  5. Return results with promotion details

  ## Configuration

  * `:min_importance` - Minimum importance score (default: 0.5)
  * `:max_age_seconds` - Maximum age before forced promotion (default: 300)
  * `:min_confidence` - Minimum confidence for promotion (default: 0.3)
  * `:infer_types` - Whether to infer missing types (default: true)

  ## Examples

  Implicit promotion (only items meeting criteria):

      {:ok, stm} = PromotionEngine.evaluate_and_promote(stm, ltm_adapter)

  Explicit promotion (all items):

      {:ok, stm, results} = PromotionEngine.promote_all(stm, ltm_adapter)

  With custom criteria:

      {:ok, stm} = PromotionEngine.evaluate_and_promote(stm, ltm_adapter,
        min_importance: 0.7,
        max_age_seconds: 600
      )

  """

  alias Jidoka.Memory.{ShortTerm, LongTerm.SessionAdapter}
  alias ShortTerm.PendingMemories

  @type promotion_result :: %{
          promoted: [promoted_item()],
          skipped: [skipped_item()],
          failed: [failed_item()]
        }

  @type promoted_item :: %{
          id: String.t(),
          confidence: float(),
          reason: String.t()
        }

  @type skipped_item :: %{
          id: String.t(),
          reason: String.t()
        }

  @type failed_item :: %{
          id: String.t() | nil,
          error: term(),
          item: map()
        }

  @type options :: [
          min_importance: float(),
          max_age_seconds: non_neg_integer(),
          min_confidence: float(),
          infer_types: boolean(),
          batch_size: non_neg_integer()
        ]

  # Default configuration values
  @default_min_importance 0.5
  @default_max_age_seconds 300
  @default_min_confidence 0.3
  @default_batch_size 10

  @doc """
  Evaluates and promotes items from STM's PendingMemories to LTM.

  Only promotes items that meet the promotion criteria (implicit promotion).

  ## Parameters

  * `stm` - The ShortTerm struct containing pending memories
  * `ltm_adapter` - The SessionAdapter for LTM storage
  * `opts` - Optional configuration overrides

  ## Returns

  * `{:ok, updated_stm}` - Promotion complete with results in access log
  * `{:error, reason}` - Promotion failed

  ## Examples

      {:ok, stm} = PromotionEngine.evaluate_and_promote(stm, adapter)

  """
  @spec evaluate_and_promote(ShortTerm.t(), SessionAdapter.t(), options()) ::
          {:ok, ShortTerm.t(), promotion_result()} | {:error, term()}
  def evaluate_and_promote(%ShortTerm{} = stm, %SessionAdapter{} = ltm_adapter, opts \\ []) do
    min_importance = Keyword.get(opts, :min_importance, @default_min_importance)
    max_age = Keyword.get(opts, :max_age_seconds, @default_max_age_seconds)
    min_confidence = Keyword.get(opts, :min_confidence, @default_min_confidence)
    infer_types = Keyword.get(opts, :infer_types, true)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    criteria = %{
      min_importance: min_importance,
      max_age_seconds: max_age,
      min_confidence: min_confidence,
      infer_types: infer_types
    }

    promote_from_queue(stm, ltm_adapter, criteria, batch_size: batch_size)
  end

  @doc """
  Promotes all items from PendingMemories regardless of criteria.

  Used for explicit promotion (agent-initiated) rather than automatic promotion.

  ## Parameters

  * `stm` - The ShortTerm struct
  * `ltm_adapter` - The SessionAdapter for LTM storage
  * `opts` - Optional configuration

  ## Returns

  * `{:ok, updated_stm, results}` - All items processed with results

  ## Examples

      {:ok, stm, results} = PromotionEngine.promote_all(stm, adapter)

  """
  @spec promote_all(ShortTerm.t(), SessionAdapter.t(), keyword()) ::
          {:ok, ShortTerm.t(), promotion_result()}
  def promote_all(%ShortTerm{} = stm, %SessionAdapter{} = ltm_adapter, opts \\ []) do
    infer_types = Keyword.get(opts, :infer_types, true)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    criteria = %{
      # No filters for explicit promotion
      min_importance: 0.0,
      max_age_seconds: :infinity,
      min_confidence: 0.0,
      infer_types: infer_types
    }

    promote_from_queue(stm, ltm_adapter, criteria, batch_size: batch_size, explicit: true)
  end

  @doc """
  Evaluates a single memory item against promotion criteria.

  ## Parameters

  * `item` - The memory item map
  * `criteria` - Promotion criteria map

  ## Returns

  * `{:ok, :promote, confidence}` - Item should be promoted
  * `{:ok, :skip, reason}` - Item doesn't meet criteria
  * `{:error, reason}` - Item is invalid

  ## Examples

      {:ok, :promote, 0.85} = PromotionEngine.evaluate_item(item, criteria)

  """
  @spec evaluate_item(map(), map()) :: {:ok, :promote | :skip, term()} | {:error, term()}
  def evaluate_item(item, criteria) when is_map(item) do
    with :ok <- validate_item(item),
         {:ok, item} <- ensure_type(item, criteria),
         {:ok, :promote, _} <- check_importance(item, criteria),
         {:ok, :promote, _} <- check_age(item, criteria) do
      confidence = calculate_confidence(item, criteria)
      {:ok, :promote, confidence}
    else
      {:error, reason} -> {:error, reason}
      {:ok, :skip, reason} -> {:ok, :skip, reason}
    end
  end

  @doc """
  Infers an appropriate memory type from the item's data.

  ## Parameters

  * `item` - The memory item (must have :data key)

  ## Returns

  * A memory type atom: :fact, :conversation, :analysis, :file_context

  ## Type Inference Rules

  * `:file_context` - Data contains file paths, code refs
  * `:analysis` - Data contains analysis, reasoning, conclusions
  * `:conversation` - Data contains messages, utterances
  * `:fact` - Default for other data

  ## Examples

      :file_context = PromotionEngine.infer_type(%{data: %{file_path: "/path"}})
      :analysis = PromotionEngine.infer_type(%{data: %{conclusion: "..."}})

  """
  @spec infer_type(map()) :: atom()
  def infer_type(%{data: data} = _item) when is_map(data) do
    cond do
      has_file_reference?(data) ->
        :file_context

      has_analysis_content?(data) ->
        :analysis

      has_conversation_content?(data) ->
        :conversation

      true ->
        :fact
    end
  end

  def infer_type(_item), do: :fact

  @doc """
  Calculates the confidence score for promoting an item.

  Confidence = weighted sum of:
  - importance * 0.4
  - data_quality * 0.3
  - type_specificity * 0.2
  - recency_bonus * 0.1

  ## Parameters

  * `item` - The memory item
  * `criteria` - Promotion criteria (for defaults)

  ## Returns

  * Float between 0.0 and 1.0

  """
  @spec calculate_confidence(map(), map()) :: float()
  def calculate_confidence(item, criteria \\ %{}) do
    importance = Map.get(item, :importance, 0.5)
    data_quality = data_quality_score(item)
    type_specificity = type_specificity_score(item)
    recency_bonus = recency_bonus_score(item, criteria)

    confidence =
      importance * 0.4 + data_quality * 0.3 + type_specificity * 0.2 + recency_bonus * 0.1

    Float.round(confidence, 3)
    |> min(1.0)
    |> max(0.0)
  end

  # Private Functions

  defp promote_from_queue(stm, ltm_adapter, criteria, opts) do
    explicit = Keyword.get(opts, :explicit, false)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    {promoted, skipped, failed, stm} =
      process_batch(stm, ltm_adapter, criteria, batch_size, explicit, [], [], [], MapSet.new())

    results = %{
      promoted: promoted,
      skipped: skipped,
      failed: failed
    }

    {:ok, stm, results}
  end

  # Base case: processed batch_size items or queue is empty
  defp process_batch(
         stm,
         _ltm_adapter,
         _criteria,
         0,
         _explicit,
         promoted,
         skipped,
         failed,
         _processed
       ) do
    {promoted, skipped, failed, stm}
  end

  defp process_batch(
         stm,
         ltm_adapter,
         criteria,
         remaining,
         explicit,
         promoted,
         skipped,
         failed,
         processed
       ) do
    # First, peek at the next item to check if it's already processed
    case PendingMemories.peek(stm.pending_memories) do
      {:ok, item} ->
        item_id = Map.get(item, :id)

        if MapSet.member?(processed, item_id) do
          # Already processed - we've cycled through all unique items
          # Stop the batch and leave the item in the queue for next time
          {promoted, skipped, failed, stm}
        else
          # Not processed yet, dequeue and process it
          case PendingMemories.dequeue(stm.pending_memories) do
            {:ok, item, updated_pending} ->
              stm = %{stm | pending_memories: updated_pending}
              item_id = item[:id]

              case process_item(stm, ltm_adapter, item, criteria, explicit) do
                {:ok, :promoted, result, stm} ->
                  # Item was promoted, count it against batch limit and track as processed
                  process_batch(
                    stm,
                    ltm_adapter,
                    criteria,
                    remaining - 1,
                    explicit,
                    [result | promoted],
                    skipped,
                    failed,
                    MapSet.put(processed, item_id)
                  )

                {:ok, :skipped, reason, stm} ->
                  # Item was re-enqueued
                  if explicit do
                    # Explicit mode: count skipped items against batch limit
                    process_batch(
                      stm,
                      ltm_adapter,
                      criteria,
                      remaining - 1,
                      explicit,
                      promoted,
                      [%{id: item_id, reason: reason} | skipped],
                      failed,
                      MapSet.put(processed, item_id)
                    )
                  else
                    # Implicit mode: don't count against batch limit, but still track as processed
                    # Continue processing if there are more unprocessed items
                    process_batch(
                      stm,
                      ltm_adapter,
                      criteria,
                      # Don't decrement - item wasn't consumed
                      remaining,
                      explicit,
                      promoted,
                      [%{id: item_id, reason: reason} | skipped],
                      failed,
                      MapSet.put(processed, item_id)
                    )
                  end

                {:error, reason, stm} ->
                  # Item failed
                  if explicit do
                    process_batch(
                      stm,
                      ltm_adapter,
                      criteria,
                      remaining - 1,
                      explicit,
                      promoted,
                      skipped,
                      [%{id: item_id, error: reason, item: item} | failed],
                      MapSet.put(processed, item_id)
                    )
                  else
                    # Implicit mode: don't count against batch limit
                    process_batch(
                      stm,
                      ltm_adapter,
                      criteria,
                      # Don't decrement - item wasn't consumed
                      remaining,
                      explicit,
                      promoted,
                      skipped,
                      [%{id: item_id, error: reason, item: item} | failed],
                      MapSet.put(processed, item_id)
                    )
                  end
              end

            {:error, :empty} ->
              {promoted, skipped, failed, stm}
          end
        end

      {:error, :empty} ->
        {promoted, skipped, failed, stm}
    end
  end

  defp process_item(stm, ltm_adapter, item, criteria, explicit) do
    with {:ok, item} <- ensure_type(item, criteria),
         {:ok, evaluation, confidence} <- evaluate_item(item, criteria) do
      maybe_promote(stm, ltm_adapter, item, evaluation, criteria, explicit, confidence)
    else
      {:error, reason} ->
        # Re-enqueue failed items for implicit promotion (not explicit)
        updated_stm =
          unless explicit do
            case PendingMemories.enqueue(stm.pending_memories, item) do
              {:ok, updated_pending} -> %{stm | pending_memories: updated_pending}
              _ -> stm
            end
          else
            stm
          end

        {:error, reason, updated_stm}
    end
  end

  defp maybe_promote(stm, ltm_adapter, item, :promote, _criteria, _explicit, confidence) do
    memory = to_memory_format(item)

    case SessionAdapter.persist_memory(ltm_adapter, memory) do
      {:ok, _persisted} ->
        {:ok, :promoted, %{id: item[:id], confidence: confidence, reason: promotion_reason(item)},
         stm}

      {:error, reason} ->
        {:error, {:ltm_error, reason}, stm}
    end
  end

  defp maybe_promote(stm, _ltm_adapter, item, :skip, _criteria, explicit, _confidence) do
    # For implicit promotion, re-enqueue skipped items
    updated_stm =
      unless explicit do
        case PendingMemories.enqueue(stm.pending_memories, item) do
          {:ok, updated_pending} ->
            %{stm | pending_memories: updated_pending}

          _ ->
            stm
        end
      else
        stm
      end

    {:ok, :skipped, "below threshold", updated_stm}
  end

  defp to_memory_format(item) do
    %{
      id: Map.get(item, :id),
      type: Map.get(item, :type, :fact),
      data: Map.get(item, :data, %{}),
      importance: Map.get(item, :importance, 0.5)
    }
  end

  defp ensure_type(item, criteria) do
    if Map.has_key?(item, :type) do
      {:ok, item}
    else
      if Map.get(criteria, :infer_types, true) do
        type = infer_type(item)
        {:ok, Map.put(item, :type, type)}
      else
        {:error, {:missing_type, :no_type_and_inference_disabled}}
      end
    end
  end

  defp validate_item(item) when is_map(item) do
    required = [:id, :data]
    missing = Enum.reject(required, &Map.has_key?(item, &1))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp check_importance(item, criteria) do
    importance = Map.get(item, :importance, 0.0)
    threshold = Map.get(criteria, :min_importance, @default_min_importance)

    if importance >= threshold do
      {:ok, :promote, :importance}
    else
      {:ok, :skip, :below_importance_threshold}
    end
  end

  defp check_age(item, criteria) do
    max_age = Map.get(criteria, :max_age_seconds, @default_max_age_seconds)

    if max_age == :infinity do
      {:ok, :promote, :age}
    else
      timestamp = Map.get(item, :timestamp, DateTime.utc_now())
      age_seconds = DateTime.diff(DateTime.utc_now(), timestamp)

      if age_seconds >= max_age do
        {:ok, :promote, :age}
      else
        # Check if importance is high enough to override age
        importance = Map.get(item, :importance, 0.0)

        if importance >= 0.8 do
          {:ok, :promote, :high_importance_override}
        else
          {:ok, :skip, :too_recent}
        end
      end
    end
  end

  defp data_quality_score(item) do
    data = Map.get(item, :data, %{})

    score =
      cond do
        map_size(data) == 0 ->
          0.0

        map_size(data) >= 3 ->
          1.0

        true ->
          0.5
      end

    # Bonus for nested structures
    if has_nested_data?(data) do
      min(score + 0.2, 1.0)
    else
      score
    end
  end

  defp type_specificity_score(item) do
    if Map.has_key?(item, :type) do
      1.0
    else
      0.5
    end
  end

  defp recency_bonus_score(item, criteria) do
    max_age = Map.get(criteria, :max_age_seconds, @default_max_age_seconds)

    if max_age == :infinity do
      0.0
    else
      timestamp = Map.get(item, :timestamp, DateTime.utc_now())
      age_seconds = DateTime.diff(DateTime.utc_now(), timestamp)

      # Older items get slight bonus (they've waited longer)
      min(age_seconds / max_age, 1.0)
    end
  end

  defp has_file_reference?(data) do
    file_keys = [:file_path, :file, :path, :code, :module, :function]
    Enum.any?(file_keys, &Map.has_key?(data, &1))
  end

  defp has_analysis_content?(data) do
    analysis_keys = [:analysis, :conclusion, :reasoning, :summary, :finding]
    Enum.any?(analysis_keys, &Map.has_key?(data, &1))
  end

  defp has_conversation_content?(data) do
    conv_keys = [:message, :utterance, :role, :content, :user, :assistant]
    Enum.any?(conv_keys, &Map.has_key?(data, &1))
  end

  defp has_nested_data?(data) do
    Enum.any?(Map.values(data), &is_map/1)
  end

  defp promotion_reason(item) do
    cond do
      Map.get(item, :importance, 0) >= 0.8 ->
        "high_importance"

      Map.get(item, :type) == :user_preference ->
        "user_preference"

      Map.get(item, :type) == :decision ->
        "decision"

      true ->
        "meets_criteria"
    end
  end
end
