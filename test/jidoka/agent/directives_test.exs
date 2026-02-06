defmodule Jidoka.Agent.DirectivesTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.{Directive, StateOp}
  alias Jido.Signal
  alias Jidoka.{Agent, Agent.Directives}

  describe "client_broadcast/3" do
    test "creates a client broadcast directive" do
      directive = Directives.client_broadcast("test_event", %{data: "value"})

      assert %Directive.Emit{} = directive
      assert directive.signal.type == "jido_coder.client.broadcast"
      assert directive.signal.data.event_type == "test_event"
      assert directive.signal.data.payload.data == "value"
      assert directive.signal.data.payload.timestamp =~ ~r/^\d{4}-\d{2}-\d{2}T/
    end

    test "includes source by default" do
      directive = Directives.client_broadcast("test_event", %{})

      assert directive.signal.source == "/jido_coder/agent"
    end

    test "can omit source" do
      directive = Directives.client_broadcast("test_event", %{}, include_source: false)

      assert directive.signal.source == "/jido_coder/coordinator"
    end

    test "uses correct PubSub dispatch config" do
      directive = Directives.client_broadcast("test_event", %{})

      assert {:pubsub, config} = directive.dispatch
      assert config[:target] == :jido_coder_pubsub
      assert config[:topic] == "jido.client.events"
    end
  end

  describe "session_broadcast/4" do
    test "creates a session broadcast directive" do
      directive =
        Directives.session_broadcast("session-123", "chat_event", %{message: "hello"})

      assert %Directive.Emit{} = directive
      assert directive.signal.type == "jido_coder.client.broadcast"
      assert directive.signal.data.event_type == "chat_event"
      assert directive.signal.data.payload.message == "hello"
      assert directive.signal.data.session_id == "session-123"
    end

    test "uses correct PubSub dispatch config for session" do
      directive = Directives.session_broadcast("session-123", "event", %{})

      assert {:pubsub, config} = directive.dispatch
      assert config[:target] == :jido_coder_pubsub
      assert config[:topic] == "jido.session.session-123"
    end
  end

  describe "emit_signal/3" do
    test "creates a signal emission directive with pubsub dispatch" do
      signal = Signal.new!("test.event", %{data: "value"})
      directive = Directives.emit_signal(signal, :pubsub, topic: "test.topic")

      assert %Directive.Emit{} = directive
      assert directive.signal == signal
      assert directive.dispatch == {:pubsub, [topic: "test.topic"]}
    end

    test "creates a signal emission directive with pid dispatch" do
      signal = Signal.new!("test.event", %{})
      pid = self()
      directive = Directives.emit_signal(signal, :pid, target: pid)

      assert directive.dispatch == {:pid, [target: pid]}
    end
  end

  describe "pubsub_broadcast/3" do
    test "creates a PubSub broadcast directive" do
      signal = Signal.new!("test.event", %{})
      directive = Directives.pubsub_broadcast(signal, "test.topic")

      assert %Directive.Emit{} = directive
      assert directive.signal == signal
      assert directive.dispatch == {:pubsub, [target: :jido_coder_pubsub, topic: "test.topic"]}
    end

    test "can use custom target" do
      signal = Signal.new!("test.event", %{})
      directive = Directives.pubsub_broadcast(signal, "test.topic", target: :custom_pubsub)

      assert directive.dispatch == {:pubsub, [target: :custom_pubsub, topic: "test.topic"]}
    end
  end

  describe "set_state/1" do
    test "creates a state update directive" do
      directive = Directives.set_state(%{count: 1, status: :processing})

      assert %StateOp.SetState{} = directive
      assert directive.attrs == %{count: 1, status: :processing}
    end
  end

  describe "combine/1" do
    test "returns the list of directives unchanged" do
      directives = [
        Directives.set_state(%{count: 1}),
        Directives.client_broadcast("test", %{})
      ]

      result = Directives.combine(directives)

      assert result == directives
    end
  end

  describe "state_and_broadcast/4" do
    test "creates state update and broadcast directives" do
      directives =
        Directives.state_and_broadcast(
          %{status: :ready},
          "status_update",
          %{message: "Ready"}
        )

      assert length(directives) == 2

      assert %StateOp.SetState{
               attrs: %{status: :ready}
             } = List.first(directives)

      assert %Directive.Emit{} = List.last(directives)
      assert List.last(directives).signal.data.event_type == "status_update"
    end
  end

  describe "state_and_session_broadcast/5" do
    test "creates state update and session broadcast directives" do
      directives =
        Directives.state_and_session_broadcast(
          %{active_tasks: %{}},
          "session-123",
          "task_started",
          %{task_id: "task_1"}
        )

      assert length(directives) == 2

      assert %StateOp.SetState{
               attrs: %{active_tasks: %{}}
             } = List.first(directives)

      assert %Directive.Emit{} = List.last(directives)
      assert List.last(directives).signal.data.event_type == "task_started"
      assert List.last(directives).signal.data.session_id == "session-123"
    end
  end
end
