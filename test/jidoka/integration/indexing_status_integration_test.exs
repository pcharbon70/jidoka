defmodule Jidoka.Integration.IndexingStatusIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration tests for Phase 6.4.5 Indexing Status Tracking.

  These tests verify that the IndexingStatusTracker works correctly
  with the Knowledge Engine and other components.

  Note: These tests use the global IndexingStatusTracker process from
  the supervision tree. Tests use unique file paths to avoid interference.
  """

  alias Jidoka.Indexing.IndexingStatusTracker
  alias Jidoka.Signals

  @moduletag :indexing_status_integration
  @moduletag :external

  describe "Application Startup" do
    test "IndexingStatusTracker is started in supervision tree" do
      assert Process.whereis(IndexingStatusTracker) != nil
    end

    test "IndexingStatusTracker is functional" do
      # Can query status before any operations
      # Note: The lists may have items from previous tests since this is a singleton
      assert {:ok, in_progress} = IndexingStatusTracker.list_in_progress()
      assert {:ok, failed} = IndexingStatusTracker.list_failed()
      assert is_list(in_progress)
      assert is_list(failed)
    end
  end

  describe "Full Indexing Workflow" do
    test "complete indexing workflow" do
      file_path = "lib/integration_complete_test_#{:erlang.unique_integer()}.ex"

      # Start indexing
      :ok = IndexingStatusTracker.start_indexing(file_path)

      # Verify in_progress status
      assert {:ok, :in_progress} = IndexingStatusTracker.get_status(file_path)

      # Complete indexing
      :ok = IndexingStatusTracker.complete_indexing(file_path, 42)

      # Verify completed status
      assert {:ok, :completed} = IndexingStatusTracker.get_status(file_path)
      assert {:ok, operation} = IndexingStatusTracker.get_operation(file_path)
      assert operation.status == :completed
      assert operation.triple_count == 42
    end

    test "get_project_status returns correct counts" do
      project_root = Path.join(["/", "tmp", "project_#{:erlang.unique_integer()}"])
      file_path = Path.join([project_root, "file.ex"])

      # Start and complete indexing
      :ok = IndexingStatusTracker.start_indexing(file_path)
      :ok = IndexingStatusTracker.complete_indexing(file_path, 42)

      # Get project status
      assert {:ok, status} = IndexingStatusTracker.get_project_status(project_root)
      assert status.total == 1
      assert status.completed == 1
      assert status.in_progress == 0
      assert status.failed == 0
    end

    test "re-indexing workflow" do
      file_path = "lib/integration_reindex_test_#{:erlang.unique_integer()}.ex"

      # Start and complete first indexing
      :ok = IndexingStatusTracker.start_indexing(file_path)
      :ok = IndexingStatusTracker.complete_indexing(file_path, 42)
      assert {:ok, :completed} = IndexingStatusTracker.get_status(file_path)

      # Start re-indexing
      :ok = IndexingStatusTracker.start_indexing(file_path)
      assert {:ok, :in_progress} = IndexingStatusTracker.get_status(file_path)

      # Complete re-indexing with new triple count
      :ok = IndexingStatusTracker.complete_indexing(file_path, 50)
      assert {:ok, :completed} = IndexingStatusTracker.get_status(file_path)

      # Verify updated triple count
      assert {:ok, operation} = IndexingStatusTracker.get_operation(file_path)
      assert operation.triple_count == 50
    end
  end

  describe "Error Handling Workflow" do
    test "failed indexing workflow" do
      file_path = "lib/integration_failed_test_#{:erlang.unique_integer()}.ex"

      # Start indexing
      :ok = IndexingStatusTracker.start_indexing(file_path)

      # Fail indexing
      error_msg = "Parse error: unexpected token"
      :ok = IndexingStatusTracker.fail_indexing(file_path, error_msg)

      # Verify failed status
      assert {:ok, :failed} = IndexingStatusTracker.get_status(file_path)
      assert {:ok, operation} = IndexingStatusTracker.get_operation(file_path)
      assert operation.status == :failed
      assert operation.error == error_msg

      # Verify in failed list
      assert {:ok, failed_ops} = IndexingStatusTracker.list_failed()
      assert length(failed_ops) >= 1
      assert Enum.any?(failed_ops, fn op -> op.file_path == file_path end)
    end

    test "get_project_status includes failed operations" do
      project_root = Path.join(["/", "tmp", "project_#{:erlang.unique_integer()}"])
      file_path = Path.join([project_root, "file.ex"])

      # Start and fail indexing
      :ok = IndexingStatusTracker.start_indexing(file_path)
      :ok = IndexingStatusTracker.fail_indexing(file_path, "error")

      # Get project status
      assert {:ok, status} = IndexingStatusTracker.get_project_status(project_root)
      assert status.total >= 1
      assert status.failed >= 1
    end
  end

  describe "Signal Integration" do
    test "indexing_status/2 creates valid signals" do
      file_path = "lib/integration_signal_test_#{:erlang.unique_integer()}.ex"

      assert {:ok, signal} = Signals.indexing_status(file_path, :in_progress)
      assert signal.type == "jido_coder.indexing.status"
      assert signal.data.file_path == file_path
      assert signal.data.status == :in_progress
    end

    test "indexing_status/2 with optional fields" do
      file_path = "lib/integration_signal_opts_test_#{:erlang.unique_integer()}.ex"

      assert {:ok, signal} =
               Signals.indexing_status(file_path, :completed,
                 project_root: "/home/user/project",
                 triple_count: 42,
                 duration_ms: 150
               )

      assert signal.data.project_root == "/home/user/project"
      assert signal.data.triple_count == 42
      assert signal.data.duration_ms == 150
    end
  end

  describe "Knowledge Graph Persistence" do
    test "operation info is retrievable after completion" do
      file_path = "lib/integration_kg_test_#{:erlang.unique_integer()}.ex"

      # Start and complete indexing
      :ok = IndexingStatusTracker.start_indexing(file_path)
      :ok = IndexingStatusTracker.complete_indexing(file_path, 10)

      assert {:ok, operation} = IndexingStatusTracker.get_operation(file_path)
      assert operation.file_path == file_path
      assert operation.status == :completed
      assert operation.triple_count == 10
      assert operation.started_at != nil
      assert operation.completed_at != nil
    end
  end

  describe "Project Filtering" do
    test "get_project_status filters by project root" do
      project_root = Path.join(["/", "home", "project_#{:erlang.unique_integer()}"])
      other_root = Path.join(["/", "home", "other_#{:erlang.unique_integer()}"])

      # Add files to different projects
      file1 = Path.join([project_root, "file1.ex"])
      file2 = Path.join([other_root, "file2.ex"])

      IndexingStatusTracker.start_indexing(file1)
      IndexingStatusTracker.complete_indexing(file1, 10)

      IndexingStatusTracker.start_indexing(file2)
      IndexingStatusTracker.complete_indexing(file2, 20)

      # Should only count files under project_root
      assert {:ok, status1} = IndexingStatusTracker.get_project_status(project_root)
      assert status1.total == 1
      assert status1.completed == 1

      # Should only count files under other_root
      assert {:ok, status2} = IndexingStatusTracker.get_project_status(other_root)
      assert status2.total == 1
      assert status2.completed == 1
    end
  end
end
