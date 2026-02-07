defmodule Jidoka.ProtocolSupervisorTest do
  use ExUnit.Case, async: false

  # Note: These tests require the application to be started
  # because ProtocolSupervisor is started by the Application

  describe "list_protocols/0" do
    test "lists all active protocol supervisors" do
      protocols = Jidoka.ProtocolSupervisor.list_protocols()
      assert is_list(protocols)

      # Check that each protocol is a {module, pid} tuple
      Enum.each(protocols, fn
        {module, pid} when is_atom(module) and is_pid(pid) ->
          assert Process.alive?(pid)

        _ ->
          flunk("Invalid protocol format")
      end)
    end

    test "includes MCP ConnectionSupervisor when configured" do
      protocols = Jidoka.ProtocolSupervisor.list_protocols()
      module_names = Enum.map(protocols, fn {module, _pid} -> module end)

      assert Jidoka.Protocol.MCP.ConnectionSupervisor in module_names
    end

    test "includes Phoenix ConnectionSupervisor when configured" do
      protocols = Jidoka.ProtocolSupervisor.list_protocols()
      module_names = Enum.map(protocols, fn {module, _pid} -> module end)

      assert Jidoka.Protocol.Phoenix.ConnectionSupervisor in module_names
    end

    test "includes A2A ConnectionSupervisor when configured" do
      protocols = Jidoka.ProtocolSupervisor.list_protocols()
      module_names = Enum.map(protocols, fn {module, _pid} -> module end)

      assert Jidoka.Protocol.A2A.ConnectionSupervisor in module_names
    end
  end

  describe "health/0" do
    test "returns aggregated health status for all protocols" do
      health = Jidoka.ProtocolSupervisor.health()
      assert is_map(health)

      # Check for expected protocol keys
      assert Map.has_key?(health, :mcp)
      assert Map.has_key?(health, :phoenix)
      assert Map.has_key?(health, :a2a)
    end

    test "mcp health includes active_connections" do
      health = Jidoka.ProtocolSupervisor.health()
      mcp_health = health[:mcp]

      assert Map.has_key?(mcp_health, :status)
      assert Map.has_key?(mcp_health, :active_connections)
      assert is_integer(mcp_health.active_connections)
    end

    test "phoenix health includes active_connections" do
      health = Jidoka.ProtocolSupervisor.health()
      phoenix_health = health[:phoenix]

      assert Map.has_key?(phoenix_health, :status)
      assert Map.has_key?(phoenix_health, :active_connections)
      assert is_integer(phoenix_health.active_connections)
    end

    test "a2a health includes active_gateways" do
      health = Jidoka.ProtocolSupervisor.health()
      a2a_health = health[:a2a]

      assert Map.has_key?(a2a_health, :status)
      assert Map.has_key?(a2a_health, :active_gateways)
      assert is_integer(a2a_health.active_gateways)
    end
  end

  describe "protocol_status/1" do
    test "returns status for MCP ConnectionSupervisor" do
      status = Jidoka.ProtocolSupervisor.protocol_status(Jidoka.Protocol.MCP.ConnectionSupervisor)

      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :type)
      assert status.type == :mcp
    end

    test "returns status for Phoenix ConnectionSupervisor" do
      status = Jidoka.ProtocolSupervisor.protocol_status(Jidoka.Protocol.Phoenix.ConnectionSupervisor)

      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :type)
      assert status.type == :phoenix
    end

    test "returns status for A2A ConnectionSupervisor" do
      status = Jidoka.ProtocolSupervisor.protocol_status(Jidoka.Protocol.A2A.ConnectionSupervisor)

      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :type)
      assert status.type == :a2a
    end

    test "returns not_found for unknown protocol" do
      status = Jidoka.ProtocolSupervisor.protocol_status(Jidoka.Unknown.Protocol)

      assert status.status == :not_found
      assert is_nil(status.pid)
    end
  end

  describe "start_protocol/2" do
    test "starts a protocol dynamically" do
      # Define a test protocol module
      defmodule TestProtocol.Dynamic do
        use DynamicSupervisor

        def start_link(opts) do
          DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
        end

        def init(_opts) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end

      # Start the test protocol
      assert {:ok, pid} = Jidoka.ProtocolSupervisor.start_protocol(TestProtocol.Dynamic)
      assert Process.alive?(pid)

      # Verify it's in the list
      protocols = Jidoka.ProtocolSupervisor.list_protocols()
      protocol_names = Enum.map(protocols, fn {module, _pid} -> module end)
      assert TestProtocol.Dynamic in protocol_names

      # Clean up
      :ok = Jidoka.ProtocolSupervisor.stop_protocol(TestProtocol.Dynamic)
    end

    test "returns ok if protocol already started" do
      # MCP is already started
      assert {:ok, _pid} = Jidoka.ProtocolSupervisor.start_protocol(Jidoka.Protocol.MCP.ConnectionSupervisor)
    end
  end

  describe "stop_protocol/1" do
    test "stops a running protocol" do
      # Define a test protocol module
      defmodule TestProtocol.ToStop do
        use DynamicSupervisor

        def start_link(opts) do
          DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
        end

        def init(_opts) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end

      # Start the test protocol
      {:ok, _pid} = Jidoka.ProtocolSupervisor.start_protocol(TestProtocol.ToStop)

      # Stop it
      assert :ok = Jidoka.ProtocolSupervisor.stop_protocol(TestProtocol.ToStop)

      # Verify it's no longer in the list
      protocols = Jidoka.ProtocolSupervisor.list_protocols()
      protocol_names = Enum.map(protocols, fn {module, _pid} -> module end)
      refute TestProtocol.ToStop in protocol_names
    end

    test "returns error for non-existent protocol" do
      assert {:error, :not_found} = Jidoka.ProtocolSupervisor.stop_protocol(Unknown.Protocol)
    end
  end

  describe "integration" do
    test "protocol supervisors are children of ProtocolSupervisor" do
      # Get ProtocolSupervisor's children (which are the connection supervisors)
      children = DynamicSupervisor.which_children(Jidoka.ProtocolSupervisor)

      # The children should be the connection supervisor processes
      # We verify by checking if at least some children exist
      assert length(children) > 0

      # Verify each child is a process
      Enum.each(children, fn
        {_id, pid, _type, _modules} when is_pid(pid) ->
          assert Process.alive?(pid)

        _ ->
          :ok
      end)
    end
  end
end
