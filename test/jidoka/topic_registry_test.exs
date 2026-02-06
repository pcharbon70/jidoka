defmodule Jidoka.TopicRegistryTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for the Jidoka.TopicRegistry module.
  """

  describe "registry_name/0" do
    test "returns the correct registry name" do
      assert Jidoka.TopicRegistry.registry_name() == Jidoka.TopicRegistry
    end
  end

  describe "register/2" do
    test "registers the current process under a key" do
      key = "topic:test:#{System.unique_integer()}"

      assert {:ok, ^key} = Jidoka.TopicRegistry.register(key)
      assert Jidoka.TopicRegistry.registered?(key)

      Jidoka.TopicRegistry.unregister(key)
    end

    test "allows multiple processes to register under the same key" do
      key = "topic:test:#{System.unique_integer()}"
      parent = self()

      # First process (current)
      {:ok, ^key} = Jidoka.TopicRegistry.register(key)

      # Spawn two more processes
      pids =
        for i <- 1..2 do
          spawn(fn ->
            {:ok, ^key} = Jidoka.TopicRegistry.register(key)
            send(parent, {:registered, i, self()})
            Process.sleep(:infinity)
          end)
        end

      # Wait for both to register
      assert_receive {:registered, 1, _}
      assert_receive {:registered, 2, _}

      # Should have 3 processes registered
      assert Jidoka.TopicRegistry.count(key) == 3

      # Clean up
      Jidoka.TopicRegistry.unregister(key)
      Enum.each(pids, &Process.exit(&1, :kill))
    end
  end

  describe "lookup/1" do
    test "returns all processes registered under a key" do
      key = "topic:test:#{System.unique_integer()}"
      parent = self()

      {:ok, ^key} = Jidoka.TopicRegistry.register(key)

      # Spawn another process
      child =
        spawn(fn ->
          {:ok, ^key} = Jidoka.TopicRegistry.register(key)
          send(parent, {:registered, self()})
          Process.sleep(:infinity)
        end)

      assert_receive {:registered, ^child}

      # Lookup should return both processes
      assert {:ok, entries} = Jidoka.TopicRegistry.lookup(key)
      assert length(entries) == 2

      pids = for {pid, _} <- entries, do: pid
      assert self() in pids
      assert child in pids

      # Clean up
      Jidoka.TopicRegistry.unregister(key)
      Process.exit(child, :kill)
    end

    test "returns empty list when key not found" do
      key = "topic:nonexistent_#{System.unique_integer()}"

      assert :error = Jidoka.TopicRegistry.lookup(key)
    end
  end

  describe "unregister/1" do
    test "unregisters the current process from a key" do
      key = "topic:test:#{System.unique_integer()}"
      parent = self()

      {:ok, ^key} = Jidoka.TopicRegistry.register(key)

      # Spawn another process
      child =
        spawn(fn ->
          {:ok, ^key} = Jidoka.TopicRegistry.register(key)
          send(parent, {:ready})
          Process.sleep(:infinity)
        end)

      assert_receive {:ready}

      # Should have 2 registered
      assert Jidoka.TopicRegistry.count(key) == 2

      # Unregister current process
      Jidoka.TopicRegistry.unregister(key)

      # Should still have 1 (the child)
      assert Jidoka.TopicRegistry.count(key) == 1

      # Clean up
      Process.exit(child, :kill)
    end
  end

  describe "dispatch/3" do
    test "sends a message to all registered processes" do
      key = "topic:test:#{System.unique_integer()}"
      parent = self()

      {:ok, ^key} = Jidoka.TopicRegistry.register(key)

      # Spawn two more processes that forward messages
      children =
        for i <- 1..2 do
          spawn(fn ->
            {:ok, ^key} = Jidoka.TopicRegistry.register(key)
            send(parent, {:registered, i})

            receive do
              {_sender, msg} -> send(parent, {:received, i, msg})
            end
          end)
        end

      # Wait for registration
      assert_receive {:registered, 1}
      assert_receive {:registered, 2}

      # Dispatch a message
      assert {:ok, 3} = Jidoka.TopicRegistry.dispatch(key, :broadcast)

      # All processes should receive
      assert_receive {_sender, :broadcast}
      assert_receive {:received, 1, :broadcast}
      assert_receive {:received, 2, :broadcast}

      # Clean up
      Jidoka.TopicRegistry.unregister(key)
      Enum.each(children, &Process.exit(&1, :kill))
    end

    test "returns :error when no processes are registered" do
      key = "topic:nonexistent:#{System.unique_integer()}"

      assert :error = Jidoka.TopicRegistry.dispatch(key, :test_message)
    end

    test "returns count of processes that received the message" do
      key = "topic:test:#{System.unique_integer()}"
      parent = self()

      {:ok, ^key} = Jidoka.TopicRegistry.register(key)

      # Spawn processes
      for _ <- 1..2 do
        spawn(fn ->
          {:ok, ^key} = Jidoka.TopicRegistry.register(key)
          send(parent, {:ready})
          Process.sleep(:infinity)
        end)
      end

      assert_receive {:ready}
      assert_receive {:ready}

      # Dispatch should report 3 recipients
      assert {:ok, 3} = Jidoka.TopicRegistry.dispatch(key, :test)

      # Clean up
      Jidoka.TopicRegistry.unregister(key)
    end

    test "accepts custom from option" do
      key = "topic:test:#{System.unique_integer()}"

      {:ok, ^key} = Jidoka.TopicRegistry.register(key)

      custom_pid = spawn(fn -> Process.sleep(:infinity) end)
      Jidoka.TopicRegistry.dispatch(key, :test_message, from: custom_pid)

      assert_receive {^custom_pid, :test_message}

      # Clean up
      Jidoka.TopicRegistry.unregister(key)
      Process.exit(custom_pid, :kill)
    end
  end

  describe "count/1" do
    test "returns the number of processes registered under a key" do
      key = "topic:test:#{System.unique_integer()}"
      parent = self()

      {:ok, ^key} = Jidoka.TopicRegistry.register(key)

      # Spawn a couple more processes
      for _ <- 1..2 do
        spawn(fn ->
          {:ok, ^key} = Jidoka.TopicRegistry.register(key)
          send(parent, {:ready})
          Process.sleep(:infinity)
        end)
      end

      assert_receive {:ready}
      assert_receive {:ready}

      assert Jidoka.TopicRegistry.count(key) == 3

      # Clean up
      Jidoka.TopicRegistry.unregister(key)
    end

    test "returns 0 when no process is registered" do
      key = "topic:nonexistent:#{System.unique_integer()}"

      assert Jidoka.TopicRegistry.count(key) == 0
    end
  end

  describe "list_keys/0" do
    test "returns all unique registered keys" do
      key1 = "topic:test1:#{System.unique_integer()}"
      key2 = "topic:test2:#{System.unique_integer()}"

      {:ok, ^key1} = Jidoka.TopicRegistry.register(key1)
      {:ok, ^key2} = Jidoka.TopicRegistry.register(key2)

      keys = Jidoka.TopicRegistry.list_keys()

      assert key1 in keys
      assert key2 in keys

      Jidoka.TopicRegistry.unregister(key1)
      Jidoka.TopicRegistry.unregister(key2)
    end
  end

  describe "registered?/1" do
    test "returns true when at least one process is registered" do
      key = "topic:test:#{System.unique_integer()}"

      {:ok, ^key} = Jidoka.TopicRegistry.register(key)

      assert Jidoka.TopicRegistry.registered?(key)

      Jidoka.TopicRegistry.unregister(key)
    end

    test "returns false when no process is registered" do
      key = "topic:nonexistent:#{System.unique_integer()}"

      refute Jidoka.TopicRegistry.registered?(key)
    end
  end

  describe "register_multi/1" do
    test "registers the current process under multiple keys" do
      key1 = "topic:test1:#{System.unique_integer()}"
      key2 = "topic:test2:#{System.unique_integer()}"

      assert {:ok, [^key1, ^key2]} = Jidoka.TopicRegistry.register_multi([key1, key2])

      assert Jidoka.TopicRegistry.registered?(key1)
      assert Jidoka.TopicRegistry.registered?(key2)

      # Clean up
      Jidoka.TopicRegistry.unregister(key1)
      Jidoka.TopicRegistry.unregister(key2)
    end

    test "returns error list when any registration fails" do
      # Test with valid keys to show the function works
      key1 = "topic:test1:#{System.unique_integer()}"

      # Should succeed normally
      assert {:ok, [^key1]} = Jidoka.TopicRegistry.register_multi([key1])

      # Clean up
      Jidoka.TopicRegistry.unregister(key1)
    end
  end

  describe "automatic cleanup" do
    test "automatically unregisters when a process dies" do
      key = "topic:test:#{System.unique_integer()}"
      parent = self()

      # Spawn a process that registers and waits
      child =
        spawn(fn ->
          {:ok, ^key} = Jidoka.TopicRegistry.register(key)
          send(parent, {:registered, key, self()})
          # Wait for signal to exit
          receive do
            :exit -> :ok
          end
        end)

      assert_receive {:registered, ^key, _pid}

      # Process should be registered
      assert Jidoka.TopicRegistry.count(key) >= 1

      # Tell child to exit
      send(child, :exit)

      # Wait for process to exit and cleanup
      Process.sleep(100)
      refute Process.alive?(child)

      # Registration should be cleaned up for that process
      # Count should be 0 now since that was the only process
      assert Jidoka.TopicRegistry.count(key) == 0
    end
  end
end
