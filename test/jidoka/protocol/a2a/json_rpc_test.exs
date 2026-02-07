defmodule Jidoka.Protocol.A2A.JSONRPCTest do
  use ExUnit.Case, async: true

  alias Jidoka.Protocol.A2A.JSONRPC

  doctest JSONRPC

  describe "request/3" do
    test "creates a valid JSON-RPC 2.0 request" do
      request = JSONRPC.request("test.method", %{"key" => "value"}, 1)

      assert request["jsonrpc"] == "2.0"
      assert request["method"] == "test.method"
      assert request["params"] == %{"key" => "value"}
      assert request["id"] == 1
    end

    test "creates request with string params" do
      request = JSONRPC.request("agent.ping", "hello", 42)

      assert request["method"] == "agent.ping"
      assert request["params"] == "hello"
      assert request["id"] == 42
    end

    test "creates request with list params" do
      request = JSONRPC.request("agent.send", ["arg1", "arg2"], 3)

      assert request["method"] == "agent.send"
      assert request["params"] == ["arg1", "arg2"]
    end
  end

  describe "notification/2" do
    test "creates a valid JSON-RPC 2.0 notification" do
      notification = JSONRPC.notification("event.happened", %{"data" => "value"})

      assert notification["jsonrpc"] == "2.0"
      assert notification["method"] == "event.happened"
      assert notification["params"] == %{"data" => "value"}
      refute Map.has_key?(notification, "id")
    end
  end

  describe "success_response/2" do
    test "creates a success response with result" do
      response = JSONRPC.success_response(1, %{"status" => "ok"})

      assert response["jsonrpc"] == "2.0"
      assert response["result"] == %{"status" => "ok"}
      assert response["id"] == 1
      refute Map.has_key?(response, "error")
    end

    test "creates success response with null id" do
      response = JSONRPC.success_response(nil, %{"done" => true})

      assert response["result"] == %{"done" => true}
      assert response["id"] == nil
    end
  end

  describe "error_response/4" do
    test "creates an error response with code and message" do
      response = JSONRPC.error_response(1, -32601, "Method not found")

      assert response["jsonrpc"] == "2.0"
      assert response["error"]["code"] == -32601
      assert response["error"]["message"] == "Method not found"
      assert response["id"] == 1
      refute Map.has_key?(response, "result")
    end

    test "creates error response with data" do
      response = JSONRPC.error_response(1, -32602, "Invalid params", %{"field" => "name"})

      assert response["error"]["code"] == -32602
      assert response["error"]["message"] == "Invalid params"
      assert response["error"]["data"] == %{"field" => "name"}
    end
  end

  describe "parse_response/1" do
    test "parses a success response" do
      response = %{
        "jsonrpc" => "2.0",
        "result" => %{"status" => "ok"},
        "id" => 1
      }

      assert {:ok, :success, %{"status" => "ok"}} = JSONRPC.parse_response(response)
    end

    test "parses an error response" do
      response = %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => -32601, "message" => "Method not found"},
        "id" => 1
      }

      assert {:ok, :error, %{"code" => -32601, "message" => "Method not found"}} =
               JSONRPC.parse_response(response)
    end

    test "returns error for invalid response" do
      response = %{"invalid" => "response"}

      assert {:error, :invalid_response} = JSONRPC.parse_response(response)
    end

    test "returns error for missing jsonrpc version" do
      response = %{
        "result" => %{"status" => "ok"},
        "id" => 1
      }

      assert {:error, :invalid_response} = JSONRPC.parse_response(response)
    end

    test "returns error for response with neither result nor error" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1
      }

      assert {:error, :invalid_response} = JSONRPC.parse_response(response)
    end
  end

  describe "parse_request/1" do
    test "parses a request with id" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "agent.ping",
        "params" => %{"from" => "agent:test"},
        "id" => 1
      }

      assert {:ok, :request, "agent.ping", %{"from" => "agent:test"}, 1} =
               JSONRPC.parse_request(request)
    end

    test "parses a notification (no id)" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "agent.ping",
        "params" => %{"from" => "agent:test"}
      }

      assert {:ok, :notification, "agent.ping", %{"from" => "agent:test"}} =
               JSONRPC.parse_request(request)
    end

    test "parses request without params" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "agent.ping",
        "id" => 1
      }

      assert {:ok, :request, "agent.ping", nil, 1} = JSONRPC.parse_request(request)
    end

    test "returns error for invalid request" do
      request = %{"invalid" => "request"}

      assert {:error, :invalid_request} = JSONRPC.parse_request(request)
    end

    test "returns error for missing method" do
      request = %{
        "jsonrpc" => "2.0",
        "params" => %{},
        "id" => 1
      }

      assert {:error, :invalid_request} = JSONRPC.parse_request(request)
    end
  end

  describe "error code constants" do
    test "provides standard JSON-RPC error codes" do
      assert JSONRPC.parse_error() == -32700
      assert JSONRPC.invalid_request() == -32600
      assert JSONRPC.method_not_found() == -32601
      assert JSONRPC.invalid_params() == -32602
      assert JSONRPC.internal_error() == -32603
    end
  end

  describe "roundtrip" do
    test "request -> parse_response preserves data" do
      original_request = JSONRPC.request("agent.send", %{"message" => "hello"}, 1)
      # Simulate a response
      response = JSONRPC.success_response(1, %{"delivered" => true})

      assert {:ok, :success, %{"delivered" => true}} = JSONRPC.parse_response(response)
    end

    test "parse_request -> response roundtrip" do
      incoming = %{
        "jsonrpc" => "2.0",
        "method" => "agent.ping",
        "params" => %{"from" => "agent:test"},
        "id" => 42
      }

      assert {:ok, :request, "agent.ping", %{"from" => "agent:test"}, 42} =
               JSONRPC.parse_request(incoming)

      response = JSONRPC.success_response(42, %{"pong" => true})
      assert response["id"] == 42
    end
  end
end
