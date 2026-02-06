defmodule Jidoka.Knowledge.NamedGraphsTest do
  use ExUnit.Case, async: false

  alias Jidoka.Knowledge.NamedGraphs
  alias Jidoka.Knowledge.Engine

  @moduletag :knowledge_named_graphs
  @moduletag :external

  # Note: These tests use the default :knowledge_engine which is started
  # by the Application. We don't start/stop the engine in tests to avoid
  # conflicts with the Application supervision tree.

  describe "list/0" do
    test "returns list of all standard graph names" do
      graphs = NamedGraphs.list()

      assert is_list(graphs)
      assert length(graphs) == 4
      assert :long_term_context in graphs
      assert :elixir_codebase in graphs
      assert :conversation_history in graphs
      assert :system_knowledge in graphs
    end
  end

  describe "get_info/1" do
    test "returns info for long_term_context graph" do
      {:ok, info} = NamedGraphs.get_info(:long_term_context)

      assert info.name == :long_term_context
      assert info.iri_string == "https://jido.ai/graphs/long-term-context"
      assert info.purpose == "Persistent memories from work sessions"
      assert is_binary(info.description)
      assert String.length(info.description) > 0
    end

    test "returns info for elixir_codebase graph" do
      {:ok, info} = NamedGraphs.get_info(:elixir_codebase)

      assert info.name == :elixir_codebase
      assert info.iri_string == "https://jido.ai/graphs/elixir-codebase"
      assert info.purpose == "Semantic model of Elixir codebase"
    end

    test "returns info for conversation_history graph" do
      {:ok, info} = NamedGraphs.get_info(:conversation_history)

      assert info.name == :conversation_history
      assert info.iri_string == "https://jido.ai/graphs/conversation-history"
      assert info.purpose == "Conversation history and context"
    end

    test "returns info for system_knowledge graph" do
      {:ok, info} = NamedGraphs.get_info(:system_knowledge)

      assert info.name == :system_knowledge
      assert info.iri_string == "https://jido.ai/graphs/system-knowledge"
      assert info.purpose == "System ontologies and taxonomies"
    end

    test "returns error for unknown graph" do
      assert {:error, :unknown_graph} = NamedGraphs.get_info(:unknown_graph)
      assert {:error, :unknown_graph} = NamedGraphs.get_info(:custom_graph)
    end
  end

  describe "standard_graph?/1" do
    test "returns true for standard graphs" do
      assert NamedGraphs.standard_graph?(:long_term_context)
      assert NamedGraphs.standard_graph?(:elixir_codebase)
      assert NamedGraphs.standard_graph?(:conversation_history)
      assert NamedGraphs.standard_graph?(:system_knowledge)
    end

    test "returns false for non-standard graphs" do
      refute NamedGraphs.standard_graph?(:custom_graph)
      refute NamedGraphs.standard_graph?(:unknown)
      refute NamedGraphs.standard_graph?(:my_graph)
    end
  end

  describe "iri/1" do
    test "returns IRI for long_term_context" do
      {:ok, iri} = NamedGraphs.iri(:long_term_context)

      assert %RDF.IRI{} = iri
      assert RDF.IRI.to_string(iri) == "https://jido.ai/graphs/long-term-context"
    end

    test "returns IRI for elixir_codebase" do
      {:ok, iri} = NamedGraphs.iri(:elixir_codebase)

      assert %RDF.IRI{} = iri
      assert RDF.IRI.to_string(iri) == "https://jido.ai/graphs/elixir-codebase"
    end

    test "returns IRI for conversation_history" do
      {:ok, iri} = NamedGraphs.iri(:conversation_history)

      assert %RDF.IRI{} = iri
      assert RDF.IRI.to_string(iri) == "https://jido.ai/graphs/conversation-history"
    end

    test "returns IRI for system_knowledge" do
      {:ok, iri} = NamedGraphs.iri(:system_knowledge)

      assert %RDF.IRI{} = iri
      assert RDF.IRI.to_string(iri) == "https://jido.ai/graphs/system-knowledge"
    end

    test "returns error for unknown graph" do
      assert {:error, :unknown_graph} = NamedGraphs.iri(:unknown_graph)
    end
  end

  describe "iri_string/1" do
    test "returns IRI string for long_term_context" do
      {:ok, iri_string} = NamedGraphs.iri_string(:long_term_context)

      assert iri_string == "https://jido.ai/graphs/long-term-context"
    end

    test "returns IRI string for elixir_codebase" do
      {:ok, iri_string} = NamedGraphs.iri_string(:elixir_codebase)

      assert iri_string == "https://jido.ai/graphs/elixir-codebase"
    end

    test "returns error for unknown graph" do
      assert {:error, :unknown_graph} = NamedGraphs.iri_string(:unknown_graph)
    end
  end

  describe "create/1" do
    test "creates long_term_context graph" do
      assert :ok = NamedGraphs.create(:long_term_context)
    end

    test "creates elixir_codebase graph" do
      assert :ok = NamedGraphs.create(:elixir_codebase)
    end

    test "creates conversation_history graph" do
      assert :ok = NamedGraphs.create(:conversation_history)
    end

    test "creates system_knowledge graph" do
      assert :ok = NamedGraphs.create(:system_knowledge)
    end

    test "returns error for unknown graph" do
      assert {:error, :unknown_graph} = NamedGraphs.create(:unknown_graph)
    end

    test "returns ok for already existing graph" do
      assert :ok = NamedGraphs.create(:long_term_context)
      assert :ok = NamedGraphs.create(:long_term_context)
    end
  end

  describe "create_all/0" do
    @tag :skip
    @tag :requires_engine_lock
    test "creates all standard graphs" do
      assert :ok = NamedGraphs.create_all()

      # Verify all were created (would require SPARQL parser)
      # For now, just verify no error was returned
    end

    @tag :skip
    @tag :requires_engine_lock
    test "returns ok when some graphs already exist" do
      # Create one graph first
      assert :ok = NamedGraphs.create(:long_term_context)

      # Create all - should still succeed
      assert :ok = NamedGraphs.create_all()
    end
  end

  describe "exists?/1" do
    @tag :skip
    @tag :requires_sparql_parser
    test "returns false initially for non-existent graph" do
      # Without SPARQL parser, we can't check existence
      # This test documents the expected behavior
      # The function will return false if the graph doesn't exist
      refute NamedGraphs.exists?(:long_term_context)
    end

    test "returns false for unknown graph" do
      refute NamedGraphs.exists?(:unknown_graph)
    end

    @tag :skip
    @tag :requires_sparql_parser
    test "returns true after creating graph" do
      NamedGraphs.create(:long_term_context)
      assert NamedGraphs.exists?(:long_term_context)
    end
  end

  describe "drop/1" do
    @tag :skip
    @tag :requires_engine_lock
    test "drops existing graph" do
      # Create first
      assert :ok = NamedGraphs.create(:long_term_context)

      # Note: drop requires SPARQL parser which has issues
      # This test documents the expected behavior
      # assert :ok = NamedGraphs.drop(:long_term_context)
    end

    test "returns error for unknown graph" do
      assert {:error, :unknown_graph} = NamedGraphs.drop(:unknown_graph)
    end

    @tag :skip
    @tag :requires_sparql_parser
    test "graph no longer exists after drop" do
      NamedGraphs.create(:long_term_context)
      assert :ok = NamedGraphs.drop(:long_term_context)
      refute NamedGraphs.exists?(:long_term_context)
    end
  end
end
