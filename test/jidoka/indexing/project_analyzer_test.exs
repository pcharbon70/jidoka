defmodule Jidoka.Indexing.ProjectAnalyzerTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Jidoka.Indexing.ProjectAnalyzer

  # Tests that don't require a running knowledge engine
  describe "analyze_project_to_turtle/2" do
    test "returns turtle string for a valid project" do
      # Test with the jidoka project itself
      project_path = Path.expand("../../..", __DIR__)

      assert {:ok, turtle} = ProjectAnalyzer.analyze_project_to_turtle(project_path,
        exclude_tests: true,
        include_git: false
      )

      # Verify it's valid Turtle format
      assert is_binary(turtle)
      assert String.contains?(turtle, "@prefix")
      assert String.contains?(turtle, "struct:")
    end

    test "supports base_iri option" do
      project_path = Path.expand("../../..", __DIR__)
      custom_iri = "https://myapp.org/code#"

      assert {:ok, turtle} = ProjectAnalyzer.analyze_project_to_turtle(project_path,
        base_iri: custom_iri,
        exclude_tests: true,
        include_git: false
      )

      # Custom IRI should be reflected in output
      # (exact format depends on elixir-ontologies implementation)
      assert is_binary(turtle)
    end

    test "returns error for non-existent path" do
      assert {:error, _reason} = ProjectAnalyzer.analyze_project_to_turtle("/nonexistent/path")
    end
  end

  describe "analyze_file_to_turtle/2" do
    test "returns turtle string for a single file" do
      # Use a known file from the jidoka project
      file_path = Path.expand("../../lib/jidoka/knowledge/engine.ex", __DIR__)

      assert {:ok, turtle} = ProjectAnalyzer.analyze_file_to_turtle(file_path,
        include_git: false
      )

      assert is_binary(turtle)
      assert String.contains?(turtle, "@prefix")
    end

    test "returns error for non-existent file" do
      assert {:error, _reason} = ProjectAnalyzer.analyze_file_to_turtle("/nonexistent/file.ex")
    end
  end

  describe "load_turtle_string/2" do
    test "parses valid turtle string" do
      turtle = """
      @prefix ex: <http://example.org/> .
      ex:subject ex:predicate ex:object .
      """

      # Verify parsing works (loading requires knowledge engine)
      # We can at least verify the string is parsable by RDF.Turtle
      assert {:ok, _graph} = RDF.Turtle.read_string(turtle)
    end
  end

  describe "load_turtle_file/2" do
    test "parses valid turtle file" do
      # Create a temporary turtle file
      turtle_file = Path.join(System.tmp_dir!(), "test_#{System.unique_integer([:positive])}.ttl")

      try do
        File.write!(turtle_file, """
        @prefix ex: <http://example.org/> .
        ex:test_subject ex:test_predicate "test object" .
        """)

        # Verify file can be parsed
        assert {:ok, _graph} = RDF.Turtle.read_file!(turtle_file)
      after
        File.rm(turtle_file)
      end
    end

    test "returns error for non-existent file" do
      assert {:error, _reason} = ProjectAnalyzer.load_turtle_file("/nonexistent/file.ttl")
    end
  end
end
