defmodule Jidoka.Tools.GetDefinition do
  @moduledoc """
  Jido Action for finding definitions in the codebase.

  This tool queries the knowledge graph to find the location and details
  of module, function, struct, protocol, or behaviour definitions.

  ## Parameters

  * `:type` - Type of definition: "module", "function", "struct", "protocol", "behaviour" (required)
  * `:name` - Name of the definition (required)
  * `:module` - Module name (required for function, struct type)
  * `:arity` - Function arity (required for function type)
  * `:include_source` - Try to include source file location (optional, default: true)

  ## Examples

      # Find module definition
      {:ok, result} = GetDefinition.run(
        %{type: "module", name: "Jidoka.Client"},
        %{}
      )

      # Find function definition
      {:ok, result} = GetDefinition.run(
        %{type: "function", name: "create_session", module: "Jidoka.Client", arity: 1},
        %{}
      )

      # Find struct definition
      {:ok, result} = GetDefinition.run(
        %{type: "struct", module: "Jidoka.Client"},
        %{}
      )

  """

  use Jido.Action,
    name: "get_definition",
    description: "Find the location and details of a code definition",
    category: "analysis",
    tags: ["definition", "knowledge-graph", "navigation"],
    vsn: "1.0.0",
    schema: [
      type: [
        type: :string,
        required: true,
        doc: "Type of definition: module, function, struct, protocol, behaviour"
      ],
      name: [
        type: :string,
        required: false,
        doc: "Name of the definition (required for module, protocol, behaviour)"
      ],
      module: [
        type: :string,
        required: false,
        doc: "Module name (required for function, struct)"
      ],
      arity: [
        type: :integer,
        required: false,
        doc: "Function arity (required for function type)"
      ],
      include_source: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Include source file location"
      ]
    ]

  alias Jidoka.Codebase.Queries

  @impl true
  def run(params, _context) do
    type = params[:type]
    name = params[:name]
    module = params[:module]
    arity = params[:arity]
    include_source = params[:include_source] != false

    result =
      case type do
        "module" ->
          find_module_definition(name, include_source)

        "function" ->
          find_function_definition(module, name, arity, include_source)

        "struct" ->
          find_struct_definition(module, include_source)

        "protocol" ->
          find_protocol_definition(name, include_source)

        "behaviour" ->
          find_behaviour_definition(name, include_source)

        _ ->
          {:error, :unknown_type}
      end

    case result do
      {:ok, definition} ->
        {:ok, definition, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp find_module_definition(nil, _), do: {:error, :name_required}

  defp find_module_definition(name, include_source) do
    case Queries.find_module(name) do
      {:ok, module_info} ->
        definition = %{
          type: "module",
          name: module_info.name,
          iri: module_info.iri,
          documentation: module_info.documentation,
          public_function_count: length(module_info.public_functions),
          private_function_count: length(module_info.private_functions),
          struct_count: length(module_info.structs),
          behaviours: module_info.behaviours,
          protocols: module_info.protocols
        }

        definition =
          if include_source and module_info.file do
            Map.put(definition, :source_file, module_info.file)
          else
            definition
          end

        {:ok, definition}

      {:error, :not_found} ->
        {:error, :module_not_found}

      {:error, _} = error ->
        error
    end
  end

  defp find_function_definition(nil, _name, _arity, _include_source),
    do: {:error, :module_required}

  defp find_function_definition(_module, nil, _arity, _include_source),
    do: {:error, :name_required}

  defp find_function_definition(_module, _name, nil, _include_source),
    do: {:error, :arity_required}

  defp find_function_definition(module, name, arity, include_source) do
    case Queries.find_function(module, name, arity) do
      {:ok, func_info} ->
        definition = %{
          type: "function",
          name: func_info.name,
          arity: func_info.arity,
          module: func_info.module,
          visibility: func_info.visibility,
          documentation: func_info.documentation,
          head: func_info.head
        }

        definition =
          if include_source do
            case Queries.find_module(module) do
              {:ok, module_info} when module_info.file != nil ->
                Map.put(definition, :source_file, module_info.file)

              _ ->
                definition
            end
          else
            definition
          end

        {:ok, definition}

      {:error, :not_found} ->
        {:error, :function_not_found}

      {:error, _} = error ->
        error
    end
  end

  defp find_struct_definition(nil, _include_source),
    do: {:error, :module_required}

  defp find_struct_definition(module, include_source) do
    case Queries.find_struct(module) do
      {:ok, struct_info} ->
        definition = %{
          type: "struct",
          module: struct_info.module,
          iri: struct_info.iri,
          fields: struct_info.fields
        }

        definition =
          if include_source do
            case Queries.find_module(module) do
              {:ok, module_info} when module_info.file != nil ->
                Map.put(definition, :source_file, module_info.file)

              _ ->
                definition
            end
          else
            definition
          end

        {:ok, definition}

      {:error, :not_found} ->
        {:error, :struct_not_found}

      {:error, _} = error ->
        error
    end
  end

  defp find_protocol_definition(nil, _include_source),
    do: {:error, :name_required}

  defp find_protocol_definition(name, _include_source) do
    case Queries.find_protocol(name) do
      {:ok, protocol_info} ->
        definition = %{
          type: "protocol",
          name: protocol_info.name,
          iri: protocol_info.iri,
          functions: protocol_info.functions,
          implementations: protocol_info.implementations
        }

        {:ok, definition}

      {:error, :not_found} ->
        {:error, :protocol_not_found}

      {:error, _} = error ->
        error
    end
  end

  defp find_behaviour_definition(nil, _include_source),
    do: {:error, :name_required}

  defp find_behaviour_definition(name, _include_source) do
    case Queries.find_behaviour(name) do
      {:ok, behaviour_info} ->
        definition = %{
          type: "behaviour",
          name: behaviour_info.name,
          iri: behaviour_info.iri,
          documentation: behaviour_info.documentation,
          callbacks: behaviour_info.callbacks,
          implementations: behaviour_info.implementations
        }

        {:ok, definition}

      {:error, :not_found} ->
        {:error, :behaviour_not_found}

      {:error, _} = error ->
        error
    end
  end
end
