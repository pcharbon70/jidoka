defmodule Jidoka.Protocol.MCP.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias Jidoka.Protocol.MCP.Capabilities

  describe "supports?/2" do
    test "returns true when capability exists" do
      # We need to mock Client.capabilities/1
      # For now, we'll test the logic with a direct map
      assert Capabilities.supports?(%{"tools" => %{}}, [:tools])
      assert Capabilities.supports?(%{"resources" => %{}}, [:resources])
    end

    test "returns true for nested capability" do
      caps = %{"resources" => %{"subscribe" => true}}
      assert Capabilities.supports?(caps, [:resources, :subscribe])
    end

    test "returns false when capability doesn't exist" do
      refute Capabilities.supports?(%{"tools" => %{}}, [:resources])
      refute Capabilities.supports?(%{}, [:tools])
    end

    test "returns false for nil capabilities" do
      refute Capabilities.supports?(nil, [:tools])
    end
  end

  describe "supports_tools?/1" do
    test "returns true when tools capability exists" do
      assert Capabilities.supports_tools?(%{"tools" => %{}})
      assert Capabilities.supports_tools?(%{"tools" => nil})
    end

    test "returns false when tools capability missing" do
      refute Capabilities.supports_tools?(%{})
      refute Capabilities.supports_tools?(nil)
    end
  end

  describe "supports_resources?/1" do
    test "returns true when resources capability exists" do
      assert Capabilities.supports_resources?(%{"resources" => %{}})
    end

    test "returns false when resources capability missing" do
      refute Capabilities.supports_resources?(%{"tools" => %{}})
    end
  end

  describe "supports_resource_subscriptions?/1" do
    test "returns true when subscribe is supported" do
      assert Capabilities.supports_resource_subscriptions?(%{"resources" => %{"subscribe" => true}})
    end

    test "returns false when subscribe not supported" do
      refute Capabilities.supports_resource_subscriptions?(%{"resources" => %{}})
      refute Capabilities.supports_resource_subscriptions?(%{"resources" => %{"subscribe" => false}})
    end
  end

  describe "supports_prompts?/1" do
    test "returns true when prompts capability exists" do
      assert Capabilities.supports_prompts?(%{"prompts" => %{}})
    end

    test "returns false when prompts capability missing" do
      refute Capabilities.supports_prompts?(%{})
    end
  end

  describe "supports_logging?/1" do
    test "returns true when logging capability exists" do
      assert Capabilities.supports_logging?(%{"logging" => %{}})
    end

    test "returns false when logging capability missing" do
      refute Capabilities.supports_logging?(%{})
    end
  end

  describe "supports_roots?/1" do
    test "returns true when roots capability exists" do
      assert Capabilities.supports_roots?(%{"roots" => %{}})
    end

    test "returns false when roots capability missing" do
      refute Capabilities.supports_roots?(%{})
    end
  end

  describe "summary/1" do
    test "returns list of supported capabilities" do
      caps = %{
        "tools" => %{},
        "resources" => %{},
        "prompts" => %{}
      }

      summary = Capabilities.summary(caps)

      assert :supports_tools in summary
      assert :supports_resources in summary
      assert :supports_prompts in summary
      refute :supports_logging in summary
    end

    test "returns empty list when no capabilities" do
      assert [] = Capabilities.summary(%{})
    end
  end

  describe "format/1" do
    test "formats capabilities as readable string" do
      caps = %{"tools" => %{}, "resources" => %{}}
      formatted = Capabilities.format(caps)

      assert String.contains?(formatted, "- supports_tools")
      assert String.contains?(formatted, "- supports_resources")
    end

    test "returns special message for no capabilities" do
      assert "No capabilities reported" = Capabilities.format(%{})
    end
  end
end
