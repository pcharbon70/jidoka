defmodule Jidoka.Protocol.Phoenix.ConnectionSupervisorTest do
  use ExUnit.Case, async: false

  alias Jidoka.Protocol.Phoenix.ConnectionSupervisor

  describe "start_link/1" do
    test "starts the supervisor successfully" do
      assert {:ok, _pid} = ConnectionSupervisor.start_link([])
    end

    test "can only be started once" do
      assert {:ok, _pid} = ConnectionSupervisor.start_link([])
      assert {:error, {:already_started, _pid}} = ConnectionSupervisor.start_link([])
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec" do
      spec = ConnectionSupervisor.child_spec([])

      assert spec.id == Jidoka.Protocol.Phoenix.ConnectionSupervisor
      assert spec.start == {ConnectionSupervisor, :start_link, [[]]}
      assert is_list(spec.start)
    end
  end
end
