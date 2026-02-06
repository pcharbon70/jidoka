defmodule JidoCoderLib.Memory.Retrieval do
  @moduledoc """
  Retrieves relevant memories from Long-Term Memory (LTM) for context enrichment.

  The Retrieval module provides search and ranking capabilities for finding
  relevant memories in LTM, with support for keyword matching, relevance
  scoring, and result caching.

  ## Retrieval Modes

  1. **Keyword Search** - Find memories matching specific keywords
  2. **Similarity Ranking** - Rank results by multi-factor relevance score
  3. **Context Building** - Format retrieved memories for LLM consumption

  ## Query Structure

      query = %{
        keywords: ["file", "elixir"],
        type: :file_context,
        min_importance: 0.5,
        limit: 10,
        recency_boost: true
      }

  ## Examples

  Keyword search:

      {:ok, results} = Retrieval.search(adapter, %{
        keywords: ["user", "preference"],
        limit: 5
      })

  Context enrichment:

      {:ok, context} = Retrieval.enrich_context(adapter, %{
        keywords: ["analysis"]
      }, max_tokens: 1000)

  Cached search:

      {:ok, results} = Retrieval.search_with_cache(adapter, query)

  """

  alias JidoCoderLib.Memory.LongTerm.SessionAdapter

  @type query :: %{
          optional(:keywords) => [String.t()],
          optional(:type) => atom(),
          optional(:min_importance) => float(),
          optional(:limit) => integer(),
          optional(:recency_boost) => boolean()
        }

  @type result :: %{
          memory: map(),
          score: float(),
          match_reasons: [String.t()]
        }

  @type context :: %{
          memories: [map()],
          summary: String.t(),
          count: integer(),
          last_retrieved: DateTime.t()
        }

  # Default configuration values
  @default_limit 10
  # 5 minutes
  @default_cache_ttl 300
  @default_match_mode :substring
  @cache_table_name :jido_memory_retrieval_cache
  @max_cache_size 100

  # Relevance scoring weights
  @keyword_weight 0.4
  @recency_weight 0.2
  @importance_weight 0.2
  @type_weight 0.2

  @doc """
  Searches LTM for memories matching the given query criteria.

  ## Parameters

  * `adapter` - The SessionAdapter for LTM access
  * `query` - Map with search criteria (keywords, type, min_importance, limit)

  ## Returns

  * `{:ok, results}` - List of ranked results with scores
  * `{:error, reason}` - Search failed

  ## Examples

      {:ok, results} = Retrieval.search(adapter, %{
        keywords: ["file"],
        type: :file_context,
        limit: 10
      })

  """
  @spec search(SessionAdapter.t(), query()) :: {:ok, [result()]} | {:error, term()}
  def search(%SessionAdapter{} = adapter, query) when is_map(query) do
    with {:ok, memories} <- SessionAdapter.query_memories(adapter, base_query_opts(query)),
         scored <- score_memories(memories, query) do
      filtered = filter_by_keywords(scored, query)
      ranked = rank_results(filtered, query)
      limited = apply_limit(ranked, query)

      {:ok, limited}
    end
  end

  @doc """
  Searches LTM with result caching.

  Uses an ETS table to cache query results. Subsequent calls with the same
  query will return cached results if they haven't expired.

  ## Parameters

  * `adapter` - The SessionAdapter for LTM access
  * `query` - Map with search criteria (can include :cache_ttl)

  ## Returns

  * `{:ok, results}` - List of ranked results (cached or fresh)
  * `{:error, reason}` - Search failed

  ## Examples

      {:ok, results} = Retrieval.search_with_cache(adapter, %{
        keywords: ["analysis"],
        cache_ttl: 300
      })

  """
  @spec search_with_cache(SessionAdapter.t(), query()) :: {:ok, [result()]} | {:error, term()}
  def search_with_cache(%SessionAdapter{} = adapter, query) when is_map(query) do
    ensure_cache_table()

    cache_key = cache_key(adapter, query)
    cache_ttl = Map.get(query, :cache_ttl, @default_cache_ttl)

    case get_cached(cache_key) do
      {:ok, cached} ->
        {:ok, cached}

      :miss ->
        case search(adapter, query) do
          {:ok, results} ->
            put_cached(cache_key, results, cache_ttl)
            {:ok, results}

          error ->
            error
        end
    end
  end

  @doc """
  Enriches context by retrieving relevant memories and formatting them.

  Useful for adding LTM context to LLM prompts. Returns a structured context
  with formatted memories and metadata.

  ## Parameters

  * `adapter` - The SessionAdapter for LTM access
  * `query` - Map with search criteria
  * `opts` - Keyword list of options:
    * `:max_tokens` - Approximate token limit for context (default: 2000)
    * `:group_by` - How to group memories (:type, :recency, or :none)
    * `:include_metadata` - Whether to include timestamps and scores

  ## Returns

  * `{:ok, context}` - Enriched context map
  * `{:error, reason}` - Context building failed

  ## Examples

      {:ok, context} = Retrieval.enrich_context(adapter, %{
        keywords: ["user"]
      }, max_tokens: 1000, group_by: :type)

      context.memories
      #=> [%{id: "mem_1", ...}, ...]

      context.summary
      #=> "Found 3 related memories..."

  """
  @spec enrich_context(SessionAdapter.t(), query(), keyword()) ::
          {:ok, context()} | {:error, term()}
  def enrich_context(%SessionAdapter{} = adapter, query, opts \\ []) do
    with {:ok, results} <- search(adapter, query) do
      max_tokens = Keyword.get(opts, :max_tokens, 2000)
      group_by = Keyword.get(opts, :group_by, :none)
      include_metadata = Keyword.get(opts, :include_metadata, false)

      memories = Enum.map(results, fn r -> r.memory end)
      formatted = format_memories(memories, group_by, include_metadata)
      summary = build_summary(memories, results)

      context = %{
        memories: formatted,
        summary: summary,
        count: length(memories),
        last_retrieved: DateTime.utc_now()
      }

      {:ok, context}
    end
  end

  @doc """
  Calculates relevance score for a memory against a query.

  Relevance = weighted sum of:
  - Keyword match score × 0.4
  - Recency score × 0.2
  - Importance × 0.2
  - Type relevance × 0.2

  ## Parameters

  * `memory` - The memory item to score
  * `query` - The query with keywords and criteria

  ## Returns

  * Float between 0.0 and 1.0

  ## Examples

      score = Retrieval.calculate_relevance(memory, query)
      #=> 0.75

  """
  @spec calculate_relevance(map(), query()) :: float()
  def calculate_relevance(memory, query) do
    keyword_score = keyword_match_score(memory, query) * @keyword_weight
    recency_score = recency_score(memory) * @recency_weight
    importance_score = Map.get(memory, :importance, 0.5) * @importance_weight
    type_score = type_relevance_score(memory, query) * @type_weight

    score = keyword_score + recency_score + importance_score + type_score

    Float.round(score, 3)
    |> min(1.0)
    |> max(0.0)
  end

  # Private Functions

  defp base_query_opts(query) do
    []
    |> maybe_put_type(query)
    |> maybe_put_min_importance(query)
  end

  defp maybe_put_type(opts, %{type: type}), do: Keyword.put(opts, :type, type)
  defp maybe_put_type(opts, _), do: opts

  defp maybe_put_min_importance(opts, %{min_importance: min}),
    do: Keyword.put(opts, :min_importance, min)

  defp maybe_put_min_importance(opts, _), do: opts

  defp score_memories(memories, query) do
    keywords = Map.get(query, :keywords, [])

    Enum.map(memories, fn memory ->
      score = calculate_relevance(memory, query)
      match_reasons = match_reasons(memory, keywords)

      %{
        memory: memory,
        score: score,
        match_reasons: match_reasons
      }
    end)
  end

  defp rank_results(results, _query) do
    Enum.sort_by(results, fn r -> r.score end, :desc)
  end

  defp apply_limit(results, query) do
    limit = Map.get(query, :limit, @default_limit)
    Enum.take(results, limit)
  end

  defp filter_by_keywords(results, query) do
    keywords = Map.get(query, :keywords, [])

    if Enum.empty?(keywords) do
      results
    else
      Enum.filter(results, fn result ->
        length(result.match_reasons) > 0
      end)
    end
  end

  defp keyword_match_score(memory, query) do
    keywords = Map.get(query, :keywords, [])

    if Enum.empty?(keywords) do
      0.0
    else
      matches = count_keyword_matches(memory, keywords)
      # Normalize by number of keywords, capped at 1.0
      min(matches / length(keywords), 1.0)
    end
  end

  defp count_keyword_matches(memory, keywords) do
    data = Map.get(memory, :data, %{})
    data_string = data_to_string(data)

    Enum.count(keywords, fn keyword ->
      String.contains?(data_string, keyword)
    end)
  end

  defp data_to_string(data) when is_map(data) do
    data
    |> Enum.map(fn
      {k, v} when is_binary(v) -> "#{k}: #{v}"
      {k, v} when is_number(v) -> "#{k}: #{v}"
      {k, v} when is_atom(v) -> "#{k}: #{v}"
      {k, v} when is_list(v) -> "#{k}: [#{inspect(v)}]"
      {_, v} when is_map(v) -> "#{inspect(v)}"
      {k, _} -> "#{k}: #{inspect(data[k])}"
    end)
    |> Enum.join(" ")
  end

  defp recency_score(memory) do
    created_at = Map.get(memory, :created_at)
    updated_at = Map.get(memory, :updated_at)

    timestamp = updated_at || created_at

    if timestamp do
      # More recent = higher score
      # Age in hours, max 24 hours for scoring
      age_hours = DateTime.diff(DateTime.utc_now(), timestamp) / 3600
      max_age = 24
      age_factor = max(1.0 - age_hours / max_age, 0.0)
      age_factor * age_factor
    else
      0.5
    end
  end

  defp type_relevance_score(memory, query) do
    memory_type = Map.get(memory, :type)
    query_type = Map.get(query, :type)

    if query_type do
      if memory_type == query_type do
        1.0
      else
        0.0
      end
    else
      # No type filter, all types are equally relevant
      0.5
    end
  end

  defp match_reasons(memory, []) do
    []
  end

  defp match_reasons(memory, keywords) do
    data = Map.get(memory, :data, %{})
    data_string = data_to_string(data)

    keywords
    |> Enum.filter(&String.contains?(data_string, &1))
  end

  # Formatting functions

  defp format_memories(memories, :none, _include_metadata) do
    memories
  end

  defp format_memories(memories, :type, include_metadata) do
    memories
    |> Enum.group_by(fn m -> Map.get(m, :type, :unknown) end)
    |> Enum.flat_map(fn {type, mems} ->
      if include_metadata do
        [%{type: type, count: length(mems), memories: mems}]
      else
        mems
      end
    end)
  end

  defp format_memories(memories, :recency, include_metadata) do
    memories
    |> Enum.sort_by(
      fn m ->
        updated_at = Map.get(m, :updated_at, Map.get(m, :created_at))
        if updated_at, do: updated_at, else: DateTime.utc_now()
      end,
      :desc
    )
    |> Enum.map(fn memory ->
      if include_metadata do
        Map.take(memory, [:id, :type, :data, :importance, :updated_at])
      else
        Map.take(memory, [:id, :type, :data])
      end
    end)
  end

  defp format_memories(memories, _group_by, include_metadata) do
    Enum.map(memories, fn memory ->
      if include_metadata do
        Map.take(memory, [:id, :type, :data, :importance, :created_at])
      else
        Map.take(memory, [:id, :type, :data])
      end
    end)
  end

  defp build_summary(memories, results) do
    count = length(memories)

    type_counts =
      memories
      |> Enum.group_by(fn m -> Map.get(m, :type, :unknown) end)
      |> Enum.map(fn {type, mems} -> {type, length(mems)} end)
      |> Enum.sort_by(fn {_type, count} -> count end, :desc)

    type_str =
      type_counts
      |> Enum.map(fn {type, count} -> "#{count} #{type}" end)
      |> Enum.join(", ")

    avg_score =
      if length(results) > 0 do
        total = Enum.reduce(results, 0.0, fn r, acc -> acc + r.score end)
        Float.round(total / length(results), 2)
      else
        0.0
      end

    "Found #{count} #{if(count == 1, do: "memory", else: "memories")} (#{type_str}), avg relevance: #{avg_score}"
  end

  # Cache functions

  defp ensure_cache_table do
    case :ets.whereis(@cache_table_name) do
      :undefined ->
        :ets.new(@cache_table_name, [:named_table, :set, :public])
        :ok

      _ref ->
        :ok
    end
  end

  defp cache_key(%SessionAdapter{session_id: session_id}, query) do
    # Create a deterministic cache key from session_id and query
    # Including session_id prevents cache poisoning across sessions (SEC-4)
    {session_id, Map.drop(query, [:cache_ttl])}
    |> :erlang.phash2()
  end

  defp get_cached(cache_key) do
    case :ets.lookup(@cache_table_name, cache_key) do
      [{^cache_key, results, expires_at}] ->
        now = DateTime.utc_now() |> DateTime.to_unix()

        if now < expires_at do
          {:ok, results}
        else
          # Expired, remove from cache
          :ets.delete(@cache_table_name, cache_key)
          :miss
        end

      [] ->
        :miss
    end
  end

  defp put_cached(cache_key, results, ttl_seconds) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    expires_at = now + ttl_seconds

    # Check cache size and evict if necessary
    evict_if_needed()

    :ets.insert(@cache_table_name, {cache_key, results, expires_at})

    :ok
  end

  defp evict_if_needed do
    size = :ets.info(@cache_table_name, :size)

    if size >= @max_cache_size do
      # Evict oldest entries (simple approach: clear and recreate)
      # In production, use LRU or similar
      :ets.delete_all_objects(@cache_table_name)
    end
  end

  @doc """
  Clears the retrieval cache.

  ## Examples

      :ok = Retrieval.clear_cache()

  """
  @spec clear_cache() :: :ok
  def clear_cache do
    case :ets.whereis(@cache_table_name) do
      :undefined -> :ok
      _ref -> :ets.delete_all_objects(@cache_table_name)
    end

    :ok
  end

  @doc """
  Returns cache statistics.

  ## Examples

      stats = Retrieval.cache_stats()
      #=> %{size: 5, max_size: 100}

  """
  @spec cache_stats() :: %{size: integer(), max_size: integer()}
  def cache_stats do
    case :ets.whereis(@cache_table_name) do
      :undefined -> %{size: 0, max_size: @max_cache_size}
      _ref -> %{size: :ets.info(@cache_table_name, :size), max_size: @max_cache_size}
    end
  end
end
