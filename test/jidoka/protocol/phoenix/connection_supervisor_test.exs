defmodule Jidoka.Protocol.Phoenix.ConnectionSupervisorTest do
  use ExUnit.Case, async: false

  alias Jidoka.Protocol.Phoenix.ConnectionSupervisor

  setup do
    # The ConnectionSupervisor is started by the application during
    # ProtocolSupervisor.start_configured_protocols/0.
    # We need to stop it first to test start_link behavior.
    case Process.whereis(Jidoka.Protocol.Phoenix.ConnectionSupervisor) do
      nil -> :ok
      pid ->
        # Use ProtocolSupervisor to properly stop the protocol
        try do
          Jidoka.ProtocolSupervisor.stop_protocol(Jidoka.Protocol.Phoenix.ConnectionSupervisor)
          # Wait for the process to fully terminate
          Process.sleep(100)
        catch
          _, _ ->
            # Fallback: try stopping the supervisor directly
            try do
              Supervisor.stop(pid)
              Process.sleep(100)
            catch
              _, _ -> Process.exit(pid, :kill)
            end
        end
    end

    :ok
  end

  describe "start_link/1" do
    test "starts the supervisor successfully" do
      # Supervisor should not be running after setup
      refute Process.whereis(Jidoka.Protocol.Phoenix.ConnectionSupervisor)

      assert {:ok, pid} = ConnectionSupervisor.start_link([])
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Clean up - stop the supervisor we just started
      :ok = Supervisor.stop(pid)
      Process.sleep(50)
    end

    test "can only be started once" do
      # Start the supervisor
      assert {:ok, pid} = ConnectionSupervisor.start_link([])
      assert is_pid(pid)

      # Trying to start again should fail
      assert {:error, {:already_started, ^pid}} = ConnectionSupervisor.start_link([])

      # Clean up
      :ok = Supervisor.stop(pid)
      Process.sleep(50)
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec" do
      spec = ConnectionSupervisor.child_spec([])

      assert spec.id == Jidoka.Protocol.Phoenix.ConnectionSupervisor
      assert spec.start == {ConnectionSupervisor, :start_link, [[]]}
      # start is a tuple in MFA format {module, function, args}, not a list
      assert is_tuple(spec.start)
      assert tuple_size(spec.start) == 3
    end
  end
end
