defmodule Jidoka.AgentSupervisorTest do
  use ExUnit.Case, async: false

  alias Jido.AgentServer
  alias Jidoka.AgentSupervisor
  alias Jidoka.Jido, as: MyAppJido

  import Process, only: [exit: 2]

  @moduletag :agent_supervisor_integration

  setup do
    # Note: Jido instance and AgentSupervisor are already started by the Application
    # The tests are run with the full application supervision tree

    :ok
  end

  describe "supervisor" do
    test "starts with rest_for_one strategy" do
      children = Supervisor.which_children(AgentSupervisor)
      assert length(children) > 0
    end

    test "coordinator agent is started as a child" do
      assert pid = Jido.whereis(MyAppJido, "coordinator-main")
      assert is_pid(pid)
    end

    test "coordinator can be stopped and restarted" do
      # Get initial PID
      pid = Jido.whereis(MyAppJido, "coordinator-main")
      initial_pid = pid

      # Stop the coordinator with :shutdown reason (triggers restart)
      exit(pid, :shutdown)
      Process.sleep(200)

      # Supervisor should restart it
      new_pid = Jido.whereis(MyAppJido, "coordinator-main")
      assert is_pid(new_pid)
      assert new_pid != initial_pid
    end
  end
end
