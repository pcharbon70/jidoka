defmodule Jidoka.Tools.SearchCodebase do
  @moduledoc """
  Jido Action for natural language codebase search.

  This tool provides access to the codebase ontology schema for
  prompt caching and helps bridge natural language questions to
  SPARQL queries.

  ## Current Implementation

  This tool currently returns the ontology schema reference for
  use in prompt caching. Full natural language to SPARQL translation
  is planned for a future phase.

  ## Examples

      # Get ontology schema for prompt caching
      {:ok, result, []} = SearchCodebase.run(
        %{question: "What modules use GenServer?"},
        %{}
      )

  ## Future Enhancements

  - Natural language to SPARQL translation using templates
  - Query pattern matching for common questions
  - Integration with LLM for complex query translation
  """

  use Jido.Action,
    name: "search_codebase",
    description: "Search the codebase using natural language. Returns ontology schema reference for SPARQL query construction.",
    category: "knowledge_graph",
    tags: ["codebase", "ontology", "search", "natural_language"],
    vsn: "1.0.0",
    schema: [
      question: [
        type: :string,
        required: true,
        doc: "Natural language question about the codebase"
      ],
      include_schema: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Include the ontology schema in the response"
      ],
      include_templates: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Include SPARQL query templates in the response"
      ]
    ]

  alias Jidoka.Tools.OntologyCache

  @impl true
  def run(%{question: question} = params, _context) do
    include_schema = Map.get(params, :include_schema, true)
    include_templates = Map.get(params, :include_templates, true)

    response = %{
      question: question,
      guidance: """
      Use the query_codebase tool for semantic queries or sparql_query for direct SPARQL execution.

      For common queries:
      - Find modules: query_codebase with query_type="find_module"
      - List modules: query_codebase with query_type="list_modules"
      - Find functions: query_codebase with query_type="find_function"
      - List functions: query_codebase with query_type="list_functions"
      - Get dependencies: query_codebase with query_type="get_dependencies"
      - Get call graph: query_codebase with query_type="get_call_graph"
      - Find protocols: query_codebase with query_type="find_protocol"
      - Find behaviours: query_codebase with query_type="find_behaviour"
      - Search by name: query_codebase with query_type="search_by_name"

      For complex queries, use sparql_query with raw SPARQL.
      """
    }

    response =
      if include_schema do
        Map.put(response, :ontology_schema, OntologyCache.schema_prompt())
      else
        response
      end

    response =
      if include_templates do
        Map.put(response, :query_templates, OntologyCache.query_templates())
      else
        response
      end

    {:ok, response, []}
  end
end
