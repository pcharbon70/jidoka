defmodule Jidoka.Agents.LLMOrchestrator.Adapter do
  @moduledoc """
  Adapter for converting Jidoka tools to Jido.AI format and executing them.

  This module handles:
  - Converting Jidoka tool schemas to Jido.AI format
  - Executing tools via Jido.Exec.run
  - Formatting tool results for LLM consumption
  - Handling tool execution errors

  """

  alias Jido.Agent.Directive
  alias Jido.Exec
  alias Jido.Signal

  @doc """
  Converts a Jidoka tool to Jido.AI tool format.

  ## Examples

      iex> tool = %{name: "read_file", module: Jidoka.Tools.ReadFile, ...}
      iex> Adapter.to_jido_tool(tool)
      %{
        name: "read_file",
        description: "...",
        parameters: %{...},
        execute: &Jidoka.Agents.LLMOrchestrator.Adapter.execute_tool/3
      }

  """
  def to_jido_tool(tool_info) do
    # Build OpenAI-style parameters from Jido schema
    parameters = build_parameters_from_schema(tool_info.schema)

    %{
      name: tool_info.name,
      description: tool_info.description,
      parameters: parameters,
      module: tool_info.module,
      schema: tool_info.schema
    }
  end

  @doc """
  Executes a tool with the given parameters.

  ## Parameters

  * `tool` - Tool info map with :module key
  * `params` - Tool parameters map
  * `context` - Execution context (optional)

  ## Returns

  * `{:ok, result}` - Tool executed successfully
  * `{:error, reason}` - Tool execution failed

  """
  def execute_tool(tool, params, context \\ %{}) do
    tool_module = tool.module

    # Convert string keys to atom keys if necessary
    normalized_params = normalize_params(params, tool.schema)

    # Execute the tool via Jido.Exec.run
    case Exec.run(tool_module, normalized_params, context) do
      {:ok, result, []} ->
        # Success - extract and format the result
        formatted_result = format_result(result)
        {:ok, formatted_result}

      {:ok, _result, directives} when is_list(directives) and length(directives) > 0 ->
        # Tool returned directives - extract result from directives
        case extract_result_from_directives(directives) do
          {:ok, extracted} ->
            {:ok, extracted}

          {:error, _} = error ->
            error
        end

      {:error, reason} ->
        # Tool execution failed
        {:error, %{error: inspect(reason), tool: tool.name}}

      error ->
        # Unexpected error format
        {:error, %{error: "Unknown error", details: inspect(error), tool: tool.name}}
    end
  rescue
    error ->
      {:error, %{error: "Exception during execution", exception: inspect(error), tool: tool.name}}
  end

  @doc """
  Formats a tool execution result for LLM consumption.

  ## Examples

      iex> Adapter.format_result(%{content: "file contents", metadata: %{}})
      %{content: "file contents", metadata: %{}}

      iex> Adapter.format_result(%{results: [%{file: "test.ex"}]})
      %{results: [%{file: "test.ex"}]}

  """
  def format_result(result) when is_map(result) do
    # Return result as-is if it's already a map
    result
  end

  def format_result(result) when is_binary(result) do
    # Wrap string result in content map
    %{content: result}
  end

  def format_result(result) do
    # Wrap other results in generic map
    %{result: result}
  end

  @doc """
  Normalizes parameters from string keys to atom keys based on schema.

  """
  def normalize_params(params, schema) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      normalized_key = normalize_key(key, schema)

      # Skip nil values for optional parameters (not required)
      if is_nil(value) and not parameter_required?(schema, normalized_key) do
        acc
      else
        Map.put(acc, normalized_key, normalize_value(value, key, schema))
      end
    end)
  end

  def normalize_params(params, _schema), do: params

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp normalize_key(key, _schema) when is_atom(key), do: key
  defp normalize_key(key, schema) when is_binary(key) do
    # Try to find matching atom key in schema
    key_str = to_string(key)

    case Enum.find(schema, fn {schema_key, _opts} ->
      key_atom = if is_atom(schema_key), do: schema_key, else: String.to_atom(schema_key)
      to_string(key_atom) == key_str
    end) do
      {schema_key, _opts} ->
        # Return the actual schema key (which is an atom)
        if is_atom(schema_key), do: schema_key, else: String.to_atom(schema_key)

      nil ->
        # Not found in schema, convert to atom
        String.to_atom(key)
    end
  end

  defp normalize_value(value, _key, _opts), do: value

  # Check if a parameter is required in the schema
  defp parameter_required?(schema, key) when is_atom(key) do
    Enum.any?(schema, fn
      {schema_key, opts} when schema_key == key ->
        Keyword.get(opts, :required, false)

      _ ->
        false
    end)
  end

  defp parameter_required?(_schema, _key), do: false

  defp build_parameters_from_schema(schema) when is_list(schema) do
    properties =
      Enum.reduce(schema, %{}, fn {field_name, field_opts}, acc ->
        field_type = get_parameter_type(field_opts)
        Map.put(acc, to_string(field_name), %{
          "type" => field_type,
          "description" => Keyword.get(field_opts, :doc, "")
        })
      end)

    required_fields =
      Enum.reduce(schema, [], fn {field_name, field_opts}, acc ->
        if Keyword.get(field_opts, :required, false) do
          [to_string(field_name) | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required_fields
    }
  end

  defp build_parameters_from_schema(_schema), do: %{"type" => "object", "properties" => %{}}

  defp get_parameter_type(field_opts) do
    case Keyword.get(field_opts, :type, :string) do
      :string -> "string"
      :integer -> "integer"
      :boolean -> "boolean"
      :float -> "number"
      {:list, _} -> "array"
      :map -> "object"
      _ -> "string"
    end
  end

  defp extract_result_from_directives(directives) do
    # Look for Emit directives with signal results
    results =
      Enum.flat_map(directives, fn
        %Directive.Emit{signal: %Signal{data: data}} ->
          # Extract result from signal data
          case Map.get(data, :result) do
            nil -> []
            result -> [result]
          end

        _ ->
          []
      end)

    case results do
      [] -> {:error, :no_result_in_directives}
      [result] -> {:ok, result}
      multiple -> {:ok, %{results: multiple}}
    end
  end
end
