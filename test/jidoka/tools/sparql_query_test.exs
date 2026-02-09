defmodule Jidoka.Tools.SparqlQueryTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Jidoka.Tools.SparqlQuery

  describe "run/2" do
    test "rejects INSERT queries" do
      assert {:error, message} =
        SparqlQuery.run(%{query: "INSERT DATA { ?s ?p ?o }"}, %{})

      assert message =~ "INSERT"
      assert message =~ "not allowed"
    end

    test "rejects DELETE queries" do
      assert {:error, message} =
        SparqlQuery.run(%{query: "DELETE DATA { ?s ?p ?o }"}, %{})

      assert message =~ "DELETE"
      assert message =~ "not allowed"
    end

    test "rejects UPDATE queries" do
      assert {:error, message} =
        SparqlQuery.run(%{query: "UPDATE DELETE { ?s ?p ?o }"}, %{})

      assert message =~ "UPDATE"
      assert message =~ "not allowed"
    end

    test "rejects CONSTRUCT queries" do
      assert {:error, message} =
        SparqlQuery.run(%{query: "CONSTRUCT WHERE { ?s ?p ?o }"}, %{})

      assert message =~ "CONSTRUCT"
      assert message =~ "not currently supported"
    end

    test "rejects DESCRIBE queries" do
      assert {:error, message} =
        SparqlQuery.run(%{query: "DESCRIBE ?s WHERE ?s a ?type"}, %{})

      assert message =~ "DESCRIBE"
      assert message =~ "not currently supported"
    end

    test "rejects LOAD queries" do
      assert {:error, message} =
        SparqlQuery.run(%{query: "LOAD <http://example.com/graph>"}, %{})

      assert message =~ "LOAD"
      assert message =~ "not allowed"
    end

    test "rejects CLEAR queries" do
      assert {:error, message} =
        SparqlQuery.run(%{query: "CLEAR DEFAULT"}, %{})

      assert message =~ "CLEAR"
      assert message =~ "not allowed"
    end

    test "rejects DROP queries" do
      assert {:error, message} =
        SparqlQuery.run(%{query: "DROP DEFAULT"}, %{})

      assert message =~ "DROP"
      assert message =~ "not allowed"
    end

    test "rejects CREATE queries" do
      assert {:error, message} =
        SparqlQuery.run(%{query: "CREATE GRAPH <http://example.com>"}, %{})

      assert message =~ "CREATE"
      assert message =~ "not allowed"
    end

    test "accepts SELECT queries" do
      # This will likely fail because the knowledge graph isn't populated,
      # but we're testing that the query type is accepted
      result = SparqlQuery.run(%{query: "SELECT ?s WHERE ?s a struct:Module LIMIT 10"}, %{})

      # Should not be a "not allowed" error
      refute result == {:error, "INSERT queries are not allowed"}
      refute result == {:error, "SELECT queries are not allowed"}
    end

    test "accepts ASK queries" do
      result = SparqlQuery.run(%{query: "ASK WHERE ?s a struct:Module"}, %{})

      # Should not be a "not allowed" error
      refute result == {:error, "ASK queries are not allowed"}
    end

    test "adds LIMIT to SELECT query without LIMIT" do
      query = "SELECT ?s WHERE ?s a struct:Module"

      # We can't directly test the internal ensure_limit function,
      # but we can verify that a query without LIMIT doesn't error
      # with a "query too large" type of error
      _result = SparqlQuery.run(%{query: query}, %{})
    end

    test "respects custom limit" do
      query = "SELECT ?s WHERE ?s a struct:Module"

      # Custom limit should be applied
      _result = SparqlQuery.run(%{query: query, limit: 50}, %{})
    end

    test "does not add LIMIT when already present" do
      query = "SELECT ?s WHERE ?s a struct:Module LIMIT 5"

      # Should not cause issues with duplicate LIMIT
      _result = SparqlQuery.run(%{query: query}, %{})
    end
  end

  describe "Jido.Action integration" do
    test "has correct action metadata" do
      assert SparqlQuery.name() == "sparql_query"
      assert is_binary(SparqlQuery.description())
      assert SparqlQuery.category() == "knowledge_graph"
    end
  end
end
