defmodule Jidoka.Tools.QueryCodebase do
  @moduledoc """
  Jido Action for querying the codebase ontology.

  This tool provides semantic access to the codebase knowledge graph
  through a variety of query types. It wraps `Jidoka.Codebase.Queries`
  to expose codebase structure information to the LLM.

  ## Query Types

  | Query Type | Description | Required Parameters |
  |------------|-------------|---------------------|
  | `find_module` | Find a module by name | `module_name` |
  | `list_modules` | List all modules | none |
  | `find_function` | Find a specific function | `module_name`, `function_name`, `arity` |
  | `list_functions` | List functions in a module | `module_name` |
  | `analyze_function` | Analyze function with module context and call graph | `module_name`, `function_name`, `arity` |
  | `get_dependencies` | Get module dependencies | `module_name` |
  | `get_call_graph` | Get call graph for module/function | `module_name` (optional: `function_name`, `arity`) |
  | `find_protocol` | Find a protocol by name | `module_name` |
  | `list_protocols` | List all protocols | none |
  | `find_behaviour` | Find a behaviour by name | `module_name` |
  | `list_behaviours` | List all behaviours | none |
  | `find_struct` | Find a struct by module name | `module_name` |
  | `list_structs` | List all structs | none |
  | `search_by_name` | Search modules/functions by pattern | `pattern` |
  | `get_index_stats` | Get codebase statistics | none |

  ## Examples

      # Find a module
      {:ok, result, []} = QueryCodebase.run(
        %{query_type: "find_module", module_name: "MyApp.User"},
        %{}
      )

      # List functions
      {:ok, result, []} = QueryCodebase.run(
        %{query_type: "list_functions", module_name: "MyApp.User", visibility: :public},
        %{}
      )

      # Get dependencies
      {:ok, result, []} = QueryCodebase.run(
        %{query_type: "get_dependencies", module_name: "MyApp.User"},
        %{}
      )

      # Search by pattern
      {:ok, result, []} = QueryCodebase.run(
        %{query_type: "search_by_name", pattern: "user"},
        %{}
      )

  ## Notes

  - This tool requires an indexed codebase knowledge graph
  - Most queries return `{:ok, :not_found}` if the entity doesn't exist
  - Use `limit` parameter to constrain result set size
  """

  use Jido.Action,
    name: "query_codebase",
    description: "Query the codebase ontology for modules, functions, protocols, behaviours, structs, and their relationships.",
    category: "knowledge_graph",
    tags: ["codebase", "ontology", "query", "semantic"],
    vsn: "1.0.0",
    schema: [
      query_type: [
        type: :string,
        required: true,
        doc: """
        Query type: find_module, list_modules, find_function, list_functions,
        analyze_function, get_dependencies, get_call_graph, find_protocol,
        list_protocols, find_behaviour, list_behaviours, find_struct,
        list_structs, search_by_name, get_index_stats
        """
      ],
      module_name: [
        type: :string,
        required: false,
        doc: "Module name (for find_module, find_function, list_functions, etc.)"
      ],
      function_name: [
        type: :string,
        required: false,
        doc: "Function name (for find_function)"
      ],
      arity: [
        type: :integer,
        required: false,
        doc: "Function arity (for find_function, get_call_graph with function)"
      ],
      pattern: [
        type: :string,
        required: false,
        doc: "Search pattern (for search_by_name)"
      ],
      visibility: [
        type: :string,
        required: false,
        default: "all",
        doc: "Function visibility: public, private, or all (for list_functions)"
      ],
      limit: [
        type: :integer,
        required: false,
        default: 100,
        doc: "Maximum number of results"
      ],
      include_call_graph: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Include call graph in the result (for analyze_function query type)"
      ]
    ]

  alias Jidoka.Codebase.Queries

  @valid_query_types [
    "find_module",
    "list_modules",
    "find_function",
    "list_functions",
    "analyze_function",
    "get_dependencies",
    "get_call_graph",
    "find_protocol",
    "list_protocols",
    "find_behaviour",
    "list_behaviours",
    "find_struct",
    "list_structs",
    "search_by_name",
    "get_index_stats"
  ]

  @valid_visibilities [:public, :private, :all, "public", "private", "all"]

  @impl true
  def run(params, _context) do
    with {:ok, validated} <- validate_query_params(params),
         opts = [limit: Map.get(validated, :limit, 100)],
         {:ok, result} <- execute_query(validated, opts) do
      {:ok, format_result(result), []}
    else
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp validate_query_params(params) do
    with :ok <- validate_query_type(params[:query_type]),
         :ok <- validate_visibility(params[:visibility]) do
      {:ok,
       %{
         query_type: params[:query_type],
         module_name: params[:module_name],
         function_name: params[:function_name],
         arity: params[:arity],
         pattern: params[:pattern],
         visibility: parse_visibility(params[:visibility]),
         limit: params[:limit],
         include_call_graph: params[:include_call_graph] || false
       }}
    end
  end

  defp validate_query_type(type) when is_binary(type) do
    if type in @valid_query_types do
      :ok
    else
      {:error, {:invalid_query_type, type, valid_types: @valid_query_types}}
    end
  end

  defp validate_query_type(nil), do: {:error, :missing_query_type}
  defp validate_query_type(_), do: {:error, :invalid_query_type}

  defp validate_visibility(nil), do: :ok
  defp validate_visibility(vis) when vis in @valid_visibilities, do: :ok
  defp validate_visibility(_), do: {:error, :invalid_visibility}

  defp parse_visibility(nil), do: :all
  defp parse_visibility(vis) when is_atom(vis), do: vis
  defp parse_visibility("public"), do: :public
  defp parse_visibility("private"), do: :private
  defp parse_visibility("all"), do: :all

  defp execute_query(%{query_type: "find_module", module_name: name}, opts) do
    Queries.find_module(name, opts)
  end

  defp execute_query(%{query_type: "list_modules"}, opts) do
    Queries.list_modules(opts)
  end

  defp execute_query(%{query_type: "find_function", module_name: mod, function_name: fun, arity: arity}, opts) do
    Queries.find_function(mod, fun, arity || 0, opts)
  end

  defp execute_query(%{query_type: "list_functions", module_name: name, visibility: vis}, opts) do
    Queries.list_functions(name, Keyword.put(opts, :visibility, vis))
  end

  defp execute_query(%{query_type: "analyze_function", module_name: mod, function_name: fun, arity: arity, include_call_graph: include_cg}, _opts) do
    with {:ok, func_info} <- Queries.find_function(mod, fun, arity || 0),
         {:ok, module_info} <- Queries.find_module(mod) do
      result = %{
        function: %{
          name: func_info.name,
          arity: func_info.arity,
          visibility: func_info.visibility,
          documentation: func_info.documentation,
          head: func_info.head
        },
        module: %{
          name: module_info.name,
          file: module_info.file
        }
      }

      result =
        if include_cg do
          case Queries.get_call_graph({mod, fun, arity || 0}) do
            {:ok, call_graph} ->
              Map.put(result, :call_graph, call_graph)

            _ ->
              result
          end
        else
          result
        end

      {:ok, result}
    end
  end

  defp execute_query(%{query_type: "get_dependencies", module_name: name}, opts) do
    Queries.get_dependencies(name, opts)
  end

  defp execute_query(%{query_type: "get_call_graph", module_name: name, function_name: nil}, opts) do
    Queries.get_call_graph(name, opts)
  end

  defp execute_query(%{query_type: "get_call_graph", module_name: mod, function_name: fun, arity: arity}, opts) do
    Queries.get_call_graph({mod, fun, arity || 0}, opts)
  end

  defp execute_query(%{query_type: "find_protocol", module_name: name}, opts) do
    Queries.find_protocol(name, opts)
  end

  defp execute_query(%{query_type: "list_protocols"}, opts) do
    Queries.list_protocols(opts)
  end

  defp execute_query(%{query_type: "find_behaviour", module_name: name}, opts) do
    Queries.find_behaviour(name, opts)
  end

  defp execute_query(%{query_type: "list_behaviours"}, opts) do
    Queries.list_behaviours(opts)
  end

  defp execute_query(%{query_type: "find_struct", module_name: name}, opts) do
    Queries.find_struct(name, opts)
  end

  defp execute_query(%{query_type: "list_structs"}, opts) do
    Queries.list_structs(opts)
  end

  defp execute_query(%{query_type: "search_by_name", pattern: pattern}, opts) do
    Queries.search_by_name(pattern, opts)
  end

  defp execute_query(%{query_type: "get_index_stats"}, opts) do
    Queries.get_index_stats(opts)
  end

  defp execute_query(%{query_type: type}, _opts) do
    {:error, {:unknown_query_type, type}}
  end

  defp format_result(data) when is_list(data) do
    %{results: data, count: length(data)}
  end

  defp format_result(data) when is_map(data) do
    # Check if it's already a formatted result
    if Map.has_key?(data, :results) do
      data
    else
      data
    end
  end

  defp format_error({:invalid_query_type, type, opts}) do
    "Invalid query_type: #{type}. Valid types: #{Enum.join(opts[:valid_types], ", ")}"
  end

  defp format_error(:missing_query_type) do
    "Missing required parameter: query_type"
  end

  defp format_error(:invalid_visibility) do
    "Invalid visibility. Must be: public, private, or all"
  end

  defp format_error({:unknown_query_type, type}) do
    "Unknown query type: #{type}"
  end

  defp format_error({:error, reason}) when is_tuple(reason) do
    "Query failed: #{inspect(reason)}"
  end

  defp format_error(reason) when is_binary(reason) do
    reason
  end

  defp format_error(reason) do
    "Query failed: #{inspect(reason)}"
  end
end
