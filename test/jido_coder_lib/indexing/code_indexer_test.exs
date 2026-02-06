defmodule JidoCoderLib.Indexing.CodeIndexerTest do
  use ExUnit.Case, async: false

  alias JidoCoderLib.Indexing.CodeIndexer
  alias JidoCoderLib.Knowledge.NamedGraphs

  @moduletag :code_indexer
  @moduletag :external

  setup_all do
    # Start the Knowledge Engine once for all tests
    # Check if it's already running (started by Application)
    case Process.whereis(:knowledge_engine) do
      nil -> {:ok, _pid} = start_knowledge_engine()
      _pid -> :ok
    end

    :ok
  end

  setup do
    # Ensure the elixir_codebase graph exists for each test
    :ok = NamedGraphs.create(:elixir_codebase)

    # Start IndexingStatusTracker if not already running
    tracker_name = JidoCoderLib.Indexing.IndexingStatusTracker

    unless Process.whereis(tracker_name) do
      {:ok, _tracker_pid} = start_indexing_status_tracker()
    end

    # Start CodeIndexer
    {:ok, pid} = CodeIndexer.start_link(name: __MODULE__.TestIndexer)

    {:ok, %{pid: pid, indexer_name: __MODULE__.TestIndexer}}
  end

  describe "start_link/1" do
    test "starts the CodeIndexer GenServer" do
      assert {:ok, pid} = CodeIndexer.start_link(name: __MODULE__.StartTest)
      assert Process.alive?(pid)
      assert :gen_server.stop(__MODULE__.StartTest) == :ok
    end

    test "starts with custom engine_name" do
      assert {:ok, _pid} =
               CodeIndexer.start_link(
                 name: __MODULE__.CustomEngine,
                 engine_name: :knowledge_engine
               )
    end
  end

  describe "index_file/2" do
    test "indexes a valid Elixir file", %{indexer_name: name} do
      # Create a test file
      test_file =
        create_test_file("""
        defmodule TestModule do
          @moduledoc \"\"\"
          A test module for indexing.
          \"\"\"

          @doc "Says hello"
          def hello(name) do
            "Hello, \#{name}!"
          end

          defp private_helper, do: :ok
        end
        """)

      # Index the file
      assert {:ok, %{triple_count: count}} = CodeIndexer.index_file(test_file, name: name)

      # Should have inserted some triples
      assert count > 0
      assert is_integer(count)

      # Verify indexing status
      assert {:ok, :completed} =
               JidoCoderLib.Indexing.IndexingStatusTracker.get_status(test_file)
    end

    test "indexes a file with a struct", %{indexer_name: name} do
      test_file =
        create_test_file("""
        defmodule TestStruct do
          defstruct [:name, :age, :email]

          def new(attrs) do
            struct!(__MODULE__, attrs)
          end
        end
        """)

      assert {:ok, %{triple_count: count}} = CodeIndexer.index_file(test_file, name: name)
      assert count > 0
    end

    test "indexes a file with a protocol", %{indexer_name: name} do
      test_file =
        create_test_file("""
        defmodule TestProtocol do
          @doc "Processes a value"
          def process(value)
        end

        defmodule StringImpl do
          def process(str), do: String.upcase(str)
        end
        """)

      assert {:ok, %{triple_count: count}} = CodeIndexer.index_file(test_file, name: name)
      assert count > 0
    end

    test "indexes a file with a behaviour", %{indexer_name: name} do
      test_file =
        create_test_file("""
        defmodule TestBehaviour do
          @callback init(term) :: {:ok, term} | {:error, term}
          @callback handle(term) :: term
        end
        """)

      assert {:ok, %{triple_count: count}} = CodeIndexer.index_file(test_file, name: name)
      assert count > 0
    end

    test "indexes a file with multiple modules", %{indexer_name: name} do
      test_file =
        create_test_file("""
        defmodule FirstModule do
          def foo, do: :ok
        end

        defmodule SecondModule do
          def bar, do: :ok
        end
        """)

      assert {:ok, %{triple_count: count}} = CodeIndexer.index_file(test_file, name: name)
      assert count > 0
    end

    test "returns error for non-existent file", %{indexer_name: name} do
      # Path validation now happens before file existence check
      assert {:error, {:path_validation_failed, :path_outside_allowed}} =
               CodeIndexer.index_file("/nonexistent/file.ex", name: name)
    end

    test "returns error for invalid file type", %{indexer_name: name} do
      # Create a non-.ex file
      invalid_file = create_test_file("content", ".txt")

      # Path validation now happens before file type check
      assert {:error, {:path_validation_failed, :invalid_extension}} =
               CodeIndexer.index_file(invalid_file, name: name)
    end

    test "returns error for file with syntax errors", %{indexer_name: name} do
      test_file =
        create_test_file("""
        defmodule BadSyntax do
          def foo(
        end
        """)

      assert {:error, _reason} = CodeIndexer.index_file(test_file, name: name)

      # Check that status is failed
      assert {:ok, :failed} =
               JidoCoderLib.Indexing.IndexingStatusTracker.get_status(test_file)
    end

    test "respects custom base_iri option", %{indexer_name: name} do
      test_file =
        create_test_file("""
        defmodule CustomIRITest do
          def test, do: :ok
        end
        """)

      assert {:ok, _} =
               CodeIndexer.index_file(test_file,
                 name: name,
                 base_iri: "https://custom.org/code#"
               )
    end
  end

  describe "index_project/2" do
    test "indexes a project with multiple files", %{indexer_name: name} do
      # Create a temporary project structure
      project_dir = tmp_project_dir()
      File.mkdir_p!(Path.join(project_dir, "lib"))

      # Create multiple source files
      File.write!(Path.join([project_dir, "lib", "file_one.ex"]), """
      defmodule FileOne do
        def one, do: :one
      end
      """)

      File.write!(Path.join([project_dir, "lib", "file_two.ex"]), """
      defmodule FileTwo do
        def two, do: :two
      end
      """)

      # Create a minimal mix.exs to make it a valid project
      File.write!(Path.join(project_dir, "mix.exs"), """
      defmodule TempProject.MixProject do
        use Mix.Project

        def project do
          [app: :temp_project, version: "0.1.0"]
        end
      end
      """)

      # Index the project
      assert {:ok, result} = CodeIndexer.index_project(project_dir, name: name)

      # Should have metadata
      assert is_map(result.metadata)
      assert result.metadata.file_count >= 2
      assert is_integer(result.metadata.triple_count)
      assert result.metadata.triple_count > 0

      # Should have error list (may be empty)
      assert is_list(result.errors)
    end

    test "excludes test files by default", %{indexer_name: name} do
      project_dir = tmp_project_dir()

      # Create lib and test directories
      File.mkdir_p!(Path.join(project_dir, "lib"))
      File.mkdir_p!(Path.join(project_dir, "test"))

      # Create files in both directories
      File.write!(Path.join([project_dir, "lib", "lib_file.ex"]), """
      defmodule LibFile do
        def lib_func, do: :ok
      end
      """)

      File.write!(Path.join([project_dir, "test", "test_file.ex"]), """
      defmodule TestFile do
        def test_func, do: :ok
      end
      """)

      # Add mix.exs
      File.write!(Path.join(project_dir, "mix.exs"), """
      defmodule TempProject.MixProject do
        use Mix.Project
        def project, do: [app: :temp_project, version: "0.1.0"]
      end
      """)

      # Index project (should exclude test/ by default)
      assert {:ok, result} = CodeIndexer.index_project(project_dir, name: name)

      # Only lib files should be indexed
      assert result.metadata.file_count >= 1
    end

    test "includes test files when exclude_tests: false", %{indexer_name: name} do
      project_dir = tmp_project_dir()

      File.mkdir_p!(Path.join(project_dir, "lib"))
      File.mkdir_p!(Path.join(project_dir, "test"))

      File.write!(Path.join([project_dir, "lib", "lib_file.ex"]), """
      defmodule LibFile do
        def lib_func, do: :ok
      end
      """)

      File.write!(Path.join([project_dir, "test", "test_file.ex"]), """
      defmodule TestFile do
        def test_func, do: :ok
      end
      """)

      File.write!(Path.join(project_dir, "mix.exs"), """
      defmodule TempProject.MixProject do
        use Mix.Project
        def project, do: [app: :temp_project, version: "0.1.0"]
      end
      """)

      # Index with tests included
      assert {:ok, result} =
               CodeIndexer.index_project(project_dir,
                 name: name,
                 exclude_tests: false
               )

      # Should have both lib and test files
      assert result.metadata.file_count >= 2
    end

    test "returns error for non-existent project directory", %{indexer_name: name} do
      # Path validation now happens before directory check
      assert {:error, {:path_validation_failed, :path_outside_allowed}} =
               CodeIndexer.index_project("/nonexistent/project", name: name)
    end
  end

  describe "reindex_file/2" do
    test "re-indexes an existing file", %{indexer_name: name} do
      # Create initial file
      test_file =
        create_test_file("""
        defmodule ReindexTest do
          def original, do: :original
        end
        """)

      # Index it first
      assert {:ok, %{triple_count: count1}} = CodeIndexer.index_file(test_file, name: name)
      assert count1 > 0

      # Modify the file
      File.write!(test_file, """
      defmodule ReindexTest do
        def original, do: :original
        def new_function, do: :new
      end
      """)

      # Reindex
      assert {:ok, %{triple_count: count2}} = CodeIndexer.reindex_file(test_file, name: name)
      assert count2 > 0
    end
  end

  describe "remove_file/2" do
    test "removes triples for a file", %{indexer_name: name} do
      test_file =
        create_test_file("""
        defmodule RemoveTest do
          def to_remove, do: :gone
        end
        """)

      # Index the file
      assert {:ok, _} = CodeIndexer.index_file(test_file, name: name)

      # Remove it
      assert :ok = CodeIndexer.remove_file(test_file, name: name)
    end
  end

  describe "get_stats/2" do
    test "returns indexing statistics for a project", %{indexer_name: name} do
      project_dir = tmp_project_dir()
      File.mkdir_p!(Path.join(project_dir, "lib"))

      File.write!(Path.join([project_dir, "lib", "stats_test.ex"]), """
      defmodule StatsTest do
        def stat_func, do: :ok
      end
      """)

      File.write!(Path.join(project_dir, "mix.exs"), """
      defmodule StatsProject.MixProject do
        use Mix.Project
        def project, do: [app: :stats_project, version: "0.1.0"]
      end
      """)

      # Index the project
      CodeIndexer.index_project(project_dir, name: name)

      # Get stats
      assert {:ok, stats} = CodeIndexer.get_stats(project_dir, name: name)

      assert is_map(stats)
      assert Map.has_key?(stats, :total)
      assert Map.has_key?(stats, :pending)
      assert Map.has_key?(stats, :in_progress)
      assert Map.has_key?(stats, :completed)
      assert Map.has_key?(stats, :failed)
      assert is_integer(stats.total)
      assert is_integer(stats.completed)
    end
  end

  # ========================================================================
  # Helper Functions
  # ========================================================================

  defp start_knowledge_engine do
    data_dir = Path.join([System.tmp_dir!(), "jido_kg_test", "code_indexer"])

    opts = [
      name: :knowledge_engine,
      data_dir: data_dir,
      schema: :local_only,
      health_check_interval: nil
    ]

    start_supervised!({JidoCoderLib.Knowledge.Engine, opts})
  end

  defp start_indexing_status_tracker do
    opts = [
      name: JidoCoderLib.Indexing.IndexingStatusTracker,
      engine_name: :knowledge_engine
    ]

    start_supervised!({JidoCoderLib.Indexing.IndexingStatusTracker, opts})
  end

  defp create_test_file(content, ext \\ ".ex") do
    # Use test/support/tmp_dir for test files (within allowed directories)
    tmp_dir = Path.join([File.cwd!(), "test", "support", "tmp"])
    File.mkdir_p!(tmp_dir)
    filename = "test_file_#{:erlang.unique_integer([:positive])}#{ext}"
    file_path = Path.join(tmp_dir, filename)
    File.write!(file_path, content)
    file_path
  end

  defp tmp_project_dir do
    # Use test/support/tmp_projects for test projects
    base_dir = Path.join([File.cwd!(), "test", "support", "tmp_projects"])
    File.mkdir_p!(base_dir)
    project_id = :erlang.unique_integer([:positive])
    Path.join([base_dir, "temp_project_#{project_id}"])
  end
end
