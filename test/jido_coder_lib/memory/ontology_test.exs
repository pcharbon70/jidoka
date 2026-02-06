defmodule JidoCoderLib.Memory.OntologyTest do
  use ExUnit.Case, async: true

  alias JidoCoderLib.Memory.Ontology
  alias RDF.{Description, IRI}

  @valid_memory %{
    id: "mem_1",
    session_id: "session_123",
    type: :fact,
    # JSON serialization converts atom keys to strings
    data: %{"key" => "value", "count" => 42},
    importance: 0.8,
    created_at: DateTime.utc_now(),
    updated_at: DateTime.utc_now()
  }

  describe "memory_types/0" do
    test "returns list of defined memory type atoms" do
      types = Ontology.memory_types()

      assert is_list(types)
      assert :fact in types
      assert :claim in types
      assert :derived_fact in types
      assert :analysis in types
      assert :conversation in types
      assert :file_context in types
      assert :decision in types
      assert :assumption in types
      assert :user_preference in types
      assert :constraint in types
      assert :tool_result in types
    end
  end

  describe "memory_uri/1" do
    test "generates URI for memory ID" do
      uri = Ontology.memory_uri("mem_1")

      assert is_struct(uri, IRI)
      assert IRI.to_string(uri) == "https://jido.ai/memory/mem_1"
    end

    test "generates unique URIs for different IDs" do
      uri1 = Ontology.memory_uri("mem_1")
      uri2 = Ontology.memory_uri("mem_2")

      assert IRI.to_string(uri1) != IRI.to_string(uri2)
    end
  end

  describe "id_from_uri/1" do
    test "extracts ID from memory URI" do
      uri = IRI.new("https://jido.ai/memory/mem_1")

      assert Ontology.id_from_uri(uri) == "mem_1"
    end

    test "returns nil for non-memory URI" do
      uri = IRI.new("https://example.com/other")

      assert is_nil(Ontology.id_from_uri(uri))
    end
  end

  describe "session_context_uri/1" do
    test "generates URI for session context" do
      uri = Ontology.session_context_uri("session_123")

      assert is_struct(uri, IRI)
      assert IRI.to_string(uri) == "https://jido.ai/sessions/session_123#context"
    end
  end

  describe "session_id_from_uri/1" do
    test "extracts session_id from session context URI" do
      uri = IRI.new("https://jido.ai/sessions/session_123#context")

      assert Ontology.session_id_from_uri(uri) == "session_123"
    end

    test "returns nil for non-session URI" do
      uri = IRI.new("https://example.com/other")

      assert is_nil(Ontology.session_id_from_uri(uri))
    end
  end

  describe "class_uri_for_type/1" do
    test "maps :fact to Fact class" do
      uri = Ontology.class_uri_for_type(:fact)

      assert IRI.to_string(uri) == "https://w3id.org/jido/memory/core#Fact"
    end

    test "maps :claim to Claim class" do
      uri = Ontology.class_uri_for_type(:claim)

      assert IRI.to_string(uri) == "https://w3id.org/jido/memory/core#Claim"
    end

    test "maps :derived_fact to DerivedFact class" do
      uri = Ontology.class_uri_for_type(:derived_fact)

      assert IRI.to_string(uri) == "https://w3id.org/jido/memory/core#DerivedFact"
    end

    test "maps :decision to PlanStepFact class" do
      uri = Ontology.class_uri_for_type(:decision)

      assert IRI.to_string(uri) == "https://w3id.org/jido/memory/core#PlanStepFact"
    end

    test "maps :user_preference to UserPreference class" do
      uri = Ontology.class_uri_for_type(:user_preference)

      assert IRI.to_string(uri) == "https://w3id.org/jido/memory/core#UserPreference"
    end

    test "defaults to Fact for unknown types" do
      uri = Ontology.class_uri_for_type(:unknown)

      assert IRI.to_string(uri) == "https://w3id.org/jido/memory/core#Fact"
    end
  end

  describe "type_for_class_uri/1" do
    test "maps Fact class URI to :fact" do
      uri = IRI.new("https://w3id.org/jido/memory/core#Fact")

      assert Ontology.type_for_class_uri(uri) == :fact
    end

    test "maps Claim class URI to :claim" do
      uri = IRI.new("https://w3id.org/jido/memory/core#Claim")

      assert Ontology.type_for_class_uri(uri) == :claim
    end

    test "maps DerivedFact class URI to :derived_fact" do
      uri = IRI.new("https://w3id.org/jido/memory/core#DerivedFact")

      assert Ontology.type_for_class_uri(uri) == :derived_fact
    end

    test "defaults to :fact for unknown classes" do
      uri = IRI.new("https://w3id.org/jido/memory/core#Unknown")

      assert Ontology.type_for_class_uri(uri) == :fact
    end
  end

  describe "to_rdf/1" do
    test "converts memory to RDF Description" do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)

      assert is_struct(desc, Description)
      assert IRI.to_string(desc.subject) == "https://jido.ai/memory/mem_1"
    end

    test "includes rdf:type triple" do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)

      type_pred = IRI.new("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
      # Check that the type predicate exists in the description
      assert Description.first(desc, type_pred) != nil
    end

    test "includes statementText with serialized data" do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)

      statement_prop = IRI.new("https://w3id.org/jido/memory/core#statementText")
      literal = Description.first(desc, statement_prop)

      assert RDF.Literal.value(literal) =~ "key"
      assert RDF.Literal.value(literal) =~ "value"
    end

    test "includes salience from importance" do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)

      salience_prop = IRI.new("https://w3id.org/jido/memory/core#salience")
      literal = Description.first(desc, salience_prop)

      assert RDF.Literal.value(literal) == 0.8
    end

    test "includes createdAt timestamp" do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)

      created_prop = IRI.new("https://w3id.org/jido/memory/core#createdAt")
      assert Description.first(desc, created_prop) != nil
    end

    test "includes updatedAt timestamp" do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)

      updated_prop = IRI.new("https://w3id.org/jido/memory/core#updatedAt")
      assert Description.first(desc, updated_prop) != nil
    end

    test "includes inContext linking to SessionContext" do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)

      context_prop = IRI.new("https://w3id.org/jido/memory/core#inContext")
      context_uri = Description.first(desc, context_prop)

      assert IRI.to_string(context_uri) == "https://jido.ai/sessions/session_123#context"
    end

    test "includes sessionId property" do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)

      session_prop = IRI.new("https://w3id.org/jido/memory/core#sessionId")
      literal = Description.first(desc, session_prop)

      assert RDF.Literal.value(literal) == "session_123"
    end

    test "uses correct ontology class for decision type" do
      memory = Map.put(@valid_memory, :type, :decision)
      {:ok, desc} = Ontology.to_rdf(memory)

      type_pred = IRI.new("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
      class_uri = Description.first(desc, type_pred)

      assert IRI.to_string(class_uri) =~ "PlanStepFact"
    end

    test "uses correct ontology class for user_preference type" do
      memory = Map.put(@valid_memory, :type, :user_preference)
      {:ok, desc} = Ontology.to_rdf(memory)

      type_pred = IRI.new("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
      class_uri = Description.first(desc, type_pred)

      assert IRI.to_string(class_uri) =~ "UserPreference"
    end
  end

  describe "from_rdf/1" do
    setup do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)
      %{description: desc}
    end

    test "reconstructs memory from RDF Description", %{description: desc} do
      {:ok, memory} = Ontology.from_rdf(desc)

      assert memory.id == "mem_1"
      assert memory.session_id == "session_123"
      assert memory.type == :fact
      assert is_map(memory.data)
      assert memory.importance == 0.8
      assert %DateTime{} = memory.created_at
      assert %DateTime{} = memory.updated_at
    end

    test "preserves data map through serialization", %{description: desc} do
      {:ok, memory} = Ontology.from_rdf(desc)

      # JSON serialization converts atom keys to strings
      assert memory.data["key"] == "value"
      assert memory.data["count"] == 42
    end

    test "extracts correct type from ontology class" do
      decision_memory = Map.put(@valid_memory, :type, :decision)
      {:ok, desc} = Ontology.to_rdf(decision_memory)

      {:ok, memory} = Ontology.from_rdf(desc)

      assert memory.type == :decision
    end
  end

  describe "round-trip conversion" do
    test "to_rdf then from_rdf preserves all memory types" do
      memory_types = [
        :fact,
        :claim,
        :derived_fact,
        :analysis,
        :conversation,
        :decision,
        :user_preference,
        :constraint,
        :tool_result
      ]

      Enum.each(memory_types, fn type ->
        memory = Map.put(@valid_memory, :type, type)

        assert {:ok, desc} = Ontology.to_rdf(memory)
        assert {:ok, restored} = Ontology.from_rdf(desc)

        assert restored.id == memory.id
        assert restored.session_id == memory.session_id
        # Type may differ for mapped types (e.g., :analysis -> :claim)
        assert restored.importance == memory.importance
      end)
    end

    test "preserves complex data structures" do
      # JSON serialization converts atom keys to strings
      complex_data = %{
        "nested" => %{"deep" => %{"value" => 123}},
        "list" => [1, 2, 3],
        "string" => "hello",
        "number" => 42.5,
        "boolean" => true
      }

      memory = Map.put(@valid_memory, :data, complex_data)

      {:ok, desc} = Ontology.to_rdf(memory)
      {:ok, restored} = Ontology.from_rdf(desc)

      assert restored.data["nested"]["deep"]["value"] == 123
      assert restored.data["list"] == [1, 2, 3]
      assert restored.data["string"] == "hello"
      assert restored.data["number"] == 42.5
      assert restored.data["boolean"] == true
    end

    test "handles empty data map" do
      memory = Map.put(@valid_memory, :data, %{})

      {:ok, desc} = Ontology.to_rdf(memory)
      {:ok, restored} = Ontology.from_rdf(desc)

      assert restored.data == %{}
    end
  end

  describe "WorkSession linking" do
    test "links memory to SessionContext" do
      {:ok, desc} = Ontology.to_rdf(@valid_memory)

      context_prop = IRI.new("https://w3id.org/jido/memory/core#inContext")
      context_uri = Description.first(desc, context_prop)

      # Context URI contains session_id
      assert IRI.to_string(context_uri) =~ "session_123"
    end

    test "SessionContext URI can be parsed back to session_id" do
      context_uri = Ontology.session_context_uri("session_123")
      session_id = Ontology.session_id_from_uri(context_uri)

      assert session_id == "session_123"
    end
  end
end
