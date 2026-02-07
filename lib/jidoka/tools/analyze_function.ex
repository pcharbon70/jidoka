defmodule Jidoka.Tools.AnalyzeFunction do
  @moduledoc """
  Jido Action for analyzing functions from the knowledge graph.

  This tool queries the indexed codebase knowledge graph to retrieve
  detailed information about functions including signature, documentation,
  module context, and related code.

  ## Parameters

  * `:module` - Module name (required)
  * `:function` - Function name (required)
  * `:arity` - Function arity (required)
  * `:include_call_graph` - Include functions called by this function (optional)

  ## Examples

      {:ok, function_info} = AnalyzeFunction.run(
        %{module: "Jidoka.Client", function: "create_session", arity: 1},
        %{}
      )

  """

  use Jido.Action,
    name: "analyze_function",
    description: "Get detailed information about a function from the codebase",
    category: "analysis",
    tags: ["function", "knowledge-graph", "analysis"],
    vsn: "1.0.0",
    schema: [
      module: [
        type: :string,
        required: true,
        doc: "Module name containing the function"
      ],
      function: [
        type: :string,
        required: true,
        doc: "Function name"
      ],
      arity: [
        type: :integer,
        required: true,
        doc: "Function arity (number of parameters)"
      ],
      include_call_graph: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Include functions called by this function"
      ]
    ]

  alias Jidoka.Codebase.Queries

  @impl true
  def run(params, _context) do
    module = params[:module]
    function = params[:function]
    arity = params[:arity]
    include_call_graph = params[:include_call_graph] || false

    with {:ok, func_info} <- Queries.find_function(module, function, arity),
         {:ok, module_info} <- Queries.find_module(module) do
      # Build result with function and module context
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

      # Optionally include call graph
      result =
        if include_call_graph do
          case Queries.get_call_graph({module, function, arity}) do
            {:ok, call_graph} ->
              Map.put(result, :call_graph, call_graph)

            _ ->
              result
          end
        else
          result
        end

      {:ok, result, []}
    else
      {:error, :not_found} ->
        {:error, :function_not_found}

      {:error, reason} ->
        {:error, "Failed to analyze function: #{inspect(reason)}"}
    end
  end
end
