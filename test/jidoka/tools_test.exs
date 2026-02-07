defmodule Jidoka.ToolsTest do
  use ExUnit.Case, async: false

  # Note: These tests require the application to be started
  # Knowledge graph tests are excluded by default
  # Run with: mix test test/jidoka/tools_test.exs --exclude knowledge_graph_required

  describe "ReadFile" do
    alias Jidoka.Tools.ReadFile

    test "reads a valid file" do
      assert {:ok, result, []} =
               ReadFile.run(%{file_path: "lib/jidoka/client.ex"}, %{})

      assert is_binary(result.content)
      assert result.content != ""
      assert result.metadata.file_path == "lib/jidoka/client.ex"
      assert is_integer(result.metadata.line_count)
      assert is_integer(result.metadata.size)
    end

    test "reads file with line range" do
      assert {:ok, result, []} =
               ReadFile.run(%{file_path: "lib/jidoka/client.ex", offset: 1, limit: 10}, %{})

      lines = String.split(result.content, "\n")
      assert length(lines) <= 10
      assert result.metadata.offset == 1
    end

    test "returns error for non-existent file" do
      assert {:error, :file_not_found} =
               ReadFile.run(%{file_path: "lib/nonexistent.ex"}, %{})
    end

    test "returns error for path outside allowed directory" do
      assert {:error, :path_outside_allowed} =
               ReadFile.run(%{file_path: "../../../etc/passwd"}, %{})
    end
  end

  describe "SearchCode" do
    alias Jidoka.Tools.SearchCode

    test "searches for a pattern in files" do
      assert {:ok, result, []} =
               SearchCode.run(%{pattern: "defmodule", file_pattern: "*.ex"}, %{})

      assert is_list(result.results)
      assert length(result.results) > 0
      assert result.metadata.matches_found > 0

      # Check result structure
      first = hd(result.results)
      assert Map.has_key?(first, :file_path)
      assert Map.has_key?(first, :line_number)
      assert Map.has_key?(first, :line_content)
    end

    test "searches case-insensitively" do
      assert {:ok, result, []} =
               SearchCode.run(%{pattern: "DEFMODULE", file_pattern: "*.ex", case_sensitive: false},
                 %{}
               )

      assert length(result.results) > 0
    end

    test "returns empty list when pattern not found" do
      assert {:ok, result, []} =
               SearchCode.run(%{pattern: "xyz nonexistent pattern 123", file_pattern: "*.ex"}, %{})

      assert result.results == []
    end

    test "returns error for invalid pattern" do
      assert {:error, :invalid_pattern} =
               SearchCode.run(%{pattern: ""}, %{})
    end
  end

  describe "AnalyzeFunction" do
    alias Jidoka.Tools.AnalyzeFunction

    @tag :knowledge_graph_required
    test "analyzes a function from the knowledge graph" do
      # This test requires the codebase to be indexed
      assert {:ok, result, []} =
               AnalyzeFunction.run(
                 %{module: "Jidoka.Client", function: "create_session", arity: 1},
                 %{}
               )

      assert result.function.name == "create_session"
      assert result.function.arity == 1
      assert result.module.name == "Jidoka.Client"
    end

    @tag :knowledge_graph_required
    test "includes call graph when requested" do
      assert {:ok, result, []} =
               AnalyzeFunction.run(
                 %{
                   module: "Jidoka.Client",
                   function: "create_session",
                   arity: 1,
                   include_call_graph: true
                 },
                 %{}
               )

      assert Map.has_key?(result, :call_graph)
    end

    @tag :knowledge_graph_required
    test "returns error for non-existent function" do
      assert {:error, :function_not_found} =
               AnalyzeFunction.run(
                 %{module: "Nonexistent.Module", function: "fake", arity: 0},
                 %{}
               )
    end
  end

  describe "ListFiles" do
    alias Jidoka.Tools.ListFiles

    test "lists files in a directory" do
      assert {:ok, result, []} = ListFiles.run(%{path: "lib/jidoka"}, %{})

      assert is_list(result.files)
      assert length(result.files) > 0
      assert result.metadata.count > 0
      assert result.metadata.path == "lib/jidoka"
    end

    test "lists files recursively" do
      assert {:ok, result, []} =
               ListFiles.run(%{path: "lib/jidoka", recursive: true}, %{})

      # Recursive should have more files than non-recursive
      {:ok, non_recursive, []} = ListFiles.run(%{path: "lib/jidoka", recursive: false}, %{})
      assert length(result.files) >= length(non_recursive.files)
    end

    test "filters files by pattern" do
      assert {:ok, result, []} =
               ListFiles.run(%{path: "lib/jidoka", pattern: "*.ex"}, %{})

      # All files should end in .ex
      assert Enum.all?(result.files, fn f -> String.ends_with?(f.name, ".ex") end)
    end

    test "excludes hidden files by default" do
      assert {:ok, result, []} =
               ListFiles.run(%{path: ".", recursive: false}, %{})

      # No files should start with .
      refute Enum.any?(result.files, fn f -> String.starts_with?(f.name, ".") end)
    end

    test "includes hidden files when requested" do
      assert {:ok, result, []} =
               ListFiles.run(%{path: ".", recursive: false, include_hidden: true}, %{})

      # We should have some files (hidden or not)
      assert length(result.files) > 0
    end

    test "returns error for invalid directory" do
      assert {:error, :not_a_directory} =
               ListFiles.run(%{path: "lib/nonexistent_directory"}, %{})
    end
  end

  describe "GetDefinition" do
    alias Jidoka.Tools.GetDefinition

    @tag :knowledge_graph_required
    test "finds a module definition" do
      assert {:ok, result, []} =
               GetDefinition.run(%{type: "module", name: "Jidoka.Client"}, %{})

      assert result.type == "module"
      assert result.name == "Jidoka.Client"
      assert result.public_function_count >= 0
      assert result.private_function_count >= 0
    end

    @tag :knowledge_graph_required
    test "finds a function definition" do
      assert {:ok, result, []} =
               GetDefinition.run(
                 %{type: "function", module: "Jidoka.Client", name: "create_session", arity: 1},
                 %{}
               )

      assert result.type == "function"
      assert result.name == "create_session"
      assert result.arity == 1
      assert result.module == "Jidoka.Client"
    end

    @tag :knowledge_graph_required
    test "returns error for unknown type" do
      assert {:error, :unknown_type} =
               GetDefinition.run(%{type: "unknown", name: "something"}, %{})
    end

    @tag :knowledge_graph_required
    test "returns error for required parameters" do
      assert {:error, :module_required} =
               GetDefinition.run(%{type: "function", name: "test", arity: 0}, %{})

      assert {:error, :name_required} =
               GetDefinition.run(%{type: "function", module: "Test", arity: 0}, %{})
    end
  end

  describe "Registry" do
    alias Jidoka.Tools.Registry

    test "lists all tools" do
      tools = Registry.list_tools()
      assert is_list(tools)
      assert length(tools) >= 5

      # Check tool structure
      first = hd(tools)
      assert Map.has_key?(first, :name)
      assert Map.has_key?(first, :module)
      assert Map.has_key?(first, :description)
      assert Map.has_key?(first, :category)
    end

    test "finds a tool by name" do
      assert {:ok, tool} = Registry.find_tool("read_file")
      assert tool.name == "read_file"
      assert tool.module == Jidoka.Tools.ReadFile
    end

    test "returns error for non-existent tool" do
      assert {:error, :not_found} = Registry.find_tool("nonexistent_tool")
    end

    test "filters tools by category" do
      filesystem_tools = Registry.list_tools(category: "filesystem")
      assert length(filesystem_tools) >= 2

      # All tools should be in filesystem category
      assert Enum.all?(filesystem_tools, fn t -> t.category == "filesystem" end)
    end

    test "returns all categories" do
      categories = Registry.categories()
      assert is_list(categories)
      assert "filesystem" in categories
      assert "search" in categories
      assert "analysis" in categories
    end

    test "checks if tool exists" do
      assert Registry.tool_exists?("read_file")
      refute Registry.tool_exists?("nonexistent")
    end
  end

  describe "Schema" do
    alias Jidoka.Tools.Schema

    test "generates OpenAI schema for a tool" do
      schema = Schema.to_openai_schema(Jidoka.Tools.ReadFile)

      assert schema.name == "read_file"
      assert is_binary(schema.description)
      assert schema.parameters.type == "object"
      assert is_map(schema.parameters.properties)
      assert is_list(schema.parameters.required)
    end

    test "generates schemas for all tools" do
      schemas = Schema.all_tool_schemas()
      assert is_list(schemas)
      assert length(schemas) >= 5

      # Check schema structure
      first = hd(schemas)
      assert Map.has_key?(first, :name)
      assert Map.has_key?(first, :description)
      assert Map.has_key?(first, :parameters)
    end

    test "converts schema to JSON" do
      schema = Schema.to_openai_schema(Jidoka.Tools.ReadFile)
      json = Schema.to_json(schema)

      assert is_binary(json)
      # Should be valid JSON
      assert {:ok, _} = Jason.decode(json)
    end

    test "describes parameters" do
      description = Schema.describe_parameters(Jidoka.Tools.ReadFile)

      assert is_binary(description)
      assert String.contains?(description, "file_path")
    end
  end
end
