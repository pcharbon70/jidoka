defmodule Jidoka.Knowledge.SparqlHelpersTest do
  use ExUnit.Case, async: true

  alias Jidoka.Knowledge.SparqlHelpers

  describe "escape_string/1" do
    test "escapes simple strings unchanged" do
      assert SparqlHelpers.escape_string("simple") == "simple"
      assert SparqlHelpers.escape_string("test123") == "test123"
    end

    test "escapes backslashes" do
      assert SparqlHelpers.escape_string("test\\value") == "test\\\\value"
      assert SparqlHelpers.escape_string("\\") == "\\\\"
    end

    test "escapes double quotes" do
      assert SparqlHelpers.escape_string("test\"quote") == "test\\\"quote"
      assert SparqlHelpers.escape_string("\"") == "\\\""
    end

    test "escapes single quotes" do
      assert SparqlHelpers.escape_string("test'quote") == "test\\'quote"
      assert SparqlHelpers.escape_string("'") == "\\'"
    end

    test "escapes newlines" do
      assert SparqlHelpers.escape_string("line1\nline2") == "line1\\nline2"
      assert SparqlHelpers.escape_string("\n") == "\\n"
    end

    test "escapes carriage returns" do
      assert SparqlHelpers.escape_string("line1\rline2") == "line1\\rline2"
      assert SparqlHelpers.escape_string("\r") == "\\r"
    end

    test "escapes tabs" do
      assert SparqlHelpers.escape_string("col1\tcol2") == "col1\\tcol2"
      assert SparqlHelpers.escape_string("\t") == "\\t"
    end

    test "escapes multiple special characters" do
      input = "test\"quote'\\slash\nnewline"
      expected = "test\\\"quote\\'\\\\slash\\nnewline"
      assert SparqlHelpers.escape_string(input) == expected
    end

    test "handles empty string" do
      assert SparqlHelpers.escape_string("") == ""
    end
  end

  describe "escape_filter_pattern/1" do
    test "escapes filter patterns correctly" do
      assert SparqlHelpers.escape_filter_pattern("test*") == "test*"
      assert SparqlHelpers.escape_filter_pattern("test\\value") == "test\\\\value"
    end
  end

  describe "validate_iri/1" do
    test "accepts valid HTTP IRIs" do
      assert SparqlHelpers.validate_iri("http://example.org/test") == :ok
      assert SparqlHelpers.validate_iri("https://example.org/test") == :ok
    end

    test "accepts valid URN IRIs" do
      assert SparqlHelpers.validate_iri("urn:isbn:0451450523") == :ok
    end

    test "accepts valid mailto IRIs" do
      assert SparqlHelpers.validate_iri("mailto:test@example.com") == :ok
    end

    test "rejects IRIs without valid scheme" do
      assert SparqlHelpers.validate_iri("not-an-iri") == {:error, :invalid_scheme}
      assert SparqlHelpers.validate_iri("ftp://example.com") == {:error, :invalid_scheme}
    end

    test "rejects IRIs with spaces" do
      assert SparqlHelpers.validate_iri("http://example.org/test with spaces") ==
               {:error, :invalid_characters}
    end

    test "rejects IRIs with newlines" do
      assert SparqlHelpers.validate_iri("http://example.org/test\n") ==
               {:error, :invalid_characters}
    end

    test "rejects IRIs with suspicious patterns" do
      assert SparqlHelpers.validate_iri("http://example.org/<>") ==
               {:error, :invalid_characters}
    end
  end

  describe "string_literal/1" do
    test "wraps simple string in quotes" do
      assert SparqlHelpers.string_literal("test") == "\"test\""
    end

    test "wraps and escapes string with quotes" do
      assert SparqlHelpers.string_literal("test\"value") == "\"test\\\"value\""
    end

    test "wraps and escapes string with backslashes" do
      assert SparqlHelpers.string_literal("test\\value") == "\"test\\\\value\""
    end
  end

  describe "contains_filter/2" do
    test "creates FILTER clause for simple string" do
      result = SparqlHelpers.contains_filter("?name", "Test")
      assert result == "FILTER (CONTAINS(?name, \"Test\"))"
    end

    test "creates FILTER clause with escaped special characters" do
      result = SparqlHelpers.contains_filter("?name", "Test\"Quote")
      assert result == "FILTER (CONTAINS(?name, \"Test\\\"Quote\"))"
    end
  end

  describe "lcase_contains_filter/2" do
    test "creates FILTER clause with LCASE" do
      result = SparqlHelpers.lcase_contains_filter("?name", "Test")
      assert result == "FILTER (CONTAINS(LCASE(?name), \"test\"))"
    end

    test "lowercases the search value" do
      result = SparqlHelpers.lcase_contains_filter("?name", "TEST")
      assert result == "FILTER (CONTAINS(LCASE(?name), \"test\"))"
    end
  end

  describe "wrap_in_graph/2" do
    test "wraps SELECT query in GRAPH block" do
      query = "SELECT ?s WHERE { ?s a ?type }"
      result = SparqlHelpers.wrap_in_graph(query, :elixir_codebase)

      assert result =~ ~r/SELECT \* WHERE/
      assert result =~ ~r/GRAPH </
      assert result =~ ~r/\{ \?s a \?type \}/
    end
  end

  describe "with_prefixes/2" do
    test "adds single PREFIX declaration" do
      query = "SELECT * WHERE { ?s a ?type }"
      prefixes = [{"rdf", "http://www.w3.org/1999/02/22-rdf-syntax-ns#"}]

      result = SparqlHelpers.with_prefixes(query, prefixes)

      assert result =~ ~r/PREFIX rdf:/
      assert result =~ ~r/<http:\/\/www\.w3\.org\/1999\/02\/22-rdf-syntax-ns#>/
      assert result =~ ~r/SELECT \* WHERE/
    end

    test "adds multiple PREFIX declarations" do
      query = "SELECT * WHERE { ?s a ?type }"
      prefixes = [
        {"rdf", "http://www.w3.org/1999/02/22-rdf-syntax-ns#"},
        {"rdfs", "http://www.w3.org/2000/01/rdf-schema#"}
      ]

      result = SparqlHelpers.with_prefixes(query, prefixes)

      assert result =~ ~r/PREFIX rdf:/
      assert result =~ ~r/PREFIX rdfs:/
    end

    test "returns query unchanged when no prefixes" do
      query = "SELECT * WHERE { ?s a ?type }"
      result = SparqlHelpers.with_prefixes(query, [])

      assert result == query
    end
  end
end
