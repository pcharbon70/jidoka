defmodule Jidoka.Signals.PhoenixChannelStateTest do
  use ExUnit.Case, async: true

  alias Jidoka.Signals.PhoenixChannelState

  describe "new/1" do
    test "creates a valid Phoenix channel state signal with required fields" do
      assert {:ok, signal} = PhoenixChannelState.new(%{
        connection_name: :test_connection,
        topic: "room:lobby",
        state: :joined
      })

      assert signal.type == "jido_coder.phoenix.channel.state"
      assert signal.source == "/jido_coder/phoenix"
      assert signal.data.connection_name == :test_connection
      assert signal.data.topic == "room:lobby"
      assert signal.data.state == :joined
    end

    test "fails with missing connection_name" do
      assert {:error, _reason} = PhoenixChannelState.new(%{
        topic: "room:lobby",
        state: :joined
      })
    end

    test "fails with missing topic" do
      assert {:error, _reason} = PhoenixChannelState.new(%{
        connection_name: :test_connection,
        state: :joined
      })
    end

    test "fails with missing state" do
      assert {:error, _reason} = PhoenixChannelState.new(%{
        connection_name: :test_connection,
        topic: "room:lobby"
      })
    end

    test "accepts optional response" do
      assert {:ok, signal} = PhoenixChannelState.new(%{
        connection_name: :test_connection,
        topic: "room:lobby",
        state: :joined,
        response: %{status: "ok"}
      })

      assert signal.data.response == %{status: "ok"}
    end

    test "accepts optional reason" do
      assert {:ok, signal} = PhoenixChannelState.new(%{
        connection_name: :test_connection,
        topic: "room:lobby",
        state: :left,
        reason: :user_leave
      })

      assert signal.data.reason == :user_leave
    end

    test "accepts optional session_id" do
      assert {:ok, signal} = PhoenixChannelState.new(%{
        connection_name: :test_connection,
        topic: "room:lobby",
        state: :joined,
        session_id: "session-123"
      })

      assert signal.data.session_id == "session-123"
    end
  end
end
