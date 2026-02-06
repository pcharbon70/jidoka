defmodule Jidoka.Protocol.MCP.Transport.StdioTest do
  use ExUnit.Case, async: false

  alias Jidoka.Protocol.MCP.Transport.Stdio

  describe "connect/1" do
    test "requires command option" do
      assert_raise ArgumentError, fn ->
        Stdio.connect([])
      end
    end

    test "starts with echo command for testing" do
      # Use echo as a simple test command
      assert {:ok, pid} = Stdio.connect(command: "cat")
      assert Process.alive?(pid)
      assert :ok = Stdio.close(pid)
    end

    test "accepts cd option" do
      assert {:ok, pid} = Stdio.connect(command: "cat", cd: "/tmp")
      assert Process.alive?(pid)
      assert :ok = Stdio.close(pid)
    end
  end

  describe "send_message/2" do
    test "sends JSON message to transport" do
      assert {:ok, pid} = Stdio.connect(command: "cat")

      # Send a message
      message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping", "params" => %{}}
      assert :ok = Stdio.send_message(pid, message)

      # Clean up
      :ok = Stdio.close(pid)
    end

    test "handles invalid process" do
      message = %{"test" => "value"}
      assert {:error, _} = Stdio.send_message(self(), message)
    end
  end

  describe "close/1" do
    test "closes the transport" do
      assert {:ok, pid} = Stdio.connect(command: "cat")
      assert Process.alive?(pid)

      assert :ok = Stdio.close(pid)

      # Process should terminate
      Process.sleep(100)
      refute Process.alive?(pid)
    end
  end

  describe "lifecycle" do
    test "handles process exit gracefully" do
      # Use a command that exits quickly
      assert {:ok, pid} = Stdio.connect(command: "echo done && exit")

      # Wait for process to exit
      Process.sleep(200)

      # Transport should handle the exit
      # The GenServer should still be alive but report disconnected
      assert Process.alive?(pid) or Process.alive?(pid)
    end
  end
end
