defmodule Jidoka.Knowledge.ElixirOntologyTest do
  use ExUnit.Case, async: false

  alias Jidoka.Knowledge.Ontology

  @moduletag :elixir_ontology
  @moduletag :external

  describe "ontology files" do
    test "elixir-core.ttl file exists" do
      core_path = Path.join([File.cwd!(), "priv", "ontologies", "elixir-core.ttl"])
      assert File.exists?(core_path), "elixir-core.ttl should exist in priv/ontologies"
    end

    test "elixir-structure.ttl file exists" do
      structure_path = Path.join([File.cwd!(), "priv", "ontologies", "elixir-structure.ttl"])
      assert File.exists?(structure_path), "elixir-structure.ttl should exist in priv/ontologies"
    end

    test "ontology files are valid Turtle format" do
      core_path = Path.join([File.cwd!(), "priv", "ontologies", "elixir-core.ttl"])
      structure_path = Path.join([File.cwd!(), "priv", "ontologies", "elixir-structure.ttl"])

      assert {:ok, core_content} = File.read(core_path)
      assert {:ok, structure_content} = File.read(structure_path)

      # RDF.Turtle.read_string should not raise
      assert {:ok, _graph} = RDF.Turtle.read_string(core_content)
      assert {:ok, _graph} = RDF.Turtle.read_string(structure_content)
    end
  end

  describe "load_elixir_ontology/0" do
    test "loads ontology successfully" do
      # Note: This test requires the knowledge engine to be running
      # The ontology should load without errors
      assert {:ok, info} = Ontology.load_elixir_ontology()
      assert info.version == "1.0.0"
      assert is_integer(info.triple_count)
      assert info.triple_count > 0
      assert length(info.files) == 2
      assert is_binary(info.graph)
    end

    test "returns consistent results on reload" do
      {:ok, info1} = Ontology.load_elixir_ontology()
      {:ok, info2} = Ontology.reload_elixir_ontology()

      # Triple count may increase due to idempotent insert
      assert info1.version == info2.version
      assert length(info1.files) == length(info2.files)
    end
  end

  describe "validate_loaded/1" do
    test "validates elixir ontology loaded correctly" do
      {:ok, info} = Ontology.validate_loaded(:elixir)

      assert info.ontology == :elixir
      assert info.classes_found > 0
      assert info.classes_found == info.expected_classes
      assert info.version == "1.0.0"
    end

    test "finds expected classes" do
      {:ok, info} = Ontology.validate_loaded(:elixir)

      # Should have at least the core Elixir classes
      assert info.classes_found >= 17
    end
  end

  describe "ontology_version/1" do
    test "returns version for elixir ontology" do
      assert "1.0.0" = Ontology.ontology_version(:elixir)
    end

    test "returns nil for unknown ontology" do
      assert nil == Ontology.ontology_version(:unknown)
    end
  end

  describe "elixir_class_exists?/1" do
    test "returns true for defined classes" do
      assert Ontology.elixir_class_exists?(:module)
      assert Ontology.elixir_class_exists?(:function)
      assert Ontology.elixir_class_exists?(:struct)
      assert Ontology.elixir_class_exists?(:protocol)
      assert Ontology.elixir_class_exists?(:behaviour)
      assert Ontology.elixir_class_exists?(:macro)
    end

    test "returns false for undefined classes" do
      refute Ontology.elixir_class_exists?(:unknown_class)
      refute Ontology.elixir_class_exists?(:not_a_class)
    end
  end

  describe "get_elixir_class_iri/1" do
    test "returns correct IRI for module class" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:module)
      assert iri == "https://w3id.org/elixir-code/structure#Module"
    end

    test "returns correct IRI for function class" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:function)
      assert iri == "https://w3id.org/elixir-code/structure#Function"
    end

    test "returns correct IRI for struct class" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:struct)
      assert iri == "https://w3id.org/elixir-code/structure#Struct"
    end

    test "returns correct IRI for protocol class" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:protocol)
      assert iri == "https://w3id.org/elixir-code/structure#Protocol"
    end

    test "returns correct IRI for behaviour class" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:behaviour)
      assert iri == "https://w3id.org/elixir-code/structure#Behaviour"
    end

    test "returns error for unknown class" do
      assert {:error, :not_found} = Ontology.get_elixir_class_iri(:unknown)
    end
  end

  describe "elixir_class_names/0" do
    test "returns list of class names" do
      names = Ontology.elixir_class_names()

      assert is_list(names)
      assert :module in names
      assert :function in names
      assert :struct in names
      assert :protocol in names
      assert :behaviour in names
      assert :macro in names
    end
  end

  describe "convenience functions" do
    test "module_iri/0 returns Module IRI" do
      iri = Ontology.module_iri()
      assert iri == "https://w3id.org/elixir-code/structure#Module"
    end

    test "function_iri/0 returns Function IRI" do
      iri = Ontology.function_iri()
      assert iri == "https://w3id.org/elixir-code/structure#Function"
    end

    test "struct_iri/0 returns Struct IRI" do
      iri = Ontology.struct_iri()
      assert iri == "https://w3id.org/elixir-code/structure#Struct"
    end

    test "protocol_iri/0 returns Protocol IRI" do
      iri = Ontology.protocol_iri()
      assert iri == "https://w3id.org/elixir-code/structure#Protocol"
    end

    test "behaviour_iri/0 returns Behaviour IRI" do
      iri = Ontology.behaviour_iri()
      assert iri == "https://w3id.org/elixir-code/structure#Behaviour"
    end

    test "macro_iri/0 returns Macro IRI" do
      iri = Ontology.macro_iri()
      assert iri == "https://w3id.org/elixir-code/structure#Macro"
    end
  end

  describe "individual creation" do
    test "create_module_individual/1 creates correct IRI for string" do
      iri = Ontology.create_module_individual("MyApp.Users")
      assert iri == "https://jido.ai/modules#MyApp.Users"
    end

    test "create_module_individual/1 creates correct IRI for atom" do
      iri = Ontology.create_module_individual(MyApp.Users)
      assert iri == "https://jido.ai/modules#MyApp.Users"
    end

    test "create_function_individual/3 creates correct IRI with arity" do
      iri = Ontology.create_function_individual("MyApp.Users", "get", 1)
      assert iri == "https://jido.ai/functions/MyApp.Users#get/1"
    end

    test "create_function_individual/3 handles atom module name" do
      iri = Ontology.create_function_individual(MyApp.Users, :get, 1)
      assert iri == "https://jido.ai/functions/MyApp.Users#get/1"
    end

    test "create_function_individual/3 handles zero arity" do
      iri = Ontology.create_function_individual("MyApp.Users", "list", 0)
      assert iri == "https://jido.ai/functions/MyApp.Users#list/0"
    end

    test "create_function_individual/3 handles higher arity" do
      iri = Ontology.create_function_individual("Enum", "map", 2)
      assert iri == "https://jido.ai/functions/Enum#map/2"
    end

    test "create_struct_individual/1 creates correct IRI for string" do
      iri = Ontology.create_struct_individual("MyApp.User")
      assert iri == "https://jido.ai/structs#MyApp.User"
    end

    test "create_struct_individual/1 creates correct IRI for atom" do
      iri = Ontology.create_struct_individual(MyApp.User)
      assert iri == "https://jido.ai/structs#MyApp.User"
    end

    test "create_source_file_individual/1 creates correct IRI" do
      iri = Ontology.create_source_file_individual("lib/my_app/users.ex")
      assert iri == "https://jido.ai/source-files/lib/my_app/users.ex"
    end

    test "create_source_file_individual/1 handles nested paths" do
      iri = Ontology.create_source_file_individual("lib/my_app/context/users/accounts.ex")
      assert iri == "https://jido.ai/source-files/lib/my_app/context/users/accounts.ex"
    end
  end

  describe "load_elixir_ontologies/2" do
    test "loads single ontology file" do
      core_path = Path.join([File.cwd!(), "priv", "ontologies", "elixir-core.ttl"])
      graph_iri = "https://jido.ai/graphs/system-knowledge"

      assert {:ok, info} = Ontology.load_elixir_ontologies([core_path], graph_iri)
      assert is_integer(info.triple_count)
      assert info.triple_count > 0
      assert length(info.files) == 1
    end

    test "loads multiple ontology files" do
      base_path = Path.join([File.cwd!(), "priv", "ontologies"])
      core_path = Path.join(base_path, "elixir-core.ttl")
      structure_path = Path.join(base_path, "elixir-structure.ttl")
      graph_iri = "https://jido.ai/graphs/system-knowledge"

      assert {:ok, info} = Ontology.load_elixir_ontologies([core_path, structure_path], graph_iri)
      assert is_integer(info.triple_count)
      assert info.triple_count > 0
      assert length(info.files) == 2
    end
  end

  describe "core ontology classes" do
    test "code element class exists" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:code_element)
      assert iri == "https://w3id.org/elixir-code/core#CodeElement"
    end

    test "source file class exists" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:source_file)
      assert iri == "https://w3id.org/elixir-code/core#SourceFile"
    end

    test "source location class exists" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:source_location)
      assert iri == "https://w3id.org/elixir-code/core#SourceLocation"
    end

    test "AST node class exists" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:ast_node)
      assert iri == "https://w3id.org/elixir-code/core#ASTNode"
    end

    test "expression class exists" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:expression)
      assert iri == "https://w3id.org/elixir-code/core#Expression"
    end

    test "literal class exists" do
      assert {:ok, iri} = Ontology.get_elixir_class_iri(:literal)
      assert iri == "https://w3id.org/elixir-code/core#Literal"
    end
  end
end
