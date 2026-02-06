defmodule Jidoka.Protocol.MCP.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias Jidoka.Protocol.MCP.ErrorHandler

  describe "translate/1" do
    test "translates parse error" do
      error = %{"code" => -32700, "message" => "Parse error"}
      assert {:parse_error, _, _} = ErrorHandler.translate(error)
    end

    test "translates invalid request error" do
      error = %{"code" => -32600, "message" => "Invalid Request"}
      assert {:invalid_request, _, _} = ErrorHandler.translate(error)
    end

    test "translates method not found error" do
      error = %{"code" => -32601, "message" => "Method not found"}
      assert {:method_not_found, _, _} = ErrorHandler.translate(error)
    end

    test "translates invalid params error with field data" do
      error = %{
        "code" => -32602,
        "message" => "Invalid params",
        "data" => %{"field" => "arg1", "reason" => "required"}
      }

      assert {:invalid_params, "Invalid parameter for arg1: required", _} =
               ErrorHandler.translate(error)
    end

    test "translates internal error" do
      error = %{"code" => -32603, "message" => "Internal error"}
      assert {:internal_error, _, _} = ErrorHandler.translate(error)
    end

    test "translates server error" do
      error = %{"code" => -32001, "message" => "Server error"}
      assert {:server_error, "Server error", _} = ErrorHandler.translate(error)
    end

    test "translates unknown error code" do
      error = %{"code" => -32099, "message" => "Unknown server error"}
      assert {:server_error, _, _} = ErrorHandler.translate(error)
    end

    test "handles error without data" do
      error = %{"code" => -32601, "message" => "Method not found"}
      assert {:method_not_found, "Method not found on server", _} = ErrorHandler.translate(error)
    end

    test "handles unexpected format" do
      assert {:unknown_error, _, _} = ErrorHandler.translate(%{"unexpected" => "format"})
      assert {:unknown_error, _, _} = ErrorHandler.translate("not a map")
    end
  end

  describe "error?/1" do
    test "returns true for error response" do
      assert ErrorHandler.error?(%{"error" => %{"code" => -32601}})
    end

    test "returns true for tool error result" do
      assert ErrorHandler.error?(%{"result" => %{"isError" => true}})
    end

    test "returns false for normal result" do
      refute ErrorHandler.error?(%{"result" => %{"data" => "success"}})
    end

    test "returns false for unexpected format" do
      refute ErrorHandler.error?(%{"unexpected" => "format"})
    end
  end

  describe "extract/1" do
    test "extracts error from error response" do
      response = %{"error" => %{"code" => -32601, "message" => "Method not found"}}
      assert {:error, _} = ErrorHandler.extract(response)
    end

    test "extracts error from tool error result" do
      response = %{"result" => %{"isError" => true, "content" => []}}
      assert {:error, {:tool_error, _}} = ErrorHandler.extract(response)
    end

    test "extracts ok result" do
      response = %{"result" => %{"data" => "success"}}
      assert {:ok, %{"data" => "success"}} = ErrorHandler.extract(response)
    end
  end

  describe "parse_error?/1" do
    test "returns true for parse error code" do
      assert ErrorHandler.parse_error?(%{"code" => -32700})
    end

    test "returns true for parse error tuple" do
      assert ErrorHandler.parse_error?({:parse_error, "msg", nil})
    end

    test "returns false for other errors" do
      refute ErrorHandler.parse_error?(%{"code" => -32601})
      refute ErrorHandler.parse_error?({:method_not_found, "msg", nil})
    end
  end

  describe "method_not_found?/1" do
    test "returns true for method not found code" do
      assert ErrorHandler.method_not_found?(%{"code" => -32601})
    end

    test "returns true for method not found tuple" do
      assert ErrorHandler.method_not_found?({:method_not_found, "msg", nil})
    end

    test "returns false for other errors" do
      refute ErrorHandler.method_not_found?(%{"code" => -32700})
      refute ErrorHandler.method_not_found?({:parse_error, "msg", nil})
    end
  end

  describe "invalid_params?/1" do
    test "returns true for invalid params code" do
      assert ErrorHandler.invalid_params?(%{"code" => -32602})
    end

    test "returns true for invalid params tuple" do
      assert ErrorHandler.invalid_params?({:invalid_params, "msg", nil})
    end

    test "returns false for other errors" do
      refute ErrorHandler.invalid_params?(%{"code" => -32601})
      refute ErrorHandler.invalid_params?({:method_not_found, "msg", nil})
    end
  end

  describe "server_error?/1" do
    test "returns true for server error codes" do
      assert ErrorHandler.server_error?(%{"code" => -32000})
      assert ErrorHandler.server_error?(%{"code" => -32050})
      assert ErrorHandler.server_error?(%{"code" => -32099})
    end

    test "returns true for server error tuple" do
      assert ErrorHandler.server_error?({:server_error, "msg", nil})
    end

    test "returns false for other error codes" do
      refute ErrorHandler.server_error?(%{"code" => -32603})
      refute ErrorHandler.server_error?(%{"code" => -31999})
      refute ErrorHandler.server_error?(%{"code" => -32100})
    end
  end

  describe "format/1" do
    test "formats parse error" do
      assert "[parse_error] Invalid JSON received" =
               ErrorHandler.format({:parse_error, "Invalid JSON received", nil})
    end

    test "formats error with data" do
      formatted = ErrorHandler.format({:parse_error, "Invalid JSON", "syntax error"})
      assert String.contains?(formatted, "syntax error")
    end

    test "formats tool error" do
      result = %{"isError" => true, "content" => [%{"type" => "text", "text" => "Error message"}]}
      assert "[Tool Error] Error message" = ErrorHandler.format({:tool_error, result})
    end

    test "formats unknown error" do
      assert "[Unknown Error] Unknown error code: 12345" =
               ErrorHandler.format({:unknown_error, "Unknown error code: 12345", nil})
    end
  end
end
