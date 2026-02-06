defmodule Jidoka.Knowledge.OntologyTest do
  use ExUnit.Case, async: false

  alias Jidoka.Knowledge.Ontology
  alias Jidoka.Knowledge.Engine

  @moduletag :knowledge_ontology
  @moduletag :external

  # Note: These tests use the default :knowledge_engine which is started
  # by the Application. We don't start/stop the engine in tests to avoid
  # conflicts with the Application supervision tree.

  describe "ontology file" do
    test "jido.ttl file exists" do
      ontology_path = Path.join([File.cwd!(), "priv", "ontologies", "jido.ttl"])
      assert File.exists?(ontology_path)
    end

    test "ontology file is readable" do
      ontology_path = Path.join([File.cwd!(), "priv", "ontologies", "jido.ttl"])

      assert {:ok, content} = File.read(ontology_path)
      assert String.length(content) > 0
      assert String.contains?(content, "@prefix jido:")
    end

    test "ontology file contains required prefixes" do
      ontology_path = Path.join([File.cwd!(), "priv", "ontologies", "jido.ttl"])
      {:ok, content} = File.read(ontology_path)

      # Check for required prefixes
      assert String.contains?(content, "@prefix jido:")
      assert String.contains?(content, "@prefix rdf:")
      assert String.contains?(content, "@prefix rdfs:")
      assert String.contains?(content, "@prefix owl:")
      assert String.contains?(content, "@prefix xsd:")
      assert String.contains?(content, "@prefix prov:")
      assert String.contains?(content, "@prefix dcterms:")
    end
  end

  describe "load_jido_ontology/0" do
    test "loads ontology successfully" do
      # First, ensure the system_knowledge graph exists
      Engine.create_graph(:knowledge_engine, :system_knowledge)

      result = Ontology.load_jido_ontology()

      assert {:ok, info} = result
      assert info.version == "1.0.0"
      assert is_integer(info.triple_count)
      assert info.triple_count > 0
      assert info.graph =~ "system-knowledge"
    end

    test "returns consistent results on reload" do
      result1 = Ontology.load_jido_ontology()
      result2 = Ontology.reload_jido_ontology()

      assert {:ok, info1} = result1
      assert {:ok, info2} = result2
      assert info1.version == info2.version
    end
  end

  describe "load_ontology/2" do
    test "loads ontology file into specified graph" do
      ontology_path = Path.join([File.cwd!(), "priv", "ontologies", "jido.ttl"])

      result = Ontology.load_ontology(ontology_path, :system_knowledge)

      assert {:ok, info} = result
      assert info.version == "1.0.0"
      assert is_integer(info.triple_count)
    end

    test "returns error for non-existent file" do
      result = Ontology.load_ontology("non-existent.ttl", :system_knowledge)

      assert {:error, _reason} = result
    end
  end

  describe "validate_loaded/1" do
    test "validates jido ontology loaded correctly" do
      # Ensure ontology is loaded
      Ontology.load_jido_ontology()

      result = Ontology.validate_loaded(:jido)

      assert {:ok, info} = result
      assert info.ontology == :jido
      assert info.classes_found > 0
      assert info.expected_classes == 5
      assert info.version == "1.0.0"
    end

    test "finds expected classes" do
      Ontology.load_jido_ontology()

      {:ok, info} = Ontology.validate_loaded(:jido)

      # Should find at least the 5 defined classes
      assert info.classes_found >= 3
    end
  end

  describe "ontology_version/1" do
    test "returns version for jido ontology" do
      Ontology.load_jido_ontology()

      version = Ontology.ontology_version(:jido)

      assert version == "1.0.0"
    end
  end

  describe "class_exists?/1" do
    test "returns true for defined classes" do
      assert Ontology.class_exists?(:memory)
      assert Ontology.class_exists?(:fact)
      assert Ontology.class_exists?(:decision)
      assert Ontology.class_exists?(:lesson_learned)
      assert Ontology.class_exists?(:work_session)
    end

    test "returns false for undefined classes" do
      refute Ontology.class_exists?(:unknown)
      refute Ontology.class_exists?(:custom_type)
      refute Ontology.class_exists?(:foo)
    end
  end

  describe "get_class_iri/1" do
    test "returns correct IRI for memory class" do
      {:ok, iri} = Ontology.get_class_iri(:memory)
      assert iri == "https://jido.ai/ontologies/core#Memory"
    end

    test "returns correct IRI for fact class" do
      {:ok, iri} = Ontology.get_class_iri(:fact)
      assert iri == "https://jido.ai/ontologies/core#Fact"
    end

    test "returns correct IRI for decision class" do
      {:ok, iri} = Ontology.get_class_iri(:decision)
      assert iri == "https://jido.ai/ontologies/core#Decision"
    end

    test "returns correct IRI for lesson_learned class" do
      {:ok, iri} = Ontology.get_class_iri(:lesson_learned)
      assert iri == "https://jido.ai/ontologies/core#LessonLearned"
    end

    test "returns correct IRI for work_session class" do
      {:ok, iri} = Ontology.get_class_iri(:work_session)
      assert iri == "https://jido.ai/ontologies/core#WorkSession"
    end

    test "returns error for unknown class" do
      assert {:error, :not_found} = Ontology.get_class_iri(:unknown)
    end
  end

  describe "memory_type_iris/0" do
    test "returns list of memory type IRIs" do
      iris = Ontology.memory_type_iris()

      assert is_list(iris)
      assert length(iris) == 3
    end

    test "includes all three memory types" do
      iris = Ontology.memory_type_iris()

      assert "https://jido.ai/ontologies/core#Fact" in iris
      assert "https://jido.ai/ontologies/core#Decision" in iris
      assert "https://jido.ai/ontologies/core#LessonLearned" in iris
    end

    test "does not include base memory or work session" do
      iris = Ontology.memory_type_iris()

      refute "https://jido.ai/ontologies/core#Memory" in iris
      refute "https://jido.ai/ontologies/core#WorkSession" in iris
    end
  end

  describe "is_memory_type?/1" do
    test "returns true for memory type IRIs" do
      assert Ontology.is_memory_type?("https://jido.ai/ontologies/core#Fact")
      assert Ontology.is_memory_type?("https://jido.ai/ontologies/core#Decision")
      assert Ontology.is_memory_type?("https://jido.ai/ontologies/core#LessonLearned")
    end

    test "returns false for non-memory type IRIs" do
      refute Ontology.is_memory_type?("https://jido.ai/ontologies/core#Memory")
      refute Ontology.is_memory_type?("https://jido.ai/ontologies/core#WorkSession")
      refute Ontology.is_memory_type?("https://jido.ai/ontologies/core#Unknown")
    end

    test "returns false for non-IRI strings" do
      refute Ontology.is_memory_type?("not-an-iri")
      refute Ontology.is_memory_type?("")
    end

    test "returns false for non-string inputs" do
      refute Ontology.is_memory_type?(nil)
      refute Ontology.is_memory_type?(123)
    end
  end

  describe "create_memory_triple/3" do
    test "creates triple for fact type" do
      {:ok, {s, p, o}} =
        Ontology.create_memory_triple(:fact, "https://jido.ai/memories#m1", "value")

      assert RDF.IRI.to_string(s) == "https://jido.ai/memories#m1"
      assert RDF.IRI.to_string(p) == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
      assert RDF.IRI.to_string(o) == "https://jido.ai/ontologies/core#Fact"
    end

    test "creates triple for decision type" do
      {:ok, {s, p, o}} =
        Ontology.create_memory_triple(:decision, "https://jido.ai/memories#m2", "value")

      assert RDF.IRI.to_string(s) == "https://jido.ai/memories#m2"
      assert RDF.IRI.to_string(o) == "https://jido.ai/ontologies/core#Decision"
    end

    test "creates triple for lesson_learned type" do
      {:ok, {s, p, o}} =
        Ontology.create_memory_triple(:lesson_learned, "https://jido.ai/memories#m3", "value")

      assert RDF.IRI.to_string(o) == "https://jido.ai/ontologies/core#LessonLearned"
    end

    test "returns error for invalid memory type" do
      assert {:error, :invalid_memory_type} =
               Ontology.create_memory_triple(:unknown, "https://jido.ai/memories#m1", "value")
    end

    test "returns error for work_session type (not a memory type)" do
      assert {:error, :invalid_memory_type} =
               Ontology.create_memory_triple(
                 :work_session,
                 "https://jido.ai/memories#m1",
                 "value"
               )
    end
  end

  describe "create_work_session_individual/1" do
    test "creates IRI for work session" do
      iri = Ontology.create_work_session_individual("session-123")
      assert iri == "https://jido.ai/sessions#session-123"
    end

    test "handles UUID-style IDs" do
      iri = Ontology.create_work_session_individual("550e8400-e29b-41d4-a716-446655440000")
      assert iri == "https://jido.ai/sessions#550e8400-e29b-41d4-a716-446655440000"
    end

    test "handles special characters in ID" do
      iri = Ontology.create_work_session_individual("session_2025-01-26")
      assert iri == "https://jido.ai/sessions#session_2025-01-26"
    end
  end

  describe "create_memory_individual/1" do
    test "creates IRI for memory" do
      iri = Ontology.create_memory_individual("memory-456")
      assert iri == "https://jido.ai/memories#memory-456"
    end

    test "handles UUID-style IDs" do
      iri = Ontology.create_memory_individual("750e8400-e29b-41d4-a716-446655440000")
      assert iri == "https://jido.ai/memories#750e8400-e29b-41d4-a716-446655440000"
    end
  end

  # ==============================================================================
  # Conversation Ontology Tests
  # ==============================================================================

  describe "conversation ontology file" do
    test "conversation-history.ttl file exists" do
      ontology_path = Path.join([File.cwd!(), "priv", "ontologies", "conversation-history.ttl"])
      assert File.exists?(ontology_path)
    end

    test "conversation ontology file is readable" do
      ontology_path = Path.join([File.cwd!(), "priv", "ontologies", "conversation-history.ttl"])

      assert {:ok, content} = File.read(ontology_path)
      assert String.length(content) > 0
      assert String.contains?(content, "@prefix :")
    end

    test "conversation ontology file contains required prefixes" do
      ontology_path = Path.join([File.cwd!(), "priv", "ontologies", "conversation-history.ttl"])
      {:ok, content} = File.read(ontology_path)

      # Check for required prefixes
      assert String.contains?(content, "@prefix :")
      assert String.contains?(content, "@prefix rdf:")
      assert String.contains?(content, "@prefix rdfs:")
      assert String.contains?(content, "@prefix owl:")
      assert String.contains?(content, "@prefix xsd:")
      assert String.contains?(content, "@prefix jido:")
    end
  end

  describe "load_conversation_ontology/0" do
    test "loads ontology successfully" do
      # First, ensure the system_knowledge graph exists
      Engine.create_graph(:knowledge_engine, :system_knowledge)

      result = Ontology.load_conversation_ontology()

      assert {:ok, info} = result
      assert info.version == "1.0.0"
      assert is_integer(info.triple_count)
      assert info.triple_count > 0
      assert info.graph =~ "system-knowledge"
    end

    test "returns consistent results on reload" do
      result1 = Ontology.load_conversation_ontology()
      result2 = Ontology.reload_conversation_ontology()

      assert {:ok, info1} = result1
      assert {:ok, info2} = result2
      assert info1.version == info2.version
    end
  end

  describe "validate_conversation_ontology/0" do
    test "validates conversation ontology loaded correctly" do
      # Ensure ontology is loaded
      Ontology.load_conversation_ontology()

      result = Ontology.validate_conversation_ontology()

      assert {:ok, info} = result
      assert info.ontology == :conversation
      assert info.classes_found == 6
      assert info.expected_classes == 6
      assert info.version == "1.0.0"
    end

    test "finds expected classes" do
      Ontology.load_conversation_ontology()

      {:ok, info} = Ontology.validate_conversation_ontology()

      # Should find exactly 6 defined classes
      assert info.classes_found >= 6
    end
  end

  describe "ontology_version/1 for conversation" do
    test "returns version for conversation ontology" do
      Ontology.load_conversation_ontology()

      version = Ontology.ontology_version(:conversation)

      assert version == "1.0.0"
    end
  end

  describe "conversation_class_iris/0" do
    test "returns list of conversation class IRIs" do
      iris = Ontology.conversation_class_iris()

      assert is_list(iris)
      assert length(iris) == 6
    end

    test "includes all six conversation classes" do
      iris = Ontology.conversation_class_iris()

      assert "https://jido.ai/ontology/conversation-history#Conversation" in iris
      assert "https://jido.ai/ontology/conversation-history#ConversationTurn" in iris
      assert "https://jido.ai/ontology/conversation-history#Prompt" in iris
      assert "https://jido.ai/ontology/conversation-history#Answer" in iris
      assert "https://jido.ai/ontology/conversation-history#ToolInvocation" in iris
      assert "https://jido.ai/ontology/conversation-history#ToolResult" in iris
    end
  end

  describe "conversation_class_names/0" do
    test "returns list of conversation class names" do
      names = Ontology.conversation_class_names()

      assert is_list(names)
      assert length(names) == 6
    end

    test "includes all conversation class names" do
      names = Ontology.conversation_class_names()

      assert :conversation in names
      assert :conversation_turn in names
      assert :prompt in names
      assert :answer in names
      assert :tool_invocation in names
      assert :tool_result in names
    end
  end

  describe "conversation_class_exists?/1" do
    test "returns true for defined conversation classes" do
      assert Ontology.conversation_class_exists?(:conversation)
      assert Ontology.conversation_class_exists?(:conversation_turn)
      assert Ontology.conversation_class_exists?(:prompt)
      assert Ontology.conversation_class_exists?(:answer)
      assert Ontology.conversation_class_exists?(:tool_invocation)
      assert Ontology.conversation_class_exists?(:tool_result)
    end

    test "returns false for undefined conversation classes" do
      refute Ontology.conversation_class_exists?(:unknown)
      refute Ontology.conversation_class_exists?(:custom_type)
      refute Ontology.conversation_class_exists?(:foo)
    end
  end

  describe "conversation class IRI helpers" do
    test "conversation_iri/0 returns correct IRI" do
      assert Ontology.conversation_iri() ==
               "https://jido.ai/ontology/conversation-history#Conversation"
    end

    test "conversation_turn_iri/0 returns correct IRI" do
      assert Ontology.conversation_turn_iri() ==
               "https://jido.ai/ontology/conversation-history#ConversationTurn"
    end

    test "prompt_iri/0 returns correct IRI" do
      assert Ontology.prompt_iri() ==
               "https://jido.ai/ontology/conversation-history#Prompt"
    end

    test "answer_iri/0 returns correct IRI" do
      assert Ontology.answer_iri() ==
               "https://jido.ai/ontology/conversation-history#Answer"
    end

    test "tool_invocation_iri/0 returns correct IRI" do
      assert Ontology.tool_invocation_iri() ==
               "https://jido.ai/ontology/conversation-history#ToolInvocation"
    end

    test "tool_result_iri/0 returns correct IRI" do
      assert Ontology.tool_result_iri() ==
               "https://jido.ai/ontology/conversation-history#ToolResult"
    end
  end

  describe "conversation individual creators" do
    test "create_conversation_individual/1 creates correct IRI" do
      iri = Ontology.create_conversation_individual("conv-123")
      assert iri == "https://jido.ai/conversations#conv-123"
    end

    test "create_conversation_turn_individual/2 creates correct IRI" do
      iri = Ontology.create_conversation_turn_individual("conv-123", 0)
      assert iri == "https://jido.ai/conversations#conv-123/turn-0"
    end

    test "create_prompt_individual/2 creates correct IRI" do
      iri = Ontology.create_prompt_individual("conv-123", 0)
      assert iri == "https://jido.ai/conversations#conv-123/turn-0/prompt"
    end

    test "create_answer_individual/2 creates correct IRI" do
      iri = Ontology.create_answer_individual("conv-123", 0)
      assert iri == "https://jido.ai/conversations#conv-123/turn-0/answer"
    end

    test "create_tool_invocation_individual/3 creates correct IRI" do
      iri = Ontology.create_tool_invocation_individual("conv-123", 0, 0)
      assert iri == "https://jido.ai/conversations#conv-123/turn-0/tool-0"
    end

    test "create_tool_result_individual/3 creates correct IRI" do
      iri = Ontology.create_tool_result_individual("conv-123", 0, 0)
      assert iri == "https://jido.ai/conversations#conv-123/turn-0/tool-0/result"
    end
  end
end
