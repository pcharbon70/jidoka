defmodule Jidoka.Protocol.A2A.GatewayTest do
  use ExUnit.Case, async: false

  alias Jidoka.Protocol.A2A.{Gateway, Registry, AgentCard, JSONRPC}

  @moduletag :capture_log

  setup do
    # Start registry for testing
    case Registry.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Start a test gateway
    start_gateway()
    register_test_agents()

    :ok
  end

  defp start_gateway do
    case Gateway.start_link(name: :test_a2a_gateway) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp register_test_agents do
    # Register this test process as an agent that can receive messages
    Registry.register(:test_agent, self())
  end

  describe "start_link/1" do
    test "starts the gateway with defaults" do
      assert {:ok, pid} = Gateway.start_link(name: :test_gateway_1)
      assert Process.alive?(pid)
      assert :ready = Gateway.status(:test_gateway_1)
    end

    test "starts the gateway with custom agent card" do
      assert {:ok, pid} =
               Gateway.start_link(
                 name: :test_gateway_2,
                 agent_card: %{
                   name: "Custom Gateway",
                   types: ["Custom"]
                 }
               )

      assert Process.alive?(pid)

      {:ok, card} = Gateway.get_agent_card(:test_gateway_2)
      assert card.name == "Custom Gateway"
    end
  end

  describe "status/1" do
    test "returns current gateway status" do
      assert :ready = Gateway.status(:test_a2a_gateway)
    end
  end

  describe "get_agent_card/1" do
    test "returns the gateway's agent card" do
      {:ok, card} = Gateway.get_agent_card(:test_a2a_gateway)

      assert card.id == "agent:jidoka:coordinator"
      assert card.name == "Jidoka"
      assert is_list(card.type)
    end
  end

  describe "discover_agent/2" do
    test "returns known agent from configuration" do
      # Add a known agent to config
      Application.put_env(:jidoka, :a2a_gateway,
        known_agents: %{
          "agent:known:test" => %{
            agent_card: %{
              id: "agent:known:test",
              name: "Known Agent",
              type: ["Test"]
            }
          }
        },
        persistent: false
      )

      # Restart gateway to pick up config
      Gateway.start_link(name: :test_gateway_known)

      {:ok, card} = Gateway.discover_agent(:test_gateway_known, "agent:known:test")

      assert card.id == "agent:known:test"
      assert card.name == "Known Agent"
    end

    test "caches discovered agents" do
      # First call discovers
      {:ok, _card} = Gateway.discover_agent(:test_gateway_known, "agent:known:test")

      # Second call should use cache
      {:ok, card} = Gateway.discover_agent(:test_gateway_known, "agent:known:test")

      assert card.id == "agent:known:test"
    end

    test "returns error for unknown agent" do
      assert {:error, :not_found} =
               Gateway.discover_agent(:test_a2a_gateway, "agent:unknown:agent")
    end
  end

  describe "list_agents/1" do
    test "lists all known and discovered agents" do
      agents = Gateway.list_agents(:test_a2a_gateway)
      assert is_list(agents)
    end
  end

  describe "register_local_agent/2" do
    test "registers a local agent to receive messages" do
      test_agent = self()
      assert :ok = Gateway.register_local_agent(:local_test, test_agent)

      # Verify registration
      assert {:ok, ^test_agent} = Registry.lookup(:local_test)
    end
  end

  describe "handle_incoming/2" do
    test "handles valid JSON-RPC request" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "agent.send_message",
        "params" => %{
          "from" => "agent:external:sender",
          "to" => "agent:jidoka:test_agent",
          "message" => %{"text" => "Hello!"}
        },
        "id" => 1
      }

      {:ok, response} = Gateway.handle_incoming(:test_a2a_gateway, request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["status"] == "delivered"

      # Verify message was delivered
      assert_receive {:a2a_message, "agent:external:sender", %{"text" => "Hello!"}}
    end

    test "handles JSON-RPC notification" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "agent.ping",
        "params" => %{
          "from" => "agent:external:pinger"
        }
      }

      {:ok, response} = Gateway.handle_incoming(:test_a2a_gateway, request)

      # Notifications get a simple ack
      assert response["result"]["status"] == "received"
    end

    test "returns error for invalid request" do
      request = %{"invalid" => "request"}

      {:ok, response} = Gateway.handle_incoming(:test_a2a_gateway, request)

      assert response["error"]
      assert response["error"]["code"] == JSONRPC.invalid_request()
    end

    test "returns error for message to unregistered agent" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "agent.send_message",
        "params" => %{
          "from" => "agent:external:sender",
          "to" => "agent:jidoka:nonexistent",
          "message" => %{"text" => "Hello!"}
        },
        "id" => 1
      }

      {:ok, response} = Gateway.handle_incoming(:test_a2a_gateway, request)

      assert response["error"]
      assert response["error"]["code"] == JSONRPC.method_not_found()
    end

    test "returns error for message to not allowed agent" do
      # Register an agent that's not in the allowed list
      Registry.register(:forbidden_agent)

      request = %{
        "jsonrpc" => "2.0",
        "method" => "agent.send_message",
        "params" => %{
          "from" => "agent:external:sender",
          "to" => "agent:jidoka:forbidden_agent",
          "message" => %{"text" => "Hello!"}
        },
        "id" => 1
      }

      {:ok, response} = Gateway.handle_incoming(:test_a2a_gateway, request)

      assert response["error"]
      assert response["error"]["code"] == JSONRPC.method_not_found()
    end
  end

  describe "agent.send_message method" do
    test "routes messages to local agents" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "agent.send_message",
        "params" => %{
          "from" => "agent:external:sender",
          "to" => "agent:jidoka:test_agent",
          "message" => %{"content" => "Test message"}
        },
        "id" => 1
      }

      {:ok, response} = Gateway.handle_incoming(:test_a2a_gateway, request)

      assert response["result"]["status"] == "delivered"
      assert response["result"]["from"] == "agent:jidoka:coordinator"

      assert_receive {:a2a_message, "agent:external:sender",
                      %{"content" => "Test message"}}
    end
  end

  describe "agent.ping notification" do
    test "handles ping notification" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "agent.ping",
        "params" => %{
          "from" => "agent:external:pinger"
        }
      }

      {:ok, response} = Gateway.handle_incoming(:test_a2a_gateway, request)

      assert response["result"]["status"] == "received"
    end
  end

  describe "unknown methods" do
    test "returns method not found for unknown methods" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "unknown.method",
        "params" => %{},
        "id" => 1
      }

      {:ok, response} = Gateway.handle_incoming(:test_a2a_gateway, request)

      assert response["error"]
      assert response["error"]["code"] == JSONRPC.method_not_found()
    end
  end
end
