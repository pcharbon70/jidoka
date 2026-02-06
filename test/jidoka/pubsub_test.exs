defmodule Jidoka.PubSubTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for the Jidoka.PubSub wrapper module.
  """

  describe "pubsub_name/0" do
    test "returns the correct PubSub name" do
      assert Jidoka.PubSub.pubsub_name() == :jido_coder_pubsub
    end
  end

  describe "topic prefixes" do
    test "agent_prefix/0 returns correct prefix" do
      assert Jidoka.PubSub.agent_prefix() == "jido.agent"
    end

    test "session_prefix/0 returns correct prefix" do
      assert Jidoka.PubSub.session_prefix() == "jido.session"
    end

    test "client_events_topic/0 returns correct topic" do
      assert Jidoka.PubSub.client_events_topic() == "jido.client.events"
    end

    test "client_session_prefix/0 returns correct prefix" do
      assert Jidoka.PubSub.client_session_prefix() == "jido.client.session"
    end

    test "signal_prefix/0 returns correct prefix" do
      assert Jidoka.PubSub.signal_prefix() == "jido.signal"
    end

    test "protocol_prefix/0 returns correct prefix" do
      assert Jidoka.PubSub.protocol_prefix() == "jido.protocol"
    end
  end

  describe "topic builders" do
    test "agent_topic/1 builds correct topic" do
      assert Jidoka.PubSub.agent_topic("coordinator") == "jido.agent.coordinator"
      assert Jidoka.PubSub.agent_topic("llm") == "jido.agent.llm"
    end

    test "session_topic/1 builds correct topic" do
      assert Jidoka.PubSub.session_topic("session-123") == "jido.session.session-123"
    end

    test "client_session_topic/1 builds correct topic" do
      assert Jidoka.PubSub.client_session_topic("abc") == "jido.client.session.abc"
    end

    test "signal_topic/1 builds correct topic" do
      assert Jidoka.PubSub.signal_topic("file_changed") == "jido.signal.file_changed"
    end

    test "protocol_topic/1 builds correct topic" do
      assert Jidoka.PubSub.protocol_topic("mcp") == "jido.protocol.mcp"
    end
  end

  describe "subscribe/2" do
    setup :unsubscribe_all

    test "subscribes the current process to a topic" do
      topic = "test.topic"
      assert Jidoka.PubSub.subscribe(topic) == :ok
      # Verify subscription by broadcasting and receiving
      Jidoka.PubSub.broadcast(topic, :test_message)
      assert_receive {_sender, :test_message}
    end

    test "subscribes a specific process to a topic" do
      parent = self()

      child =
        spawn(fn ->
          send(parent, {:ready})
          Process.sleep(:infinity)
        end)

      assert_receive {:ready}
      assert Jidoka.PubSub.subscribe(child, "test.topic2") == :ok
    end
  end

  describe "subscribe helpers" do
    setup :unsubscribe_all

    test "subscribe_client_events/0 subscribes to client events" do
      assert Jidoka.PubSub.subscribe_client_events() == :ok
      Jidoka.PubSub.broadcast_client_event(:test)
      # Messages from broadcast are wrapped as {sender, message}
      assert_receive {_, :test}
    after
      Jidoka.PubSub.unsubscribe(Jidoka.PubSub.client_events_topic())
    end

    test "subscribe_agent/1 subscribes to agent events" do
      assert Jidoka.PubSub.subscribe_agent("coordinator") == :ok
      Jidoka.PubSub.broadcast_agent("coordinator", :agent_event)
      assert_receive {_, :agent_event}
    after
      Jidoka.PubSub.unsubscribe(Jidoka.PubSub.agent_topic("coordinator"))
    end

    test "subscribe_session/1 subscribes to session events" do
      assert Jidoka.PubSub.subscribe("jido.session.test123") == :ok
      Jidoka.PubSub.broadcast_session("test123", :session_event)
      assert_receive {_, :session_event}
    after
      Jidoka.PubSub.unsubscribe("jido.session.test123")
    end
  end

  describe "broadcast/3" do
    setup :unsubscribe_all

    test "broadcasts a message to a topic" do
      topic = "test.broadcast"
      Jidoka.PubSub.subscribe(topic)

      Jidoka.PubSub.broadcast(topic, :hello)
      assert_receive {_sender, :hello}
    end

    test "broadcast includes the sender in the message tuple" do
      topic = "test.broadcast_sender"
      Jidoka.PubSub.subscribe(topic)

      Jidoka.PubSub.broadcast(topic, :message)
      assert_receive {sender, :message}
      assert is_pid(sender)
      assert sender == self()
    end

    test "broadcast with custom from option" do
      topic = "test.broadcast_from"
      Jidoka.PubSub.subscribe(topic)

      custom_pid = spawn(fn -> Process.sleep(:infinity) end)
      Jidoka.PubSub.broadcast(topic, :message, from: custom_pid)
      assert_receive {^custom_pid, :message}
    end
  end

  describe "broadcast helpers" do
    setup :unsubscribe_all

    test "broadcast_client_event/2 broadcasts to client events topic" do
      Jidoka.PubSub.subscribe_client_events()
      Jidoka.PubSub.broadcast_client_event(:client_msg)
      assert_receive {_, :client_msg}
    after
      Jidoka.PubSub.unsubscribe(Jidoka.PubSub.client_events_topic())
    end

    test "broadcast_agent/2 broadcasts to agent topic" do
      Jidoka.PubSub.subscribe_agent("test_agent")
      Jidoka.PubSub.broadcast_agent("test_agent", :agent_msg)
      assert_receive {_, :agent_msg}
    after
      Jidoka.PubSub.unsubscribe(Jidoka.PubSub.agent_topic("test_agent"))
    end

    test "broadcast_session/2 broadcasts to session topic" do
      Jidoka.PubSub.subscribe("jido.session.test_session")
      Jidoka.PubSub.broadcast_session("test_session", :session_msg)
      assert_receive {_, :session_msg}
    after
      Jidoka.PubSub.unsubscribe("jido.session.test_session")
    end

    test "broadcast_signal/2 broadcasts to signal topic" do
      Jidoka.PubSub.subscribe("jido.signal.test_signal")
      Jidoka.PubSub.broadcast_signal("test_signal", :signal_msg)
      assert_receive {_, :signal_msg}
    after
      Jidoka.PubSub.unsubscribe("jido.signal.test_signal")
    end
  end

  describe "unsubscribe/1" do
    setup :unsubscribe_all

    test "unsubscribes the current process from a topic" do
      topic = "test.unsubscribe"
      Jidoka.PubSub.subscribe(topic)
      assert Jidoka.PubSub.unsubscribe(topic) == :ok

      # Should not receive message after unsubscribe
      Jidoka.PubSub.broadcast(topic, :after_unsub)
      refute_receive {:_, :after_unsub}, 100
    end
  end

  describe "multiple subscribers" do
    setup :unsubscribe_all

    test "multiple processes receive broadcasts" do
      topic = "test.multi_sub"
      parent = self()

      # Spawn multiple subscribers that forward messages to parent
      for i <- 1..3 do
        spawn(fn ->
          Jidoka.PubSub.subscribe(topic)
          send(parent, {:subscribed, i})
          # Forward received messages to parent
          receive do
            {_sender, msg} -> send(parent, {:received, i, msg})
          end
        end)
      end

      # Wait for all to subscribe
      Enum.each(1..3, fn i -> assert_receive {:subscribed, ^i} end)

      # Broadcast a message
      Jidoka.PubSub.broadcast(topic, :broadcast_to_all)

      # All subscribers should receive
      assert_receive {:received, 1, :broadcast_to_all}
      assert_receive {:received, 2, :broadcast_to_all}
      assert_receive {:received, 3, :broadcast_to_all}
    end
  end

  # Helper to ensure clean state between tests
  defp unsubscribe_all(_context) do
    # Unsubscribe from any topics we might have used in tests
    topics = [
      "test.topic",
      "test.topic2",
      "test.broadcast",
      "test.broadcast_sender",
      "test.broadcast_from",
      "test.unsubscribe",
      "test.multi_sub",
      "jido.session.test123",
      "jido.session.test_session",
      "jido.signal.test_signal",
      Jidoka.PubSub.client_events_topic(),
      Jidoka.PubSub.agent_topic("coordinator"),
      Jidoka.PubSub.agent_topic("test_agent"),
      Jidoka.PubSub.session_topic("test_session"),
      Jidoka.PubSub.signal_topic("test_signal")
    ]

    Enum.each(topics, fn topic ->
      Phoenix.PubSub.unsubscribe(:jido_coder_pubsub, topic)
    end)

    :ok
  end
end
