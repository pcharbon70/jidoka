defmodule Jidoka.Protocol.MCP.ToolsTest do
  use ExUnit.Case, async: true

  alias Jidoka.Protocol.MCP.Tools

  describe "parse_tools/1" do
    test "parses tools list from response" do
      response = %{
        "tools" => [
          %{
            "name" => "test_tool",
            "description" => "A test tool",
            "inputSchema" => %{"type" => "object"}
          }
        ]
      }

      tools = Tools.parse_tools(response)

      assert [%{name: "test_tool", description: "A test tool", input_schema: %{}}] = tools
    end

    test "handles empty tools list" do
      assert [] = Tools.parse_tools(%{"tools" => []})
    end

    test "handles missing tools key" do
      assert [] = Tools.parse_tools(%{})
    end
  end

  describe "extract_text/1" do
    test "extracts text from content array" do
      result = %{
        content: [
          %{"type" => "text", "text" => "Hello"},
          %{"type" => "text", "text" => "World"}
        ]
      }

      assert {:ok, "Hello\nWorld"} = Tools.extract_text(result)
    end

    test "filters non-text content" do
      result = %{
        content: [
          %{"type" => "text", "text" => "Text content"},
          %{"type" => "image", "data" => %{"mimeType" => "image/png"}}
        ]
      }

      assert {:ok, "Text content"} = Tools.extract_text(result)
    end

    test "returns error for no text content" do
      result = %{content: [%{"type" => "image", "data" => %{}}]}
      assert {:error, :no_text_content} = Tools.extract_text(result)
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = Tools.extract_text(%{})
      assert {:error, :invalid_format} = Tools.extract_text(%{content: "invalid"})
    end
  end

  describe "parse_tool_result/1" do
    test "parses successful result" do
      response = %{
        "result" => %{
          "content" => [%{"type" => "text", "text" => "Success"}],
          "isError" => false
        }
      }

      assert {:ok, %{content: _, is_error: false}} = Tools.parse_tool_result(response)
    end

    test "parses error result" do
      response = %{
        "result" => %{
          "content" => [%{"type" => "text", "text" => "Error"}],
          "isError" => true
        }
      }

      assert {:error, {:tool_error, _}} = Tools.parse_tool_result(response)
    end

    test "parses RPC error" do
      response = %{"error" => %{"code" => -32601, "message" => "Method not found"}}
      assert {:error, {:rpc_error, _}} = Tools.parse_tool_result(response)
    end

    test "handles unknown format" do
      assert {:error, {:unknown_format, _}} = Tools.parse_tool_result(%{"unexpected" => "value"})
    end
  end

  describe "tool_name_to_atom/1" do
    test "converts tool name to atom" do
      assert :test_tool = Tools.tool_name_to_atom("test-tool")
      assert :my_tool = Tools.tool_name_to_atom("my-tool")
      assert :read_file = Tools.tool_name_to_atom("read_file")
    end
  end

  describe "validate_arguments/2" do
    test "returns ok when tool has no schema" do
      tool = %{name: "test_tool", input_schema: %{}}
      assert :ok = Tools.validate_arguments(tool, %{})
      assert :ok = Tools.validate_arguments(tool, %{arg1: "value"})
    end

    test "validates against JSON schema" do
      tool = %{
        name: "test_tool",
        input_schema: %{
          "type" => "object",
          "required" => ["name"],
          "properties" => %{
            "name" => %{"type" => "string"}
          }
        }
      }

      assert :ok = Tools.validate_arguments(tool, %{"name" => "test"})
      assert {:error, _} = Tools.validate_arguments(tool, %{})
    end
  end
end
