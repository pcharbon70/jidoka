defmodule Jidoka.Memory.ShortTerm.WorkingContextTest do
  use ExUnit.Case, async: true

  alias Jidoka.Memory.ShortTerm.WorkingContext

  describe "new/1" do
    test "creates context with defaults" do
      ctx = WorkingContext.new()

      assert ctx.data == %{}
      assert ctx.max_items == 50
      assert ctx.access_log == []
    end

    test "creates context with custom options" do
      ctx = WorkingContext.new(max_items: 100)

      assert ctx.max_items == 100
    end
  end

  describe "put/3" do
    test "stores a value" do
      ctx = WorkingContext.new()

      assert {:ok, ctx} = WorkingContext.put(ctx, "key", "value")
      assert {:ok, "value"} = WorkingContext.get(ctx, "key")
    end

    test "returns error when at capacity" do
      ctx = WorkingContext.new(max_items: 1)

      {:ok, ctx} = WorkingContext.put(ctx, "key1", "val1")
      assert {:error, :at_capacity} = WorkingContext.put(ctx, "key2", "val2")
    end

    test "allows updating existing key even at capacity" do
      ctx = WorkingContext.new(max_items: 1)

      {:ok, ctx} = WorkingContext.put(ctx, "key", "val1")
      assert {:ok, ctx} = WorkingContext.put(ctx, "key", "val2")

      assert {:ok, "val2"} = WorkingContext.get(ctx, "key")
    end
  end

  describe "get/2" do
    test "retrieves stored value" do
      ctx = WorkingContext.new()
      {:ok, ctx} = WorkingContext.put(ctx, "key", "value")

      assert {:ok, "value"} = WorkingContext.get(ctx, "key")
    end

    test "returns error for missing key" do
      ctx = WorkingContext.new()

      assert {:error, :not_found} = WorkingContext.get(ctx, "missing")
    end
  end

  describe "get/3" do
    test "returns default for missing key" do
      ctx = WorkingContext.new()

      assert WorkingContext.get(ctx, "missing", "default") == "default"
    end
  end

  describe "has_key?/2" do
    test "returns true for existing key" do
      ctx = WorkingContext.new()
      {:ok, ctx} = WorkingContext.put(ctx, "key", "value")

      assert WorkingContext.has_key?(ctx, "key")
    end

    test "returns false for missing key" do
      ctx = WorkingContext.new()

      refute WorkingContext.has_key?(ctx, "missing")
    end
  end

  describe "delete/2" do
    test "deletes a key" do
      ctx = WorkingContext.new()
      {:ok, ctx} = WorkingContext.put(ctx, "key", "value")

      {:ok, ctx} = WorkingContext.delete(ctx, "key")

      refute WorkingContext.has_key?(ctx, "key")
    end

    test "returns error for missing key" do
      ctx = WorkingContext.new()

      assert {:error, :not_found} = WorkingContext.delete(ctx, "missing")
    end
  end

  describe "keys/1" do
    test "returns all keys" do
      ctx = WorkingContext.new()
      {:ok, ctx} = WorkingContext.put(ctx, "key1", "val1")
      {:ok, ctx} = WorkingContext.put(ctx, "key2", "val2")

      keys = WorkingContext.keys(ctx)

      assert "key1" in keys
      assert "key2" in keys
    end
  end

  describe "count/1" do
    test "returns item count" do
      ctx = WorkingContext.new()
      assert WorkingContext.count(ctx) == 0

      {:ok, ctx} = WorkingContext.put(ctx, "key", "val")
      assert WorkingContext.count(ctx) == 1
    end
  end

  describe "clear/1" do
    test "clears all data" do
      ctx = WorkingContext.new()
      {:ok, ctx} = WorkingContext.put(ctx, "key", "val")

      {:ok, ctx} = WorkingContext.clear(ctx)

      assert WorkingContext.count(ctx) == 0
    end
  end

  describe "recent_keys/2" do
    test "returns recently accessed keys" do
      ctx = WorkingContext.new()
      {:ok, ctx} = WorkingContext.put(ctx, "key1", "val1")
      {:ok, ctx} = WorkingContext.put(ctx, "key2", "val2")
      {:ok, ctx} = WorkingContext.put(ctx, "key1", "val1")

      recent = WorkingContext.recent_keys(ctx, 2)

      assert hd(recent) == "key1"
      assert Enum.at(recent, 1) == "key2"
    end
  end

  describe "put_many/2" do
    test "stores multiple values" do
      ctx = WorkingContext.new()

      updates = %{"key1" => "val1", "key2" => "val2"}
      assert {:ok, ctx} = WorkingContext.put_many(ctx, updates)

      assert {:ok, "val1"} = WorkingContext.get(ctx, "key1")
      assert {:ok, "val2"} = WorkingContext.get(ctx, "key2")
    end

    test "returns error when would exceed capacity" do
      ctx = WorkingContext.new(max_items: 1)

      assert {:error, :at_capacity} = WorkingContext.put_many(ctx, %{"k1" => "v1", "k2" => "v2"})
    end
  end

  describe "list/1" do
    test "returns all items as list of tuples" do
      ctx = WorkingContext.new()
      {:ok, ctx} = WorkingContext.put(ctx, "key1", "val1")
      {:ok, ctx} = WorkingContext.put(ctx, "key2", "val2")

      items = WorkingContext.list(ctx)

      assert is_list(items)
      assert length(items) == 2
      assert {"key1", "val1"} in items
      assert {"key2", "val2"} in items
    end

    test "returns empty list when context is empty" do
      ctx = WorkingContext.new()

      assert WorkingContext.list(ctx) == []
    end
  end

  describe "suggest_type/3" do
    test "suggests file_context for file-related keys" do
      ctx = WorkingContext.new()

      assert WorkingContext.suggest_type(ctx, "current_file", "/path/to/file.ex") == :file_context
      assert WorkingContext.suggest_type(ctx, "file_path", "/src/app.ex") == :file_context
      assert WorkingContext.suggest_type(ctx, "directory", "/home/user") == :file_context
      assert WorkingContext.suggest_type(ctx, "folder", "project") == :file_context
    end

    test "suggests analysis for analysis-related keys" do
      ctx = WorkingContext.new()

      assert WorkingContext.suggest_type(ctx, "analysis_result", %{status: :ok}) == :analysis
      assert WorkingContext.suggest_type(ctx, "conclusion", "bug_found") == :analysis
      assert WorkingContext.suggest_type(ctx, "decision", "refactor") == :analysis
      assert WorkingContext.suggest_type(ctx, "recommendation", "use_enum") == :analysis
    end

    test "suggests conversation for conversation-related keys" do
      ctx = WorkingContext.new()

      assert WorkingContext.suggest_type(ctx, "last_message", "hello") == :conversation
      assert WorkingContext.suggest_type(ctx, "chat_id", "123") == :conversation
      assert WorkingContext.suggest_type(ctx, "dialog_state", "active") == :conversation
      assert WorkingContext.suggest_type(ctx, "conversation_history", []) == :conversation
    end

    test "suggests analysis for task-related keys" do
      ctx = WorkingContext.new()

      assert WorkingContext.suggest_type(ctx, "current_task", "refactor") == :analysis
      assert WorkingContext.suggest_type(ctx, "todo_item", "fix_bug") == :analysis
      assert WorkingContext.suggest_type(ctx, "action", "commit") == :analysis
      assert WorkingContext.suggest_type(ctx, "next_step", "test") == :analysis
    end

    test "suggests fact for generic keys" do
      ctx = WorkingContext.new()

      assert WorkingContext.suggest_type(ctx, "user_name", "Alice") == :fact
      assert WorkingContext.suggest_type(ctx, "count", 42) == :fact
      assert WorkingContext.suggest_type(ctx, "status", :active) == :fact
    end

    test "handles case-insensitive key matching" do
      ctx = WorkingContext.new()

      assert WorkingContext.suggest_type(ctx, "Current_File", "/path.ex") == :file_context
      assert WorkingContext.suggest_type(ctx, "ANALYSIS_RESULT", %{}) == :analysis
      assert WorkingContext.suggest_type(ctx, "Message", "test") == :conversation
    end
  end
end
