defmodule Jidoka.Knowledge.Queries do
  @moduledoc """
  Reusable SPARQL query helpers for common knowledge operations.

  This module provides convenience functions for querying memories in the
  knowledge graph without writing raw SPARQL. All functions return memory
  maps with consistent structure.

  ## Memory Types

  The module supports three memory types from the Jido ontology:

  | Type | Class | IRI |
  |------|-------|-----|
  | `:fact` | `jido:Fact` | `https://jido.ai/ontologies/core#Fact` |
  | `:decision` | `jido:Decision` | `https://jido.ai/ontologies/core#Decision` |
  | `:lesson_learned` | `jido:LessonLearned` | `https://jido.ai/ontologies/core#LessonLearned` |

  ## Options

  All query functions support common options:

  | Option | Type | Description |
  |--------|------|-------------|
  | `:session_id` | String | Scope to specific session |
  | `:min_confidence` | Float | Minimum confidence score (0.0-1.0) |
  | `:limit` | Integer | Maximum number of results |
  | `:offset` | Integer | Pagination offset |
  | `:engine_name` | Atom | Name of the knowledge engine |

  ## Examples

  Find all facts:

      {:ok, facts} = Queries.find_facts()

  Find facts for a session:

      {:ok, facts} = Queries.find_facts(session_id: "session-123")

  Find recent memories:

      {:ok, recent} = Queries.recent_memories(limit: 20)

  Get all memories for a session:

      {:ok, memories} = Queries.session_memories("session-123")

  """

  alias Jidoka.Knowledge.{Engine, Context, Ontology, NamedGraphs}
  alias TripleStore.SPARQL.Query

  # Default engine name
  @default_engine :knowledge_engine

  # Memory graph
  @memory_graph :long_term_context

  # Jido namespace
  @jido_namespace "https://jido.ai/ontologies/core#"

  # Property IRIs
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

  # ========================================================================
  # Type Definitions
  # ========================================================================

  @type query_opts :: [
          {:session_id, String.t()},
          {:min_confidence, float()},
          {:limit, pos_integer()},
          {:offset, non_neg_integer()},
          {:engine_name, atom()}
        ]

  # ========================================================================
  # Public API - Type-Based Queries
  # ========================================================================

  @doc """
  Finds all Fact memories in the knowledge graph.

  ## Options

  - `:session_id` - Scope to specific session
  - `:min_confidence` - Minimum confidence score (0.0-1.0)
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  - `:engine_name` - Name of the knowledge engine

  ## Returns

  - `{:ok, memories}` - List of memory maps
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, facts} = Queries.find_facts()

      {:ok, facts} = Queries.find_facts(session_id: "session-123")

      {:ok, facts} = Queries.find_facts(min_confidence: 0.8, limit: 10)

  """
  @spec find_facts(keyword()) :: {:ok, [map()]} | {:error, term()}
  def find_facts(opts \\ []) do
    with {:ok, type_iri} <- Ontology.get_class_iri(:fact) do
      query_by_type(type_iri, opts)
    end
  end

  @doc """
  Finds all Decision memories in the knowledge graph.

  See `find_facts/1` for options.

  ## Examples

      {:ok, decisions} = Queries.find_decisions()

      {:ok, decisions} = Queries.find_decisions(limit: 5)

  """
  @spec find_decisions(keyword()) :: {:ok, [map()]} | {:error, term()}
  def find_decisions(opts \\ []) do
    with {:ok, type_iri} <- Ontology.get_class_iri(:decision) do
      query_by_type(type_iri, opts)
    end
  end

  @doc """
  Finds all LessonLearned memories in the knowledge graph.

  See `find_facts/1` for options.

  ## Examples

      {:ok, lessons} = Queries.find_lessons()

      {:ok, lessons} = Queries.find_lessons(session_id: "session-123")

  """
  @spec find_lessons(keyword()) :: {:ok, [map()]} | {:error, term()}
  def find_lessons(opts \\ []) do
    with {:ok, type_iri} <- Ontology.get_class_iri(:lesson_learned) do
      query_by_type(type_iri, opts)
    end
  end

  # ========================================================================
  # Public API - Session-Scoped Queries
  # ========================================================================

  @doc """
  Finds all memories for a specific session.

  ## Parameters

  - `session_id` - The session identifier
  - `opts` - Additional options (min_confidence, limit, offset, engine_name)

  ## Returns

  - `{:ok, memories}` - List of memory maps
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, memories} = Queries.session_memories("session-123")

      {:ok, memories} = Queries.session_memories("session-123", limit: 20)

      {:ok, facts} = Queries.session_memories("session-123", type: :fact)

  """
  @spec session_memories(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def session_memories(session_id, opts \\ []) when is_binary(session_id) do
    # Extract type option if provided, otherwise query all memory types
    type = Keyword.get(opts, :type)

    case type do
      nil -> query_all_session_memories(session_id, opts)
      _ -> memories_by_type(type, Keyword.put(opts, :session_id, session_id))
    end
  end

  # ========================================================================
  # Public API - Generic Type Query
  # ========================================================================

  @doc """
  Finds memories by type with optional filters.

  ## Parameters

  - `type` - Memory type atom (:fact, :decision, :lesson_learned)
  - `opts` - Additional filters (session_id, min_confidence, limit, offset, engine_name)

  ## Returns

  - `{:ok, memories}` - List of memory maps
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, facts} = Queries.memories_by_type(:fact)

      {:ok, facts} = Queries.memories_by_type(:fact, session_id: "session-123")

      {:ok, recent} = Queries.memories_by_type(:decision,
        min_confidence: 0.8,
        limit: 10
      )

  """
  @spec memories_by_type(atom(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def memories_by_type(type, opts \\ [])

  def memories_by_type(type, opts) when type in [:fact, :decision, :lesson_learned] do
    with {:ok, type_iri} <- Ontology.get_class_iri(type) do
      query_by_type(type_iri, opts)
    end
  end

  def memories_by_type(type, _opts) do
    {:error, {:invalid_type, type}}
  end

  # ========================================================================
  # Public API - Temporal Queries
  # ========================================================================

  @doc """
  Finds recent memories across all sessions.

  ## Options

  - `:type` - Filter by memory type (:fact, :decision, :lesson_learned)
  - `:session_id` - Scope to specific session
  - `:limit` - Maximum number of results (default: 10)
  - `:offset` - Pagination offset
  - `:min_confidence` - Minimum confidence score

  ## Returns

  - `{:ok, memories}` - List of memory maps ordered by timestamp (newest first)
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, recent} = Queries.recent_memories()

      {:ok, recent} = Queries.recent_memories(limit: 20)

      {:ok, recent_facts} = Queries.recent_memories(type: :fact, limit: 5)

  """
  @spec recent_memories(keyword()) :: {:ok, [map()]} | {:error, term()}
  def recent_memories(opts \\ []) do
    # Default limit for recent memories
    limit = Keyword.get(opts, :limit, 10)
    opts = Keyword.put(opts, :limit, limit)

    # If type specified, use type-based query
    case Keyword.get(opts, :type) do
      nil -> query_all_recent(opts)
      type -> memories_by_type(type, opts)
    end
  end

  # ========================================================================
  # Private Helpers - Query Execution
  # ========================================================================

  # Query by specific type IRI
  defp query_by_type(type_iri, opts) do
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    confidence_filter = build_confidence_filter(opts)
    limit_clause = build_limit_clause(opts)

    # Build WHERE clause with optional session_id
    where_clause = build_where_clause(type_iri, opts)

    # Derive type atom from type_iri for result parsing
    result_type = iri_to_type(type_iri)

    query =
      """
      PREFIX jido: <#{@jido_namespace}>

      SELECT ?s ?content ?confidence ?timestamp WHERE {
        GRAPH <#{graph_iri}> {
          #{where_clause}
          #{confidence_filter}
        }
      }
      ORDER BY DESC(?timestamp)
      #{limit_clause}
      """
      |> String.trim()

    execute_query(ctx, query, result_type)
  end

  # Query all memory types for a session
  defp query_all_session_memories(session_id, opts) do
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    confidence_filter = build_confidence_filter(opts)
    limit_clause = build_limit_clause(opts)

    query =
      """
      PREFIX jido: <#{@jido_namespace}>

      SELECT ?s ?type ?content ?confidence ?timestamp WHERE {
        GRAPH <#{graph_iri}> {
          ?s <#{@rdf_type}> ?type ;
             jido:sessionId "#{session_id}" ;
             jido:content ?content ;
             jido:confidence ?confidence ;
             jido:timestamp ?timestamp .
             #{confidence_filter}
        }
      }
      ORDER BY DESC(?timestamp)
      #{limit_clause}
      """
      |> String.trim()

    execute_query(ctx, query, :all)
  end

  # Query all recent memories (any type)
  defp query_all_recent(opts) do
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    confidence_filter = build_confidence_filter(opts)
    limit_clause = build_limit_clause(opts)

    # Build WHERE clause with optional session_id
    where_clause = build_recent_where_clause(opts)

    query =
      """
      PREFIX jido: <#{@jido_namespace}>

      SELECT ?s ?type ?content ?confidence ?timestamp WHERE {
        GRAPH <#{graph_iri}> {
          #{where_clause}
          #{confidence_filter}
        }
      }
      ORDER BY DESC(?timestamp)
      #{limit_clause}
      """
      |> String.trim()

    execute_query(ctx, query, :all)
  end

  # Execute SPARQL query and parse results
  defp execute_query(ctx, query, result_type) do
    case Query.query(ctx, query, []) do
      {:ok, []} ->
        {:ok, []}

      {:ok, results} when is_list(results) ->
        memories = parse_results(results, result_type)
        {:ok, memories}

      {:error, :unauthorized} ->
        # User doesn't have permission to query the graph
        # Return empty results as a safe default
        {:ok, []}

      {:error, _} = error ->
        error
    end
  end

  # ========================================================================
  # Private Helpers - Result Parsing
  # ========================================================================

  # Parse SPARQL results into memory maps
  # Handles SELECT query results where values are returned directly as keys
  defp parse_results(results, result_type) do
    results
    |> Enum.map(fn result -> parse_result_row(result, result_type) end)
    |> Enum.filter(& &1)
  end

  # Parse a single result row from SELECT query
  defp parse_result_row(result, result_type) do
    # Extract subject IRI
    subject =
      case Map.get(result, "s") do
        {:iri, iri} -> iri
        {:named_node, iri} -> iri
        iri_string when is_binary(iri_string) -> iri_string
        _ -> nil
      end

    if is_nil(subject) do
      nil
    else
      # Extract values directly from result map
      content = Map.get(result, "content")
      confidence = Map.get(result, "confidence")
      timestamp_str = Map.get(result, "timestamp")

      # For query_all_recent, extract type from result
      type =
        case result_type do
          :all -> extract_type_from_result(Map.get(result, "type"))
          _ -> result_type
        end

      # Parse values
      data = parse_content(content)
      importance = parse_confidence(confidence)
      timestamp = parse_timestamp(timestamp_str)

      # Extract memory ID and session ID from subject IRI
      {memory_id, session_id} = parse_subject_iri(subject)

      %{
        id: memory_id,
        session_id: session_id,
        type: type,
        data: data,
        importance: importance,
        created_at: timestamp,
        updated_at: timestamp
      }
    end
  end

  # Extract type atom from type IRI in results
  defp extract_type_from_result(nil), do: :fact
  defp extract_type_from_result({:iri, iri}), do: iri_to_type(iri)
  defp extract_type_from_result({:named_node, iri}), do: iri_to_type(iri)
  defp extract_type_from_result(iri) when is_binary(iri), do: iri_to_type(iri)

  defp iri_to_type(iri) do
    cond do
      String.contains?(iri, "#Fact") -> :fact
      String.contains?(iri, "#Decision") -> :decision
      String.contains?(iri, "#LessonLearned") -> :lesson_learned
      true -> :fact
    end
  end

  # Parse content (JSON string) into map
  defp parse_content(nil), do: %{}

  defp parse_content(content_str) when is_binary(content_str) do
    case Jason.decode(content_str) do
      {:ok, data} when is_map(data) -> data
      _ -> %{"content" => content_str}
    end
  end

  defp parse_content({:literal, val}) when is_binary(val), do: parse_content(val)
  defp parse_content({:literal, :simple, val}) when is_binary(val), do: parse_content(val)
  defp parse_content({:literal, :typed, val, _type}) when is_binary(val), do: parse_content(val)
  defp parse_content(_), do: %{}

  # Parse confidence string to float
  defp parse_confidence(nil), do: 0.5

  defp parse_confidence(confidence_str) when is_binary(confidence_str) do
    case Float.parse(confidence_str) do
      {val, _} -> val
      :error -> 0.5
    end
  end

  defp parse_confidence({:literal, val}) when is_binary(val), do: parse_confidence(val)
  defp parse_confidence({:literal, :simple, val}) when is_binary(val), do: parse_confidence(val)

  defp parse_confidence({:literal, :typed, val, _type}) when is_binary(val),
    do: parse_confidence(val)

  defp parse_confidence(_), do: 0.5

  # Parse timestamp string to DateTime
  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(timestamp_str) when is_binary(timestamp_str) do
    case DateTime.from_iso8601(timestamp_str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp({:literal, val}) when is_binary(val), do: parse_timestamp(val)
  defp parse_timestamp({:literal, :simple, val}) when is_binary(val), do: parse_timestamp(val)

  defp parse_timestamp({:literal, :typed, val, _type}) when is_binary(val),
    do: parse_timestamp(val)

  defp parse_timestamp({:literal, _type, val, _datatype}) when is_binary(val),
    do: parse_timestamp(val)

  defp parse_timestamp(_), do: DateTime.utc_now()

  # Parse subject IRI to extract memory_id and session_id
  defp parse_subject_iri(subject_iri) do
    # Subject IRI format: https://jido.ai/memories#session-123_mem-456
    case String.split(subject_iri, "#") do
      [_, fragment] ->
        case String.split(fragment, "_", parts: 2) do
          [session_id, memory_id] -> {memory_id, session_id}
          _ -> {fragment, nil}
        end

      _ ->
        {subject_iri, nil}
    end
  end

  # ========================================================================
  # Private Helpers - Query Building
  # ========================================================================

  # Build WHERE clause with optional session_id
  # FILTER EXISTS is not supported by triple_store, so we include
  # sessionId directly in the pattern matching
  defp build_where_clause(type_iri, opts) do
    session_id = Keyword.get(opts, :session_id)

    case session_id do
      nil ->
        """
        ?s <#{@rdf_type}> <#{type_iri}> ;
           jido:content ?content ;
           jido:confidence ?confidence ;
           jido:timestamp ?timestamp .
        """

      session_id ->
        """
        ?s <#{@rdf_type}> <#{type_iri}> ;
           jido:sessionId \"#{session_id}\" ;
           jido:content ?content ;
           jido:confidence ?confidence ;
           jido:timestamp ?timestamp .
        """
    end
  end

  # Build WHERE clause for recent memories query (includes ?type variable)
  defp build_recent_where_clause(opts) do
    session_id = Keyword.get(opts, :session_id)

    case session_id do
      nil ->
        """
        ?s <#{@rdf_type}> ?type ;
           jido:content ?content ;
           jido:confidence ?confidence ;
           jido:timestamp ?timestamp .
        """

      session_id ->
        """
        ?s <#{@rdf_type}> ?type ;
           jido:sessionId \"#{session_id}\" ;
           jido:content ?content ;
           jido:confidence ?confidence ;
           jido:timestamp ?timestamp .
        """
    end
  end

  # Build confidence filter clause
  defp build_confidence_filter(opts) do
    case Keyword.get(opts, :min_confidence) do
      nil -> ""
      min when is_number(min) -> "FILTER(?confidence >= #{min})"
      _ -> ""
    end
  end

  # Build limit clause
  defp build_limit_clause(opts) do
    case Keyword.get(opts, :limit) do
      nil -> ""
      limit when is_integer(limit) and limit > 0 -> "LIMIT #{limit}"
      _ -> ""
    end
  end

  # ========================================================================
  # Private Helpers - Context
  # ========================================================================

  defp get_context(opts) do
    default_engine = Application.get_env(:jidoka, :knowledge_engine_name, @default_engine)
    engine_name = Keyword.get(opts, :engine_name, default_engine)

    engine_name
    |> Engine.context()
    |> Map.put(:transaction, nil)
    |> Context.with_permit_all()
  end

  defp get_graph_iri do
    {:ok, iri_string} = NamedGraphs.iri_string(@memory_graph)
    iri_string
  end
end
