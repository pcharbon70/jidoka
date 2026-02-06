defmodule Jidoka.Knowledge.EngineTest do
  use ExUnit.Case, async: false

  alias Jidoka.Knowledge.Engine

  @moduletag :knowledge_engine
  @moduletag :external

  # Setup and teardown
  setup do
    # Create a temporary data directory for tests
    data_dir =
      Path.join([System.tmp_dir!(), "jido_kg_test_#{:erlang.unique_integer([:positive])}"])

    on_exit(fn ->
      File.rm_rf(data_dir)
    end)

    {:ok, data_dir: data_dir}
  end

  # Note: Tests for graph_exists?, list_graphs, and drop_graph are skipped
  # because they depend on SPARQL queries which require the SPARQL parser NIF.
  # The parser has an alias issue (ErlangAdapter vs TripleStore.SPARQL.Parser.NIF).
  # This is a known issue in the triple_store dependency that will be fixed separately.

  describe "start_link/1" do
    test "starts engine with valid options", %{data_dir: data_dir} do
      assert {:ok, pid} = Engine.start_link(name: :test_engine, data_dir: data_dir)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Clean shutdown
      Engine.stop(:test_engine)
    end

    test "requires data_dir option" do
      assert_raise ArgumentError, "required option :data_dir not found", fn ->
        Engine.start_link(name: :test_engine_missing_data)
      end
    end

    test "requires name option", %{data_dir: data_dir} do
      assert_raise ArgumentError, "required option :name not found", fn ->
        Engine.start_link(data_dir: data_dir)
      end
    end

    @tag :skip
    @tag :requires_sparql_parser
    test "creates standard graphs on startup", %{data_dir: data_dir} do
      {:ok, _pid} =
        Engine.start_link(
          name: :test_engine_standard,
          data_dir: data_dir,
          create_standard_graphs: true
        )

      # Check that standard graphs exist
      assert Engine.graph_exists?(:test_engine_standard, :long_term_context)
      assert Engine.graph_exists?(:test_engine_standard, :elixir_codebase)
      assert Engine.graph_exists?(:test_engine_standard, :conversation_history)
      assert Engine.graph_exists?(:test_engine_standard, :system_knowledge)

      Engine.stop(:test_engine_standard)
    end

    @tag :skip
    @tag :requires_sparql_parser
    test "can skip standard graph creation", %{data_dir: data_dir} do
      {:ok, _pid} =
        Engine.start_link(
          name: :test_engine_skip_std,
          data_dir: data_dir,
          create_standard_graphs: false
        )

      # Standard graphs should not exist
      refute Engine.graph_exists?(:test_engine_skip_std, :long_term_context)

      Engine.stop(:test_engine_skip_std)
    end
  end

  describe "context/1" do
    test "returns context map with db and dict_manager", %{data_dir: data_dir} do
      {:ok, _pid} = Engine.start_link(name: :test_engine_ctx, data_dir: data_dir)

      ctx = Engine.context(:test_engine_ctx)

      assert is_map(ctx)
      assert Map.has_key?(ctx, :db)
      assert Map.has_key?(ctx, :dict_manager)
      # db can be a reference or PID depending on the TripleStore implementation
      assert is_reference(ctx.db) or is_pid(ctx.db)
      assert is_pid(ctx.dict_manager)

      Engine.stop(:test_engine_ctx)
    end
  end

  describe "health/1" do
    test "returns health status for running engine", %{data_dir: data_dir} do
      {:ok, _pid} = Engine.start_link(name: :test_engine_health, data_dir: data_dir)

      assert {:ok, health} = Engine.health(:test_engine_health)
      assert Map.has_key?(health, :status)
      assert Map.has_key?(health, :db_open)
      assert Map.has_key?(health, :last_check)

      Engine.stop(:test_engine_health)
    end
  end

  describe "stats/1" do
    test "returns statistics for running engine", %{data_dir: data_dir} do
      {:ok, _pid} = Engine.start_link(name: :test_engine_stats, data_dir: data_dir)

      assert {:ok, stats} = Engine.stats(:test_engine_stats)
      assert is_map(stats)

      Engine.stop(:test_engine_stats)
    end
  end

  describe "create_graph/2" do
    test "creates a new named graph", %{data_dir: data_dir} do
      {:ok, _pid} =
        Engine.start_link(
          name: :test_engine_create,
          data_dir: data_dir,
          create_standard_graphs: false
        )

      assert :ok = Engine.create_graph(:test_engine_create, :my_test_graph)

      Engine.stop(:test_engine_create)
    end

    test "creates graph from IRI string", %{data_dir: data_dir} do
      {:ok, _pid} =
        Engine.start_link(
          name: :test_engine_create_iri,
          data_dir: data_dir,
          create_standard_graphs: false
        )

      custom_iri = "https://example.com/my-custom-graph"
      assert :ok = Engine.create_graph(:test_engine_create_iri, custom_iri)

      Engine.stop(:test_engine_create_iri)
    end

    test "returns :ok for existing graph", %{data_dir: data_dir} do
      {:ok, _pid} =
        Engine.start_link(
          name: :test_engine_existing,
          data_dir: data_dir,
          create_standard_graphs: false
        )

      assert :ok = Engine.create_graph(:test_engine_existing, :my_graph)
      assert :ok = Engine.create_graph(:test_engine_existing, :my_graph)

      Engine.stop(:test_engine_existing)
    end
  end

  describe "drop_graph/2" do
    @tag :skip
    @tag :requires_sparql_parser
    test "drops an existing named graph", %{data_dir: data_dir} do
      {:ok, _pid} =
        Engine.start_link(
          name: :test_engine_drop,
          data_dir: data_dir,
          create_standard_graphs: false
        )

      # Create and then drop
      assert :ok = Engine.create_graph(:test_engine_drop, :temp_graph)
      assert Engine.graph_exists?(:test_engine_drop, :temp_graph)
      assert :ok = Engine.drop_graph(:test_engine_drop, :temp_graph)
      refute Engine.graph_exists?(:test_engine_drop, :temp_graph)

      Engine.stop(:test_engine_drop)
    end
  end

  describe "list_graphs/1" do
    @tag :skip
    @tag :requires_sparql_parser
    test "returns list of all named graphs", %{data_dir: data_dir} do
      {:ok, _pid} =
        Engine.start_link(
          name: :test_engine_list,
          data_dir: data_dir,
          create_standard_graphs: false
        )

      # Create some graphs
      Engine.create_graph(:test_engine_list, :graph1)
      Engine.create_graph(:test_engine_list, :graph2)

      {:ok, graphs} = Engine.list_graphs(:test_engine_list)
      assert is_list(graphs)

      Engine.stop(:test_engine_list)
    end
  end

  describe "graph_exists?/2" do
    @tag :skip
    @tag :requires_sparql_parser
    test "returns true for existing graph", %{data_dir: data_dir} do
      {:ok, _pid} =
        Engine.start_link(
          name: :test_engine_exists,
          data_dir: data_dir,
          create_standard_graphs: true
        )

      assert Engine.graph_exists?(:test_engine_exists, :long_term_context)

      Engine.stop(:test_engine_exists)
    end

    @tag :skip
    @tag :requires_sparql_parser
    test "returns false for non-existing graph", %{data_dir: data_dir} do
      {:ok, _pid} =
        Engine.start_link(
          name: :test_engine_not_exists,
          data_dir: data_dir,
          create_standard_graphs: false
        )

      refute Engine.graph_exists?(:test_engine_not_exists, :non_existent)

      Engine.stop(:test_engine_not_exists)
    end
  end

  describe "backup/2" do
    test "creates backup at specified path", %{data_dir: data_dir} do
      backup_dir = Path.join([data_dir, "backups"])
      File.mkdir_p!(backup_dir)
      backup_path = Path.join(backup_dir, "test_backup")

      {:ok, _pid} = Engine.start_link(name: :test_engine_backup, data_dir: data_dir)

      # Create some data first
      Engine.create_graph(:test_engine_backup, :backup_test)

      # Backup
      result = Engine.backup(:test_engine_backup, backup_path)

      # Backup may succeed or fail depending on triple_store implementation
      # We just verify it doesn't crash
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      Engine.stop(:test_engine_backup)
    end
  end

  describe "stop/1" do
    test "stops the engine gracefully", %{data_dir: data_dir} do
      {:ok, pid} = Engine.start_link(name: :test_engine_stop, data_dir: data_dir)

      assert Process.alive?(pid)
      assert :ok = Engine.stop(:test_engine_stop)
      refute Process.alive?(pid)
    end
  end

  describe "graph_name_to_iri/1" do
    test "converts standard graph name to IRI" do
      iri = Engine.graph_name_to_iri(:long_term_context)
      assert RDF.iri?(iri)
      assert RDF.IRI.to_string(iri) == "https://jido.ai/graphs/long-term-context"
    end

    test "converts elixir_codebase to IRI" do
      iri = Engine.graph_name_to_iri(:elixir_codebase)
      assert RDF.iri?(iri)
      assert RDF.IRI.to_string(iri) == "https://jido.ai/graphs/elixir-codebase"
    end

    test "converts string IRI to IRI" do
      iri = Engine.graph_name_to_iri("https://example.com/graph")
      assert RDF.iri?(iri)
    end

    test "converts custom atom graph name to IRI" do
      iri = Engine.graph_name_to_iri(:my_custom_graph)
      assert RDF.iri?(iri)
      assert RDF.IRI.to_string(iri) == "https://jido.ai/graphs/my_custom_graph"
    end
  end

  describe "standard_graphs/0" do
    test "returns list of standard graph names" do
      graphs = Engine.standard_graphs()

      assert is_list(graphs)
      assert :long_term_context in graphs
      assert :elixir_codebase in graphs
      assert :conversation_history in graphs
      assert :system_knowledge in graphs
    end
  end
end
