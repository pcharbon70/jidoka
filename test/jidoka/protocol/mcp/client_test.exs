defmodule Jidoka.Protocol.MCP.ClientTest do
  use ExUnit.Case, async: false

  alias Jidoka.Protocol.MCP.Client

  describe "start_link/1" do
    test "requires transport configuration" do
      assert_raise ArgumentError, fn ->
        Client.start_link([])
      end
    end

    test "starts with STDIO transport using cat for testing" do
      # Note: This test spawns a real process (cat)
      # In a real integration scenario, you'd use an actual MCP server
      assert {:ok, _pid} = Client.start_link(transport: {:stdio, command: "cat"})
    end

    test "fails with HTTP transport (not implemented)" do
      assert {:error, {:transport_error, :http_not_yet_implemented}} =
               Client.start_link(transport: {:http, url: "http://localhost"})
    end
  end
end
