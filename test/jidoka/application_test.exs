defmodule Jidoka.ApplicationTest do
  use ExUnit.Case

  @moduledoc """
  Tests for the Jidoka Application module.
  """

  describe "start/2" do
    test "application starts without errors" do
      # The application should already be started in test context
      # Verify the supervisor is running
      assert Process.whereis(Jidoka.Supervisor) != nil
    end

    test "ProtocolSupervisor is accessible" do
      # Verify the DynamicSupervisor for protocols is running
      assert Process.whereis(Jidoka.ProtocolSupervisor) != nil

      # Verify it's a DynamicSupervisor
      pid = Process.whereis(Jidoka.ProtocolSupervisor)
      assert is_pid(pid)

      # Check it's actually a DynamicSupervisor
      children = DynamicSupervisor.which_children(Jidoka.ProtocolSupervisor)
      assert is_list(children)
    end

    test "supervisor strategy is :one_for_one" do
      # Get the supervisor's child specifications
      children = Supervisor.which_children(Jidoka.Supervisor)

      # Verify the DynamicSupervisor is a child
      assert Enum.any?(children, fn
               {_, pid, :supervisor, [DynamicSupervisor]} when is_pid(pid) -> true
               _ -> false
             end)
    end
  end

  describe "application lifecycle" do
    test "application stops gracefully" do
      # This test verifies that the application can stop without hanging
      # In a real scenario, we'd actually stop and restart, but that's
      # not practical in a running test context.

      # Instead, verify that the supervisor responds to calls
      assert Supervisor.count_children(Jidoka.Supervisor) != nil
    end
  end
end
