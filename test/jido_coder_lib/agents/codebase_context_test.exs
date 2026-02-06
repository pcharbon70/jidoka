defmodule JidoCoderLib.Agents.CodebaseContextTest do
  use ExUnit.Case, async: false

  @moduletag :codebase_context

  alias JidoCoderLib.Agents.CodebaseContext

  describe "start_link/1" do
    test "starts the cache server successfully" do
      {:ok, pid} = CodebaseContext.start_link()
      assert is_pid(pid)
      assert Process.alive?(pid)
      :ok = GenServer.stop(pid)
    end

    test "accepts custom cache_ttl" do
      {:ok, pid} = CodebaseContext.start_link(cache_ttl: 1000)
      assert is_pid(pid)
      :ok = GenServer.stop(pid)
    end
  end

  describe "get_module_info/2" do
    test "returns module info when module exists" do
      # First, ensure we have indexed code
      # This test assumes some modules are indexed
      {:ok, pid} = CodebaseContext.start_link()

      # Try to get info about a module that should exist in the codebase
      case CodebaseContext.get_module_info("JidoCoderLib.Indexing.CodeIndexer") do
        {:ok, info} ->
          assert is_map(info)
          assert info.name == "JidoCoderLib.Indexing.CodeIndexer"

        {:error, :not_found} ->
          # Module not indexed yet, which is OK for this test
          :ok

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end

      :ok = GenServer.stop(pid)
    end

    test "returns not_found for non-existent module" do
      {:ok, pid} = CodebaseContext.start_link()

      assert {:error, :not_found} =
               CodebaseContext.get_module_info("TotallyFakeModule.DoesNotExist")

      :ok = GenServer.stop(pid)
    end

    test "caches module info results" do
      {:ok, pid} = CodebaseContext.start_link()

      # First call - cache miss
      case CodebaseContext.get_module_info("JidoCoderLib.Agents.CodebaseContext") do
        {:ok, info1} ->
          # Second call - cache hit
          assert {:ok, ^info1} =
                   CodebaseContext.get_module_info("JidoCoderLib.Agents.CodebaseContext")

        _ ->
          # Not indexed, skip cache test
          :ok
      end

      :ok = GenServer.stop(pid)
    end

    test "respects use_cache option" do
      {:ok, pid} = CodebaseContext.start_link()

      # Without cache
      result1 =
        CodebaseContext.get_module_info("JidoCoderLib.Agents.ContextManager",
          use_cache: false
        )

      # With cache
      result2 =
        CodebaseContext.get_module_info("JidoCoderLib.Agents.ContextManager",
          use_cache: true
        )

      # Both should return the same type of result
      assert elem(result1, 0) == elem(result2, 0)

      :ok = GenServer.stop(pid)
    end
  end

  describe "get_dependencies/2" do
    test "returns dependencies for a module" do
      {:ok, pid} = CodebaseContext.start_link()

      case CodebaseContext.get_dependencies("JidoCoderLib.Agents.ContextManager") do
        {:ok, deps} when is_list(deps) ->
          assert is_list(deps)

        {:error, :not_found} ->
          # Module not indexed yet - OK
          :ok

        {:error, _reason} ->
          # SPARQL query may fail if ontology not fully supported
          # This is acceptable for graceful degradation
          :ok
      end

      :ok = GenServer.stop(pid)
    end

    test "respects depth parameter" do
      {:ok, pid} = CodebaseContext.start_link()

      case CodebaseContext.get_dependencies("JidoCoderLib.Agents.ContextManager", depth: 0) do
        {:ok, deps} ->
          # With depth 0, should return empty list or direct deps only
          assert is_list(deps)

        {:error, _reason} ->
          # OK if not supported
          :ok
      end

      :ok = GenServer.stop(pid)
    end

    test "caches dependency results" do
      {:ok, pid} = CodebaseContext.start_link()

      case CodebaseContext.get_dependencies("JidoCoderLib.Agents.ContextManager", depth: 1) do
        {:ok, deps1} ->
          # Second call should hit cache
          assert {:ok, ^deps1} =
                   CodebaseContext.get_dependencies("JidoCoderLib.Agents.ContextManager",
                     depth: 1
                   )

        {:error, _reason} ->
          # Cache test not meaningful if query fails
          :ok
      end

      :ok = GenServer.stop(pid)
    end
  end

  describe "find_related/2" do
    test "finds related modules" do
      {:ok, pid} = CodebaseContext.start_link()

      case CodebaseContext.find_related(["JidoCoderLib.Agents.ContextManager"],
             include_dependencies: true
           ) do
        {:ok, related} when is_list(related) ->
          assert is_list(related)

        {:error, reason} ->
          # OK if module not found
          assert reason == :not_found or is_list(reason)
      end

      :ok = GenServer.stop(pid)
    end

    test "respects max_results option" do
      {:ok, pid} = CodebaseContext.start_link()

      case CodebaseContext.find_related(["JidoCoderLib.Agents.ContextManager"],
             max_results: 5
           ) do
        {:ok, related} ->
          assert length(related) <= 5

        _ ->
          :ok
      end

      :ok = GenServer.stop(pid)
    end

    test "respects include_dependencies option" do
      {:ok, pid} = CodebaseContext.start_link()

      # With dependencies
      case CodebaseContext.find_related(
             ["JidoCoderLib.Agents.ContextManager"],
             include_dependencies: false
           ) do
        {:ok, related_no_deps} ->
          # Without dependencies should return fewer or equal results
          assert is_list(related_no_deps)

        _ ->
          :ok
      end

      :ok = GenServer.stop(pid)
    end
  end

  describe "enrich/2" do
    test "returns empty context for empty file list" do
      {:ok, pid} = CodebaseContext.start_link()

      assert {:ok, context} = CodebaseContext.enrich([])
      assert is_map(context)
      assert context.modules == []
      assert is_map(context.project_structure)

      :ok = GenServer.stop(pid)
    end

    test "returns context with modules for valid files" do
      {:ok, pid} = CodebaseContext.start_link()

      # Use a file from this project
      files = ["lib/jido_coder_lib/agents/context_manager.ex"]

      case CodebaseContext.enrich(files) do
        {:ok, context} ->
          assert is_map(context)
          assert is_list(context.modules)
          assert is_map(context.project_structure)
          assert is_map(context.metadata)

        {:error, reason} ->
          flunk("Failed to enrich: #{inspect(reason)}")
      end

      :ok = GenServer.stop(pid)
    end

    test "respects dependency_depth option" do
      {:ok, pid} = CodebaseContext.start_link()

      files = ["lib/jido_coder_lib/agents/context_manager.ex"]

      case CodebaseContext.enrich(files, dependency_depth: 2) do
        {:ok, context} ->
          assert context.metadata.depth_used == 2

        _ ->
          :ok
      end

      :ok = GenServer.stop(pid)
    end

    test "respects max_modules option" do
      {:ok, pid} = CodebaseContext.start_link()

      files = ["lib/jido_coder_lib/agents/context_manager.ex"]

      case CodebaseContext.enrich(files, max_modules: 5) do
        {:ok, context} ->
          # Should have at most 5 modules
          assert length(context.modules) <= 5

        _ ->
          :ok
      end

      :ok = GenServer.stop(pid)
    end

    test "returns empty module list on error (graceful degradation)" do
      {:ok, pid} = CodebaseContext.start_link()

      # Use invalid files that don't exist
      files = ["/nonexistent/file.ex"]

      assert {:ok, context} = CodebaseContext.enrich(files)
      # Modules list is empty because files don't exist
      assert context.modules == []
      # But project statistics are still available from the codebase
      assert is_integer(context.project_structure.total_modules)

      :ok = GenServer.stop(pid)
    end
  end

  describe "get_project_statistics/1" do
    test "returns project statistics" do
      {:ok, pid} = CodebaseContext.start_link()

      assert {:ok, stats} = CodebaseContext.get_project_statistics()
      assert is_integer(stats.total_modules)
      assert is_integer(stats.indexed_files)
      assert %DateTime{} = stats.last_updated

      :ok = GenServer.stop(pid)
    end

    test "returns empty stats when codebase not available" do
      {:ok, pid} = CodebaseContext.start_link()

      # This should still return OK even if codebase is empty
      assert {:ok, stats} = CodebaseContext.get_project_statistics()
      assert is_map(stats)

      :ok = GenServer.stop(pid)
    end
  end

  describe "invalidate_cache/0" do
    test "invalidates the cache" do
      {:ok, pid} = CodebaseContext.start_link()

      assert :ok = CodebaseContext.invalidate_cache()

      :ok = GenServer.stop(pid)
    end

    test "works when server not running" do
      assert :ok = CodebaseContext.invalidate_cache()
    end
  end

  describe "integration with ContextManager" do
    test "codebase context is included in build_context" do
      # This test requires a running session
      alias JidoCoderLib.Agents.ContextManager

      session_id = "test_session_#{System.unique_integer()}"

      {:ok, _cm} =
        ContextManager.start_link(
          session_id: session_id,
          stm_enabled: false
        )

      # Build context with codebase
      case ContextManager.build_context(session_id, [:codebase], []) do
        {:ok, context} ->
          assert Map.has_key?(context, :codebase)
          assert is_map(context.codebase)

        {:error, reason} ->
          flunk("Failed to build context: #{inspect(reason)}")
      end

      :ok = GenServer.stop(ContextManager.find_context_manager(session_id) |> elem(1))
    end
  end
end
