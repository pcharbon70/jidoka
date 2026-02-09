defmodule Jidoka.Protocol.MCP.ErrorHandler do
  @moduledoc """
  Error handling and translation for MCP protocol errors.

  This module provides functions for parsing and translating
  JSON-RPC and MCP-specific errors into user-friendly formats.

  ## JSON-RPC Error Codes

  * `-32700` - Parse error: Invalid JSON was received
  * `-32600` - Invalid request: The JSON sent is not a valid Request object
  * `-32601` - Method not found: The method does not exist / is not available
  * `-32602` - Invalid params: Invalid method parameter(s)
  * `-32603` - Internal error: Internal JSON-RPC error
  * `-32000 to -32099` - Server error: Reserved for implementation-defined server errors

  ## Example

      case response do
        %{"error" => error} ->
          {:error, ErrorHandler.translate(error)}
        %{"result" => result} ->
          {:ok, result}
      end
  """

  require Logger

  @type json_rpc_error :: %{
          code: integer(),
          message: String.t(),
          data: term() | nil
        }

  @type translated_error :: {
          atom(),    # Error category
          String.t() | nil,  # Human-readable message
          term() | nil   # Additional data
        }

  ## JSON-RPC Error Codes

  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602
  @internal_error -32603
  @server_error_start -32000
  @server_error_end -32099

  ## Translation Functions

  @doc """
  Translate a JSON-RPC error map to a user-friendly error tuple.

  Returns `{category, message, data}` where category is an atom
  describing the error type.
  """
  def translate(%{"code" => code, "message" => message, "data" => data}) do
    translate_error(code, message, data)
  end

  def translate(%{"code" => code, "message" => message}) do
    translate_error(code, message, nil)
  end

  def translate(error) do
    {:unknown_error, "Unexpected error format", error}
  end

  @doc """
  Check if a response is an error response.
  """
  def error?(%{"error" => _}), do: true
  def error?(%{"result" => %{"isError" => true}}), do: true
  def error?(_), do: false

  @doc """
  Extract error from a response, if present.
  """
  def extract(%{"error" => error}), do: {:error, translate(error)}
  def extract(%{"result" => %{"isError" => true} = result}), do: {:error, {:tool_error, result}}
  def extract(%{"result" => result}), do: {:ok, result}
  def extract(response), do: {:error, {:unknown_format, response}}

  ## Error Categories

  @doc """
  Check if an error is a parse error.
  """
  def parse_error?(%{"code" => code}), do: code == @parse_error
  def parse_error?({:parse_error, _, _}), do: true
  def parse_error?(_), do: false

  @doc """
  Check if an error is a method not found error.
  """
  def method_not_found?(%{"code" => code}), do: code == @method_not_found
  def method_not_found?({:method_not_found, _, _}), do: true
  def method_not_found?(_), do: false

  @doc """
  Check if an error is an invalid params error.
  """
  def invalid_params?(%{"code" => code}), do: code == @invalid_params
  def invalid_params?({:invalid_params, _, _}), do: true
  def invalid_params?(_), do: false

  @doc """
  Check if an error is a server error.
  """
  def server_error?(%{"code" => code}) do
    # Server error codes are negative: -32000 to -32099
    code <= @server_error_start and code >= @server_error_end
  end
  def server_error?({:server_error, _, _}), do: true
  def server_error?(_), do: false

  @doc """
  Format an error for logging or display.
  """
  # Special formatting for unknown_error (must come before general atom clause)
  def format({:unknown_error, message, data}) do
    formatted = "[Unknown Error] #{message}"

    if data do
      formatted <> " - " <> inspect(data)
    else
      formatted
    end
  end

  def format({category, message, data}) when is_atom(category) do
    formatted = "[#{Atom.to_string(category)}] #{message}"

    if data do
      formatted <> " - " <> inspect(data)
    else
      formatted
    end
  end

  def format({:tool_error, result}) do
    content = Map.get(result, "content", [])
    "[Tool Error] " <> extract_content_text(content)
  end

  def format(other) do
    "[Error] #{inspect(other)}"
  end

  @doc """
  Log an error with appropriate level.
  """
  def log(error, level \\ :error) do
    message = format(error)
    Logger.log(level, message)
    error
  end

  ## Private Functions

  defp translate_error(@parse_error, message, data) do
    {:parse_error, "Invalid JSON received", maybe_add_data(message, data)}
  end

  defp translate_error(@invalid_request, message, data) do
    {:invalid_request, "Invalid request format", maybe_add_data(message, data)}
  end

  defp translate_error(@method_not_found, message, data) do
    {:method_not_found, "Method not found on server", maybe_add_data(message, data)}
  end

  defp translate_error(@invalid_params, message, data) do
    case data do
      %{"field" => field, "reason" => reason} ->
        {:invalid_params, "Invalid parameter for #{field}: #{reason}", data}

      _ ->
        {:invalid_params, message, data}
    end
  end

  defp translate_error(@internal_error, message, data) do
    {:internal_error, "Server internal error", maybe_add_data(message, data)}
  end

  defp translate_error(code, message, data) when code <= @server_error_start and code >= @server_error_end do
    # Note: server error codes are negative, so we check reverse
    {:server_error, message, data}
  end

  defp translate_error(code, message, data) do
    {:unknown_error, "Unknown error code: #{code}", maybe_add_data(message, data)}
  end

  defp maybe_add_data(message, nil), do: message
  defp maybe_add_data(message, data), do: "#{message}: #{inspect(data)}"

  defp extract_content_text(content) when is_list(content) do
    content
    |> Enum.map(fn item -> Map.get(item, "text", "") end)
    |> Enum.join(", ")
  end

  defp extract_content_text(_), do: ""
end
