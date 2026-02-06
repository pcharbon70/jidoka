defmodule JidoCoderLib.TelemetryTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for JidoCoderLib.Telemetry event definitions.
  """

  doctest JidoCoderLib.Telemetry

  describe "session event names" do
    test "session_started/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.session_started() == [:jido_coder_lib, :session, :started]
    end

    test "session_stopped/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.session_stopped() == [:jido_coder_lib, :session, :stopped]
    end

    test "session_error/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.session_error() == [:jido_coder_lib, :session, :error]
    end
  end

  describe "agent event names" do
    test "agent_dispatch/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.agent_dispatch() == [:jido_coder_lib, :agent, :dispatch]
    end

    test "agent_complete/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.agent_complete() == [:jido_coder_lib, :agent, :complete]
    end

    test "agent_error/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.agent_error() == [:jido_coder_lib, :agent, :error]
    end
  end

  describe "LLM event names" do
    test "llm_request/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.llm_request() == [:jido_coder_lib, :llm, :request]
    end

    test "llm_response/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.llm_response() == [:jido_coder_lib, :llm, :response]
    end

    test "llm_error/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.llm_error() == [:jido_coder_lib, :llm, :error]
    end
  end

  describe "context event names" do
    test "context_cache_hit/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.context_cache_hit() == [:jido_coder_lib, :context, :cache_hit]
    end

    test "context_cache_miss/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.context_cache_miss() == [
               :jido_coder_lib,
               :context,
               :cache_miss
             ]
    end

    test "context_cache_eviction/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.context_cache_eviction() == [
               :jido_coder_lib,
               :context,
               :cache_eviction
             ]
    end
  end

  describe "PubSub event names" do
    test "pubsub_broadcast/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.pubsub_broadcast() == [:jido_coder_lib, :pubsub, :broadcast]
    end

    test "pubsub_receive/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.pubsub_receive() == [:jido_coder_lib, :pubsub, :receive]
    end
  end

  describe "Registry event names" do
    test "registry_register/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.registry_register() == [:jido_coder_lib, :registry, :register]
    end

    test "registry_unregister/0 returns correct event name" do
      assert JidoCoderLib.Telemetry.registry_unregister() == [
               :jido_coder_lib,
               :registry,
               :unregister
             ]
    end
  end

  describe "telemetry event emission" do
    setup do
      # Create a unique handler ID for this test
      handler_id = "test-handler-#{:erlang.unique_integer([:positive])}"

      # Store the test process as the receiver
      parent = self()

      # Attach handlers for events we want to test
      events = [
        JidoCoderLib.Telemetry.session_started(),
        JidoCoderLib.Telemetry.session_stopped(),
        JidoCoderLib.Telemetry.agent_complete()
      ]

      Enum.each(events, fn event ->
        handler_name = "#{handler_id}-#{:erlang.phash2(event)}"

        :telemetry.attach(
          handler_name,
          event,
          fn event, measurements, metadata, _config ->
            send(parent, {event, measurements, metadata})
          end,
          nil
        )
      end)

      on_exit(fn ->
        Enum.each(events, fn event ->
          handler_name = "#{handler_id}-#{:erlang.phash2(event)}"
          :telemetry.detach(handler_name)
        end)
      end)

      :ok
    end

    test "can emit and receive session_started event" do
      measurements = %{duration: 100}
      metadata = %{session_id: "test-123"}

      :telemetry.execute(JidoCoderLib.Telemetry.session_started(), measurements, metadata)

      assert_receive {[_, :session, :started], ^measurements, ^metadata}, 100
    end

    test "can emit and receive session_stopped event" do
      measurements = %{duration: 5000}
      metadata = %{session_id: "test-456", reason: :normal}

      :telemetry.execute(JidoCoderLib.Telemetry.session_stopped(), measurements, metadata)

      assert_receive {[_, :session, :stopped], ^measurements, ^metadata}, 100
    end

    test "can emit and receive agent_complete event" do
      measurements = %{duration: 250}
      metadata = %{agent_id: "agent-1", action_name: "chat", status: :ok}

      :telemetry.execute(JidoCoderLib.Telemetry.agent_complete(), measurements, metadata)

      assert_receive {[_, :agent, :complete], ^measurements, ^metadata}, 100
    end
  end

  describe "execute_with_telemetry/3" do
    test "emits event with duration on success" do
      # Attach a test handler
      handler_id = "test-execute-handler"
      parent = self()

      :telemetry.attach(
        handler_id,
        JidoCoderLib.Telemetry.session_started(),
        fn _event, measurements, _metadata, _config ->
          send(parent, {:telemetry_event, measurements})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      # Execute function
      result =
        JidoCoderLib.Telemetry.execute_with_telemetry(
          &JidoCoderLib.Telemetry.session_started/0,
          %{session_id: "test-123"},
          fn -> :success end
        )

      assert result == :success

      # Verify telemetry was emitted
      assert_receive {:telemetry_event, measurements}, 100
      assert %{duration: duration} = measurements
      assert is_integer(duration)
      assert duration >= 0
    end

    test "includes error metadata when function raises" do
      handler_id = "test-execute-error-handler"
      parent = self()

      :telemetry.attach(
        handler_id,
        JidoCoderLib.Telemetry.session_started(),
        fn _event, _measurements, metadata, _config ->
          send(parent, {:telemetry_metadata, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      # Execute failing function
      assert_raise RuntimeError, "test error", fn ->
        JidoCoderLib.Telemetry.execute_with_telemetry(
          &JidoCoderLib.Telemetry.session_started/0,
          %{session_id: "test-123"},
          fn -> raise "test error" end
        )
      end

      # Verify error metadata was included
      assert_receive {:telemetry_metadata, metadata}, 100
      assert Map.has_key?(metadata, :error)
      assert is_binary(metadata.error)
    end
  end

  describe "execute_with_start_complete/4" do
    test "emits start and complete events" do
      handler_id = "test-start-complete-handler"
      parent = self()

      :telemetry.attach(
        "#{handler_id}-start",
        JidoCoderLib.Telemetry.agent_dispatch(),
        fn _event, _measurements, _metadata, _config ->
          send(parent, {:start_event})
        end,
        nil
      )

      :telemetry.attach(
        "#{handler_id}-complete",
        JidoCoderLib.Telemetry.agent_complete(),
        fn _event, measurements, metadata, _config ->
          send(parent, {:complete_event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("#{handler_id}-start")
        :telemetry.detach("#{handler_id}-complete")
      end)

      # Execute function
      result =
        JidoCoderLib.Telemetry.execute_with_start_complete(
          &JidoCoderLib.Telemetry.agent_dispatch/0,
          &JidoCoderLib.Telemetry.agent_complete/0,
          %{agent_id: "agent-1", action_name: "chat"},
          fn -> :success end
        )

      assert result == :success

      # Verify both events were emitted
      assert_receive {:start_event}, 100
      assert_receive {:complete_event, measurements, metadata}, 100

      assert %{duration: duration} = measurements
      assert is_integer(duration)
      assert duration >= 0
      assert metadata.status == :ok
    end

    test "includes error status when function raises" do
      handler_id = "test-start-complete-error-handler"
      parent = self()

      :telemetry.attach(
        "#{handler_id}-complete",
        JidoCoderLib.Telemetry.agent_complete(),
        fn _event, _measurements, metadata, _config ->
          send(parent, {:complete_metadata, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("#{handler_id}-complete") end)

      # Execute failing function
      assert_raise RuntimeError, "test error", fn ->
        JidoCoderLib.Telemetry.execute_with_start_complete(
          &JidoCoderLib.Telemetry.agent_dispatch/0,
          &JidoCoderLib.Telemetry.agent_complete/0,
          %{agent_id: "agent-1", action_name: "chat"},
          fn -> raise "test error" end
        )
      end

      # Verify error status was included
      assert_receive {:complete_metadata, metadata}, 100
      assert metadata.status == :error
      assert metadata.error_type == RuntimeError
      assert Map.has_key?(metadata, :error_message)
    end
  end
end
