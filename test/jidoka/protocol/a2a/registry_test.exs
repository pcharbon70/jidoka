defmodule Jidoka.Protocol.A2A.RegistryTest do
  use ExUnit.Case, async: false

  alias Jidoka.Protocol.A2A.Registry

  doctest Registry

  setup do
    # Ensure a clean registry for each test
    case Registry.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "start_link/0" do
    test "starts the registry" do
      assert {:ok, _pid} = Registry.start_link()
    end

    test "returns already started if registry exists" do
      assert {:error, {:already_started, _pid}} = Registry.start_link()
    end
  end

  describe "register/2" do
    test "registers a process with an agent ID" do
      test_agent = self()

      assert :ok = Registry.register(:coordinator, test_agent)
      assert {:ok, ^test_agent} = Registry.lookup(:coordinator)
    end

    test "registers current process by default" do
      assert :ok = Registry.register(:llm_agent)
      assert {:ok, pid} = Registry.lookup(:llm_agent)
      assert pid == self()
    end

    test "returns error when registering duplicate agent ID" do
      assert :ok = Registry.register(:duplicate)
      assert {:error, :already_registered} = Registry.register(:duplicate)
    end
  end

  describe "unregister/1" do
    test "unregisters an agent" do
      assert :ok = Registry.register(:to_unregister)
      assert :ok = Registry.unregister(:to_unregister)
      assert {:error, :not_found} = Registry.lookup(:to_unregister)
    end

    test "returns error when unregistering non-existent agent" do
      assert {:error, :not_found} = Registry.unregister(:non_existent)
    end
  end

  describe "lookup/1" do
    test "finds a registered agent" do
      test_agent = self()

      Registry.register(:lookup_test, test_agent)
      assert {:ok, ^test_agent} = Registry.lookup(:lookup_test)
    end

    test "returns error for non-existent agent" do
      assert {:error, :not_found} = Registry.lookup(:ghost_agent)
    end
  end

  describe "send_message/2" do
    test "sends message to registered agent" do
      # Register this process
      Registry.register(:message_target)

      # Send a message
      assert :ok = Registry.send_message(:message_target, {:test, "data"})

      # Verify the message was received
      assert_received {:test, "data"}
    end

    test "returns error when agent not found" do
      assert {:error, :not_found} = Registry.send_message(:unknown_agent, :message)
    end

    test "returns error when agent is not running" do
      # Create a short-lived process and register it
      {pid, ref} = spawn_monitor(fn -> :timer.sleep(1000) end)

      # Register the agent (using the Registry directly)
      # We need to use the internal API for this test
      :ok = Registry.register(:dead_agent_walking, pid)

      # Wait for process to die
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000

      # The registry should have cleaned up the dead process
      # Attempting to send a message should fail
      assert {:error, :not_found} = Registry.send_message(:dead_agent_walking, :message)
    end
  end

  describe "list_agents/0" do
    test "lists all registered agents" do
      # Register some agents
      :ok = Registry.register(:agent1)
      :ok = Registry.register(:agent2)
      :ok = Registry.register(:agent3)

      agents = Registry.list_agents()

      # Check that our agents are in the list
      assert :agent1 in agents
      assert :agent2 in agents
      assert :agent3 in agents
    end

    test "returns empty list when no agents registered" do
      # Unregister all agents from previous tests
      Registry.list_agents()
      |> Enum.each(&Registry.unregister/1)

      agents = Registry.list_agents()
      assert agents == []
    end
  end

  describe "process monitoring" do
    test "automatically unregisters dead processes" do
      # Create a short-lived process
      {pid, ref} = spawn_monitor(fn -> :timer.sleep(500) end)

      # Register the agent
      :ok = Registry.register(:temporary_agent, pid)

      # Verify it's registered
      assert {:ok, ^pid} = Registry.lookup(:temporary_agent)

      # Wait for process to die
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000

      # Give the registry a moment to clean up
      Process.sleep(100)

      # Verify it's unregistered
      assert {:error, :not_found} = Registry.lookup(:temporary_agent)
    end
  end

  describe "whereis/1" do
    test "returns pid of registered agent" do
      test_agent = self()
      Registry.register(:whereis_test, test_agent)

      assert ^test_agent = Registry.whereis(:whereis_test)
    end

    test "returns nil for non-existent agent" do
      assert nil == Registry.whereis(:non_existent)
    end
  end
end
