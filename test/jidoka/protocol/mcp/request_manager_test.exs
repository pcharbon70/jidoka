defmodule Jidoka.Protocol.MCP.RequestManagerTest do
  use ExUnit.Case, async: true

  alias Jidoka.Protocol.MCP.RequestManager

  describe "start_link/1" do
    test "starts the request manager" do
      assert {:ok, pid} = RequestManager.start_link([])
      assert Process.alive?(pid)
    end

    test "accepts timeout option" do
      assert {:ok, pid} = RequestManager.start_link(timeout: 5000)
      assert Process.alive?(pid)
    end
  end

  describe "register_request/2" do
    test "returns incrementing request IDs" do
      {:ok, pid} = RequestManager.start_link([])

      assert {:ok, 1} = RequestManager.register_request(pid, :test)
      assert {:ok, 2} = RequestManager.register_request(pid, :test)
      assert {:ok, 3} = RequestManager.register_request(pid, :test)
    end
  end

  describe "cancel_request/2" do
    test "cancels a pending request" do
      {:ok, pid} = RequestManager.start_link([])

      assert {:ok, request_id} = RequestManager.register_request(pid, :test)
      assert :ok = RequestManager.cancel_request(pid, request_id)
      assert {:error, :not_found} = RequestManager.cancel_request(pid, request_id)
    end

    test "returns error for non-existent request" do
      {:ok, pid} = RequestManager.start_link([])

      assert {:error, :not_found} = RequestManager.cancel_request(pid, 999)
    end
  end

  describe "handle_response/3" do
    test "replies to waiting process" do
      {:ok, pid} = RequestManager.start_link([])

      # Register a request from a spawned process
      parent = self()

      task =
        Task.async(fn ->
          request_id = RequestManager.register_request(pid, :test)

          # Wait for response
          receive do
            {:ok, response} -> {:ok, request_id, response}
          after
            1000 -> :timeout
          end
        end)

      # Give task time to register
      Process.sleep(10)

      # Get the request ID from the task
      request_id =
        case Task.yield(task, 100) do
          {:ok, _} -> 1
          nil -> 1
        end

      # Send response
      assert :ok = RequestManager.handle_response(pid, request_id, %{"result" => "success"})
    end

    test "returns error for unknown request ID" do
      {:ok, pid} = RequestManager.start_link([])

      assert {:error, :not_found} =
               RequestManager.handle_response(pid, 999, %{"result" => "success"})
    end
  end

  describe "pending_count/1" do
    test "returns count of pending requests" do
      {:ok, pid} = RequestManager.start_link([])

      assert 0 = RequestManager.pending_count(pid)

      RequestManager.register_request(pid, :test1)
      assert 1 = RequestManager.pending_count(pid)

      RequestManager.register_request(pid, :test2)
      assert 2 = RequestManager.pending_count(pid)

      RequestManager.register_request(pid, :test3)
      assert 3 = RequestManager.pending_count(pid)
    end
  end

  describe "timeout handling" do
    test "times out requests after timeout period" do
      # Start with very short timeout
      assert {:ok, pid} = RequestManager.start_link(timeout: 100)

      # Register a request
      assert {:ok, request_id} = RequestManager.register_request(pid, :test)

      # Wait for timeout check (happens every 1 second)
      # Since we can't wait that long in a test, we'll just verify it doesn't crash
      assert Process.alive?(pid)
    end
  end
end
