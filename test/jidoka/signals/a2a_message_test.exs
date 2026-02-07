defmodule Jidoka.Signals.A2AMessageTest do
  use ExUnit.Case, async: true

  alias Jidoka.Signals.A2AMessage

  doctest A2AMessage

  describe "new/1" do
    test "creates an outgoing message signal" do
      attrs = %{
        direction: :outgoing,
        from_agent: "agent:jidoka:coordinator",
        to_agent: "agent:external:assistant",
        method: "agent.send_message",
        message: %{"text" => "Hello!"},
        status: :pending
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.type == "jido_coder.a2a.message"
      assert signal.data.direction == :outgoing
      assert signal.data.from_agent == "agent:jidoka:coordinator"
      assert signal.data.to_agent == "agent:external:assistant"
      assert signal.data.method == "agent.send_message"
      assert signal.data.message == %{"text" => "Hello!"}
      assert signal.data.status == :pending
    end

    test "creates an incoming message signal" do
      attrs = %{
        direction: :incoming,
        from_agent: "agent:external:assistant",
        to_agent: "agent:jidoka:coordinator",
        method: "agent.send_message",
        message: %{"text" => "Hi there!"},
        status: :success
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.data.direction == :incoming
      assert signal.data.status == :success
    end

    test "creates message with response" do
      attrs = %{
        direction: :outgoing,
        from_agent: "agent:jidoka:coordinator",
        to_agent: "agent:external:assistant",
        method: "agent.send_message",
        message: %{},
        status: :success,
        response: %{"delivered" => true}
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.data.response == %{"delivered" => true}
    end

    test "returns error for missing required fields" do
      attrs = %{
        direction: :outgoing,
        from_agent: "agent:jidoka:coordinator"
        # Missing to_agent, method, message, status
      }

      assert {:error, _} = A2AMessage.new(attrs)
    end

    test "creates message with optional gateway_name" do
      attrs = %{
        direction: :outgoing,
        from_agent: "agent:jidoka:coordinator",
        to_agent: "agent:external:assistant",
        method: "agent.send_message",
        message: %{},
        status: :pending,
        gateway_name: :a2a_gateway
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.data.gateway_name == :a2a_gateway
    end
  end

  describe "signal source" do
    test "uses default source for A2A messages" do
      attrs = %{
        direction: :outgoing,
        from_agent: "agent:jidoka:coordinator",
        to_agent: "agent:external:assistant",
        method: "agent.send_message",
        message: %{},
        status: :pending
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.source == "/jido_coder/a2a"
    end
  end

  describe "valid directions" do
    test "accepts :outgoing direction" do
      attrs = %{
        direction: :outgoing,
        from_agent: "agent:a",
        to_agent: "agent:b",
        method: "test",
        message: %{},
        status: :pending
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.data.direction == :outgoing
    end

    test "accepts :incoming direction" do
      attrs = %{
        direction: :incoming,
        from_agent: "agent:a",
        to_agent: "agent:b",
        method: "test",
        message: %{},
        status: :pending
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.data.direction == :incoming
    end
  end

  describe "valid statuses" do
    test "accepts :pending status" do
      attrs = %{
        direction: :outgoing,
        from_agent: "agent:a",
        to_agent: "agent:b",
        method: "test",
        message: %{},
        status: :pending
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.data.status == :pending
    end

    test "accepts :success status" do
      attrs = %{
        direction: :outgoing,
        from_agent: "agent:a",
        to_agent: "agent:b",
        method: "test",
        message: %{},
        status: :success
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.data.status == :success
    end

    test "accepts :error status" do
      attrs = %{
        direction: :outgoing,
        from_agent: "agent:a",
        to_agent: "agent:b",
        method: "test",
        message: %{},
        status: :error
      }

      assert {:ok, signal} = A2AMessage.new(attrs)
      assert signal.data.status == :error
    end
  end
end
