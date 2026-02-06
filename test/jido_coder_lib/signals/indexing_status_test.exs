defmodule JidoCoderLib.Signals.IndexingStatusTest do
  use ExUnit.Case, async: true

  alias JidoCoderLib.Signals

  @moduletag :signals
  @moduletag :indexing_status

  describe "indexing_status/3" do
    test "creates a signal with required fields" do
      assert {:ok, signal} = Signals.indexing_status("lib/my_app.ex", :in_progress)

      assert signal.type == "jido_coder.indexing.status"
      assert signal.data.file_path == "lib/my_app.ex"
      assert signal.data.status == :in_progress
    end

    test "creates a completed signal with triple count" do
      assert {:ok, signal} =
               Signals.indexing_status("lib/my_app.ex", :completed,
                 triple_count: 42,
                 duration_ms: 150
               )

      assert signal.data.file_path == "lib/my_app.ex"
      assert signal.data.status == :completed
      assert signal.data.triple_count == 42
      assert signal.data.duration_ms == 150
    end

    test "creates a failed signal with error message" do
      assert {:ok, signal} =
               Signals.indexing_status("lib/invalid.ex", :failed,
                 error_message: "Syntax error at line 10",
                 duration_ms: 50
               )

      assert signal.data.file_path == "lib/invalid.ex"
      assert signal.data.status == :failed
      assert signal.data.error_message == "Syntax error at line 10"
      assert signal.data.duration_ms == 50
    end

    test "creates a signal with project root" do
      assert {:ok, signal} =
               Signals.indexing_status("lib/my_app.ex", :in_progress,
                 project_root: "/home/user/project"
               )

      assert signal.data.file_path == "lib/my_app.ex"
      assert signal.data.project_root == "/home/user/project"
    end

    test "creates a signal without dispatching when dispatch: false" do
      assert {:ok, signal} =
               Signals.indexing_status("lib/my_app.ex", :in_progress, dispatch: false)

      assert signal.type == "jido_coder.indexing.status"
    end
  end

  describe "signal data validation" do
    test "requires file_path" do
      assert {:error, _reason} = Signals.IndexingStatus.new(%{status: :in_progress})
    end

    test "requires status" do
      assert {:error, _reason} =
               Signals.IndexingStatus.new(%{file_path: "lib/my_app.ex"})
    end

    test "accepts valid status values" do
      valid_statuses = [:pending, :in_progress, :completed, :failed]

      Enum.each(valid_statuses, fn status ->
        assert {:ok, _signal} =
                 Signals.IndexingStatus.new(%{
                   file_path: "lib/my_app.ex",
                   status: status
                 })
      end)
    end
  end
end
