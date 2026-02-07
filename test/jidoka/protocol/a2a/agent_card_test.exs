defmodule Jidoka.Protocol.A2A.AgentCardTest do
  use ExUnit.Case, async: true

  alias Jidoka.Protocol.A2A.AgentCard

  doctest AgentCard

  describe "new/1" do
    test "creates a minimal agent card with required fields" do
      attrs = %{
        id: "agent:test:example",
        name: "Test Agent",
        type: ["Assistant"],
        version: "1.0.0"
      }

      assert {:ok, card} = AgentCard.new(attrs)
      assert card.id == "agent:test:example"
      assert card.name == "Test Agent"
      assert card.type == ["Assistant"]
    end

    test "creates a complete agent card with all fields" do
      attrs = %{
        id: "agent:test:complete",
        name: "Complete Agent",
        type: ["Coordinator", "Assistant"],
        version: "1.0.0",
        description: "A complete test agent",
        capabilities: %{
          actions: ["code", "chat"],
          max_tokens: 4000
        },
        endpoints: %{
          http: "https://example.com/a2a"
        }
      }

      assert {:ok, card} = AgentCard.new(attrs)
      assert card.id == "agent:test:complete"
      assert card.version == "1.0.0"
      assert card.description == "A complete test agent"
      assert card.capabilities.max_tokens == 4000
    end

    test "returns error for missing id" do
      attrs = %{
        name: "Test Agent",
        type: ["Assistant"]
      }

      assert {:error, _} = AgentCard.new(attrs)
    end

    test "returns error for missing name" do
      attrs = %{
        id: "agent:test:example",
        type: ["Assistant"]
      }

      assert {:error, _} = AgentCard.new(attrs)
    end

    test "returns error for missing type" do
      attrs = %{
        id: "agent:test:example",
        name: "Test Agent"
      }

      assert {:error, _} = AgentCard.new(attrs)
    end
  end

  describe "for_jidoka/1" do
    test "creates a Jidoka agent card with defaults" do
      card = AgentCard.for_jidoka()
      assert String.starts_with?(card.id, "agent:jidoka:")
      assert card.name == "Jidoka Jidoka"
      assert "Jidoka" in card.type
    end

    test "creates a Jidoka agent card with custom agent_type" do
      card = AgentCard.for_jidoka(agent_type: ["CustomAgent"])
      assert "CustomAgent" in card.type
    end

    test "creates a Jidoka agent card with multiple agent_type values" do
      card = AgentCard.for_jidoka(agent_type: ["Assistant", "Coder"])
      assert "Assistant" in card.type
      assert "Coder" in card.type
    end
  end

  describe "to_json_ld/1" do
    test "converts agent card to JSON-LD map" do
      card = %AgentCard{
        id: "agent:test:example",
        name: "Test Agent",
        type: ["Assistant"],
        version: "1.0.0"
      }

      json_ld = AgentCard.to_json_ld(card)

      assert json_ld["@id"] == "agent:test:example"
      assert json_ld["name"] == "Test Agent"
      assert json_ld["type"] == ["Assistant"]
      assert json_ld["version"] == "1.0.0"
      assert json_ld["@context"] == "https://jidoka.ai/ns/a2a#"
    end

    test "includes capabilities in JSON-LD" do
      card = %AgentCard{
        id: "agent:test:example",
        name: "Test Agent",
        type: ["Assistant"],
        capabilities: %{actions: ["code", "chat"]}
      }

      json_ld = AgentCard.to_json_ld(card)

      assert json_ld["capabilities"] == %{actions: ["code", "chat"]}
    end
  end

  describe "from_json_ld/1" do
    test "parses JSON-LD map back to agent card" do
      json_ld = %{
        "@id" => "agent:test:example",
        "name" => "Test Agent",
        "type" => ["Assistant"],
        "version" => "1.0.0"
      }

      assert {:ok, card} = AgentCard.from_json_ld(json_ld)
      assert card.id == "agent:test:example"
      assert card.name == "Test Agent"
      assert card.type == ["Assistant"]
      assert card.version == "1.0.0"
    end

    test "returns error for invalid JSON-LD" do
      json_ld = %{
        "name" => "Test Agent"
        # Missing @id
      }

      assert {:error, _} = AgentCard.from_json_ld(json_ld)
    end
  end

  describe "roundtrip conversion" do
    test "to_json_ld and from_json_ld are inverses" do
      original = %AgentCard{
        id: "agent:test:example",
        name: "Test Agent",
        type: ["Coordinator", "Assistant"],
        version: "2.0.0",
        description: "A test agent",
        capabilities: %{actions: ["code", "chat"]},
        endpoints: %{http: "https://example.com/a2a"}
      }

      json_ld = AgentCard.to_json_ld(original)
      assert {:ok, restored} = AgentCard.from_json_ld(json_ld)

      assert restored.id == original.id
      assert restored.name == original.name
      assert restored.type == original.type
      assert restored.version == original.version
      assert restored.description == original.description
      assert restored.capabilities == original.capabilities
      assert restored.endpoints == original.endpoints
    end
  end
end
