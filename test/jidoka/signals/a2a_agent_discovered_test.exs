defmodule Jidoka.Signals.A2AAgentDiscoveredTest do
  use ExUnit.Case, async: true

  alias Jidoka.Signals.A2AAgentDiscovered

  # Skip auto-generated doctests that use placeholder module names
  # We have comprehensive unit tests instead
  # doctest A2AAgentDiscovered

  describe "new/1" do
    test "creates an agent discovered signal" do
      agent_card = %{
        id: "agent:external:assistant",
        name: "External Assistant",
        type: ["Assistant"],
        version: "1.0.0",
        capabilities: %{actions: ["chat", "code"]}
      }

      attrs = %{
        agent_id: "agent:external:assistant",
        agent_card: agent_card,
        source: :directory
      }

      assert {:ok, signal} = A2AAgentDiscovered.new(attrs)
      assert signal.type == "jido_coder.a2a.agent_discovered"
      assert signal.data.agent_id == "agent:external:assistant"
      assert signal.data.agent_card == agent_card
      assert signal.data.source == :directory
    end

    test "creates signal for static source" do
      attrs = %{
        agent_id: "agent:static:worker",
        agent_card: %{id: "agent:static:worker", name: "Worker", type: ["Worker"]},
        source: :static
      }

      assert {:ok, signal} = A2AAgentDiscovered.new(attrs)
      assert signal.data.source == :static
    end

    test "creates signal for cache source" do
      attrs = %{
        agent_id: "agent:cached:bot",
        agent_card: %{id: "agent:cached:bot", name: "Bot", type: ["Bot"]},
        source: :cache
      }

      assert {:ok, signal} = A2AAgentDiscovered.new(attrs)
      assert signal.data.source == :cache
    end

    test "creates signal with optional gateway_name" do
      attrs = %{
        agent_id: "agent:external:assistant",
        agent_card: %{id: "agent:external:assistant", name: "Assistant", type: []},
        source: :directory,
        gateway_name: :a2a_gateway
      }

      assert {:ok, signal} = A2AAgentDiscovered.new(attrs)
      assert signal.data.gateway_name == :a2a_gateway
    end

    test "creates signal with optional session_id" do
      attrs = %{
        agent_id: "agent:external:assistant",
        agent_card: %{id: "agent:external:assistant", name: "Assistant", type: []},
        source: :directory,
        session_id: "session-123"
      }

      assert {:ok, signal} = A2AAgentDiscovered.new(attrs)
      assert signal.data.session_id == "session-123"
    end

    test "returns error for missing required fields" do
      # Missing agent_card
      attrs = %{
        agent_id: "agent:test",
        source: :static
      }

      assert {:error, _} = A2AAgentDiscovered.new(attrs)
    end

    test "returns error for missing source" do
      attrs = %{
        agent_id: "agent:test",
        agent_card: %{id: "agent:test", name: "Test", type: []}
        # Missing source
      }

      assert {:error, _} = A2AAgentDiscovered.new(attrs)
    end
  end

  describe "signal source" do
    test "uses default source for A2A agent discovery" do
      attrs = %{
        agent_id: "agent:external:assistant",
        agent_card: %{id: "agent:external:assistant", name: "Assistant", type: []},
        source: :directory
      }

      assert {:ok, signal} = A2AAgentDiscovered.new(attrs)
      assert signal.source == "/jido_coder/a2a"
    end
  end

  describe "valid sources" do
    test "accepts :directory source" do
      attrs = %{
        agent_id: "agent:test",
        agent_card: %{id: "agent:test", name: "Test", type: []},
        source: :directory
      }

      assert {:ok, signal} = A2AAgentDiscovered.new(attrs)
      assert signal.data.source == :directory
    end

    test "accepts :static source" do
      attrs = %{
        agent_id: "agent:test",
        agent_card: %{id: "agent:test", name: "Test", type: []},
        source: :static
      }

      assert {:ok, signal} = A2AAgentDiscovered.new(attrs)
      assert signal.data.source == :static
    end

    test "accepts :cache source" do
      attrs = %{
        agent_id: "agent:test",
        agent_card: %{id: "agent:test", name: "Test", type: []},
        source: :cache
      }

      assert {:ok, signal} = A2AAgentDiscovered.new(attrs)
      assert signal.data.source == :cache
    end
  end
end
