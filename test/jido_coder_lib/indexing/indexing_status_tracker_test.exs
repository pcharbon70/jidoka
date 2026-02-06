defmodule JidoCoderLib.Indexing.IndexingStatusTrackerTest do
  use ExUnit.Case, async: false

  alias JidoCoderLib.Indexing.IndexingStatusTracker

  @moduletag :indexing_status_tracker
  @moduletag :external

  # Helper to start a tracker with a unique name for each test
  defp start_unique_tracker do
    name = :"tracker_#{:erlang.unique_integer()}"
    {:ok, pid} = IndexingStatusTracker.start_link(name: name, engine_name: :knowledge_engine)
    {name, pid}
  end

  # Helper to safely stop a tracker
  defp stop_tracker(name) do
    if Process.whereis(name) do
      GenServer.stop(name, :normal, 1000)
    else
      :ok
    end
  end

  describe "start_link/1" do
    test "starts the tracker successfully" do
      {_name, pid} = start_unique_tracker()
      assert is_pid(pid)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "initial state is empty" do
      {name, _pid} = start_unique_tracker()
      assert {:ok, []} = IndexingStatusTracker.list_in_progress(name: name)
      assert {:ok, []} = IndexingStatusTracker.list_failed(name: name)
      GenServer.stop(name)
    end
  end

  describe "start_indexing/2" do
    setup do
      {name, _pid} = start_unique_tracker()
      on_exit(fn -> stop_tracker(name) end)
      %{name: name}
    end

    test "creates an in_progress operation", context do
      file_path = "lib/my_app.ex"
      assert :ok = IndexingStatusTracker.start_indexing(file_path, name: context.name)
      assert {:ok, :in_progress} = IndexingStatusTracker.get_status(file_path, name: context.name)
      assert {:ok, [operation]} = IndexingStatusTracker.list_in_progress(name: context.name)
      assert operation.file_path == file_path
      assert operation.status == :in_progress
    end

    test "emits telemetry event on start", context do
      file_path = "lib/my_app.ex"
      test_pid = self()
      handler_id = :erlang.unique_integer()

      :telemetry.attach(
        "start-test-#{handler_id}",
        [:jido_coder_lib, :indexing, :started],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_started, metadata})
        end,
        nil
      )

      IndexingStatusTracker.start_indexing(file_path, name: context.name)
      assert_received {:telemetry_started, metadata}
      assert metadata.file_path == file_path
      :telemetry.detach("start-test-#{handler_id}")
    end
  end

  describe "complete_indexing/3" do
    setup do
      {name, _pid} = start_unique_tracker()
      on_exit(fn -> stop_tracker(name) end)
      file_path = "lib/my_app.ex"
      IndexingStatusTracker.start_indexing(file_path, name: name)
      %{name: name, file_path: file_path}
    end

    test "marks operation as completed with triple count", context do
      assert :ok =
               IndexingStatusTracker.complete_indexing(context.file_path, 42, name: context.name)

      assert {:ok, :completed} =
               IndexingStatusTracker.get_status(context.file_path, name: context.name)

      assert {:ok, operation} =
               IndexingStatusTracker.get_operation(context.file_path, name: context.name)

      assert operation.status == :completed
      assert operation.triple_count == 42
      assert {:ok, []} = IndexingStatusTracker.list_in_progress(name: context.name)
    end

    test "emits telemetry event on completion", context do
      test_pid = self()
      handler_id = :erlang.unique_integer()

      :telemetry.attach(
        "complete-test-#{handler_id}",
        [:jido_coder_lib, :indexing, :completed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_completed, measurements, metadata})
        end,
        nil
      )

      IndexingStatusTracker.complete_indexing(context.file_path, 42, name: context.name)
      assert_received {:telemetry_completed, measurements, metadata}
      assert measurements.duration != nil
      assert measurements.triple_count == 42
      :telemetry.detach("complete-test-#{handler_id}")
    end
  end

  describe "fail_indexing/3" do
    setup do
      {name, _pid} = start_unique_tracker()
      on_exit(fn -> stop_tracker(name) end)
      file_path = "lib/invalid.ex"
      IndexingStatusTracker.start_indexing(file_path, name: name)
      %{name: name, file_path: file_path}
    end

    test "marks operation as failed with error message", context do
      error_msg = "Syntax error at line 10"

      assert :ok =
               IndexingStatusTracker.fail_indexing(context.file_path, error_msg,
                 name: context.name
               )

      assert {:ok, :failed} =
               IndexingStatusTracker.get_status(context.file_path, name: context.name)

      assert {:ok, operation} =
               IndexingStatusTracker.get_operation(context.file_path, name: context.name)

      assert operation.status == :failed
      assert operation.error == error_msg
      assert {:ok, []} = IndexingStatusTracker.list_in_progress(name: context.name)
      assert {:ok, [failed_op]} = IndexingStatusTracker.list_failed(name: context.name)
      assert failed_op.file_path == context.file_path
    end

    test "emits telemetry event on failure", context do
      error_msg = "Parse error"
      test_pid = self()
      handler_id = :erlang.unique_integer()

      :telemetry.attach(
        "fail-test-#{handler_id}",
        [:jido_coder_lib, :indexing, :failed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_failed, measurements, metadata})
        end,
        nil
      )

      IndexingStatusTracker.fail_indexing(context.file_path, error_msg, name: context.name)
      assert_received {:telemetry_failed, measurements, metadata}
      assert measurements.duration != nil
      assert metadata.file_path == context.file_path
      assert metadata.error_message == error_msg
      :telemetry.detach("fail-test-#{handler_id}")
    end
  end

  describe "get_status/2" do
    setup do
      {name, _pid} = start_unique_tracker()
      on_exit(fn -> stop_tracker(name) end)
      %{name: name}
    end

    test "returns :in_progress for active operations", context do
      file_path = "lib/my_app.ex"
      IndexingStatusTracker.start_indexing(file_path, name: context.name)
      assert {:ok, :in_progress} = IndexingStatusTracker.get_status(file_path, name: context.name)
    end

    test "returns :completed for completed operations", context do
      file_path = "lib/my_app.ex"
      IndexingStatusTracker.start_indexing(file_path, name: context.name)
      IndexingStatusTracker.complete_indexing(file_path, 10, name: context.name)
      assert {:ok, :completed} = IndexingStatusTracker.get_status(file_path, name: context.name)
    end

    test "returns :failed for failed operations", context do
      file_path = "lib/invalid.ex"
      IndexingStatusTracker.start_indexing(file_path, name: context.name)
      IndexingStatusTracker.fail_indexing(file_path, "error", name: context.name)
      assert {:ok, :failed} = IndexingStatusTracker.get_status(file_path, name: context.name)
    end

    test "returns error for unknown files", context do
      assert {:error, :not_found} =
               IndexingStatusTracker.get_status("lib/unknown.ex", name: context.name)
    end
  end

  describe "get_project_status/2" do
    setup do
      {name, _pid} = start_unique_tracker()
      on_exit(fn -> stop_tracker(name) end)
      %{name: name, project_root: System.tmp_dir!()}
    end

    test "returns aggregate status for project", context do
      IndexingStatusTracker.start_indexing(Path.join([context.project_root, "file1.ex"]),
        name: context.name
      )

      IndexingStatusTracker.start_indexing(Path.join([context.project_root, "file2.ex"]),
        name: context.name
      )

      IndexingStatusTracker.start_indexing(Path.join([context.project_root, "file3.ex"]),
        name: context.name
      )

      IndexingStatusTracker.complete_indexing(Path.join([context.project_root, "file1.ex"]), 10,
        name: context.name
      )

      IndexingStatusTracker.fail_indexing(Path.join([context.project_root, "file2.ex"]), "error",
        name: context.name
      )

      assert {:ok, status} =
               IndexingStatusTracker.get_project_status(context.project_root, name: context.name)

      assert status.total == 3
      assert status.in_progress == 1
      assert status.completed == 1
      assert status.failed == 1
    end

    test "filters by project root", context do
      IndexingStatusTracker.start_indexing(Path.join([context.project_root, "file1.ex"]),
        name: context.name
      )

      IndexingStatusTracker.complete_indexing(Path.join([context.project_root, "file1.ex"]), 5,
        name: context.name
      )

      # Use a completely different directory for the other project (not under tmp dir)
      other_project = Path.join(["/", "home", "other_project_#{:erlang.unique_integer()}"])

      IndexingStatusTracker.start_indexing(Path.join([other_project, "other.ex"]),
        name: context.name
      )

      assert {:ok, status} =
               IndexingStatusTracker.get_project_status(context.project_root, name: context.name)

      assert status.total == 1
      assert status.completed == 1
    end
  end

  describe "re-indexing" do
    setup do
      {name, _pid} = start_unique_tracker()
      on_exit(fn -> stop_tracker(name) end)
      %{name: name}
    end

    test "allows re-indexing a completed file", context do
      name = context.name
      file_path = "lib/my_app.ex"
      IndexingStatusTracker.start_indexing(file_path, name: name)
      IndexingStatusTracker.complete_indexing(file_path, 10, name: name)
      assert {:ok, :completed} = IndexingStatusTracker.get_status(file_path, name: name)

      IndexingStatusTracker.start_indexing(file_path, name: name)
      assert {:ok, :in_progress} = IndexingStatusTracker.get_status(file_path, name: name)
      IndexingStatusTracker.complete_indexing(file_path, 15, name: name)
      assert {:ok, :completed} = IndexingStatusTracker.get_status(file_path, name: name)

      assert {:ok, operation} = IndexingStatusTracker.get_operation(file_path, name: name)
      assert operation.triple_count == 15
    end

    test "allows re-indexing a failed file", context do
      name = context.name
      file_path = "lib/fixing.ex"
      IndexingStatusTracker.start_indexing(file_path, name: name)
      IndexingStatusTracker.fail_indexing(file_path, "syntax error", name: name)
      assert {:ok, :failed} = IndexingStatusTracker.get_status(file_path, name: name)

      IndexingStatusTracker.start_indexing(file_path, name: name)
      assert {:ok, :in_progress} = IndexingStatusTracker.get_status(file_path, name: name)
      IndexingStatusTracker.complete_indexing(file_path, 20, name: name)
      assert {:ok, :completed} = IndexingStatusTracker.get_status(file_path, name: name)

      assert {:ok, []} = IndexingStatusTracker.list_failed(name: name)
    end
  end
end
