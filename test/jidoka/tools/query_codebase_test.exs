defmodule Jidoka.Tools.QueryCodebaseTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Jidoka.Tools.QueryCodebase

  describe "run/2" do
    test "validates query_type parameter" do
      assert {:error, message} =
        QueryCodebase.run(%{}, %{})

      assert message =~ "Missing required parameter" || message =~ "query_type"

      assert {:error, message} =
        QueryCodebase.run(%{query_type: "invalid_type"}, %{})

      assert message =~ "Invalid query_type"
    end

    test "accepts valid query types" do
      # Query types that don't require additional parameters
      no_param_types = [
        "list_modules",
        "list_protocols",
        "list_behaviours",
        "list_structs",
        "get_index_stats"
      ]

      Enum.each(no_param_types, fn type ->
        # These will likely fail because the knowledge graph isn't populated,
        # but we're testing parameter validation, not query execution
        result = QueryCodebase.run(%{query_type: type}, %{})

        # Should either succeed with {:ok, _, _} or fail with a query error,
        # but NOT a parameter validation error
        refute match?({:error, <<_::binary>>}, result) and String.contains?(elem(result, 1), "Missing required parameter")
        refute match?({:error, <<_::binary>>}, result) and String.contains?(elem(result, 1), "Invalid query_type")
      end)

      # Query types that require module_name
      module_param_types = [
        "find_module",
        "list_functions",
        "get_dependencies",
        "get_call_graph",
        "find_protocol",
        "find_behaviour",
        "find_struct"
      ]

      Enum.each(module_param_types, fn type ->
        result = QueryCodebase.run(%{query_type: type, module_name: "SomeModule"}, %{})

        # Should not be a parameter validation error
        refute match?({:error, <<_::binary>>}, result) and String.contains?(elem(result, 1), "Invalid query_type")
      end)

      # Query types that require pattern
      result = QueryCodebase.run(%{query_type: "search_by_name", pattern: "test"}, %{})
      refute match?({:error, <<_::binary>>}, result) and String.contains?(elem(result, 1), "Invalid query_type")

      # Query types that require function_name and arity
      result = QueryCodebase.run(%{query_type: "find_function", module_name: "SomeModule", function_name: "foo", arity: 0}, %{})
      refute match?({:error, <<_::binary>>}, result) and String.contains?(elem(result, 1), "Invalid query_type")
    end

    test "validates visibility parameter" do
      assert {:error, message} =
        QueryCodebase.run(%{query_type: "list_functions", module_name: "MyApp", visibility: "invalid"}, %{})

      assert message =~ "Invalid visibility"
    end

    test "accepts valid visibility values" do
      valid_visibilities = [:public, :private, :all, "public", "private", "all"]

      Enum.each(valid_visibilities, fn vis ->
        result = QueryCodebase.run(%{query_type: "list_functions", module_name: "MyApp", visibility: vis}, %{})

        # Should not be a visibility validation error
        refute match?({:error, <<_::binary>>}, result) and String.contains?(elem(result, 1), "Invalid visibility")
      end)
    end
  end

  describe "Jido.Action integration" do
    test "has correct action metadata" do
      assert QueryCodebase.name() == "query_codebase"
      assert is_binary(QueryCodebase.description())
      assert QueryCodebase.category() == "knowledge_graph"
      assert QueryCodebase.tags() == ["codebase", "ontology", "query", "semantic"]
    end
  end
end
