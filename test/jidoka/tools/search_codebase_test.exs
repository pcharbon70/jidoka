defmodule Jidoka.Tools.SearchCodebaseTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Jidoka.Tools.SearchCodebase

  describe "run/2" do
    test "returns ontology schema when asked" do
      assert {:ok, result, []} =
        SearchCodebase.run(%{question: "What modules use GenServer?"}, %{})

      assert Map.has_key?(result, :question)
      assert Map.has_key?(result, :guidance)
      assert Map.has_key?(result, :ontology_schema)
      assert Map.has_key?(result, :query_templates)
    end

    test "can exclude schema from response" do
      assert {:ok, result, []} =
        SearchCodebase.run(%{question: "test", include_schema: false}, %{})

      refute Map.has_key?(result, :ontology_schema)
      assert Map.has_key?(result, :guidance)
    end

    test "can exclude templates from response" do
      assert {:ok, result, []} =
        SearchCodebase.run(%{question: "test", include_templates: false}, %{})

      refute Map.has_key?(result, :query_templates)
      assert Map.has_key?(result, :ontology_schema)
    end
  end

  describe "Jido.Action integration" do
    test "has correct action metadata" do
      assert SearchCodebase.name() == "search_codebase"
      assert is_binary(SearchCodebase.description())
      assert SearchCodebase.category() == "knowledge_graph"
    end
  end
end
