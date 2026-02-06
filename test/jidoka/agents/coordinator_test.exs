defmodule Jidoka.Agents.CoordinatorTest do
  use ExUnit.Case, async: false

  alias Jido.AgentServer
  alias Jido.Signal
  alias Jidoka.Agents.Coordinator
  alias Jidoka.PubSub
  alias Jidoka.Jido, as: MyAppJido

  @moduletag :coordinator_integration

  setup do
    # Note: Phoenix PubSub and Jido instance are already started by the Application
    # The tests are run with the full application supervision tree

    # Start the coordinator agent
    {:ok, _pid} = start_coordinator()

    # Subscribe to client events to verify broadcasts
    PubSub.subscribe(PubSub.client_events_topic())

    on_exit(fn ->
      stop_coordinator()
      PubSub.unsubscribe(PubSub.client_events_topic())
    end)

    :ok
  end

  describe "agent lifecycle" do
    test "coordinator starts successfully" do
      assert {:ok, _pid} = Coordinator.start_link(id: "coordinator-test-1")
    end

    test "coordinator can be found via whereis" do
      assert pid = Jido.whereis(MyAppJido, "coordinator-main")
      assert is_pid(pid)
    end
  end

  describe "signal routing" do
    test "routes analysis.complete signals and broadcasts to clients" do
      # Create and dispatch an analysis complete signal
      signal =
        Signal.new!(
          "jido_coder.analysis.complete",
          %{
            analysis_type: "credo",
            results: %{errors: 2, warnings: 5},
            session_id: "session-123"
          }
        )

      # Send signal to coordinator
      pid = Jido.whereis(MyAppJido, "coordinator-main")
      Jido.AgentServer.cast(pid, signal)

      # Verify broadcast was sent to clients
      # The PubSub adapter broadcasts signals directly
      assert_receive(broadcast_signal, 500)
      assert broadcast_signal.type == "jido_coder.client.broadcast"
      assert broadcast_signal.data.event_type == "analysis_complete"
      assert broadcast_signal.data.payload.analysis_type == "credo"
    end

    test "routes issue.found signals and broadcasts to clients" do
      # Create and dispatch an issue found signal
      signal =
        Signal.new!(
          "jido_coder.analysis.issue.found",
          %{
            issue_type: "warning",
            message: "Unused variable",
            file_path: "/lib/test.ex",
            line: 42,
            severity: :medium
          }
        )

      # Send signal to coordinator
      pid = Jido.whereis(MyAppJido, "coordinator-main")
      Jido.AgentServer.cast(pid, signal)

      # Verify broadcast was sent to clients
      # The PubSub adapter broadcasts signals directly
      assert_receive(broadcast_signal, 500)
      assert broadcast_signal.type == "jido_coder.client.broadcast"
      assert broadcast_signal.data.event_type == "issue_found"
      assert broadcast_signal.data.payload.message == "Unused variable"
    end

    test "routes chat.request signals and broadcasts to clients" do
      # Create and dispatch a chat request signal
      signal =
        Signal.new!(
          "jido_coder.chat.request",
          %{
            message: "Help me debug this function",
            session_id: "session-456"
          }
        )

      # Send signal to coordinator
      pid = Jido.whereis(MyAppJido, "coordinator-main")
      Jido.AgentServer.cast(pid, signal)

      # Verify broadcast was sent to clients
      # The PubSub adapter broadcasts signals directly
      assert_receive(broadcast_signal, 500)
      assert broadcast_signal.type == "jido_coder.client.broadcast"
      assert broadcast_signal.data.event_type == "chat_received"
    end
  end

  describe "state management" do
    test "active_tasks are tracked" do
      # Send a chat request which creates an active task
      signal =
        Signal.new!(
          "jido_coder.chat.request",
          %{
            message: "Test message",
            session_id: "session-state-1"
          }
        )

      pid = Jido.whereis(MyAppJido, "coordinator-main")
      Jido.AgentServer.cast(pid, signal)

      # Wait for processing
      Process.sleep(100)

      # Check state has active_tasks
      {:ok, agent_state} = Jido.AgentServer.state(pid)
      assert agent_state.agent.state.active_tasks != %{}
    end
  end

  # Helper functions

  defp start_coordinator do
    # Stop any existing coordinator first
    case Jido.whereis(MyAppJido, "coordinator-main") do
      pid when is_pid(pid) ->
        Jido.stop_agent(MyAppJido, pid)
        # Give it time to fully stop
        Process.sleep(50)

      nil ->
        :ok
    end

    # Try to start the coordinator
    case Coordinator.start_link(id: "coordinator-main", name: :coordinator) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  defp stop_coordinator do
    case Jido.whereis(MyAppJido, "coordinator-main") do
      pid when is_pid(pid) -> Jido.stop_agent(MyAppJido, pid)
      nil -> :ok
    end
  end
end
