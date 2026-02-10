defmodule Jidoka.Memory.LongTerm.TripleStoreAdapter do
  @moduledoc """
  SPARQL-based adapter for long-term memory storage in the knowledge graph.

  The TripleStoreAdapter stores memories as RDF triples in the knowledge graph
  using the Jido ontology defined in `Jidoka.Knowledge.Ontology`. All
  operations are scoped to a specific session_id for isolation.

  ## Memory Types

  The adapter maps Elixir memory types to Jido ontology classes:

  | Elixir Type | Jido Ontology Class | IRI |
  |-------------|---------------------|-----|
  | `:fact` | `jido:Fact` | `https://jido.ai/ontologies/core#Fact` |
  | `:decision` | `jido:Decision` | `https://jido.ai/ontologies/core#Decision` |
  | `:lesson_learned` | `jido:LessonLearned` | `https://jido.ai/ontologies/core#LessonLearned` |

  Note: `:analysis` maps to `jido:Decision` (analysis represents decision-making).
  `:conversation` and `:file_context` are not stored (they have their own graphs).

  ## Memory Triple Structure

  Each memory is stored as a set of triples:

  ```turtle
  <https://jido.ai/memories#session-123_mem-456> a jido:Fact ;
      jido:sessionId "session-123" ;
      jido:content "Named graphs segregate triples" ;
      jido:confidence "0.9"^^xsd:decimal ;
      jido:timestamp "2025-01-26T12:00:00Z"^^xsd:dateTime ;
      jido:sourceSession <https://jido.ai/sessions#session-123> .
  ```

  ## WorkSession Linking

  Each memory is linked to a WorkSession individual for provenance:

  ```turtle
  <https://jido.ai/sessions#session-123> a jido:WorkSession ;
      jido:sessionId "session-123" ;
      prov:startedAtTime "2025-01-26T12:00:00Z"^^xsd:dateTime .
  ```

  ## Examples

      {:ok, adapter} = TripleStoreAdapter.new("session-123")

      {:ok, memory} = TripleStoreAdapter.persist_memory(adapter, %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8
      })

      {:ok, memories} = TripleStoreAdapter.query_memories(adapter)

      {:ok, memories} = TripleStoreAdapter.query_memories(adapter,
        type: :fact,
        min_importance: 0.7
      )

  """

  alias Jidoka.Knowledge.{Engine, Context, Ontology, NamedGraphs}
  alias Jidoka.Memory.Validation
  alias RDF.IRI
  alias TripleStore.SPARQL.Query
  import TripleStore, only: [update: 2]

  # Default engine name
  @default_engine :knowledge_engine

  # Graph where memories are stored
  @memory_graph :long_term_context

  # Jido namespace IRIs
  @jido_namespace "https://jido.ai/ontologies/core#"
  @memory_namespace "https://jido.ai/memories#"
  @session_namespace "https://jido.ai/sessions#"

  # Property IRIs
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @jido_session_id "#{@jido_namespace}sessionId"
  @jido_content "#{@jido_namespace}content"
  @jido_confidence "#{@jido_namespace}confidence"
  @jido_timestamp "#{@jido_namespace}timestamp"
  @jido_source_session "#{@jido_namespace}sourceSession"
  @prov_started_at_time "http://www.w3.org/ns/prov#startedAtTime"

  # ========================================================================
  # Type Definitions
  # ========================================================================

  defstruct [:session_id, :engine_name, :graph_name]

  @type t :: %__MODULE__{
          session_id: String.t(),
          engine_name: atom(),
          graph_name: atom()
        }

  # ========================================================================
  # Public API - Constructor
  # ========================================================================

  @doc """
  Creates a new TripleStoreAdapter for the given session_id.

  ## Parameters

  - `session_id` - The session identifier
  - `opts` - Keyword options:
    - `:engine_name` - Name of the knowledge engine (default: `:knowledge_engine`)
    - `:graph_name` - Name of the graph for memories (default: `:long_term_context`)

  ## Returns

  - `{:ok, adapter}` - Adapter created successfully
  - `{:error, reason}` - Creation failed

  ## Examples

      {:ok, adapter} = TripleStoreAdapter.new("session_123")

      {:ok, adapter} = TripleStoreAdapter.new("session_123",
        engine_name: :custom_engine,
        graph_name: :long_term_context
      )

  """
  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(session_id, opts \\ [])
  def new(session_id, _opts) when not is_binary(session_id) do
    {:error, :invalid_session_id}
  end

  def new(session_id, opts) when is_binary(session_id) do
    with :ok <- Validation.validate_session_id(session_id) do
      default_engine =
        Application.get_env(:jidoka, :knowledge_engine_name, @default_engine)

      adapter = %__MODULE__{
        session_id: session_id,
        engine_name: Keyword.get(opts, :engine_name, default_engine),
        graph_name: Keyword.get(opts, :graph_name, @memory_graph)
      }

      {:ok, adapter}
    end
  end

  @doc """
  Creates a new TripleStoreAdapter, raising on error.

  ## Examples

      adapter = TripleStoreAdapter.new!("session_123")

  """
  @spec new!(String.t(), keyword()) :: t()
  def new!(session_id, opts \\ []) when is_binary(session_id) do
    case new(session_id, opts) do
      {:ok, adapter} -> adapter
      {:error, reason} -> raise ArgumentError, "Failed to create adapter: #{inspect(reason)}"
    end
  end

  # ========================================================================
  # Public API - CRUD Operations
  # ========================================================================

  @doc """
  Persists a memory item to the knowledge graph.

  Creates RDF triples from the memory item and inserts them into the
  long-term-context named graph. Also creates a WorkSession individual
  if it doesn't exist.

  ## Parameters

  - `adapter` - The TripleStoreAdapter struct
  - `item` - Map with at least `:id`, `:type`, `:data`, `:importance`

  ## Returns

  - `{:ok, memory}` - Memory persisted with added fields
  - `{:error, reason}` - Persistence failed

  ## Examples

      {:ok, memory} = TripleStoreAdapter.persist_memory(adapter, %{
        id: "mem_1",
        type: :fact,
        data: %{key: "value"},
        importance: 0.8
      })

  """
  @spec persist_memory(t(), map()) :: {:ok, map()} | {:error, term()}
  def persist_memory(%__MODULE__{} = adapter, item) when is_map(item) do
    with :ok <- Validation.validate_required_fields(item),
         :ok <- Validation.validate_memory_size(Map.get(item, :data, %{})),
         :ok <- Validation.validate_importance(Map.get(item, :importance)),
         :ok <- validate_memory_type(Map.get(item, :type)),
         :ok <- ensure_work_session(adapter),
         now <- DateTime.utc_now(),
         memory = build_memory_map(adapter, item, now),
         {:ok, triples} <- memory_to_triples(memory),
         {:ok, _count} <- insert_triples(adapter, triples) do
      {:ok, memory}
    end
  end

  @doc """
  Queries memories from the knowledge graph with optional filters.

  ## Parameters

  - `adapter` - The TripleStoreAdapter struct
  - `opts` - Keyword list of filters:
    - `:type` - Filter by memory type (`:fact`, `:decision`, `:lesson_learned`)
    - `:min_importance` - Minimum importance (confidence) score
    - `:limit` - Maximum number of results

  ## Returns

  - `{:ok, memories}` - List of memory items (may be empty)
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, all} = TripleStoreAdapter.query_memories(adapter)

      {:ok, facts} = TripleStoreAdapter.query_memories(adapter, type: :fact)

      {:ok, important} = TripleStoreAdapter.query_memories(adapter,
        min_importance: 0.7,
        limit: 10
      )

  """
  @spec query_memories(t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def query_memories(%__MODULE__{} = adapter, opts \\ []) do
    ctx = engine_context(adapter)

    query = build_select_query(adapter.session_id, opts)

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        memories = triples_to_memories(results)
        {:ok, memories}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Retrieves a single memory by ID.

  ## Parameters

  - `adapter` - The TripleStoreAdapter struct
  - `memory_id` - The memory ID to retrieve

  ## Returns

  - `{:ok, memory}` - Memory found
  - `{:error, :not_found}` - Memory not found
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, memory} = TripleStoreAdapter.get_memory(adapter, "mem_1")
      {:error, :not_found} = TripleStoreAdapter.get_memory(adapter, "nonexistent")

  """
  @spec get_memory(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_memory(%__MODULE__{} = adapter, memory_id) when is_binary(memory_id) do
    ctx = engine_context(adapter)
    memory_iri = generate_memory_iri(adapter.session_id, memory_id)

    query = """
    PREFIX jido: <#{@jido_namespace}>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

    SELECT ?p ?o WHERE {
      GRAPH <#{graph_iri(adapter)}> {
        <#{memory_iri}> ?p ?o .
      }
    }
    """

    case Query.query(ctx, query, []) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, triples} when is_list(triples) ->
        memory = triples_to_memory(triples, adapter.session_id, memory_id)
        {:ok, memory}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates an existing memory in the knowledge graph.

  Only updates the fields provided; maintains id, session_id, and created_at.
  Updates the timestamp automatically.

  ## Parameters

  - `adapter` - The TripleStoreAdapter struct
  - `memory_id` - The ID of the memory to update
  - `updates` - Map of fields to update

  ## Returns

  - `{:ok, updated_memory}` - Memory updated
  - `{:error, :not_found}` - Memory not found
  - `{:error, reason}` - Update failed

  ## Examples

      {:ok, updated} = TripleStoreAdapter.update_memory(adapter, "mem_1", %{
        importance: 0.9,
        data: %{new: "data"}
      })

  """
  @spec update_memory(t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_memory(%__MODULE__{} = adapter, memory_id, updates) when is_map(updates) do
    with {:ok, existing} <- get_memory(adapter, memory_id),
         :ok <- validate_updates(updates),
         updated = merge_updates(existing, updates),
         {:ok, _} <- delete_memory_triples(adapter, memory_id),
         {:ok, triples} <- memory_to_triples(updated),
         {:ok, _count} <- insert_triples(adapter, triples) do
      {:ok, updated}
    end
  end

  @doc """
  Deletes a memory from the knowledge graph.

  ## Parameters

  - `adapter` - The TripleStoreAdapter struct
  - `memory_id` - The ID of the memory to delete

  ## Returns

  - `{:ok, :deleted}` - Memory deleted
  - `{:error, :not_found}` - Memory not found
  - `{:error, reason}` - Deletion failed

  ## Examples

      {:ok, :deleted} = TripleStoreAdapter.delete_memory(adapter, "mem_1")

  """
  @spec delete_memory(t(), String.t()) :: {:ok, :deleted} | {:error, term()}
  def delete_memory(%__MODULE__{} = adapter, memory_id) when is_binary(memory_id) do
    with {:ok, _} <- get_memory(adapter, memory_id),
         {:ok, :deleted} <- delete_memory_triples(adapter, memory_id) do
      {:ok, :deleted}
    end
  end

  # ========================================================================
  # Public API - Session Operations
  # ========================================================================

  @doc """
  Returns the count of memories for this session.

  ## Examples

      count = TripleStoreAdapter.count(adapter)

  """
  @spec count(t()) :: non_neg_integer() | {:error, term()}
  def count(%__MODULE__{} = adapter) do
    ctx = engine_context(adapter)

    query = """
    PREFIX jido: <#{@jido_namespace}>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

    SELECT (COUNT(?s) AS ?count) WHERE {
      GRAPH <#{graph_iri(adapter)}> {
        ?s rdf:type ?type ;
           jido:sessionId "#{adapter.session_id}" .
        FILTER (?type != jido:WorkSession)
      }
    }
    """

    case Query.query(ctx, query, []) do
      {:ok, [%{"count" => count}]} when is_integer(count) ->
        count

      {:ok, [%{"count" => {:literal, count}}]} when is_binary(count) ->
        case Integer.parse(count) do
          {val, _} -> val
          :error -> 0
        end

      {:ok, [%{"count" => {:literal, :typed, count, _datatype}}]} when is_binary(count) ->
        case Integer.parse(count) do
          {val, _} -> val
          :error -> 0
        end

      {:ok, [%{"count" => {:literal, _, count}}]} when is_binary(count) ->
        case Integer.parse(count) do
          {val, _} -> val
          :error -> 0
        end

      {:ok, [%{"count" => count}]} when is_binary(count) ->
        case Integer.parse(count) do
          {val, _} -> val
          :error -> 0
        end

      _ ->
        0
    end
  end

  @doc """
  Clears all memories for this session from the knowledge graph.

  ## Examples

      {:ok, :cleared} = TripleStoreAdapter.clear(adapter)

  """
  @spec clear(t()) :: {:ok, :cleared} | {:error, term()}
  def clear(%__MODULE__{} = adapter) do
    ctx = engine_context(adapter)

    # First, find all subjects with this session_id
    query = """
    PREFIX jido: <#{@jido_namespace}>

    SELECT DISTINCT ?s WHERE {
      GRAPH <#{graph_iri(adapter)}> {
        ?s jido:sessionId "#{adapter.session_id}" .
      }
    }
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        # Extract subject IRIs from results
        subjects =
          Enum.flat_map(results, fn
            %{"s" => {:named_node, iri}} -> [iri]
            %{"s" => {:iri, iri}} -> [iri]
            %{"s" => iri} when is_binary(iri) -> [iri]
            _ -> []
          end)

        # Delete all triples for each subject using DELETE WHERE
        Enum.each(subjects, fn subject_iri ->
          delete_query = """
          DELETE {
            GRAPH <#{graph_iri(adapter)}> {
              <#{subject_iri}> ?p ?o .
            }
          }
          WHERE {
            GRAPH <#{graph_iri(adapter)}> {
              <#{subject_iri}> ?p ?o .
            }
          }
          """

          # Ignore errors for individual deletes
          update(ctx, delete_query)
        end)

        {:ok, :cleared}

      _ ->
        {:error, :query_failed}
    end
  end

  @doc """
  Returns the session_id for this adapter.

  ## Examples

      "session_123" = TripleStoreAdapter.session_id(adapter)

  """
  @spec session_id(t()) :: String.t()
  def session_id(%__MODULE__{session_id: session_id}), do: session_id

  # ========================================================================
  # Private Helpers - Triple Conversion
  # ========================================================================

  # Builds the memory map with timestamps and metadata
  defp build_memory_map(adapter, item, now) do
    base_type = Map.get(item, :type)

    # Map to Jido ontology types
    jido_type = map_to_jido_type(base_type)

    item
    |> Map.put(:session_id, adapter.session_id)
    |> Map.put(:created_at, now)
    |> Map.put(:updated_at, now)
    |> Map.put(:jido_type, jido_type)
  end

  # Maps Elixir types to Jido ontology types
  defp map_to_jido_type(:fact), do: :fact
  defp map_to_jido_type(:decision), do: :decision
  defp map_to_jido_type(:lesson_learned), do: :lesson_learned
  # analysis maps to Decision
  defp map_to_jido_type(:analysis), do: :decision
  # default fallback
  defp map_to_jido_type(_), do: :fact

  # Validates memory type is supported
  defp validate_memory_type(type) when type in [:fact, :decision, :lesson_learned, :analysis],
    do: :ok

  defp validate_memory_type(type), do: {:error, {:invalid_type, type}}

  # Validates update fields
  defp validate_updates(updates) when is_map(updates) do
    # Check that only valid fields are being updated
    valid_keys = [:data, :importance, :type]
    invalid_keys = Map.keys(updates) -- valid_keys

    if invalid_keys == [] do
      :ok
    else
      {:error, {:invalid_update_fields, invalid_keys}}
    end
  end

  # Merges updates into existing memory
  defp merge_updates(existing, updates) do
    existing
    |> Map.merge(updates)
    |> Map.put(:updated_at, DateTime.utc_now())
    |> maybe_update_jido_type(updates)
  end

  defp maybe_update_jido_type(memory, %{type: new_type}) do
    jido_type = map_to_jido_type(new_type)
    Map.put(memory, :jido_type, jido_type)
  end

  defp maybe_update_jido_type(memory, _), do: memory

  # Converts memory map to RDF triples
  defp memory_to_triples(memory) do
    with {:ok, type_iri} <- Ontology.get_class_iri(memory.jido_type) do
      memory_iri = generate_memory_iri(memory.session_id, memory.id)
      session_iri = generate_session_iri(memory.session_id)
      timestamp = datetime_to_xsd_string(memory.updated_at)
      confidence = Map.get(memory, :importance, 0.5)

      # Serialize data to JSON for content
      content = Jason.encode!(Map.get(memory, :data, %{}))

      triples = [
        # Type assertion
        {memory_iri, @rdf_type, type_iri},
        # Session ID
        {memory_iri, @jido_session_id, memory.session_id},
        # Content (serialized data)
        {memory_iri, @jido_content, content},
        # Confidence (importance)
        {memory_iri, @jido_confidence, to_string(confidence)},
        # Timestamp
        {memory_iri, @jido_timestamp, timestamp},
        # Source session link
        {memory_iri, @jido_source_session, session_iri}
      ]

      {:ok, triples}
    else
      {:error, _} = error -> error
    end
  end

  # Converts SPARQL results to memory maps
  defp triples_to_memories(results) when is_list(results) do
    # Group triples by subject (memory IRI)
    results
    |> Enum.group_by(fn
      %{"s" => {:named_node, iri}} -> iri
      %{"s" => {:iri, iri}} -> iri
      %{"s" => iri_string} when is_binary(iri_string) -> iri_string
    end)
    |> Enum.map(fn {_subject, triples} -> triples_to_memory(triples) end)
    |> Enum.filter(& &1)
  end

  # Converts a group of triples to a single memory map
  defp triples_to_memory(triples, session_id \\ nil, memory_id \\ nil) do
    # Extract properties from triples
    type = extract_type(triples)
    extracted_id = extract_memory_id(triples) || memory_id
    extracted_session = extract_session_id(triples) || session_id
    content = extract_content(triples)
    confidence = extract_confidence(triples)
    timestamp = extract_timestamp(triples)

    # Parse content JSON back to data map
    data = parse_content(content)

    %{
      id: extracted_id,
      session_id: extracted_session,
      type: type,
      jido_type: type,
      data: data,
      importance: confidence,
      created_at: timestamp,
      updated_at: timestamp
    }
  end

  defp extract_type(triples) do
    Enum.find_value(triples, fn
      %{"p" => {:iri, @rdf_type}, "o" => {:iri, type_iri}} ->
        iri_to_type(type_iri)

      %{"p" => @rdf_type, "o" => {:iri, type_iri}} ->
        iri_to_type(type_iri)

      %{"type" => {:named_node, type_iri}} ->
        iri_to_type(type_iri)

      %{"type" => {:iri, type_iri}} ->
        iri_to_type(type_iri)

      _ ->
        nil
    end) || :fact
  end

  defp iri_to_type("https://jido.ai/ontologies/core#Fact"), do: :fact
  defp iri_to_type("https://jido.ai/ontologies/core#Decision"), do: :decision
  defp iri_to_type("https://jido.ai/ontologies/core#LessonLearned"), do: :lesson_learned
  defp iri_to_type(_), do: :fact

  defp extract_memory_id(triples) do
    # First try to get the session_id to properly extract memory_id
    session_id = extract_session_id(triples)

    Enum.find_value(triples, fn
      %{"s" => {:iri, s}} -> extract_id_from_iri(s, session_id)
      %{"s" => {:named_node, s}} -> extract_id_from_iri(s, session_id)
      %{"s" => s} when is_binary(s) -> extract_id_from_iri(s, session_id)
      _ -> nil
    end)
  end

  # Extracts memory ID from IRI by removing the session_id prefix
  # Format: https://jido.ai/memories#{session_id}_#{memory_id}
  defp extract_id_from_iri(iri, session_id) when is_binary(session_id) and session_id != "" do
    # Get the fragment part after #
    fragment =
      case String.split(iri, "#") do
        [_prefix, frag] -> frag
        [frag] -> frag
      end

    # Remove session_id prefix (and the underscore separator) to get memory_id
    # fragment format: {session_id}_{memory_id}
    fragment
    |> String.replace_prefix(session_id <> "_", "")
    # Fallback in case there's no underscore
    |> String.replace_prefix(session_id, "")
  end

  defp extract_id_from_iri(iri, _session_id) do
    # Fallback: try to extract by taking the part after the last underscore
    # This works for simple cases where session_id doesn't end with a number
    fragment =
      case String.split(iri, "#") do
        [_prefix, frag] -> frag
        [frag] -> frag
      end

    # Get everything after the last underscore
    case String.split(fragment, "_") |> Enum.reverse() do
      [id | _rest] -> id
      _ -> fragment
    end
  end

  defp extract_session_id(triples) do
    Enum.find_value(triples, fn
      %{"p" => @jido_session_id, "o" => session_id} when is_binary(session_id) ->
        session_id

      %{"p" => {:iri, @jido_session_id}, "o" => {:literal, session_id}} ->
        session_id

      %{"session_id" => {:literal, _, session_id}} ->
        # SPARQL SELECT format with session_id as column
        session_id

      %{"session_id" => session_id} when is_binary(session_id) ->
        # SPARQL SELECT format with session_id as column (string)
        session_id

      %{"o" => session_id} when is_binary(session_id) ->
        # SPARQL SELECT format with session_id as column
        session_id

      %{"o" => {:literal, _, session_id}} ->
        # SPARQL SELECT format with typed literal
        session_id

      _ ->
        nil
    end)
  end

  defp extract_content(triples) do
    Enum.find_value(triples, fn
      %{"p" => @jido_content, "o" => content} when is_binary(content) -> content
      %{"p" => {:iri, @jido_content}, "o" => {:literal, content}} -> content
      %{"p" => {:named_node, @jido_content}, "o" => {:literal, _, content}} -> content
      %{"p" => {:iri, @jido_content}, "o" => {:literal, _, content}} -> content
      %{"content" => {:literal, _, content}} -> content
      %{"content" => content} when is_binary(content) -> content
      _ -> nil
    end)
  end

  defp extract_confidence(triples) do
    jido_confidence = @jido_confidence

    result =
      Enum.find_value(triples, fn
        %{"p" => @jido_confidence, "o" => confidence} when is_binary(confidence) ->
          case Float.parse(confidence) do
            {val, _} -> val
            :error -> 0.5
          end

        %{"p" => {:iri, @jido_confidence}, "o" => {:literal, confidence}} ->
          case Float.parse(confidence) do
            {val, _} -> val
            :error -> 0.5
          end

        %{"p" => {:named_node, @jido_confidence}, "o" => {:literal, :simple, confidence}} ->
          case Float.parse(confidence) do
            {val, _} -> val
            :error -> 0.5
          end

        %{"p" => {:named_node, @jido_confidence}, "o" => {:literal, confidence}} ->
          case Float.parse(confidence) do
            {val, _} -> val
            :error -> 0.5
          end

        %{"p" => {:named_node, @jido_confidence}, "o" => confidence} when is_binary(confidence) ->
          case Float.parse(confidence) do
            {val, _} -> val
            :error -> 0.5
          end

        %{"confidence" => {:literal, _, confidence_str}} ->
          case Float.parse(confidence_str) do
            {val, _} -> val
            :error -> 0.5
          end

        %{"confidence" => confidence} when is_binary(confidence) ->
          case Float.parse(confidence) do
            {val, _} -> val
            :error -> 0.5
          end

        _ ->
          nil
      end)

    result || 0.5
  end

  defp extract_timestamp(triples) do
    Enum.find_value(triples, fn
      %{"p" => @jido_timestamp, "o" => timestamp} when is_binary(timestamp) ->
        parse_xsd_datetime(timestamp)

      %{"p" => {:iri, @jido_timestamp}, "o" => {:literal, timestamp}} ->
        parse_xsd_datetime(timestamp)

      %{"timestamp" => {:literal, _, timestamp}} ->
        parse_xsd_datetime(timestamp)

      %{"timestamp" => timestamp} when is_binary(timestamp) ->
        parse_xsd_datetime(timestamp)

      _ ->
        DateTime.utc_now()
    end)
  end

  defp parse_content(nil), do: %{}

  defp parse_content(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end

  defp parse_content(_), do: %{}

  defp parse_xsd_datetime(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp datetime_to_xsd_string(%DateTime{} = dt) do
    DateTime.to_iso8601(dt, :extended)
  end

  # ========================================================================
  # Private Helpers - Query Building
  # ========================================================================

  defp build_select_query(session_id, opts) do
    type_filter = build_type_filter(opts)
    confidence_filter = build_confidence_filter(opts)
    limit_clause = build_limit_clause(opts)

    graph_iri = get_graph_iri_string()

    """
    PREFIX jido: <#{@jido_namespace}>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

    SELECT ?s ?type ?content ?confidence ?timestamp ?session_id WHERE {
      GRAPH <#{graph_iri}> {
        ?s rdf:type ?type ;
           jido:sessionId ?session_id ;
           jido:content ?content ;
           jido:confidence ?confidence ;
           jido:timestamp ?timestamp .
        FILTER(?session_id = "#{session_id}")
        #{type_filter}
        #{confidence_filter}
      }
    }
    ORDER BY DESC(?timestamp)
    #{limit_clause}
    """
    |> String.trim()
  end

  defp build_type_filter(opts) do
    case Keyword.get(opts, :type) do
      nil ->
        ""

      type when type in [:fact, :decision, :lesson_learned] ->
        type_iri = get_type_iri(type)
        "FILTER(?type = <#{type_iri}>)"

      _ ->
        ""
    end
  end

  defp get_type_iri(:fact), do: "#{@jido_namespace}Fact"
  defp get_type_iri(:decision), do: "#{@jido_namespace}Decision"
  defp get_type_iri(:lesson_learned), do: "#{@jido_namespace}LessonLearned"

  defp build_confidence_filter(opts) do
    case Keyword.get(opts, :min_importance) do
      nil ->
        ""

      min when is_number(min) ->
        "FILTER(?confidence >= #{min})"

      _ ->
        ""
    end
  end

  defp build_limit_clause(opts) do
    case Keyword.get(opts, :limit) do
      nil ->
        ""

      limit when is_integer(limit) and limit > 0 ->
        "LIMIT #{limit}"

      _ ->
        ""
    end
  end

  # ========================================================================
  # Private Helpers - IRI Generation
  # ========================================================================

  defp generate_memory_iri(session_id, memory_id) do
    @memory_namespace <> "#{session_id}_#{memory_id}"
  end

  defp generate_session_iri(session_id) do
    @session_namespace <> session_id
  end

  # ========================================================================
  # Private Helpers - Session Management
  # ========================================================================

  # Ensures a WorkSession individual exists for the session
  defp ensure_work_session(%__MODULE__{} = adapter) do
    ctx = engine_context(adapter)
    session_id = adapter.session_id
    session_iri = generate_session_iri(session_id)
    now = DateTime.to_iso8601(DateTime.utc_now(), :extended)
    graph_iri = get_graph_iri_string()

    # Use INSERT DATA to create the WorkSession
    # This is idempotent - if it exists, the insert will be ignored
    update = """
    PREFIX jido: <#{@jido_namespace}>
    PREFIX prov: <http://www.w3.org/ns/prov#>

    INSERT DATA {
      GRAPH <#{graph_iri}> {
        <#{session_iri}> a jido:WorkSession ;
            jido:sessionId "#{session_id}" ;
            prov:startedAtTime "#{now}"^^<http://www.w3.org/2001/XMLSchema#dateTime> .
      }
    }
    """

    # Try to insert, ignore errors if it already exists
    case update(ctx, update) do
      {:ok, _count} -> :ok
      # If already exists or other error, still return :ok
      _ -> :ok
    end
  end

  # ========================================================================
  # Private Helpers - Triple Operations
  # ========================================================================

  defp insert_triples(adapter, triples) do
    ctx = engine_context(adapter)
    graph_iri_str = graph_iri_string(adapter)

    # Convert triples to INSERT DATA format
    triple_strings =
      Enum.map(triples, fn {s, p, o} ->
        object = format_object(o)
        "  <#{s}> <#{p}> #{object} ."
      end)
      |> Enum.join("\n")

    update = """
    INSERT DATA {
      GRAPH <#{graph_iri_str}> {
        #{triple_strings}
      }
    }
    """

    update(ctx, update)
  end

  defp delete_memory_triples(adapter, memory_id) do
    ctx = engine_context(adapter)
    memory_iri = generate_memory_iri(adapter.session_id, memory_id)

    update = """
    DELETE {
      GRAPH <#{graph_iri_string(adapter)}> {
        <#{memory_iri}> ?p ?o .
      }
    }
    WHERE {
      GRAPH <#{graph_iri_string(adapter)}> {
        <#{memory_iri}> ?p ?o .
      }
    }
    """

    case update(ctx, update) do
      {:ok, _count} -> {:ok, :deleted}
      {:error, _} = error -> error
    end
  end

  defp format_object(value) when is_binary(value) do
    # Check if it's an IRI (starts with http:// or https://)
    if String.starts_with?(value, ["http://", "https://"]) do
      "<#{value}>"
    else
      # Escape and quote as literal
      escaped = String.replace(value, "\"", "\\\"")
      "\"#{escaped}\""
    end
  end

  defp format_object(value) when is_number(value) do
    to_string(value)
  end

  defp format_object(value) when is_boolean(value) do
    if value, do: "true", else: "false"
  end

  # ========================================================================
  # Private Helpers - Context and Graph
  # ========================================================================

  defp engine_context(%__MODULE__{engine_name: name}) do
    name
    |> Engine.context()
    |> Map.put(:transaction, nil)
    |> Context.with_permit_all()
  end

  defp default_context do
    Engine.context(@default_engine)
  end

  defp graph_iri(%__MODULE__{} = adapter) do
    {:ok, iri} = NamedGraphs.iri(adapter.graph_name)
    iri
  end

  defp graph_iri_string(%__MODULE__{} = adapter) do
    {:ok, iri_string} = NamedGraphs.iri_string(adapter.graph_name)
    iri_string
  end

  defp get_graph_iri_string do
    {:ok, iri_string} = NamedGraphs.iri_string(@memory_graph)
    iri_string
  end
end
