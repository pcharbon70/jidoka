defmodule JidoCoderLib.Codebase.Queries do
  @moduledoc """
  High-level query interface for the codebase semantic model.

  This module provides convenience functions for querying the indexed Elixir code
  in the `:elixir_codebase` named graph without writing raw SPARQL. All functions
  return clean Elixir maps with domain-relevant keys.

  ## Codebase Graph

  The module queries the `:elixir_codebase` named graph which contains:
  - Indexed code from CodeIndexer (using elixir-ontologies)
  - Module definitions and their functions
  - Struct definitions and fields
  - Protocol definitions and implementations
  - Behaviour definitions and implementations
  - Module dependencies and call relationships

  ## Elixir Ontology Classes

  The module uses the Elixir ontology from elixir-ontologies:

  | Class | IRI |
  |-------|-----|
  | `Module` | `https://w3id.org/elixir-code/structure#Module` |
  | `Function` | `https://w3id.org/elixir-code/structure#Function` |
  | `PublicFunction` | `https://w3id.org/elixir-code/structure#PublicFunction` |
  | `PrivateFunction` | `https://w3id.org/elixir-code/structure#PrivateFunction` |
  | `Struct` | `https://w3id.org/elixir-code/structure#Struct` |
  | `Protocol` | `https://w3id.org/elixir-code/structure#Protocol` |
  | `Behaviour` | `https://w3id.org/elixir-code/structure#Behaviour` |

  ## Options

  All query functions support common options:

  | Option | Type | Description |
  |--------|------|-------------|
  | `:limit` | Integer | Maximum number of results |
  | `:offset` | Integer | Pagination offset |
  | `:engine_name` | Atom | Name of the knowledge engine |

  ## Examples

  Find a module by name:

      {:ok, module} = Queries.find_module("MyApp.Users")

  List all functions in a module:

      {:ok, functions} = Queries.list_functions("MyApp.Users")

  Find a specific function:

      {:ok, function} = Queries.find_function("MyApp.Users", "get_user", 1)

  Get module dependencies:

      {:ok, deps} = Queries.get_dependencies("MyApp.Users")

  Find protocol implementations:

      {:ok, impls} = Queries.find_implementations("Enumerable")

  """

  alias JidoCoderLib.Knowledge.{Engine, Context, NamedGraphs, Ontology, SparqlHelpers}
  alias TripleStore.SPARQL.Query

  # Default engine name
  @default_engine :knowledge_engine

  # Codebase graph
  @codebase_graph :elixir_codebase

  # Elixir ontology namespaces
  @elixir_namespace "https://w3id.org/elixir-code/"
  @elixir_structure "#{@elixir_namespace}structure#"
  @elixir_core "#{@elixir_namespace}core#"

  # RDF type
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @type query_opts :: [
          {:limit, pos_integer()},
          {:offset, non_neg_integer()},
          {:engine_name, atom()}
        ]

  @type module_result :: %{
          name: String.t(),
          iri: String.t(),
          file: String.t() | nil,
          documentation: String.t() | nil,
          public_functions: [function_result()],
          private_functions: [function_result()],
          structs: [struct_result()],
          behaviours: [String.t()],
          protocols: [String.t()]
        }

  @type function_result :: %{
          name: String.t(),
          arity: non_neg_integer(),
          iri: String.t(),
          module: String.t(),
          visibility: :public | :private,
          documentation: String.t() | nil,
          head: String.t() | nil
        }

  @type struct_result :: %{
          module: String.t(),
          iri: String.t(),
          fields: [map()]
        }

  @type protocol_result :: %{
          name: String.t(),
          iri: String.t(),
          functions: [function_result()],
          implementations: [String.t()]
        }

  # ============================================================================
  # Public API - Module Queries
  # ============================================================================

  @doc """
  Finds a module by name.

  ## Parameters

  - `module_name` - Module name as string or atom
  - `opts` - Additional options (limit, offset, engine_name)

  ## Returns

  - `{:ok, module_map}` - Module found
  - `{:error, :not_found}` - Module not found
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, module} = Queries.find_module("MyApp.Users")
      module.name #=> "MyApp.Users"
      module.public_functions #=> [%{name: "get_user", arity: 1}, ...]

      {:ok, module} = Queries.find_module(MyApp.Users)

  """
  @spec find_module(String.t() | atom(), keyword()) ::
          {:ok, module_result()} | {:error, :not_found | term()}
  def find_module(module_name, opts \\ []) when is_binary(module_name) or is_atom(module_name) do
    module_str = module_name_to_string(module_name)
    module_literal = SparqlHelpers.string_literal(module_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    # Create module IRI pattern - elixir-ontologies uses base_iri + ModuleName
    # We need to find the module with a matching name property
    query = """
    PREFIX struct: <#{@elixir_structure}>
    PREFIX core: <#{@elixir_core}>
    PREFIX rdf: <#{@rdf_type}>

    SELECT ?module ?file ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?module a struct:Module ;
               struct:moduleName #{module_literal} .
        OPTIONAL { ?module core:inSourceFile ?file . }
        OPTIONAL { ?module struct:hasDocumentation ?doc . }
      }
    }
    LIMIT 1
    """

    case Query.query(ctx, query, []) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, [result | _]} ->
        module_iri = extract_iri(result["module"])
        file = extract_string(result["file"])
        doc = extract_string(result["doc"])

        # Get functions, structs, behaviours, protocols for this module
        functions = get_module_functions(ctx, graph_iri, module_iri)
        structs = get_module_structs(ctx, graph_iri, module_iri)
        behaviours = get_module_behaviours(ctx, graph_iri, module_iri)
        protocols = get_module_protocols(ctx, graph_iri, module_iri)

        {:ok,
         %{
           name: module_str,
           iri: module_iri,
           file: file,
           documentation: doc,
           public_functions: Enum.filter(functions, &(&1.visibility == :public)),
           private_functions: Enum.filter(functions, &(&1.visibility == :private)),
           structs: structs,
           behaviours: behaviours,
           protocols: protocols
         }}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Lists all modules in the codebase.

  ## Options

  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Pagination offset
  - `:engine_name` - Name of the knowledge engine

  ## Returns

  - `{:ok, modules}` - List of module maps with basic info
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, modules} = Queries.list_modules()
      Enum.map(modules, & &1.name) #=> ["MyApp.Users", "MyApp.Posts", ...]

      {:ok, modules} = Queries.list_modules(limit: 10)

  """
  @spec list_modules(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_modules(opts \\ []) do
    ctx = get_context(opts)
    graph_iri = get_graph_iri()
    limit = Keyword.get(opts, :limit, 100)

    query = """
    PREFIX struct: <#{@elixir_structure}>
    PREFIX core: <#{@elixir_core}>
    PREFIX rdf: <#{@rdf_type}>

    SELECT ?module ?name ?file
    WHERE {
      GRAPH <#{graph_iri}> {
        ?module a struct:Module .
        OPTIONAL { ?module struct:moduleName ?name . }
        OPTIONAL { ?module core:inSourceFile ?file . }
      }
    }
    ORDER BY ?name
    LIMIT #{limit}
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        modules =
          Enum.map(results, fn result ->
            %{
              name: extract_string(result["name"]) || extract_local_name(result["module"]),
              iri: extract_iri(result["module"]),
              file: extract_string(result["file"])
            }
          end)

        {:ok, modules}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets complete details for a module including all functions and metadata.

  Similar to `find_module/2` but includes more detailed information.

  ## Parameters

  - `module_name` - Module name as string or atom
  - `opts` - Additional options

  ## Returns

  - `{:ok, module_map}` - Module with full details
  - `{:error, :not_found}` - Module not found
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, details} = Queries.get_module_details("MyApp.Users")
      details.public_function_count #=> 15
      details.private_function_count #=> 8
      details.struct_count #=> 1

  """
  @spec get_module_details(String.t() | atom(), keyword()) ::
          {:ok, map()} | {:error, :not_found | term()}
  def get_module_details(module_name, opts \\ []) do
    with {:ok, module} <- find_module(module_name, opts) do
      # Add computed fields
      details = Map.put(module, :public_function_count, length(module.public_functions))
      details = Map.put(details, :private_function_count, length(module.private_functions))
      details = Map.put(details, :struct_count, length(module.structs))
      details = Map.put(details, :behaviour_count, length(module.behaviours))
      details = Map.put(details, :protocol_count, length(module.protocols))
      {:ok, details}
    end
  end

  # ============================================================================
  # Public API - Function Queries
  # ============================================================================

  @doc """
  Finds a specific function by module, name, and arity.

  ## Parameters

  - `module_name` - Module name as string or atom
  - `function_name` - Function name as string or atom
  - `arity` - Function arity (number of parameters)
  - `opts` - Additional options

  ## Returns

  - `{:ok, function_map}` - Function found
  - `{:error, :not_found}` - Function not found
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, func} = Queries.find_function("MyApp.Users", "get_user", 1)
      func.name #=> "get_user"
      func.arity #=> 1
      func.visibility #=> :public

  """
  @spec find_function(String.t() | atom(), String.t() | atom(), non_neg_integer(), keyword()) ::
          {:ok, function_result()} | {:error, :not_found | term()}
  def find_function(module_name, function_name, arity, opts \\ []) do
    module_str = module_name_to_string(module_name)
    module_literal = SparqlHelpers.string_literal(module_str)
    func_str = to_string(function_name)
    func_literal = SparqlHelpers.string_literal(func_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    # First query to check if it's a private function
    private_query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?function ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?function a struct:PrivateFunction ;
                  struct:functionName #{func_literal} ;
                  struct:arity #{arity} ;
                  struct:belongsTo ?module .
        ?module struct:moduleName #{module_literal} .
        OPTIONAL { ?function struct:hasDocumentation ?doc . }
      }
    }
    LIMIT 1
    """

    case Query.query(ctx, private_query, []) do
      {:ok, [result | _]} ->
        function_iri = extract_iri(result["function"])

        {:ok,
         %{
           name: func_str,
           arity: arity,
           iri: function_iri,
           module: module_str,
           visibility: :private,
           documentation: extract_string(result["doc"]),
           head: nil
         }}

      {:ok, []} ->
        # Not private, check for public function
        public_query = """
        PREFIX struct: <#{@elixir_structure}>

        SELECT ?function ?doc
        WHERE {
          GRAPH <#{graph_iri}> {
            ?function a struct:PublicFunction ;
                      struct:functionName #{func_literal} ;
                      struct:arity #{arity} ;
                      struct:belongsTo ?module .
            ?module struct:moduleName #{module_literal} .
            OPTIONAL { ?function struct:hasDocumentation ?doc . }
          }
        }
        LIMIT 1
        """

        case Query.query(ctx, public_query, []) do
          {:ok, [result | _]} ->
            function_iri = extract_iri(result["function"])

            {:ok,
             %{
               name: func_str,
               arity: arity,
               iri: function_iri,
               module: module_str,
               visibility: :public,
               documentation: extract_string(result["doc"]),
               head: nil
             }}

          {:ok, []} ->
            {:error, :not_found}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Lists all functions in a module.

  ## Parameters

  - `module_name` - Module name as string or atom
  - `opts` - Additional options including:
    - `:visibility` - Filter by `:public`, `:private`, or `:all` (default: `:all`)

  ## Returns

  - `{:ok, functions}` - List of function maps
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, funcs} = Queries.list_functions("MyApp.Users")
      {:ok, public} = Queries.list_functions("MyApp.Users", visibility: :public)

  """
  @spec list_functions(String.t() | atom(), keyword()) ::
          {:ok, [function_result()]} | {:error, term()}
  def list_functions(module_name, opts \\ []) do
    module_str = module_name_to_string(module_name)
    visibility = Keyword.get(opts, :visibility, :all)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    # Build query based on visibility filter
    {query_public, query_private} =
      case visibility do
        :public ->
          {
            build_function_query(module_str, graph_iri, "PublicFunction"),
            nil
          }

        :private ->
          {
            nil,
            build_function_query(module_str, graph_iri, "PrivateFunction")
          }

        :all ->
          {
            build_function_query(module_str, graph_iri, "PublicFunction"),
            build_function_query(module_str, graph_iri, "PrivateFunction")
          }
      end

    # Query public functions
    public_functions =
      if query_public do
        case Query.query(ctx, query_public, []) do
          {:ok, results} when is_list(results) ->
            Enum.map(results, fn result ->
              func_name = extract_string(result["name"]) || "unknown"
              arity_str = extract_string(result["arity"])
              arity = if arity_str, do: String.to_integer(arity_str), else: 0

              %{
                name: func_name,
                arity: arity,
                iri: extract_iri(result["function"]),
                module: module_str,
                visibility: :public,
                documentation: extract_string(result["doc"]),
                head: nil
              }
            end)

          _ ->
            []
        end
      else
        []
      end

    # Query private functions
    private_functions =
      if query_private do
        case Query.query(ctx, query_private, []) do
          {:ok, results} when is_list(results) ->
            Enum.map(results, fn result ->
              func_name = extract_string(result["name"]) || "unknown"
              arity_str = extract_string(result["arity"])
              arity = if arity_str, do: String.to_integer(arity_str), else: 0

              %{
                name: func_name,
                arity: arity,
                iri: extract_iri(result["function"]),
                module: module_str,
                visibility: :private,
                documentation: extract_string(result["doc"]),
                head: nil
              }
            end)

          _ ->
            []
        end
      else
        []
      end

    {:ok, public_functions ++ private_functions}
  end

  defp build_function_query(module_str, graph_iri, function_class) do
    module_literal = SparqlHelpers.string_literal(module_str)

    """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?function ?name ?arity ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?function a struct:#{function_class} ;
                  struct:belongsTo ?module .
        ?module struct:moduleName #{module_literal} .
        OPTIONAL { ?function struct:functionName ?name . }
        OPTIONAL { ?function struct:arity ?arity . }
        OPTIONAL { ?function struct:hasDocumentation ?doc . }
      }
    }
    ORDER BY ?name ?arity
    """
  end

  @doc """
  Finds functions by name across all modules.

  ## Parameters

  - `function_name` - Function name as string or atom
  - `opts` - Additional options

  ## Returns

  - `{:ok, functions}` - List of matching functions
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, funcs} = Queries.find_functions_by_name("init")
      # => [%{name: "init", arity: 1, module: "MyApp.Users"}, ...]

  """
  @spec find_functions_by_name(String.t() | atom(), keyword()) ::
          {:ok, [function_result()]} | {:error, term()}
  def find_functions_by_name(function_name, opts \\ []) do
    func_str = to_string(function_name)
    func_literal = SparqlHelpers.string_literal(func_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()
    limit = Keyword.get(opts, :limit, 100)

    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?function ?arity ?module ?module_name ?doc ?type
    WHERE {
      GRAPH <#{graph_iri}> {
        ?function a struct:Function ;
                  struct:functionName #{func_literal} ;
                  struct:belongsTo ?module .
        ?module struct:moduleName ?module_name .
        OPTIONAL { ?function struct:arity ?arity . }
        OPTIONAL { ?function struct:hasDocumentation ?doc . }
        OPTIONAL {
          { ?function a struct:PublicFunction } UNION
          { ?function a struct:PrivateFunction }
          ?function a ?type .
        }
      }
    }
    ORDER BY ?module_name ?arity
    LIMIT #{limit}
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        functions =
          Enum.map(results, fn result ->
            module_name = extract_string(result["module_name"]) || "unknown"
            arity_str = extract_string(result["arity"])
            arity = if arity_str, do: String.to_integer(arity_str), else: 0

            %{
              name: func_str,
              arity: arity,
              iri: extract_iri(result["function"]),
              module: module_name,
              visibility: determine_visibility(result),
              documentation: extract_string(result["doc"]),
              head: nil
            }
          end)

        {:ok, functions}

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Public API - Relationship Queries
  # ============================================================================

  @doc """
  Gets the call graph for a module or function.

  Shows which functions are called by the specified module or function.

  ## Parameters

  - `subject` - Module name or `{module, function, arity}` tuple
  - `opts` - Additional options

  ## Returns

  - `{:ok, call_graph}` - Map of called functions
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, graph} = Queries.get_call_graph("MyApp.Users")
      graph.called #=> ["Enum.map/2", "String.to_integer/1", ...]

      {:ok, graph} = Queries.get_call_graph({"MyApp.Users", "process", 1})

  """
  @spec get_call_graph(String.t() | {String.t(), String.t(), non_neg_integer()}, keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_call_graph(subject, opts \\ [])

  def get_call_graph(module_name, opts) when is_binary(module_name) or is_atom(module_name) do
    module_str = module_name_to_string(module_name)
    module_literal = SparqlHelpers.string_literal(module_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()
    limit = Keyword.get(opts, :limit, 500)

    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?called_func ?called_module ?called_name ?called_arity
    WHERE {
      GRAPH <#{graph_iri}> {
        ?caller struct:belongsTo ?module .
        ?module struct:moduleName #{module_literal} .
        ?caller struct:callsFunction ?called_func .
        OPTIONAL { ?called_func struct:belongsTo ?called_module . }
        OPTIONAL { ?called_func struct:functionName ?called_name . }
        OPTIONAL { ?called_func struct:arity ?called_arity . }
      }
    }
    LIMIT #{limit}
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        called =
          Enum.map(results, fn result ->
            called_module = extract_string(result["called_module"])
            called_name = extract_string(result["called_name"])
            called_arity = extract_string(result["called_arity"])

            format_function_reference(called_module, called_name, called_arity)
          end)

        {:ok, %{called: called}}

      {:error, _} = error ->
        error
    end
  end

  def get_call_graph({module_name, function_name, arity}, opts) do
    module_str = module_name_to_string(module_name)
    module_literal = SparqlHelpers.string_literal(module_str)
    func_str = to_string(function_name)
    func_literal = SparqlHelpers.string_literal(func_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()
    limit = Keyword.get(opts, :limit, 500)

    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?called_func ?called_module ?called_name ?called_arity
    WHERE {
      GRAPH <#{graph_iri}> {
        ?caller struct:functionName #{func_literal} ;
                struct:arity #{arity} ;
                struct:belongsTo ?module .
        ?module struct:moduleName #{module_literal} .
        ?caller struct:callsFunction ?called_func .
        OPTIONAL { ?called_func struct:belongsTo ?called_module . }
        OPTIONAL { ?called_func struct:functionName ?called_name . }
        OPTIONAL { ?called_func struct:arity ?called_arity . }
      }
    }
    LIMIT #{limit}
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        called =
          Enum.map(results, fn result ->
            called_module = extract_string(result["called_module"])
            called_name = extract_string(result["called_name"])
            called_arity = extract_string(result["called_arity"])

            format_function_reference(called_module, called_name, called_arity)
          end)

        {:ok, %{called: called}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets the dependencies of a module.

  Returns modules that this module depends on through use, require, import,
  or alias statements.

  ## Parameters

  - `module_name` - Module name as string or atom
  - `opts` - Additional options

  ## Returns

  - `{:ok, dependencies}` - List of module names and relationship types
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, deps} = Queries.get_dependencies("MyApp.Users")
      deps #=> [
      #=>   %{module: "Ecto.Schema", type: :use},
      #=>   %{module: "Ecto.Changeset", type: :import},
      #=>   ...
      #=> ]

  """
  @spec get_dependencies(String.t() | atom(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def get_dependencies(module_name, opts \\ []) do
    module_str = module_name_to_string(module_name)
    module_literal = SparqlHelpers.string_literal(module_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()
    limit = Keyword.get(opts, :limit, 500)

    # Query for all dependency types
    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?dep_module ?dep_name
    WHERE {
      GRAPH <#{graph_iri}> {
        ?module struct:moduleName #{module_literal} .
        {
          ?module struct:usesModule ?dep_module .
          BIND("use" AS ?rel_type)
        } UNION {
          ?module struct:requiresModule ?dep_module .
          BIND("require" AS ?rel_type)
        } UNION {
          ?module struct:importsFrom ?dep_module .
          BIND("import" AS ?rel_type)
        } UNION {
          ?module struct:aliasesModule ?dep_module .
          BIND("alias" AS ?rel_type)
        }
        ?dep_module struct:moduleName ?dep_name .
      }
    }
    LIMIT #{limit}
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        deps =
          Enum.map(results, fn result ->
            dep_name = extract_string(result["dep_name"])
            rel_type = extract_string(result["rel_type"])

            %{
              module: dep_name,
              type: string_to_dependency_type(rel_type)
            }
          end)

        {:ok, deps}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets modules that depend on the given module.

  Reverse dependency lookup.

  ## Parameters

  - `module_name` - Module name as string or atom
  - `opts` - Additional options

  ## Returns

  - `{:ok, dependents}` - List of dependent module names
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, dependents} = Queries.get_dependents("Ecto.Schema")
      dependents #=> ["MyApp.Users", "MyApp.Posts", ...]

  """
  @spec get_dependents(String.t() | atom(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def get_dependents(module_name, opts \\ []) do
    module_str = module_name_to_string(module_name)
    module_literal = SparqlHelpers.string_literal(module_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()
    limit = Keyword.get(opts, :limit, 500)

    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?dependent ?dep_name
    WHERE {
      GRAPH <#{graph_iri}> {
        ?dep_module struct:moduleName #{module_literal} .
        {
          ?dependent struct:usesModule ?dep_module .
        } UNION {
          ?dependent struct:requiresModule ?dep_module .
        } UNION {
          ?dependent struct:importsFrom ?dep_module .
        } UNION {
          ?dependent struct:aliasesModule ?dep_module .
        }
        ?dependent struct:moduleName ?dep_name .
      }
    }
    LIMIT #{limit}
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        dependents =
          Enum.map(results, fn result ->
            extract_string(result["dep_name"])
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        {:ok, dependents}

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Public API - Protocol Queries
  # ============================================================================

  @doc """
  Finds a protocol by name.

  ## Parameters

  - `protocol_name` - Protocol name as string or atom
  - `opts` - Additional options

  ## Returns

  - `{:ok, protocol_map}` - Protocol found with functions and implementations
  - `{:error, :not_found}` - Protocol not found
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, protocol} = Queries.find_protocol("Enumerable")
      protocol.functions #=> [%{name: "reduce", arity: 3}, ...]
      protocol.implementations #=> ["List", "Map", "MyApp.CustomEnum"]

  """
  @spec find_protocol(String.t() | atom(), keyword()) ::
          {:ok, protocol_result()} | {:error, :not_found | term()}
  def find_protocol(protocol_name, opts \\ []) do
    proto_str = module_name_to_string(protocol_name)
    proto_literal = SparqlHelpers.string_literal(proto_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    query = """
    PREFIX struct: <#{@elixir_structure}>
    PREFIX rdf: <#{@rdf_type}>

    SELECT ?protocol ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?protocol a struct:Protocol ;
                  struct:moduleName #{proto_literal} .
        OPTIONAL { ?protocol struct:hasDocumentation ?doc . }
      }
    }
    LIMIT 1
    """

    case Query.query(ctx, query, []) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, [result | _]} ->
        protocol_iri = extract_iri(result["protocol"])

        # Get protocol functions and implementations
        functions = get_protocol_functions(ctx, graph_iri, protocol_iri)
        implementations = get_protocol_implementations(ctx, graph_iri, protocol_iri)

        {:ok,
         %{
           name: proto_str,
           iri: protocol_iri,
           functions: functions,
           implementations: implementations
         }}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Lists all protocols in the codebase.

  ## Options

  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Pagination offset
  - `:engine_name` - Name of the knowledge engine

  ## Returns

  - `{:ok, protocols}` - List of protocol maps
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, protocols} = Queries.list_protocols()
      Enum.map(protocols, & &1.name) #=> ["Enumerable", "Collectable", ...]

  """
  @spec list_protocols(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_protocols(opts \\ []) do
    ctx = get_context(opts)
    graph_iri = get_graph_iri()
    limit = Keyword.get(opts, :limit, 100)

    query = """
    PREFIX struct: <#{@elixir_structure}>
    PREFIX rdf: <#{@rdf_type}>

    SELECT ?protocol ?name ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?protocol a struct:Protocol .
        OPTIONAL { ?protocol struct:moduleName ?name . }
        OPTIONAL { ?protocol struct:hasDocumentation ?doc . }
      }
    }
    ORDER BY ?name
    LIMIT #{limit}
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        protocols =
          Enum.map(results, fn result ->
            %{
              name: extract_string(result["name"]) || extract_local_name(result["protocol"]),
              iri: extract_iri(result["protocol"]),
              documentation: extract_string(result["doc"])
            }
          end)

        {:ok, protocols}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Finds all implementations of a protocol.

  ## Parameters

  - `protocol_name` - Protocol name as string or atom
  - `opts` - Additional options

  ## Returns

  - `{:ok, implementations}` - List of implementing module names
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, impls} = Queries.find_implementations("Enumerable")
      impls #=> ["List", "Map", "Function", "MyApp.Users"]

  """
  @spec find_implementations(String.t() | atom(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def find_implementations(protocol_name, opts \\ []) do
    case find_protocol(protocol_name, opts) do
      {:ok, protocol} ->
        {:ok, protocol.implementations}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets functions defined by a protocol.

  ## Parameters

  - `protocol_name` - Protocol name as string or atom
  - `opts` - Additional options

  ## Returns

  - `{:ok, functions}` - List of protocol function maps
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, funcs} = Queries.get_protocol_functions("Enumerable")
      funcs #=> [%{name: "reduce", arity: 3}, %{name: "member?", arity: 2}]

  """
  @spec get_protocol_functions(String.t() | atom(), keyword()) ::
          {:ok, [function_result()]} | {:error, term()}
  def get_protocol_functions(protocol_name, opts \\ []) do
    case find_protocol(protocol_name, opts) do
      {:ok, protocol} ->
        {:ok, protocol.functions}

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Public API - Behaviour Queries
  # ============================================================================

  @doc """
  Finds a behaviour by name.

  ## Parameters

  - `behaviour_name` - Behaviour name as string or atom
  - `opts` - Additional options

  ## Returns

  - `{:ok, behaviour_map}` - Behaviour found
  - `{:error, :not_found}` - Behaviour not found
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, behaviour} = Queries.find_behaviour("GenServer")
      behaviour.callbacks #=> [%{name: "init", arity: 1}, ...]

  """
  @spec find_behaviour(String.t() | atom(), keyword()) ::
          {:ok, map()} | {:error, :not_found | term()}
  def find_behaviour(behaviour_name, opts \\ []) do
    behaviour_str = module_name_to_string(behaviour_name)
    behaviour_literal = SparqlHelpers.string_literal(behaviour_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    query = """
    PREFIX struct: <#{@elixir_structure}>
    PREFIX rdf: <#{@rdf_type}>

    SELECT ?behaviour ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?behaviour a struct:Behaviour ;
                   struct:moduleName #{behaviour_literal} .
        OPTIONAL { ?behaviour struct:hasDocumentation ?doc . }
      }
    }
    LIMIT 1
    """

    case Query.query(ctx, query, []) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, [result | _]} ->
        behaviour_iri = extract_iri(result["behaviour"])

        # Get callbacks defined by this behaviour
        callbacks = get_behaviour_callbacks(ctx, graph_iri, behaviour_iri)
        implementations = get_behaviour_implementations(ctx, graph_iri, behaviour_iri)

        {:ok,
         %{
           name: behaviour_str,
           iri: behaviour_iri,
           documentation: extract_string(result["doc"]),
           callbacks: callbacks,
           implementations: implementations
         }}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Lists all behaviours in the codebase.

  ## Options

  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Pagination offset
  - `:engine_name` - Name of the knowledge engine

  ## Returns

  - `{:ok, behaviours}` - List of behaviour maps
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, behaviours} = Queries.list_behaviours()
      Enum.map(behaviours, & &1.name) #=> ["GenServer", "Supervisor", ...]

  """
  @spec list_behaviours(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_behaviours(opts \\ []) do
    ctx = get_context(opts)
    graph_iri = get_graph_iri()
    limit = Keyword.get(opts, :limit, 100)

    query = """
    PREFIX struct: <#{@elixir_structure}>
    PREFIX rdf: <#{@rdf_type}>

    SELECT ?behaviour ?name ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?behaviour a struct:Behaviour .
        OPTIONAL { ?behaviour struct:moduleName ?name . }
        OPTIONAL { ?behaviour struct:hasDocumentation ?doc . }
      }
    }
    ORDER BY ?name
    LIMIT #{limit}
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        behaviours =
          Enum.map(results, fn result ->
            %{
              name: extract_string(result["name"]) || extract_local_name(result["behaviour"]),
              iri: extract_iri(result["behaviour"]),
              documentation: extract_string(result["doc"])
            }
          end)

        {:ok, behaviours}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Finds modules that implement a behaviour.

  ## Parameters

  - `behaviour_name` - Behaviour name as string or atom
  - `opts` - Additional options

  ## Returns

  - `{:ok, implementations}` - List of implementing module names
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, impls} = Queries.find_behaviour_implementations("GenServer")
      impls #=> ["MyApp.Server", "MyApp.Worker", ...]

  """
  @spec find_behaviour_implementations(String.t() | atom(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def find_behaviour_implementations(behaviour_name, opts \\ []) do
    case find_behaviour(behaviour_name, opts) do
      {:ok, behaviour} ->
        {:ok, behaviour.implementations}

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Public API - Struct Queries
  # ============================================================================

  @doc """
  Finds a struct by its defining module name.

  ## Parameters

  - `module_name` - Module name defining the struct
  - `opts` - Additional options

  ## Returns

  - `{:ok, struct_map}` - Struct found with fields
  - `{:error, :not_found}` - Struct not found
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, struct} = Queries.find_struct("MyApp.User")
      struct.fields #=> [%{name: "id", type: nil}, %{name: "name", type: nil}]

  """
  @spec find_struct(String.t() | atom(), keyword()) ::
          {:ok, struct_result()} | {:error, :not_found | term()}
  def find_struct(module_name, opts \\ []) do
    module_str = module_name_to_string(module_name)
    module_literal = SparqlHelpers.string_literal(module_str)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    query = """
    PREFIX struct: <#{@elixir_structure}>
    PREFIX rdf: <#{@rdf_type}>

    SELECT ?struct ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?struct a struct:Struct ;
                struct:belongsTo ?module .
        ?module struct:moduleName #{module_literal} .
        OPTIONAL { ?struct struct:hasDocumentation ?doc . }
      }
    }
    LIMIT 1
    """

    case Query.query(ctx, query, []) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, [result | _]} ->
        struct_iri = extract_iri(result["struct"])
        fields = get_struct_fields(ctx, graph_iri, struct_iri)

        {:ok,
         %{
           module: module_str,
           iri: struct_iri,
           fields: fields
         }}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Lists all structs in the codebase.

  ## Options

  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Pagination offset
  - `:engine_name` - Name of the knowledge engine

  ## Returns

  - `{:ok, structs}` - List of struct maps
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, structs} = Queries.list_structs()
      Enum.map(structs, & &1.module) #=> ["MyApp.User", "MyApp.Post", ...]

  """
  @spec list_structs(keyword()) :: {:ok, [struct_result()]} | {:error, term()}
  def list_structs(opts \\ []) do
    ctx = get_context(opts)
    graph_iri = get_graph_iri()
    limit = Keyword.get(opts, :limit, 100)

    query = """
    PREFIX struct: <#{@elixir_structure}>
    PREFIX core: <#{@elixir_core}>
    PREFIX rdf: <#{@rdf_type}>

    SELECT ?struct ?module_name
    WHERE {
      GRAPH <#{graph_iri}> {
        ?struct a struct:Struct ;
                struct:belongsTo ?module .
        ?module struct:moduleName ?module_name .
      }
    }
    ORDER BY ?module_name
    LIMIT #{limit}
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        structs =
          Enum.map(results, fn result ->
            module_name = extract_string(result["module_name"]) || "unknown"
            struct_iri = extract_iri(result["struct"])

            %{
              module: module_name,
              iri: struct_iri,
              # Fields loaded separately
              fields: []
            }
          end)

        {:ok, structs}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets the fields of a struct.

  ## Parameters

  - `module_name` - Module name defining the struct
  - `opts` - Additional options

  ## Returns

  - `{:ok, fields}` - List of field maps with name, type, and default
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, fields} = Queries.get_struct_fields("MyApp.User")
      fields #=> [%{name: "id", type: nil, default: nil}, ...]

  """
  @spec get_struct_fields(String.t() | atom(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def get_struct_fields(module_name, opts \\ []) do
    case find_struct(module_name, opts) do
      {:ok, struct} ->
        {:ok, struct.fields}

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Public API - Utility Queries
  # ============================================================================

  @doc """
  Searches for modules and functions by name pattern.

  Performs a case-insensitive substring search on module and function names.

  ## Parameters

  - `pattern` - Search pattern string
  - `opts` - Additional options including:
    - `:limit` - Maximum results per type (default: 50)
    - `:types` - Types to search: `:modules`, `:functions`, or `:all` (default: `:all`)

  ## Returns

  - `{:ok, results}` - Map with `:modules` and `:functions` keys
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, results} = Queries.search_by_name("user")
      results.modules #=> ["MyApp.User", "MyApp.Users", ...]
      results.functions #=> ["get_user", "update_user", ...]

      {:ok, results} = Queries.search_by_name("user", types: :modules)

  """
  @spec search_by_name(String.t(), keyword()) ::
          {:ok, %{modules: [String.t()], functions: [String.t()]}} | {:error, term()}
  def search_by_name(pattern, opts \\ []) when is_binary(pattern) do
    types = Keyword.get(opts, :types, :all)
    limit = Keyword.get(opts, :limit, 50)
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    # Escape the search pattern to prevent SPARQL injection
    escaped_pattern = SparqlHelpers.escape_string(String.downcase(pattern))

    # SPARQL FILTER with CONTAINS for case-insensitive search
    modules =
      if types in [:all, :modules] do
        query = """
        PREFIX struct: <#{@elixir_structure}>

        SELECT ?name
        WHERE {
          GRAPH <#{graph_iri}> {
            ?module a struct:Module ;
                    struct:moduleName ?name .
            FILTER(CONTAINS(LCASE(STR(?name)), "#{escaped_pattern}"))
          }
        }
        ORDER BY ?name
        LIMIT #{limit}
        """

        case Query.query(ctx, query, []) do
          {:ok, results} -> Enum.map(results, fn r -> extract_string(r["name"]) end)
          _ -> []
        end
      else
        []
      end

    functions =
      if types in [:all, :functions] do
        query = """
        PREFIX struct: <#{@elixir_structure}>

        SELECT ?func_name
        WHERE {
          GRAPH <#{graph_iri}> {
            ?function a struct:Function ;
                     struct:functionName ?func_name .
            FILTER(CONTAINS(LCASE(STR(?func_name)), "#{escaped_pattern}"))
          }
        }
        ORDER BY ?func_name
        LIMIT #{limit}
        """

        case Query.query(ctx, query, []) do
          {:ok, results} -> Enum.map(results, fn r -> extract_string(r["func_name"]) end)
          _ -> []
        end
      else
        []
      end

    {:ok,
     %{
       modules: Enum.reject(modules, &is_nil/1),
       functions: Enum.reject(functions, &is_nil/1)
     }}
  end

  @doc """
  Gets statistics about the indexed codebase.

  Returns counts of modules, functions, structs, protocols, and behaviours.

  ## Options

  - `:engine_name` - Name of the knowledge engine

  ## Returns

  - `{:ok, stats}` - Map with codebase statistics
  - `{:error, reason}` - Query failed

  ## Examples

      {:ok, stats} = Queries.get_index_stats()
      stats.module_count #=> 42
      stats.function_count #=> 315
      stats.struct_count #=> 12

  """
  @spec get_index_stats(keyword()) :: {:ok, map()} | {:error, term()}
  def get_index_stats(opts \\ []) do
    ctx = get_context(opts)
    graph_iri = get_graph_iri()

    # Run separate queries for each type since VALUES is not supported
    types = [
      {:module_count, "Module"},
      {:function_count, "Function"},
      {:struct_count, "Struct"},
      {:protocol_count, "Protocol"},
      {:behaviour_count, "Behaviour"}
    ]

    stats =
      Enum.reduce(types, %{}, fn {key, type_name}, acc ->
        query = """
        PREFIX struct: <#{@elixir_structure}>

        SELECT (COUNT(?s) AS ?count)
        WHERE {
          GRAPH <#{graph_iri}> {
            ?s a struct:#{type_name} .
          }
        }
        """

        case Query.query(ctx, query, []) do
          {:ok, [result | _]} ->
            count_str = extract_string(result["count"])
            count = if count_str, do: String.to_integer(count_str), else: 0
            Map.put(acc, key, count)

          _ ->
            Map.put(acc, key, 0)
        end
      end)

    {:ok, stats}
  end

  # ============================================================================
  # Private Helpers - Module Details
  # ============================================================================

  defp get_module_functions(ctx, graph_iri, module_iri) do
    # Query both public and private functions separately to properly get visibility
    public_query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?function ?name ?arity ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?function a struct:PublicFunction ;
                  struct:belongsTo <#{module_iri}> .
        OPTIONAL { ?function struct:functionName ?name . }
        OPTIONAL { ?function struct:arity ?arity . }
        OPTIONAL { ?function struct:hasDocumentation ?doc . }
      }
    }
    ORDER BY ?name ?arity
    """

    private_query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?function ?name ?arity ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?function a struct:PrivateFunction ;
                  struct:belongsTo <#{module_iri}> .
        OPTIONAL { ?function struct:functionName ?name . }
        OPTIONAL { ?function struct:arity ?arity . }
        OPTIONAL { ?function struct:hasDocumentation ?doc . }
      }
    }
    ORDER BY ?name ?arity
    """

    public_functions =
      case Query.query(ctx, public_query, []) do
        {:ok, results} when is_list(results) ->
          Enum.map(results, fn result ->
            func_name = extract_string(result["name"]) || "unknown"
            arity_str = extract_string(result["arity"])
            arity = if arity_str, do: String.to_integer(arity_str), else: 0

            %{
              name: func_name,
              arity: arity,
              iri: extract_iri(result["function"]),
              module: extract_local_name(module_iri),
              visibility: :public,
              documentation: extract_string(result["doc"]),
              head: nil
            }
          end)

        _ ->
          []
      end

    private_functions =
      case Query.query(ctx, private_query, []) do
        {:ok, results} when is_list(results) ->
          Enum.map(results, fn result ->
            func_name = extract_string(result["name"]) || "unknown"
            arity_str = extract_string(result["arity"])
            arity = if arity_str, do: String.to_integer(arity_str), else: 0

            %{
              name: func_name,
              arity: arity,
              iri: extract_iri(result["function"]),
              module: extract_local_name(module_iri),
              visibility: :private,
              documentation: extract_string(result["doc"]),
              head: nil
            }
          end)

        _ ->
          []
      end

    public_functions ++ private_functions
  end

  defp get_module_structs(ctx, graph_iri, module_iri) do
    query = """
    PREFIX struct: <#{@elixir_structure}>
    PREFIX core: <#{@elixir_core}>
    PREFIX rdf: <#{@rdf_type}>

    SELECT ?struct_iri ?field ?field_name
    WHERE {
      GRAPH <#{graph_iri}> {
        ?struct_iri a struct:Struct ;
                   struct:belongsTo <#{module_iri}> .
        OPTIONAL { ?struct_iri struct:hasField ?field . }
        OPTIONAL { ?field struct:fieldName ?field_name . }
      }
    }
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        # Group by struct_iri
        results
        |> Enum.group_by(fn result -> extract_iri(result["struct_iri"]) end)
        |> Enum.map(fn {struct_iri, field_results} ->
          fields =
            field_results
            |> Enum.flat_map(fn result ->
              field_name = extract_string(result["field_name"])
              if field_name, do: [%{name: field_name}], else: []
            end)

          %{
            module: extract_local_name(module_iri),
            iri: struct_iri,
            fields: fields
          }
        end)

      _ ->
        []
    end
  end

  defp get_module_behaviours(ctx, graph_iri, module_iri) do
    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?behaviour_name
    WHERE {
      GRAPH <#{graph_iri}> {
        <#{module_iri}> struct:implementsBehaviour ?behaviour .
        ?behaviour struct:moduleName ?behaviour_name .
      }
    }
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        Enum.map(results, &extract_string/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp get_module_protocols(ctx, graph_iri, module_iri) do
    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?protocol_name
    WHERE {
      GRAPH <#{graph_iri}> {
        <#{module_iri}> struct:implementsProtocol ?protocol .
        ?protocol struct:moduleName ?protocol_name .
      }
    }
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        Enum.map(results, &extract_string/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp get_protocol_functions(ctx, graph_iri, protocol_iri) do
    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?function ?name ?arity ?doc
    WHERE {
      GRAPH <#{graph_iri}> {
        ?function struct:belongsTo <#{protocol_iri}> ;
                  a struct:ProtocolFunction .
        OPTIONAL { ?function struct:functionName ?name . }
        OPTIONAL { ?function struct:arity ?arity . }
        OPTIONAL { ?function struct:hasDocumentation ?doc . }
      }
    }
    ORDER BY ?name ?arity
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        Enum.map(results, fn result ->
          func_name = extract_string(result["name"]) || "unknown"
          arity_str = extract_string(result["arity"])
          arity = if arity_str, do: String.to_integer(arity_str), else: 0

          %{
            name: func_name,
            arity: arity,
            iri: extract_iri(result["function"]),
            module: extract_local_name(protocol_iri),
            visibility: :public,
            documentation: extract_string(result["doc"]),
            head: nil
          }
        end)

      _ ->
        []
    end
  end

  defp get_protocol_implementations(ctx, graph_iri, protocol_iri) do
    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?impl ?impl_name
    WHERE {
      GRAPH <#{graph_iri}> {
        ?impl struct:implementsProtocol <#{protocol_iri}> ;
             struct:moduleName ?impl_name .
      }
    }
    ORDER BY ?impl_name
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        Enum.map(results, &extract_string(&1["impl_name"]))
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp get_behaviour_callbacks(ctx, graph_iri, behaviour_iri) do
    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?callback ?name ?arity
    WHERE {
      GRAPH <#{graph_iri}> {
        <#{behaviour_iri}> struct:definesCallback ?callback .
        OPTIONAL { ?callback struct:functionName ?name . }
        OPTIONAL { ?callback struct:arity ?arity . }
      }
    }
    ORDER BY ?name ?arity
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        Enum.map(results, fn result ->
          name = extract_string(result["name"]) || "unknown"
          arity_str = extract_string(result["arity"])
          arity = if arity_str, do: String.to_integer(arity_str), else: 0

          %{name: name, arity: arity}
        end)

      _ ->
        []
    end
  end

  defp get_behaviour_implementations(ctx, graph_iri, behaviour_iri) do
    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?impl ?impl_name
    WHERE {
      GRAPH <#{graph_iri}> {
        ?impl struct:implementsBehaviour <#{behaviour_iri}> ;
             struct:moduleName ?impl_name .
      }
    }
    ORDER BY ?impl_name
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        Enum.map(results, &extract_string(&1["impl_name"]))
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp get_struct_fields(ctx, graph_iri, struct_iri) do
    query = """
    PREFIX struct: <#{@elixir_structure}>

    SELECT ?field ?name ?default
    WHERE {
      GRAPH <#{graph_iri}> {
        <#{struct_iri}> struct:hasField ?field .
        OPTIONAL { ?field struct:fieldName ?name . }
        OPTIONAL { ?field struct:hasDefaultValue ?default . }
      }
    }
    ORDER BY ?name
    """

    case Query.query(ctx, query, []) do
      {:ok, results} when is_list(results) ->
        Enum.map(results, fn result ->
          name = extract_string(result["name"])
          default = extract_string(result["default"])

          %{
            name: name,
            # Type specs not fully implemented yet
            type: nil,
            default: default
          }
        end)
        |> Enum.reject(&is_nil(&1.name))

      _ ->
        []
    end
  end

  # ============================================================================
  # Private Helpers - Result Parsing
  # ============================================================================

  defp extract_iri(nil), do: nil
  defp extract_iri({:iri, iri}), do: iri
  defp extract_iri({:named_node, iri}), do: iri
  defp extract_iri(iri) when is_binary(iri), do: iri
  defp extract_iri(_), do: nil

  defp extract_string(nil), do: nil
  defp extract_string({:literal, val}) when is_binary(val), do: val
  defp extract_string({:literal, :simple, val}) when is_binary(val), do: val
  defp extract_string({:literal, :typed, val, _type}) when is_binary(val), do: val
  defp extract_string(val) when is_binary(val), do: val
  defp extract_string(_), do: nil

  defp extract_local_name(nil), do: nil

  defp extract_local_name(iri_string) when is_binary(iri_string) do
    case String.split(iri_string, "#") do
      [_] -> iri_string
      [_, fragment] -> fragment
      _ -> iri_string
    end
  end

  defp extract_local_name(_), do: nil

  defp determine_visibility(result) do
    case extract_iri(result["type"]) do
      # Default to public
      nil ->
        :public

      type_iri when is_binary(type_iri) ->
        cond do
          String.contains?(type_iri, "#PublicFunction") -> :public
          String.contains?(type_iri, "#PrivateFunction") -> :private
          true -> :public
        end

      _ ->
        :public
    end
  end

  defp format_function_reference(nil, name, arity), do: "#{name}/#{arity}"
  defp format_function_reference(module, nil, _arity), do: module

  defp format_function_reference(module, name, arity) do
    "#{module}.#{name}/#{arity}"
  end

  defp string_to_dependency_type("use"), do: :use
  defp string_to_dependency_type("require"), do: :require
  defp string_to_dependency_type("import"), do: :import
  defp string_to_dependency_type("alias"), do: :alias
  defp string_to_dependency_type(_), do: :unknown

  defp module_name_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp module_name_to_string(str) when is_binary(str), do: str

  # ============================================================================
  # Private Helpers - Context
  # ============================================================================

  defp get_context(opts) do
    default_engine = Application.get_env(:jido_coder_lib, :knowledge_engine_name, @default_engine)
    engine_name = Keyword.get(opts, :engine_name, default_engine)

    engine_name
    |> Engine.context()
    |> Map.put(:transaction, nil)
    |> Context.with_permit_all()
  end

  defp get_graph_iri do
    {:ok, iri_string} = NamedGraphs.iri_string(@codebase_graph)
    iri_string
  end
end
