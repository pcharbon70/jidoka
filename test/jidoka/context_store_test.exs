defmodule Jidoka.ContextStoreTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for the Jidoka.ContextStore GenServer.
  """

  # Ensure the application is running for these tests
  setup_all do
    Application.ensure_all_started(:jidoka)
    :ok
  end

  # Helper to create temp file names
  defp temp_file_name, do: "/tmp/jido_test_#{System.unique_integer()}.tmp"

  describe "table_names/0" do
    test "returns the list of managed table names" do
      assert Jidoka.ContextStore.table_names() == [
               :file_content,
               :file_metadata,
               :analysis_cache
             ]
    end
  end

  describe "cache_file/3 and get_file/1" do
    test "caches and retrieves file content" do
      temp_file = temp_file_name()
      content = "defmodule Test do\n  :ok\nend"

      File.write!(temp_file, content)

      # Cache the file
      assert :ok = Jidoka.ContextStore.cache_file(temp_file, content)

      # Retrieve cached content
      assert {:ok, {^content, _mtime, size}} = Jidoka.ContextStore.get_file(temp_file)
      assert size > 0

      # Clean up
      File.rm!(temp_file)
      Jidoka.ContextStore.invalidate_file(temp_file)
    end

    test "caches file with metadata" do
      temp_file = temp_file_name()
      content = "test content"

      File.write!(temp_file, content)

      metadata = %{language: :elixir, lines: 1}
      assert :ok = Jidoka.ContextStore.cache_file(temp_file, content, metadata)

      # Check metadata was stored
      assert {:ok, stored_meta} = Jidoka.ContextStore.get_metadata(temp_file)
      assert stored_meta.language == :elixir
      assert stored_meta.lines == 1
      assert Map.has_key?(stored_meta, :mtime)
      assert Map.has_key?(stored_meta, :size)

      # Clean up
      File.rm!(temp_file)
      Jidoka.ContextStore.invalidate_file(temp_file)
    end
  end

  describe "get_metadata/1" do
    test "returns error for uncached file" do
      file_path = "/nonexistent/file_#{System.unique_integer()}.ex"

      assert Jidoka.ContextStore.get_metadata(file_path) == :error
    end

    test "returns metadata for cached file" do
      temp_file = temp_file_name()
      content = "test"

      File.write!(temp_file, content)

      metadata = %{language: :text}
      assert :ok = Jidoka.ContextStore.cache_file(temp_file, content, metadata)

      assert {:ok, stored} = Jidoka.ContextStore.get_metadata(temp_file)
      assert stored.language == :text

      # Clean up
      File.rm!(temp_file)
      Jidoka.ContextStore.invalidate_file(temp_file)
    end
  end

  describe "cache_analysis/3 and get_analysis/2" do
    test "caches and retrieves analysis results" do
      file_path = "/test/file_#{System.unique_integer()}.ex"
      analysis_type = :syntax_tree
      result = %{ast: [:module, :test]}

      # Not cached initially
      assert Jidoka.ContextStore.get_analysis(file_path, analysis_type) == :error

      # Cache the analysis
      assert :ok = Jidoka.ContextStore.cache_analysis(file_path, analysis_type, result)

      # Retrieve the analysis
      assert {:ok, ^result} = Jidoka.ContextStore.get_analysis(file_path, analysis_type)

      # Clean up
      Jidoka.ContextStore.invalidate_file(file_path)
    end

    test "caches multiple analysis types for same file" do
      file_path = "/test/file_#{System.unique_integer()}.ex"

      ast_result = %{ast: [:module]}
      lint_result = %{errors: [], warnings: []}

      # Cache both analyses
      assert :ok = Jidoka.ContextStore.cache_analysis(file_path, :syntax_tree, ast_result)
      assert :ok = Jidoka.ContextStore.cache_analysis(file_path, :lint, lint_result)

      # Retrieve both
      assert {:ok, ^ast_result} = Jidoka.ContextStore.get_analysis(file_path, :syntax_tree)
      assert {:ok, ^lint_result} = Jidoka.ContextStore.get_analysis(file_path, :lint)

      # Clean up
      Jidoka.ContextStore.invalidate_file(file_path)
    end

    test "get_analysis_with_timestamp returns timestamp" do
      file_path = "/test/file_#{System.unique_integer()}.ex"
      analysis_type = :test
      result = :test_result

      assert :ok = Jidoka.ContextStore.cache_analysis(file_path, analysis_type, result)

      assert {:ok, ^result, timestamp} =
               Jidoka.ContextStore.get_analysis_with_timestamp(file_path, analysis_type)

      assert is_integer(timestamp)

      # Clean up
      Jidoka.ContextStore.invalidate_file(file_path)
    end
  end

  describe "invalidate_file/1" do
    test "removes file from all caches" do
      temp_file = temp_file_name()
      content = "test content"

      File.write!(temp_file, content)

      # Cache file and analyses
      assert :ok = Jidoka.ContextStore.cache_file(temp_file, content)
      assert :ok = Jidoka.ContextStore.cache_analysis(temp_file, :test, :result)

      # Verify cached
      assert {:ok, _} = Jidoka.ContextStore.get_file(temp_file)
      assert {:ok, _} = Jidoka.ContextStore.get_metadata(temp_file)
      assert {:ok, _} = Jidoka.ContextStore.get_analysis(temp_file, :test)

      # Invalidate
      assert :ok = Jidoka.ContextStore.invalidate_file(temp_file)

      # Verify removed
      assert :error = Jidoka.ContextStore.get_file(temp_file)
      assert :error = Jidoka.ContextStore.get_metadata(temp_file)
      assert :error = Jidoka.ContextStore.get_analysis(temp_file, :test)

      # Clean up
      File.rm!(temp_file)
    end

    test "handles invalidating non-existent file gracefully" do
      file_path = "/nonexistent/file_#{System.unique_integer()}.ex"

      # Should not raise
      assert :ok = Jidoka.ContextStore.invalidate_file(file_path)
    end
  end

  describe "clear_all/0" do
    setup do
      # Clear everything before each test
      Jidoka.ContextStore.clear_all()
      :ok
    end

    test "clears all cache tables" do
      # Add some data
      temp_file = temp_file_name()
      content = "test"

      File.write!(temp_file, content)
      Jidoka.ContextStore.cache_file(temp_file, content)
      Jidoka.ContextStore.cache_analysis(temp_file, :test, :result)

      # Verify data exists
      assert {:ok, _} = Jidoka.ContextStore.get_file(temp_file)
      assert stats = Jidoka.ContextStore.stats()
      assert stats.file_content > 0
      assert stats.file_metadata > 0
      assert stats.analysis_cache > 0

      # Clear all
      assert :ok = Jidoka.ContextStore.clear_all()

      # Verify cleared
      assert :error = Jidoka.ContextStore.get_file(temp_file)
      assert stats = Jidoka.ContextStore.stats()
      assert stats.file_content == 0
      assert stats.file_metadata == 0
      assert stats.analysis_cache == 0

      # Clean up
      File.rm!(temp_file)
    end
  end

  describe "stats/0" do
    setup do
      Jidoka.ContextStore.clear_all()
      :ok
    end

    test "returns cache statistics" do
      temp_file = temp_file_name()
      content = "test"

      File.write!(temp_file, content)

      # Initially empty
      assert stats = Jidoka.ContextStore.stats()
      assert stats.file_content == 0
      assert stats.file_metadata == 0
      assert stats.analysis_cache == 0

      # Add data
      Jidoka.ContextStore.cache_file(temp_file, content, %{test: true})
      Jidoka.ContextStore.cache_analysis(temp_file, :type1, :result1)
      Jidoka.ContextStore.cache_analysis(temp_file, :type2, :result2)

      # Check stats
      assert stats = Jidoka.ContextStore.stats()
      assert stats.file_content == 1
      assert stats.file_metadata == 1
      assert stats.analysis_cache == 2

      # Clean up
      File.rm!(temp_file)
      Jidoka.ContextStore.clear_all()
    end
  end

  describe "ETS table configuration" do
    test "tables are created with correct options" do
      # Check if tables exist and have correct configuration
      for table <- [:file_content, :file_metadata, :analysis_cache] do
        info = :ets.info(table)

        # Table should exist
        assert is_list(info)

        # Check it's a set
        assert Keyword.get(info, :type) == :set

        # Check it's named
        assert Keyword.get(info, :named_table) == true

        # Check the owner (protection) is protected
        # :protected means only the owner GenServer can write, all processes can read
        # This provides security by preventing cache poisoning from other processes
        assert Keyword.get(info, :protection) == :protected
      end
    end

    test "file_content has read_concurrency" do
      info = :ets.info(:file_content)
      # read_concurrency is stored in :read_concurrency key
      assert Keyword.get(info, :read_concurrency) == true
    end

    test "file_metadata has read_concurrency" do
      info = :ets.info(:file_metadata)
      assert Keyword.get(info, :read_concurrency) == true
    end

    test "analysis_cache has read and write concurrency" do
      info = :ets.info(:analysis_cache)
      assert Keyword.get(info, :read_concurrency) == true
      assert Keyword.get(info, :write_concurrency) == true
    end
  end

  describe "concurrent access" do
    setup do
      Jidoka.ContextStore.clear_all()
      :ok
    end

    test "concurrent reads do not block" do
      temp_file = temp_file_name()
      content = "test content"

      File.write!(temp_file, content)
      Jidoka.ContextStore.cache_file(temp_file, content, %{test: true})

      # Spawn multiple readers
      parent = self()

      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            result = Jidoka.ContextStore.get_file(temp_file)
            send(parent, {:read_result, result})
          end)
        end

      # All should complete successfully
      results =
        for _ <- tasks do
          assert_receive {:read_result, result}
          result
        end

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)

      # Clean up
      File.rm!(temp_file)
      Jidoka.ContextStore.clear_all()
    end

    test "concurrent writes work correctly" do
      file_path = "/test/file_#{System.unique_integer()}.ex"

      # Spawn multiple writers
      parent = self()

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            result = Jidoka.ContextStore.cache_analysis(file_path, :test, i)
            send(parent, {:write_result, result})
          end)
        end

      # All should complete
      for _ <- tasks do
        assert_receive {:write_result, result}
        assert result == :ok
      end

      # One should have won (last write wins in ETS)
      assert {:ok, value} = Jidoka.ContextStore.get_analysis(file_path, :test)
      assert is_integer(value)

      # Clean up
      Jidoka.ContextStore.invalidate_file(file_path)
    end
  end

  describe "session-scoped operations (Phase 3.5)" do
    setup do
      # Clear everything before each test
      Jidoka.ContextStore.clear_all()
      :ok
    end

    test "cache_file/4 stores with composite session key" do
      session_id = "session-123"
      temp_file = temp_file_name()
      content = "defmodule SessionTest do\n  :ok\nend"

      File.write!(temp_file, content)

      # Cache with session_id
      assert :ok = Jidoka.ContextStore.cache_file(session_id, temp_file, content)

      # Retrieve with same session_id
      assert {:ok, {^content, _mtime, _size}} =
               Jidoka.ContextStore.get_file(session_id, temp_file)

      # Retrieve without session_id (global) should not find it
      assert :error = Jidoka.ContextStore.get_file(temp_file)

      # Clean up
      File.rm!(temp_file)
      Jidoka.ContextStore.clear_session_cache(session_id)
    end

    test "cache_file/4 with metadata stores session-scoped metadata" do
      session_id = "session-456"
      temp_file = temp_file_name()
      content = "test"

      File.write!(temp_file, content)

      metadata = %{language: :elixir, lines: 5}
      assert :ok = Jidoka.ContextStore.cache_file(session_id, temp_file, content, metadata)

      # Check metadata with session_id
      assert {:ok, stored_meta} = Jidoka.ContextStore.get_metadata(session_id, temp_file)
      assert stored_meta.language == :elixir
      assert stored_meta.lines == 5

      # Global metadata should be different
      assert :error = Jidoka.ContextStore.get_metadata(temp_file)

      # Clean up
      File.rm!(temp_file)
      Jidoka.ContextStore.clear_session_cache(session_id)
    end

    test "data is isolated between sessions" do
      session_a = "session-a"
      session_b = "session-b"
      file_path = temp_file_name()
      content_a = "content from session a"
      content_b = "content from session b"

      File.write!(file_path, content_a)

      # Cache same file with different content for each session
      assert :ok = Jidoka.ContextStore.cache_file(session_a, file_path, content_a)

      File.write!(file_path, content_b)
      assert :ok = Jidoka.ContextStore.cache_file(session_b, file_path, content_b)

      # Each session should get its own content
      assert {:ok, {^content_a, _, _}} = Jidoka.ContextStore.get_file(session_a, file_path)
      assert {:ok, {^content_b, _, _}} = Jidoka.ContextStore.get_file(session_b, file_path)

      # Clean up
      File.rm!(file_path)
      Jidoka.ContextStore.clear_session_cache(session_a)
      Jidoka.ContextStore.clear_session_cache(session_b)
    end

    test "invalidate_file/2 only affects session data" do
      session_a = "session-invalidate-a"
      session_b = "session-invalidate-b"
      file_path = temp_file_name()
      content = "test content"

      File.write!(file_path, content)

      # Cache for both sessions
      assert :ok = Jidoka.ContextStore.cache_file(session_a, file_path, content)
      assert :ok = Jidoka.ContextStore.cache_file(session_b, file_path, content)

      # Invalidate only session_a
      assert :ok = Jidoka.ContextStore.invalidate_file(session_a, file_path)

      # Session a should not have the file
      assert :error = Jidoka.ContextStore.get_file(session_a, file_path)

      # Session b should still have it
      assert {:ok, {^content, _, _}} = Jidoka.ContextStore.get_file(session_b, file_path)

      # Clean up
      File.rm!(file_path)
      Jidoka.ContextStore.clear_session_cache(session_a)
      Jidoka.ContextStore.clear_session_cache(session_b)
    end

    test "clear_session_cache/1 removes all session data" do
      session_id = "session-clear-test"
      file1 = temp_file_name() <> ".1"
      file2 = temp_file_name() <> ".2"
      file3 = temp_file_name() <> ".3"

      File.write!(file1, "content1")
      File.write!(file2, "content2")
      File.write!(file3, "content3")

      # Cache files for session
      assert :ok = Jidoka.ContextStore.cache_file(session_id, file1, "content1")
      assert :ok = Jidoka.ContextStore.cache_file(session_id, file2, "content2")
      assert :ok = Jidoka.ContextStore.cache_file(session_id, file3, "content3")

      # Cache some analyses
      assert :ok = Jidoka.ContextStore.cache_analysis(session_id, file1, :ast, :ast_result)

      assert :ok =
               Jidoka.ContextStore.cache_analysis(session_id, file2, :lint, :lint_result)

      # Verify data exists
      assert {:ok, _} = Jidoka.ContextStore.get_file(session_id, file1)
      assert {:ok, _} = Jidoka.ContextStore.get_file(session_id, file2)
      assert {:ok, _} = Jidoka.ContextStore.get_file(session_id, file3)
      assert {:ok, _} = Jidoka.ContextStore.get_metadata(session_id, file1)
      assert {:ok, _} = Jidoka.ContextStore.get_analysis(session_id, file1, :ast)

      # Clear session cache
      assert :ok = Jidoka.ContextStore.clear_session_cache(session_id)

      # All session data should be gone
      assert :error = Jidoka.ContextStore.get_file(session_id, file1)
      assert :error = Jidoka.ContextStore.get_file(session_id, file2)
      assert :error = Jidoka.ContextStore.get_file(session_id, file3)
      assert :error = Jidoka.ContextStore.get_metadata(session_id, file1)
      assert :error = Jidoka.ContextStore.get_analysis(session_id, file1, :ast)

      # Clean up files
      File.rm!(file1)
      File.rm!(file2)
      File.rm!(file3)
    end

    test "analysis cache is session-scoped" do
      session_a = "session-analysis-a"
      session_b = "session-analysis-b"
      file_path = temp_file_name()

      File.write!(file_path, "content")

      # Cache different analyses for each session
      assert :ok =
               Jidoka.ContextStore.cache_analysis(session_a, file_path, :ast, %{
                 ast: [:session_a]
               })

      assert :ok =
               Jidoka.ContextStore.cache_analysis(session_b, file_path, :ast, %{
                 ast: [:session_b]
               })

      # Each session should get its own analysis
      assert {:ok, %{ast: [:session_a]}} =
               Jidoka.ContextStore.get_analysis(session_a, file_path, :ast)

      assert {:ok, %{ast: [:session_b]}} =
               Jidoka.ContextStore.get_analysis(session_b, file_path, :ast)

      # Clean up
      File.rm!(file_path)
      Jidoka.ContextStore.clear_session_cache(session_a)
      Jidoka.ContextStore.clear_session_cache(session_b)
    end

    test "analysis cache with timestamp is session-scoped" do
      session_a = "session-timestamp-a"
      session_b = "session-timestamp-b"
      file_path = temp_file_name()

      File.write!(file_path, "content")

      # Cache analysis for session_a
      assert :ok =
               Jidoka.ContextStore.cache_analysis(session_a, file_path, :test, :result_a)

      Process.sleep(10)

      # Cache analysis for session_b
      assert :ok =
               Jidoka.ContextStore.cache_analysis(session_b, file_path, :test, :result_b)

      # Get timestamps
      assert {:ok, :result_a, timestamp_a} =
               Jidoka.ContextStore.get_analysis_with_timestamp(session_a, file_path, :test)

      assert {:ok, :result_b, timestamp_b} =
               Jidoka.ContextStore.get_analysis_with_timestamp(session_b, file_path, :test)

      # Timestamps should be different (cached at different times)
      assert timestamp_a < timestamp_b

      # Clean up
      File.rm!(file_path)
      Jidoka.ContextStore.clear_session_cache(session_a)
      Jidoka.ContextStore.clear_session_cache(session_b)
    end

    test "concurrent session access works correctly" do
      sessions = ["session-1", "session-2", "session-3", "session-4", "session-5"]
      file_path = temp_file_name()

      File.write!(file_path, "content")

      # Concurrent writes from different sessions
      tasks =
        for session <- sessions do
          Task.async(fn ->
            content = "content from #{session}"
            Jidoka.ContextStore.cache_file(session, file_path, content)
          end)
        end

      # All writes should succeed
      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))

      # Each session should have its own content
      for session <- sessions do
        expected_content = "content from #{session}"

        assert {:ok, {^expected_content, _, _}} =
                 Jidoka.ContextStore.get_file(session, file_path)
      end

      # Clean up
      File.rm!(file_path)
      for session <- sessions, do: Jidoka.ContextStore.clear_session_cache(session)
    end

    test "global cache is separate from session caches" do
      session_id = "session-global-test"
      file_path = temp_file_name()

      File.write!(file_path, "global content")

      # Cache in global scope
      assert :ok = Jidoka.ContextStore.cache_file(file_path, "global content")

      # Cache in session scope
      assert :ok = Jidoka.ContextStore.cache_file(session_id, file_path, "session content")

      # Global should have global content
      assert {:ok, {"global content", _, _}} = Jidoka.ContextStore.get_file(file_path)

      # Session should have session content
      assert {:ok, {"session content", _, _}} =
               Jidoka.ContextStore.get_file(session_id, file_path)

      # Invalidate session should not affect global
      assert :ok = Jidoka.ContextStore.invalidate_file(session_id, file_path)
      assert {:ok, {"global content", _, _}} = Jidoka.ContextStore.get_file(file_path)

      # Invalidate global should not affect session (if session re-caches)
      assert :ok =
               Jidoka.ContextStore.cache_file(session_id, file_path, "session content 2")

      assert :ok = Jidoka.ContextStore.invalidate_file(file_path)
      assert :error = Jidoka.ContextStore.get_file(file_path)

      assert {:ok, {"session content 2", _, _}} =
               Jidoka.ContextStore.get_file(session_id, file_path)

      # Clean up
      File.rm!(file_path)
      Jidoka.ContextStore.clear_session_cache(session_id)
    end

    test "backward compatibility - 2-arity cache_file uses global" do
      file_path = temp_file_name()

      File.write!(file_path, "content")

      # Using 2-arity (backward compatible)
      assert :ok = Jidoka.ContextStore.cache_file(file_path, "content")

      # Should be accessible via global get_file/1
      assert {:ok, {"content", _, _}} = Jidoka.ContextStore.get_file(file_path)

      # Should NOT be accessible via session-scoped get_file/2
      assert :error = Jidoka.ContextStore.get_file("some-session", file_path)

      # Clean up
      File.rm!(file_path)
      Jidoka.ContextStore.invalidate_file(file_path)
    end

    test "backward compatibility - 3-arity cache_file with metadata uses global" do
      file_path = temp_file_name()

      File.write!(file_path, "content")

      metadata = %{language: :elixir}
      assert :ok = Jidoka.ContextStore.cache_file(file_path, "content", metadata)

      # Should be accessible via global get_file/1 and get_metadata/1
      assert {:ok, {"content", _, _}} = Jidoka.ContextStore.get_file(file_path)
      assert {:ok, meta} = Jidoka.ContextStore.get_metadata(file_path)
      assert meta.language == :elixir

      # Clean up
      File.rm!(file_path)
      Jidoka.ContextStore.invalidate_file(file_path)
    end

    test "stats reflect session-scoped data" do
      session_a = "session-stats-a"
      session_b = "session-stats-b"
      file_a = temp_file_name() <> ".a"
      file_b = temp_file_name() <> ".b"

      File.write!(file_a, "content a")
      File.write!(file_b, "content b")

      # Cache files for different sessions
      assert :ok = Jidoka.ContextStore.cache_file(session_a, file_a, "content a")
      assert :ok = Jidoka.ContextStore.cache_file(session_b, file_b, "content b")

      # Add some analyses
      assert :ok = Jidoka.ContextStore.cache_analysis(session_a, file_a, :ast, :ast_a)
      assert :ok = Jidoka.ContextStore.cache_analysis(session_b, file_b, :ast, :ast_b)

      # Stats should reflect all entries
      assert stats = Jidoka.ContextStore.stats()
      assert stats.file_content == 2
      assert stats.file_metadata == 2
      assert stats.analysis_cache == 2

      # Clear one session
      assert :ok = Jidoka.ContextStore.clear_session_cache(session_a)

      # Stats should update
      assert stats = Jidoka.ContextStore.stats()
      assert stats.file_content == 1
      assert stats.file_metadata == 1
      assert stats.analysis_cache == 1

      # Clean up
      File.rm!(file_a)
      File.rm!(file_b)
      Jidoka.ContextStore.clear_session_cache(session_b)
    end
  end
end
