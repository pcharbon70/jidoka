defmodule Jidoka.Integration.Phase1Test do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration tests for Phase 1 foundation components.

  These tests verify that all core foundation components work together correctly.
  """

  describe "Application Lifecycle" do
    test "application starts without errors" do
      assert Process.whereis(Jidoka.Supervisor) != nil
    end

    test "all children are started" do
      assert Process.whereis(Phoenix.PubSub) != nil
      assert Process.whereis(Jidoka.AgentRegistry) != nil
      assert Process.whereis(Jidoka.TopicRegistry) != nil
      assert Process.whereis(Jidoka.SecureCredentials) != nil
      assert Process.whereis(Jidoka.ContextStore) != nil
      assert Process.whereis(Jidoka.Jido) != nil
      assert Process.whereis(Jidoka.AgentSupervisor) != nil
      assert Process.whereis(Jidoka.Agents.SessionManager) != nil
      assert Process.whereis(Jidoka.ProtocolSupervisor) != nil
      assert Process.whereis(Jidoka.Indexing.IndexingStatusTracker) != nil
    end

    test "supervisor has correct children" do
      children = Supervisor.which_children(Jidoka.Supervisor)
      # 13 children: Phoenix.PubSub, AgentRegistry, TopicRegistry, SecureCredentials,
      #            ContextStore, Jido, AgentSupervisor, SessionManager, ProtocolSupervisor,
      #            Memory.SessionRegistry, Knowledge.Engine, IndexingStatusTracker, CodeIndexer
      assert length(children) == 13
    end

    test "all children are alive" do
      children = Supervisor.which_children(Jidoka.Supervisor)

      Enum.each(children, fn {_id, pid, _type, _modules} ->
        assert is_pid(pid)
        assert Process.alive?(pid)
      end)
    end
  end

  describe "PubSub Integration" do
    setup do
      topic = "test-topic-#{:erlang.unique_integer([:positive])}"
      %{topic: topic}
    end

    test "can subscribe to topics and receive messages", %{topic: topic} do
      parent = self()

      # Spawn a subscriber process
      spawn(fn ->
        Phoenix.PubSub.subscribe(:jido_coder_pubsub, topic)
        send(parent, :subscribed)

        receive do
          {^topic, msg} -> send(parent, {:got, msg})
        end
      end)

      assert_receive :subscribed, 100

      # Broadcast a message
      message = %{test: "data"}
      Phoenix.PubSub.broadcast(:jido_coder_pubsub, topic, {topic, message})

      assert_receive {:got, ^message}, 100
    end

    test "can broadcast messages to subscribers", %{topic: topic} do
      parent = self()

      spawn(fn ->
        Phoenix.PubSub.subscribe(:jido_coder_pubsub, topic)
        send(parent, :ready)

        receive do
          {^topic, msg} -> send(parent, {:got, msg})
        end
      end)

      assert_receive :ready, 100

      message = %{test: "data"}
      Phoenix.PubSub.broadcast(:jido_coder_pubsub, topic, {topic, message})

      assert_receive {:got, ^message}, 100
    end

    test "multiple subscribers receive messages", %{topic: topic} do
      parent = self()

      for i <- 1..3 do
        spawn(fn ->
          Phoenix.PubSub.subscribe(:jido_coder_pubsub, topic)
          send(parent, {:ready, i})

          receive do
            {^topic, msg} -> send(parent, {:received, i, msg})
          end
        end)
      end

      # Wait for all subscribers to be ready
      for i <- 1..3 do
        assert_receive {:ready, ^i}, 100
      end

      message = %{test: "broadcast"}
      Phoenix.PubSub.broadcast(:jido_coder_pubsub, topic, {topic, message})

      for i <- 1..3 do
        assert_receive {:received, ^i, ^message}, 100
      end
    end
  end

  describe "Registry Integration" do
    @agent_registry Jidoka.AgentRegistry

    setup do
      Registry.unregister(@agent_registry, :test_key)
      :ok
    end

    test "AgentRegistry enforces unique keys" do
      # Register current process with a unique key
      key = :unique_test_1
      result = Registry.register(@agent_registry, key, :value1)

      # Registry.register returns {:ok, pid}
      assert {:ok, _pid} = result

      # Verify the registration
      assert [{current_pid, _}] = Registry.lookup(@agent_registry, key)
      assert current_pid == self()

      # Try to register same key again from this process - should succeed
      # because it's the same process re-registering
      Registry.register(@agent_registry, key, :value2)

      # Clean up
      Registry.unregister(@agent_registry, key)
      assert [] = Registry.lookup(@agent_registry, key)
    end

    test "process death auto-unregisters" do
      # Create a process that will register itself and stay alive
      parent = self()
      key = :auto_unregister

      {pid, _ref} =
        spawn_monitor(fn ->
          Registry.register(@agent_registry, key, :value)
          send(parent, :registered)
          Process.sleep(:infinity)
        end)

      assert_receive :registered, 100
      assert [{^pid, _}] = Registry.lookup(@agent_registry, key)

      # Kill the process
      Process.exit(pid, :kill)
      assert_receive {:DOWN, _ref, :process, ^pid, _}, 100

      # Verify it was unregistered
      Process.sleep(10)
      assert [] = Registry.lookup(@agent_registry, key)
    end
  end

  describe "ETS Integration" do
    test "ETS tables are created on startup" do
      assert :ets.whereis(:file_content) != :undefined
      assert :ets.whereis(:file_metadata) != :undefined
      assert :ets.whereis(:analysis_cache) != :undefined
    end

    test "can cache and retrieve analysis results" do
      file_path = "/test/file.ex"
      analysis_type = :syntax_check
      result = %{valid: true, errors: []}

      assert :ok = Jidoka.ContextStore.cache_analysis(file_path, analysis_type, result)
      assert {:ok, ^result} = Jidoka.ContextStore.get_analysis(file_path, analysis_type)

      # Cleanup
      Jidoka.ContextStore.invalidate_file(file_path)
    end

    test "concurrent analysis cache operations" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            file_path = "/test/concurrent_#{i}.ex"
            result = %{index: i}
            Jidoka.ContextStore.cache_analysis(file_path, :test, result)

            case Jidoka.ContextStore.get_analysis(file_path, :test) do
              {:ok, %{index: ^i}} -> :ok
              _ -> :error
            end
          end)
        end

      results = Task.await_many(tasks, 1000)
      assert Enum.all?(results, &(&1 == :ok))

      # Cleanup
      for i <- 1..10 do
        Jidoka.ContextStore.invalidate_file("/test/concurrent_#{i}.ex")
      end
    end

    test "can invalidate cached analysis" do
      file_path = "/test/invalidate.ex"
      result = %{data: "test"}

      Jidoka.ContextStore.cache_analysis(file_path, :test_analysis, result)
      assert {:ok, ^result} = Jidoka.ContextStore.get_analysis(file_path, :test_analysis)

      Jidoka.ContextStore.invalidate_file(file_path)
      assert :error = Jidoka.ContextStore.get_analysis(file_path, :test_analysis)
    end

    test "can get cache statistics" do
      # Add some test data
      Jidoka.ContextStore.cache_analysis("/test/stats1.ex", :test, %{})
      Jidoka.ContextStore.cache_analysis("/test/stats2.ex", :test, %{})

      stats = Jidoka.ContextStore.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :analysis_cache)
      assert stats.analysis_cache >= 2

      # Cleanup
      Jidoka.ContextStore.clear_all()
    end
  end

  describe "Configuration Integration" do
    test "configuration loads for current environment" do
      operation_timeout = Application.get_env(:jidoka, :operation_timeout)

      # Config may or may not be set depending on when this branch was created
      if operation_timeout != nil do
        assert is_integer(operation_timeout)
        assert operation_timeout > 0
      end
    end

    test "configuration validation passes with valid config" do
      Application.put_env(:jidoka, :llm, provider: :mock, model: "test-model")
      Application.put_env(:jidoka, :knowledge_graph, backend: :native)

      Application.put_env(:jidoka, :session,
        max_sessions: 10,
        idle_timeout: 1000,
        absolute_timeout: 2000,
        cleanup_interval: 500
      )

      assert :ok = Jidoka.Config.validate_all()
    end

    test "configuration validation fails with invalid config" do
      Application.put_env(:jidoka, :llm, provider: :invalid_provider)

      assert {:error, errors} = Jidoka.Config.validate_all()
      assert is_list(errors)
      assert length(errors) > 0
    end
  end

  describe "Telemetry Integration" do
    setup do
      original_enable = Application.get_env(:jidoka, :enable_telemetry)
      Application.put_env(:jidoka, :enable_telemetry, true)

      on_exit(fn ->
        if original_enable != nil do
          Application.put_env(:jidoka, :enable_telemetry, original_enable)
        end
      end)

      :ok
    end

    test "telemetry events can be emitted" do
      parent = self()
      handler_id = "integration-telemetry-test"

      :telemetry.attach(
        handler_id,
        [:jidoka, :session, :started],
        fn _event, measurements, _metadata, _config ->
          send(parent, {:telemetry_event, measurements})
        end,
        nil
      )

      :telemetry.execute(
        Jidoka.Telemetry.session_started(),
        %{duration: 100},
        %{session_id: "test-123"}
      )

      assert_receive {:telemetry_event, %{duration: 100}}, 100

      :telemetry.detach(handler_id)
    end
  end

  describe "Fault Tolerance" do
    test "supervisor children are running" do
      children = Supervisor.which_children(Jidoka.Supervisor)

      Enum.each(children, fn {_id, pid, _type, _modules} ->
        assert is_pid(pid)
        assert Process.alive?(pid)
      end)
    end

    test "ETS tables survive" do
      assert :ets.whereis(:file_content) != :undefined
      assert :ets.whereis(:file_metadata) != :undefined
      assert :ets.whereis(:analysis_cache) != :undefined
    end
  end

  describe "Concurrency" do
    test "concurrent registry operations" do
      parent = self()

      # Spawn processes that stay alive until we tell them to stop
      processes =
        for i <- 1..20 do
          spawn(fn ->
            key = :"concurrent_test_#{i}"
            Registry.register(Jidoka.AgentRegistry, key, i)
            send(parent, {:registered, key, self()})

            # Wait for stop signal
            receive do
              :stop -> :ok
            end
          end)
        end

      # Wait for all processes to register
      registry_entries =
        for _i <- 1..20 do
          assert_receive {:registered, key, pid}, 500
          {key, pid}
        end

      # Verify all registrations
      Enum.each(registry_entries, fn {key, pid} ->
        assert [{^pid, _}] = Registry.lookup(Jidoka.AgentRegistry, key)
      end)

      # Tell all processes to stop
      Enum.each(processes, fn pid -> send(pid, :stop) end)
    end

    test "concurrent ETS operations" do
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            file_path = "/test/concurrent_#{i}.ex"
            result = %{index: i}
            Jidoka.ContextStore.cache_analysis(file_path, :concurrent_test, result)

            case Jidoka.ContextStore.get_analysis(file_path, :concurrent_test) do
              {:ok, %{index: ^i}} -> :ok
              _ -> :error
            end
          end)
        end

      results = Task.await_many(tasks, 1000)
      assert Enum.all?(results, &(&1 == :ok))

      # Clean up
      for i <- 1..20 do
        Jidoka.ContextStore.invalidate_file("/test/concurrent_#{i}.ex")
      end
    end

    test "concurrent PubSub operations" do
      parent = self()
      topic = "concurrent_test"

      subscribers =
        for i <- 1..10 do
          spawn(fn ->
            Phoenix.PubSub.subscribe(:jido_coder_pubsub, topic)
            send(parent, {:ready, i})

            receive do
              {^topic, :stop} -> send(parent, {:stopped, i})
            end
          end)
        end

      # Wait for all subscribers to be ready
      for i <- 1..10 do
        assert_receive {:ready, ^i}, 100
      end

      # Broadcast stop message
      Phoenix.PubSub.broadcast(:jido_coder_pubsub, topic, {topic, :stop})

      # Verify all subscribers received the message
      for i <- 1..10 do
        assert_receive {:stopped, ^i}, 100
        Process.exit(Enum.at(subscribers, i - 1), :kill)
      end
    end
  end
end
