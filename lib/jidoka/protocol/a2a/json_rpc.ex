defmodule Jidoka.Protocol.A2A.JSONRPC do
  @moduledoc """
  JSON-RPC 2.0 utilities for A2A communication.

  This module provides functions for building and parsing JSON-RPC 2.0
  requests, responses, and errors following the official specification.

  ## JSON-RPC 2.0 Specification Summary

  A JSON-RPC request has this format:
  ```json
  {
    "jsonrpc": "2.0",
    "method": "method.name",
    "params": {...},
    "id": 1
  }
  ```

  A response has this format:
  ```json
  {
    "jsonrpc": "2.0",
    "result": {...},
    "id": 1
  }
  ```

  An error response:
  ```json
  {
    "jsonrpc": "2.0",
    "error": {
      "code": -32601,
      "message": "Method not found",
      "data": null
    },
    "id": 1
  }
  ```

  ## Examples

      iex> req = JSONRPC.request("ping", %{}, 1)
      iex> req["method"]
      "ping"

      iex> resp = JSONRPC.success_response(1, %{status: "ok"})
      iex> resp["result"]
      %{status: "ok"}

      iex> err = JSONRPC.error_response(1, -32601, "Method not found")
      iex> err["error"]["code"]
      -32601

  """

  require Logger

  # Standard JSON-RPC 2.0 error codes
  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602
  @internal_error -32603

  @type request :: %{
          jsonrpc: String.t(),
          method: String.t(),
          params: map() | [map()],
          id: integer() | String.t() | nil
        }

  @type response :: %{
          jsonrpc: String.t(),
          result: term() | nil,
          error: error() | nil,
          id: integer() | String.t() | nil
        }

  @type error :: %{
          code: integer(),
          message: String.t(),
          data: term() | nil
        }

  # ===========================================================================
  # Request Building
  # ===========================================================================

  @doc """
  Builds a JSON-RPC 2.0 request map.

  ## Parameters

  - `method` - The method name to invoke
  - `params` - The parameters for the method (map or list)
  - `id` - Request identifier (integer or string)

  ## Examples

      iex> req = JSONRPC.request("agent.send_message", %{to: "agent:test"}, 1)
      iex> req["jsonrpc"]
      "2.0"
      iex> req["method"]
      "agent.send_message"

  """
  @spec request(String.t(), map() | list(), integer() | String.t()) :: request()
  def request(method, params, id) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    }
  end

  @doc """
  Builds a JSON-RPC 2.0 notification (no ID, no response expected).

  ## Examples

      iex> notif = JSONRPC.notification("agent.status_changed", %{status: "ready"})
      iex> Map.has_key?(notif, "id")
      false

  """
  @spec notification(String.t(), map() | list()) :: map()
  def notification(method, params) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }
  end

  # ===========================================================================
  # Response Building
  # ===========================================================================

  @doc """
  Builds a JSON-RPC 2.0 success response.

  ## Examples

      iex> resp = JSONRPC.success_response(1, %{result: "success"})
      iex> resp["result"]
      %{result: "success"}

  """
  @spec success_response(integer() | String.t(), term()) :: response()
  def success_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "result" => result,
      "id" => id
    }
  end

  @doc """
  Builds a JSON-RPC 2.0 error response.

  ## Parameters

  - `id` - The request ID
  - `code` - Error code (use standard codes or custom)
  - `message` - Human-readable error message
  - `data` - Optional additional error data

  ## Examples

      iex> err = JSONRPC.error_response(1, -32601, "Method not found")
      iex> err["error"]["code"]
      -32601

  """
  @spec error_response(integer() | String.t(), integer(), String.t(), term() | nil) :: response()
  def error_response(id, code, message, data \\ nil) do
    error_map = %{
      "code" => code,
      "message" => message
    }

    error_map = if data, do: Map.put(error_map, "data", data), else: error_map

    %{
      "jsonrpc" => "2.0",
      "error" => error_map,
      "id" => id
    }
  end

  # ===========================================================================
  # Response Parsing
  # ===========================================================================

  @doc """
  Parses a JSON-RPC response map, returning `{:ok, :success, result}` or
  `{:ok, :error, error_map}` or `{:error, :invalid_response}`.

  ## Examples

      iex> resp = %{"jsonrpc" => "2.0", "result" => %{data: 1}, "id" => 1}
      iex> JSONRPC.parse_response(resp)
      {:ok, :success, %{data: 1}}

      iex> err = %{"jsonrpc" => "2.0", "error" => %{"code" => -1, "message" => "fail"}, "id" => 1}
      iex> JSONRPC.parse_response(err)
      {:ok, :error, %{"code" => -1, "message" => "fail"}}

  """
  def parse_response(%{"jsonrpc" => "2.0", "result" => result, "id" => _id}) do
    {:ok, :success, result}
  end

  def parse_response(%{"jsonrpc" => "2.0", "error" => error, "id" => _id}) do
    {:ok, :error, error}
  end

  def parse_response(_other) do
    {:error, :invalid_response}
  end

  # ===========================================================================
  # Request Parsing
  # ===========================================================================

  @doc """
  Parses a JSON-RPC request map, returning `{:ok, method, params, id}` or
  `{:ok, :notification, method, params}` or `{:error, reason}`.

  ## Examples

      iex> req = %{"jsonrpc" => "2.0", "method" => "ping", "params" => %{}, "id" => 1}
      iex> JSONRPC.parse_request(req)
      {:ok, :request, "ping", %{}, 1}

      iex> notif = %{"jsonrpc" => "2.0", "method" => "ping", "params" => %{}}
      iex> JSONRPC.parse_request(notif)
      {:ok, :notification, "ping", %{}}

  """
  def parse_request(%{"jsonrpc" => "2.0", "method" => method, "id" => id} = req) do
    params = Map.get(req, "params", %{})
    {:ok, :request, method, params, id}
  end

  def parse_request(%{"jsonrpc" => "2.0", "method" => method} = req) do
    params = Map.get(req, "params", %{})
    {:ok, :notification, method, params}
  end

  def parse_request(_other) do
    {:error, :invalid_request}
  end

  # ===========================================================================
  # Validation
  # ===========================================================================

  @doc """
  Validates a JSON-RPC request map.

  Returns `:ok` if valid, `{:error, reason}` if invalid.

  """
  def validate_request(%{"jsonrpc" => "2.0", "method" => method} = req)
      when is_binary(method) and method != "" do
    case Map.get(req, "id") do
      nil -> :ok  # Notification is valid
      id when is_integer(id) or is_binary(id) -> :ok
      _ -> {:error, {:invalid_id, "ID must be integer or string"}}
    end
  end

  def validate_request(%{"jsonrpc" => version}) do
    {:error, {:invalid_version, "Expected '2.0', got: #{version}"}}
  end

  def validate_request(_other) do
    {:error, :invalid_request}
  end

  @doc """
  Validates a JSON-RPC response map.

  Returns `:ok` if valid, `{:error, reason}` if invalid.

  """
  def validate_response(%{"jsonrpc" => "2.0", "id" => _id}) do
    :ok
  end

  def validate_response(%{"jsonrpc" => "2.0"}) do
    # Responses without ID are technically invalid per spec, but some servers do this
    {:error, :missing_id}
  end

  def validate_response(_other) do
    {:error, :invalid_response}
  end

  # ===========================================================================
  # Error Constants
  # ===========================================================================

  @doc """
  Returns the standard JSON-RPC 2.0 parse error code.

  """
  def parse_error, do: @parse_error

  @doc """
  Returns the standard JSON-RPC 2.0 invalid request error code.

  """
  def invalid_request, do: @invalid_request

  @doc """
  Returns the standard JSON-RPC 2.0 method not found error code.

  """
  def method_not_found, do: @method_not_found

  @doc """
  Returns the standard JSON-RPC 2.0 invalid params error code.

  """
  def invalid_params, do: @invalid_params

  @doc """
  Returns the standard JSON-RPC 2.0 internal error code.

  """
  def internal_error, do: @internal_error

  # ===========================================================================
  # Encoding/Decoding
  # ===========================================================================

  @doc """
  Encodes a JSON-RPC request or response map to JSON string.

  """
  @spec encode(map()) :: {:ok, String.t()} | {:error, term()}
  def encode(data) when is_map(data) do
    case Jason.encode(data) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:encode_error, reason}}
    end
  end

  @doc """
  Decodes a JSON string to a map.

  """
  @spec decode(String.t()) :: {:ok, map()} | {:error, term()}
  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  @doc """
  Encodes and then validates a request, returning `{:ok, json_string}` or `{:error, reason}`.

  """
  @spec encode_request(request()) :: {:ok, String.t()} | {:error, term()}
  def encode_request(request) do
    with :ok <- validate_request(request),
         {:ok, json} <- encode(request) do
      {:ok, json}
    end
  end

  @doc """
  Decodes and then validates a response, returning `{:ok, response_map}` or `{:error, reason}`.

  """
  @spec decode_response(String.t()) :: {:ok, map()} | {:error, term()}
  def decode_response(json_string) when is_binary(json_string) do
    with {:ok, data} <- decode(json_string),
         :ok <- validate_response(data) do
      {:ok, data}
    end
  end
end
