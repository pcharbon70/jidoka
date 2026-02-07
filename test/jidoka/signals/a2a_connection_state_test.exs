defmodule Jidoka.Signals.A2AConnectionStateTest do
  use ExUnit.Case, async: true

  alias Jidoka.Signals.A2AConnectionState

  doctest A2AConnectionState

  describe "new/1" do
    test "creates a connection state signal" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :ready
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.type == "jido_coder.a2a.connection_state"
      assert signal.data.gateway_name == :a2a_gateway
      assert signal.data.state == :ready
    end

    test "creates signal with reason" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :terminated,
        reason: :shutdown
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.state == :terminated
      assert signal.data.reason == :shutdown
    end

    test "creates signal with session_id" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :ready,
        session_id: "session-123"
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.session_id == "session-123"
    end

    test "creates signal with all fields" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :closing,
        reason: :user_disconnect,
        session_id: "session-456"
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.gateway_name == :a2a_gateway
      assert signal.data.state == :closing
      assert signal.data.reason == :user_disconnect
      assert signal.data.session_id == "session-456"
    end

    test "returns error for missing gateway_name" do
      attrs = %{
        state: :ready
        # Missing gateway_name
      }

      assert {:error, _} = A2AConnectionState.new(attrs)
    end

    test "returns error for missing state" do
      attrs = %{
        gateway_name: :a2a_gateway
        # Missing state
      }

      assert {:error, _} = A2AConnectionState.new(attrs)
    end
  end

  describe "signal source" do
    test "uses default source for A2A connection state" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :ready
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.source == "/jido_coder/a2a"
    end
  end

  describe "valid states" do
    test "accepts :initializing state" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :initializing
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.state == :initializing
    end

    test "accepts :ready state" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :ready
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.state == :ready
    end

    test "accepts :closing state" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :closing
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.state == :closing
    end

    test "accepts :terminated state" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :terminated
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.state == :terminated
    end
  end

  describe "reason types" do
    test "accepts atom reason" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :terminated,
        reason: :normal
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.reason == :normal
    end

    test "accepts string reason" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :terminated,
        reason: "Connection closed by peer"
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.reason == "Connection closed by peer"
    end

    test "accepts map reason with details" do
      attrs = %{
        gateway_name: :a2a_gateway,
        state: :terminated,
        reason: %{type: :error, message: "Network timeout"}
      }

      assert {:ok, signal} = A2AConnectionState.new(attrs)
      assert signal.data.reason == %{type: :error, message: "Network timeout"}
    end
  end
end
