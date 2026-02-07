defmodule Jidoka.Signals.PhoenixConnectionStateTest do
  use ExUnit.Case, async: true

  alias Jidoka.Signals.PhoenixConnectionState

  describe "new/1" do
    test "creates a valid Phoenix connection state signal with required fields" do
      assert {:ok, signal} = PhoenixConnectionState.new(%{
        connection_name: :test_connection,
        state: :connected
      })

      assert signal.type == "jido_coder.phoenix.connection.state"
      assert signal.source == "/jido_coder/phoenix"
      assert signal.data.connection_name == :test_connection
      assert signal.data.state == :connected
    end

    test "fails with missing connection_name" do
      assert {:error, _reason} = PhoenixConnectionState.new(%{
        state: :connected
      })
    end

    test "fails with missing state" do
      assert {:error, _reason} = PhoenixConnectionState.new(%{
        connection_name: :test_connection
      })
    end

    test "accepts optional reason" do
      assert {:ok, signal} = PhoenixConnectionState.new(%{
        connection_name: :test_connection,
        state: :disconnected,
        reason: :closed
      })

      assert signal.data.reason == :closed
    end

    test "accepts optional reconnect_attempts" do
      assert {:ok, signal} = PhoenixConnectionState.new(%{
        connection_name: :test_connection,
        state: :disconnected,
        reconnect_attempts: 3
      })

      assert signal.data.reconnect_attempts == 3
    end

    test "accepts optional session_id" do
      assert {:ok, signal} = PhoenixConnectionState.new(%{
        connection_name: :test_connection,
        state: :connected,
        session_id: "session-123"
      })

      assert signal.data.session_id == "session-123"
    end
  end
end
