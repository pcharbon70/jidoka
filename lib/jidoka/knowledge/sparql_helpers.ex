defmodule Jidoka.Knowledge.SparqlHelpers do
  @moduledoc """
  Helper functions for SPARQL query construction and escaping.

  This module provides utilities for safely constructing SPARQL queries,
  preventing injection attacks through proper string escaping.

  ## SPARQL Escaping

  SPARQL string literals require proper escaping to prevent injection
  attacks and ensure query validity.

  ## Examples

      iex> SparqlHelpers.escape_string("simple")
      "simple"

      iex> SparqlHelpers.escape_string("test\\n")
      "test\\\\n"

  """

  @type sparql_string() :: String.t()
  @type iri() :: String.t()

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Escapes a string value for safe use in SPARQL string literals.

  Prevents SPARQL injection by escaping special characters according to
  W3C SPARQL 1.1 specification.

  ## Characters Escaped

  - Backslash (\) → \\
  - Double quote (") → \\"
  - Single quote (') → \\\\'
  - Newline (\n) → \\n
  - Carriage return (\r) → \\r
  - Tab (\t) → \\t

  ## Examples

      iex> SparqlHelpers.escape_string("simple")
      "simple"

      iex> SparqlHelpers.escape_string("quote\"test")
      "quote\\\"test"

      iex> SparqlHelpers.escape_string("back\\\\slash")
      "back\\\\\\\\slash"

  """
  @spec escape_string(String.t()) :: String.t()
  def escape_string(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\'", "\\'")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  @doc """
  Validates and escapes a value for use as a SPARQL filter pattern.

  For use in FILTER regex or CONTAINS operations where the value
  needs additional escaping.

  ## Examples

      iex> SparqlHelpers.escape_filter_pattern("test*")
      "test*"

  """
  @spec escape_filter_pattern(String.t()) :: String.t()
  def escape_filter_pattern(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\'", "\\'")
  end

  @doc """
  Validates an IRI string for safe use in SPARQL queries.

  Returns :ok if the IRI appears valid, {:error, reason} otherwise.

  ## IRI Validation Rules

  - Must start with http://, https://, or urn:
  - Must not contain unescaped spaces
  - Must not contain control characters
  - Must follow basic IRI syntax

  ## Examples

      iex> SparqlHelpers.validate_iri("http://example.org/test")
      :ok

      iex> SparqlHelpers.validate_iri("http://example.org/test with spaces")
      {:error, :invalid_characters}

      iex> SparqlHelpers.validate_iri("not-an-iri")
      {:error, :invalid_scheme}

  """
  @spec validate_iri(String.t()) :: :ok | {:error, atom()}
  def validate_iri(iri) when is_binary(iri) do
    cond do
      # Check for valid scheme
      not valid_scheme?(iri) ->
        {:error, :invalid_scheme}

      # Check for spaces (unescaped)
      String.contains?(iri, " ") ->
        {:error, :invalid_characters}

      # Check for control characters
      String.contains?(iri, "\n") or String.contains?(iri, "\r") or
        String.contains?(iri, "\t") or String.contains?(iri, "\0") ->
        {:error, :invalid_characters}

      # Check for suspicious patterns that might indicate injection
      String.contains?(iri, "<>") or String.contains?(iri, "><") ->
        {:error, :invalid_characters}

      true ->
        :ok
    end
  end

  @doc """
  Wraps a value in SPARQL string literal quotes and escapes it.

  ## Examples

      iex> SparqlHelpers.string_literal("test")
      "\"test\""

      iex> SparqlHelpers.string_literal("test\"value")
      "\"test\\\"value\""

  """
  @spec string_literal(String.t()) :: String.t()
  def string_literal(value) when is_binary(value) do
    "\"#{escape_string(value)}\""
  end

  @doc """
  Creates a SPARQL FILTER clause for string containment.

  ## Examples

      iex> SparqlHelpers.contains_filter("?name", "Test")
      "FILTER (CONTAINS(?name, \"Test\"))"

  """
  @spec contains_filter(String.t(), String.t()) :: String.t()
  def contains_filter(variable, value) when is_binary(variable) and is_binary(value) do
    "FILTER (CONTAINS(#{variable}, #{string_literal(value)}))"
  end

  @doc """
  Creates a SPARQL FILTER clause for string matching with LCASE.

  ## Examples

      iex> SparqlHelpers.lcase_contains_filter("?name", "test")
      "FILTER (CONTAINS(LCASE(?name), \"test\"))"

  """
  @spec lcase_contains_filter(String.t(), String.t()) :: String.t()
  def lcase_contains_filter(variable, value) when is_binary(variable) and is_binary(value) do
    escaped = escape_string(String.downcase(value))
    "FILTER (CONTAINS(LCASE(#{variable}), \"#{escaped}\"))"
  end

  @doc """
  Builds a SPARQL GRAPH query wrapper.

  ## Examples

      iex> graph_name = :elixir_codebase
      ...> query = "SELECT ?s WHERE { ?s a ?type }"
      ...> result = SparqlHelpers.wrap_in_graph(query, graph_name)
      ...> result =~ ~r/SELECT \* WHERE \{ GRAPH </
      true

  """
  @spec wrap_in_graph(String.t(), atom()) :: String.t()
  def wrap_in_graph(query, graph_name) when is_atom(graph_name) do
    {:ok, graph_iri} = Jidoka.Knowledge.NamedGraphs.iri_string(graph_name)
    "SELECT * WHERE { GRAPH <#{graph_iri}> { #{query} } }"
  end

  @doc """
  Adds PREFIX declarations to a SPARQL query.

  ## Examples

      iex> query = "SELECT * WHERE { ?s a ?type }"
      ...> prefixes = [{"rdf", "http://www.w3.org/1999/02/22-rdf-syntax-ns#"}]
      ...> result = SparqlHelpers.with_prefixes(query, prefixes)
      ...> String.starts_with?(result, "PREFIX rdf:")
      true

  """
  @spec with_prefixes(String.t(), [{String.t(), String.t()}]) :: String.t()
  def with_prefixes(query, prefixes) when is_list(prefixes) do
    prefix_declarations =
      Enum.map(prefixes, fn {prefix, iri} ->
        "PREFIX #{prefix}: <#{iri}>"
      end)
      |> Enum.join("\n")

    if Enum.empty?(prefixes) do
      query
    else
      prefix_declarations <> "\n" <> query
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp valid_scheme?(iri) do
    String.starts_with?(iri, "http://") or
      String.starts_with?(iri, "https://") or
      String.starts_with?(iri, "urn:") or
      String.starts_with?(iri, "tel:") or
      String.starts_with?(iri, "mailto:") or
      String.starts_with?(iri, "file://")
  end
end
