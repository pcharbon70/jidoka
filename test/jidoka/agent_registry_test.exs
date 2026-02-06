defmodule Jidoka.AgentRegistryTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for the Jidoka.AgentRegistry module.
  """

  describe "registry_name/0" do
    test "returns the correct registry name" do
      assert Jidoka.AgentRegistry.registry_name() == Jidoka.AgentRegistry
    end
  end

  describe "register/2" do
    test "registers the current process under a unique key" do
      key = "agent:test_#{System.unique_integer()}"

      assert {:ok, ^key} = Jidoka.AgentRegistry.register(key)
      assert Jidoka.AgentRegistry.registered?(key)

      Jidoka.AgentRegistry.unregister(key)
    end

    test "prevents duplicate registration under the same key" do
      key = "agent:test_#{System.unique_integer()}"

      assert {:ok, ^key} = Jidoka.AgentRegistry.register(key)

      assert {:error, _} = Jidoka.AgentRegistry.register(key)

      Jidoka.AgentRegistry.unregister(key)
    end

    test "allows different processes to register under different keys" do
      key1 = "agent:test1_#{System.unique_integer()}"
      key2 = "agent:test2_#{System.unique_integer()}"

      assert {:ok, ^key1} = Jidoka.AgentRegistry.register(key1)

      # Spawn a process to register under a different key
      parent = self()

      child =
        spawn(fn ->
          {:ok, ^key2} = Jidoka.AgentRegistry.register(key2)
          send(parent, {:registered, key2})
          Process.sleep(:infinity)
        end)

      assert_receive {:registered, ^key2}

      # Both should be registered
      assert Jidoka.AgentRegistry.registered?(key1)
      assert Jidoka.AgentRegistry.registered?(key2)

      Jidoka.AgentRegistry.unregister(key1)
      # Clean up child process
      Process.exit(child, :kill)
    end
  end

  describe "lookup/1" do
    test "returns the process PID when found" do
      key = "agent:test_#{System.unique_integer()}"

      {:ok, ^key} = Jidoka.AgentRegistry.register(key)

      assert {:ok, pid} = Jidoka.AgentRegistry.lookup(key)
      assert pid == self()

      Jidoka.AgentRegistry.unregister(key)
    end

    test "returns :error when key not found" do
      key = "agent:nonexistent_#{System.unique_integer()}"

      assert :error = Jidoka.AgentRegistry.lookup(key)
    end
  end

  describe "unregister/1" do
    test "unregisters the current process from a key" do
      key = "agent:test_#{System.unique_integer()}"

      {:ok, ^key} = Jidoka.AgentRegistry.register(key)
      assert Jidoka.AgentRegistry.registered?(key)

      Jidoka.AgentRegistry.unregister(key)
      refute Jidoka.AgentRegistry.registered?(key)
    end
  end

  describe "dispatch/3" do
    test "sends a message to the registered process" do
      key = "agent:test_#{System.unique_integer()}"

      {:ok, ^key} = Jidoka.AgentRegistry.register(key)

      Jidoka.AgentRegistry.dispatch(key, :test_message)

      assert_receive {sender, :test_message}
      assert sender == self()

      Jidoka.AgentRegistry.unregister(key)
    end

    test "returns :error when no process is registered" do
      key = "agent:nonexistent_#{System.unique_integer()}"

      assert :error = Jidoka.AgentRegistry.dispatch(key, :test_message)
    end

    test "accepts custom from option" do
      key = "agent:test_#{System.unique_integer()}"

      {:ok, ^key} = Jidoka.AgentRegistry.register(key)

      custom_pid = spawn(fn -> Process.sleep(:infinity) end)
      Jidoka.AgentRegistry.dispatch(key, :test_message, from: custom_pid)

      assert_receive {^custom_pid, :test_message}

      Jidoka.AgentRegistry.unregister(key)
      Process.exit(custom_pid, :kill)
    end
  end

  describe "count/1" do
    test "returns 1 when a process is registered" do
      key = "agent:test_#{System.unique_integer()}"

      {:ok, ^key} = Jidoka.AgentRegistry.register(key)

      assert Jidoka.AgentRegistry.count(key) == 1

      Jidoka.AgentRegistry.unregister(key)
    end

    test "returns 0 when no process is registered" do
      key = "agent:nonexistent_#{System.unique_integer()}"

      assert Jidoka.AgentRegistry.count(key) == 0
    end
  end

  describe "list_keys/0" do
    test "returns all registered keys" do
      key1 = "agent:test1_#{System.unique_integer()}"
      key2 = "agent:test2_#{System.unique_integer()}"

      {:ok, ^key1} = Jidoka.AgentRegistry.register(key1)
      {:ok, ^key2} = Jidoka.AgentRegistry.register(key2)

      keys = Jidoka.AgentRegistry.list_keys()

      assert key1 in keys
      assert key2 in keys

      Jidoka.AgentRegistry.unregister(key1)
      Jidoka.AgentRegistry.unregister(key2)
    end
  end

  describe "registered?/1" do
    test "returns true when a process is registered" do
      key = "agent:test_#{System.unique_integer()}"

      {:ok, ^key} = Jidoka.AgentRegistry.register(key)

      assert Jidoka.AgentRegistry.registered?(key)

      Jidoka.AgentRegistry.unregister(key)
    end

    test "returns false when no process is registered" do
      key = "agent:nonexistent_#{System.unique_integer()}"

      refute Jidoka.AgentRegistry.registered?(key)
    end
  end

  describe "automatic cleanup" do
    test "automatically unregisters when process dies" do
      key = "agent:test_#{System.unique_integer()}"

      # Spawn a process that registers and waits
      parent = self()

      child =
        spawn(fn ->
          {:ok, ^key} = Jidoka.AgentRegistry.register(key)
          send(parent, {:registered, key, self()})
          # Wait for signal to exit
          receive do
            :exit -> :ok
          end
        end)

      assert_receive {:registered, ^key, _pid}

      # Process should be registered
      assert Jidoka.AgentRegistry.registered?(key)

      # Tell child to exit
      send(child, :exit)

      # Wait for process to exit
      Process.sleep(100)
      refute Process.alive?(child)

      # Registration should be cleaned up
      refute Jidoka.AgentRegistry.registered?(key)
    end
  end
end
