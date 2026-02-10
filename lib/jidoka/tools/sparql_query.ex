defmodule Jidoka.Tools.SparqlQuery do
  @moduledoc """
  Jido Action for executing read-only SPARQL queries against the codebase ontology.

  This tool provides direct SPARQL access to the codebase knowledge graph
  with safety enforcement for read-only queries.

  ## Security

  Only SELECT and ASK query types are allowed. All other query types
  (INSERT, DELETE, UPDATE, CONSTRUCT, DESCRIBE) are rejected.

  ## Query Enforcement

  - SELECT queries are automatically limited if no LIMIT clause is present
  - ASK queries are allowed (boolean results only)
  - Query timeout is enforced by TripleStore.SPARQL.Query

  ## Examples

      # Simple SELECT query
      {:ok, result, []} = SparqlQuery.run(
        %{
          query: "SELECT ?module ?name WHERE ?module a struct:Module . ?module struct:moduleName ?name . LIMIT 10"
        },
        %{}
      )

      # ASK query
      {:ok, result, []} = SparqlQuery.run(
        %{
          query: "ASK WHERE ?module a struct:Module . ?module struct:moduleName 'MyApp.User'"
        },
        %{}
      )

  ## Notes

  - Results are formatted with type information (IRI, literal, etc.)
  - Query is executed in read-only mode (no transaction)
  - Default limit of 100 is applied if not specified
  """

  use Jido.Action,
    name: "sparql_query",
    description: "Execute read-only SPARQL queries against the codebase ontology graph. Supports SELECT and ASK queries only.",
    category: "knowledge_graph",
    tags: ["sparql", "ontology", "query", "read_only"],
    vsn: "1.0.0",
    schema: [
      query: [
        type: :string,
        required: true,
        doc: "SPARQL SELECT or ASK query (no modifications allowed)"
      ],
      limit: [
        type: :integer,
        required: false,
        default: 100,
        doc: "Maximum number of results (enforced if not in query)"
      ]
    ]

  alias TripleStore.SPARQL.Query
  alias Jidoka.Knowledge.{Engine, Context}

  @allowed_query_types ["SELECT", "ASK"]
  @default_limit 100

  @impl true
  def run(%{query: query} = params, _context) do
    limit = Map.get(params, :limit, @default_limit)
    normalized = normalize_query(query)

    with :ok <- validate_query_type(normalized),
         final_query = ensure_limit(query, limit),
         ctx = get_query_context(),
         {:ok, result} <- execute_query(final_query, ctx) do
      {:ok, format_result(result), []}
    else
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp normalize_query(query) when is_binary(query) do
    query
    |> String.trim()
    |> String.upcase()
  end

  defp validate_query_type(normalized_query) do
    cond do
      Enum.any?(@allowed_query_types, &String.starts_with?(normalized_query, &1)) ->
        :ok

      String.starts_with?(normalized_query, "INSERT") ->
        {:error, :insert_not_allowed}

      String.starts_with?(normalized_query, "DELETE") ->
        {:error, :delete_not_allowed}

      String.starts_with?(normalized_query, "UPDATE") ->
        {:error, :update_not_allowed}

      String.starts_with?(normalized_query, "CONSTRUCT") ->
        {:error, :construct_not_allowed}

      String.starts_with?(normalized_query, "DESCRIBE") ->
        {:error, :describe_not_allowed}

      String.starts_with?(normalized_query, "LOAD") ->
        {:error, :load_not_allowed}

      String.starts_with?(normalized_query, "CLEAR") ->
        {:error, :clear_not_allowed}

      String.starts_with?(normalized_query, "DROP") ->
        {:error, :drop_not_allowed}

      String.starts_with?(normalized_query, "CREATE") ->
        {:error, :create_not_allowed}

      String.starts_with?(normalized_query, "COPY") ->
        {:error, :copy_not_allowed}

      String.starts_with?(normalized_query, "MOVE") ->
        {:error, :move_not_allowed}

      String.starts_with?(normalized_query, "ADD") ->
        {:error, :add_not_allowed}

      true ->
        {:error, :unknown_query_type}
    end
  end

  defp get_query_context do
    engine_name = Application.get_env(:jidoka, :knowledge_engine_name, :knowledge_engine)

    engine_name
    |> Engine.context()
    |> Map.put(:transaction, nil)
    |> Context.with_permit_all()
  end

  defp ensure_limit(query, default_limit) do
    # Check if LIMIT is already in the query (case-insensitive)
    query_upper = String.upcase(query)

    if String.contains?(query_upper, "LIMIT") do
      query
    else
      # Add LIMIT to prevent runaway queries
      query <> "\nLIMIT #{default_limit}"
    end
  end

  defp execute_query(query, ctx) do
    Query.query(ctx, query, [])
  end

  defp format_result(results) when is_list(results) do
    formatted = Enum.map(results, &format_row/1)
    %{
      results: formatted,
      count: length(formatted)
    }
  end

  defp format_result(result) when is_boolean(result) do
    %{
      result: result,
      type: "boolean"
    }
  end

  defp format_row(row) when is_map(row) do
    Map.new(row, fn {key, value} -> {key, format_value(value)} end)
  end

  defp format_value({:iri, iri}) when is_binary(iri) do
    %{type: "iri", value: iri}
  end

  defp format_value({:named_node, iri}) when is_binary(iri) do
    %{type: "iri", value: iri}
  end

  defp format_value({:literal, val}) when is_binary(val) do
    %{type: "literal", value: val}
  end

  defp format_value({:literal, :simple, val}) when is_binary(val) do
    %{type: "literal", value: val}
  end

  defp format_value({:literal, :typed, val, type}) when is_binary(val) and is_binary(type) do
    %{type: "literal", value: val, datatype: type}
  end

  defp format_value({:literal, :lang, val, lang}) when is_binary(val) and is_binary(lang) do
    %{type: "literal", value: val, language: lang}
  end

  defp format_value(nil) do
    nil
  end

  defp format_value(val) when is_binary(val) do
    val
  end

  defp format_value(val) when is_number(val) do
    val
  end

  defp format_value(val) when is_boolean(val) do
    val
  end

  defp format_value(val) do
    %{type: "unknown", value: inspect(val)}
  end

  defp format_error(:insert_not_allowed) do
    "INSERT queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:delete_not_allowed) do
    "DELETE queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:update_not_allowed) do
    "UPDATE queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:construct_not_allowed) do
    "CONSTRUCT queries are not currently supported. Use SELECT instead."
  end

  defp format_error(:describe_not_allowed) do
    "DESCRIBE queries are not currently supported. Use SELECT instead."
  end

  defp format_error(:load_not_allowed) do
    "LOAD queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:clear_not_allowed) do
    "CLEAR queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:drop_not_allowed) do
    "DROP queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:create_not_allowed) do
    "CREATE queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:copy_not_allowed) do
    "COPY queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:move_not_allowed) do
    "MOVE queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:add_not_allowed) do
    "ADD queries are not allowed. Only SELECT and ASK queries are permitted."
  end

  defp format_error(:unknown_query_type) do
    "Unknown query type. Only SELECT and ASK queries are permitted."
  end

  defp format_error({:error, reason}) when is_tuple(reason) do
    "Query execution failed: #{inspect(reason)}"
  end

  defp format_error(reason) when is_binary(reason) do
    reason
  end

  defp format_error(reason) do
    "Query execution failed: #{inspect(reason)}"
  end
end
