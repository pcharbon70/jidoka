defmodule Jidoka.Signals.PhoenixEventTest do
  use ExUnit.Case, async: true

  alias Jidoka.Signals.PhoenixEvent

  describe "new/1" do
    test "creates a valid Phoenix event signal with required fields" do
      assert {:ok, signal} = PhoenixEvent.new(%{
        connection_name: :test_connection,
        topic: "room:lobby",
        event: "new_msg",
        payload: %{body: "Hello!"}
      })

      assert signal.type == "jido_coder.phoenix.event"
      assert signal.source == "/jido_coder/phoenix"
      assert signal.data.connection_name == :test_connection
      assert signal.data.topic == "room:lobby"
      assert signal.data.event == "new_msg"
      assert signal.data.payload == %{body: "Hello!"}
    end

    test "fails with missing connection_name" do
      assert {:error, _reason} = PhoenixEvent.new(%{
        topic: "room:lobby",
        event: "new_msg",
        payload: %{body: "Hello!"}
      })
    end

    test "fails with missing topic" do
      assert {:error, _reason} = PhoenixEvent.new(%{
        connection_name: :test_connection,
        event: "new_msg",
        payload: %{body: "Hello!"}
      })
    end

    test "fails with missing event" do
      assert {:error, _reason} = PhoenixEvent.new(%{
        connection_name: :test_connection,
        topic: "room:lobby",
        payload: %{body: "Hello!"}
      })
    end

    test "fails with missing payload" do
      assert {:error, _reason} = PhoenixEvent.new(%{
        connection_name: :test_connection,
        topic: "room:lobby",
        event: "new_msg"
      })
    end

    test "accepts optional session_id" do
      assert {:ok, signal} = PhoenixEvent.new(%{
        connection_name: :test_connection,
        topic: "room:lobby",
        event: "new_msg",
        payload: %{body: "Hello!"},
        session_id: "session-123"
      })

      assert signal.data.session_id == "session-123"
    end
  end
end
