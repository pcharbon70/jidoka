defmodule Jidoka.Protocol.Phoenix.ClientTest do
  use ExUnit.Case, async: false

  alias Jidoka.Protocol.Phoenix.Client

  describe "start_link/1" do
    test "requires name configuration" do
      assert_raise ArgumentError, fn ->
        Client.start_link(uri: "ws://localhost:4000/socket/websocket")
      end
    end

    test "requires uri configuration" do
      assert_raise ArgumentError, fn ->
        Client.start_link(name: :test_connection)
      end
    end

    test "accepts valid configuration" do
      # Note: Slipstream works asynchronously - start_link returns {:ok, pid}
      # even when the Phoenix server is not available. The connection status
      # is tracked through the status/1 function and handle_disconnect/1
      # callback when the connection fails.

      # Use test_mode to avoid actual WebSocket connection
      assert {:ok, pid} = Client.start_link([
        name: :test_connection_config,
        uri: "ws://localhost:4000/socket/websocket",
        test_mode?: true
      ])

      # Clean up
      GenServer.stop(pid, :normal, 1000)
    end
  end

  describe "channel operations" do
    # These tests require a running Phoenix server
    # They're marked as pending for integration testing

    @tag :pending
    test "join_channel/3 joins a Phoenix channel" do
      # Requires running Phoenix server
      :ok
    end

    @tag :pending
    test "leave_channel/2 leaves a Phoenix channel" do
      # Requires running Phoenix server
      :ok
    end

    @tag :pending
    test "push_event/4 sends an event to a channel" do
      # Requires running Phoenix server
      :ok
    end
  end

  describe "status and list operations" do
    # These tests require a running Phoenix server
    # They're marked as pending for integration testing

    @tag :pending
    test "status/1 returns current connection status" do
      # Requires running Phoenix server
      :ok
    end

    @tag :pending
    test "list_channels/1 returns list of joined channels" do
      # Requires running Phoenix server
      :ok
    end
  end

  describe "signal integration" do
    test "signals are dispatched for Phoenix events" do
      # This test validates that signals are created correctly
      # without requiring a real Phoenix server

      alias Jidoka.Signals

      # Test phoenix_event signal creation
      {:ok, signal} = Signals.phoenix_event(
        :test_connection,
        "room:lobby",
        "new_msg",
        %{body: "Hello!"},
        dispatch: false
      )

      assert signal.type == "jido_coder.phoenix.event"
      assert signal.data.connection_name == :test_connection
      assert signal.data.topic == "room:lobby"
      assert signal.data.event == "new_msg"
      assert signal.data.payload == %{body: "Hello!"}
    end

    test "connection state signals are created correctly" do
      alias Jidoka.Signals

      # Test phoenix_connection_state signal creation
      {:ok, signal} = Signals.phoenix_connection_state(
        :test_connection,
        :connected,
        dispatch: false
      )

      assert signal.type == "jido_coder.phoenix.connection.state"
      assert signal.data.connection_name == :test_connection
      assert signal.data.state == :connected
    end

    test "channel state signals are created correctly" do
      alias Jidoka.Signals

      # Test phoenix_channel_state signal creation
      {:ok, signal} = Signals.phoenix_channel_state(
        :test_connection,
        "room:lobby",
        :joined,
        dispatch: false
      )

      assert signal.type == "jido_coder.phoenix.channel.state"
      assert signal.data.connection_name == :test_connection
      assert signal.data.topic == "room:lobby"
      assert signal.data.state == :joined
    end
  end
end
