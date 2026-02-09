defmodule Jidoka.Protocol.MCP.Tools do
  @moduledoc """
  Helper functions for working with MCP tools.

  This module provides utilities for:
  - Discovering available tools from an MCP server
  - Calling tools with proper argument validation
  - Converting MCP tool definitions to Jido Action format

  ## Example

      # Discover tools
      {:ok, tools} = Tools.discover(client)

      # Call a tool
      {:ok, result} = Tools.call(client, "echo", %{text: "Hello"})

      # Convert to Jido Action format
      actions = Tools.to_jido_actions(tools)
  """

  alias Jidoka.Protocol.MCP.Client

  @type tool :: %{
          name: String.t(),
          description: String.t(),
          input_schema: map()
        }

  @type tool_result :: %{
          content: list(map()),
          is_error: boolean() | nil
        }

  ## Discovery

  @doc """
  Discover all available tools from the MCP server.

  Returns a list of tool maps with name, description, and input schema.
  """
  def discover(client \\ Client) do
    case Client.list_tools(client) do
      {:ok, response} ->
        tools = parse_tools(response)
        {:ok, tools}

      {:error, reason} ->
        {:error, {:discovery_failed, reason}}
    end
  end

  @doc """
  Get a specific tool by name from the MCP server.
  """
  def get_tool(client \\ Client, tool_name) when is_binary(tool_name) do
    with {:ok, tools} <- discover(client),
         %{} = tool <- Enum.find(tools, fn t -> t.name == tool_name end) do
      {:ok, tool}
    else
      nil -> {:error, :tool_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a tool exists on the server.
  """
  def tool_exists?(client \\ Client, tool_name) when is_binary(tool_name) do
    case discover(client) do
      {:ok, tools} ->
        Enum.any?(tools, fn t -> t.name == tool_name end)

      _ ->
        false
    end
  end

  ## Execution

  @doc """
  Call a tool on the MCP server.

  Returns the tool result content or an error.

  Arguments are validated against the tool's schema before sending to the server.
  """
  def call(client \\ Client, tool_name, arguments) when is_binary(tool_name) and is_map(arguments) do
    with {:ok, tool} <- get_tool(client, tool_name),
         :ok <- validate_arguments(tool, arguments),
         {:ok, response} <- Client.call_tool(client, tool_name, arguments) do
      parse_tool_result(response)
    else
      {:error, :tool_not_found} ->
        {:error, {:tool_not_found, tool_name}}

      {:error, errors} when is_list(errors) ->
        {:error, {:validation_failed, errors}}

      {:error, reason} ->
        {:error, {:call_failed, reason}}
    end
  end

  @doc """
  Call a tool and extract text content from the result.

  Useful for tools that return simple text responses.
  """
  def call_and_get_text(client \\ Client, tool_name, arguments) when is_binary(tool_name) and is_map(arguments) do
    with {:ok, result} <- call(client, tool_name, arguments),
         {:ok, text} <- extract_text(result) do
      {:ok, text}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  ## Conversion

  @doc """
  Convert MCP tools to Jido Action format.

  Returns a list of action specifications that can be used
  to register MCP tools as Jido actions.
  """
  def to_jido_actions(tools, client \\ Client) when is_list(tools) do
    Enum.map(tools, fn tool ->
      %{
        name: tool_name_to_atom(tool.name),
        description: tool.description,
        params: convert_schema_to_params(tool.input_schema),
        module: __MODULE__,
        function: :execute_jido_action,
        args: [client, tool.name]
      }
    end)
  end

  @doc """
  Execute function for Jido Action wrapper.

  This function is called by Jido when executing an MCP tool action.
  """
  def execute_jido_action(client, tool_name, arguments) do
    case call(client, tool_name, arguments) do
      {:ok, result} ->
        {:ok, format_for_jido(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Validation

  @doc """
  Validate arguments against a tool's input schema.

  Uses JSON Schema validation to ensure arguments match the tool's
  expected input format before sending to the MCP server.

  Returns `:ok` if valid, `{:error, errors}` if invalid.
  """
  def validate_arguments(tool, arguments) when is_map(tool) and is_map(arguments) do
    schema = Map.get(tool, :input_schema, tool["input_schema"] || %{})

    # If no schema, accept any arguments
    if schema == %{} do
      :ok
    else
      do_json_schema_validation(arguments, schema)
    end
  end

  # JSON Schema validation using ex_json_schema
  defp do_json_schema_validation(data, schema) do
    # Resolve the schema to get a validated root schema
    resolved_schema = ExJsonSchema.Schema.resolve(schema)

    # Validate the data against the resolved schema
    case ExJsonSchema.Validator.validate(resolved_schema, data) do
      :ok ->
        :ok

      {:error, errors} when is_list(errors) ->
        # Format errors for user-friendly display
        formatted_errors = Enum.map(errors, &format_validation_error/1)
        {:error, formatted_errors}
    end
  end

  # Format validation errors from ex_json_schema into readable messages
  defp format_validation_error(error) do
    # ex_json_schema errors look like: {"#/path/to/field", "error type"}
    {path, error_type} = error

    formatted_path =
      path
      |> String.replace("#", "")
      |> String.replace(~r|^/|, "")
      |> String.replace("/", ".")

    case error_type do
      "required" -> "Required field '#{formatted_path}' is missing"
      "type" -> "Field '#{formatted_path}' has incorrect type"
      "minimum" -> "Field '#{formatted_path}' is below minimum value"
      "maximum" -> "Field '#{formatted_path}' exceeds maximum value"
      "minLength" -> "Field '#{formatted_path}' is too short"
      "maxLength" -> "Field '#{formatted_path}' is too long"
      "pattern" -> "Field '#{formatted_path}' does not match required pattern"
      "minItems" -> "Array '#{formatted_path}' has too few items"
      "maxItems" -> "Array '#{formatted_path}' has too many items"
      "enum" -> "Field '#{formatted_path}' is not one of the allowed values"
      _ -> "Validation error at #{formatted_path}: #{error_type}"
    end
  end

  ## Private Functions

  @doc false
  def parse_tools(%{"tools" => tools}) when is_list(tools) do
    Enum.map(tools, &parse_tool/1)
  end

  @doc false
  def parse_tools(_other) do
    []
  end

  defp parse_tool(tool) when is_map(tool) do
    %{
      name: Map.get(tool, "name"),
      description: Map.get(tool, "description", ""),
      input_schema: Map.get(tool, "inputSchema", %{})
    }
  end

  @doc false
  def parse_tool_result(%{"result" => result}) when is_map(result) do
    is_error = Map.get(result, "isError", false)

    if is_error do
      {:error, {:tool_error, extract_error_content(result)}}
    else
      {:ok, %{
        content: Map.get(result, "content", []),
        is_error: is_error
      }}
    end
  end

  @doc false
  def parse_tool_result(%{"error" => error}) do
    {:error, {:rpc_error, error}}
  end

  @doc false
  def parse_tool_result(response) do
    {:error, {:unknown_format, response}}
  end

  @doc false
  def extract_text(%{content: content}) when is_list(content) do
    text_items =
      content
      |> Enum.filter(fn item -> Map.get(item, "type") == "text" end)
      |> Enum.map(fn item -> Map.get(item, "text", "") end)
      |> Enum.join("\n")

    if text_items == "" do
      {:error, :no_text_content}
    else
      {:ok, text_items}
    end
  end

  @doc false
  def extract_text(_) do
    {:error, :invalid_format}
  end

  defp extract_error_content(%{content: content}) when is_list(content) do
    Enum.map(content, fn item ->
      type = Map.get(item, "type", "unknown")
      data = Map.get(item, "text", Map.get(item, "data", ""))
      "#{type}: #{data}"
    end)
    |> Enum.join(", ")
  end

  defp extract_error_content(_) do
    "Unknown error"
  end

  defp format_for_jido(%{content: content}) do
    Enum.map(content, fn item ->
      type = Map.get(item, "type", "text")
      text = Map.get(item, "text", "")
      data = Map.get(item, "data", %{})

      case type do
        "text" -> text
        "image" -> "[Image: #{Map.get(data, "mimeType", "unknown")}]"
        "resource" -> "[Resource: #{Map.get(data, "uri", "unknown")}]"
        _ -> inspect(item)
      end
    end)
    |> Enum.join("\n")
  end

  @doc false
  def tool_name_to_atom(name) when is_binary(name) do
    name
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp convert_schema_to_params(%{"type" => "object", "properties" => props}) when is_map(props) do
    Enum.map(props, fn {name, schema} ->
      type = schema_type_to_atom(Map.get(schema, "type", "string"))
      {String.to_atom(name), type, Map.get(schema, "description", "")}
    end)
  end

  defp convert_schema_to_params(_schema) do
    []
  end

  defp schema_type_to_atom("string"), do: :string
  defp schema_type_to_atom("number"), do: :number
  defp schema_type_to_atom("integer"), do: :integer
  defp schema_type_to_atom("boolean"), do: :boolean
  defp schema_type_to_atom("array"), do: :array
  defp schema_type_to_atom("object"), do: :map
  defp schema_type_to_atom(_), do: :any
end
