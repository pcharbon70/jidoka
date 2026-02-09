defmodule Jidoka.Tools.OntologyCache do
  @moduledoc """
  Provides the ontology schema for prompt caching.

  This module contains the static ontology schema that should be
  cached by the LLM for efficient query generation. The schema
  describes the Elixir codebase ontology from elixir-ontologies.

  ## Usage

  Use this module's schema prompt in system prompts to enable
  prompt caching. The schema is static and changes only when
  elixir-ontologies is updated.

      iex> OntologyCache.schema_prompt()
      #=> "ELIXIR CODEBASE ONTOLOGY REFERENCE..."

  ## Prompt Caching

  Include the output of `schema_prompt/0` in the LLM system prompt
  to enable prompt caching. This ensures the schema is cached after
  the first request and reused for subsequent queries.

  ## Example

      system_prompt = "You are a coding assistant with access to a codebase knowledge graph. " <>
        OntologyCache.schema_prompt() <>
        "When you need to query the codebase, use the sparql_query tool with SPARQL queries."
  """

  @doc """
  Returns the ontology schema as a string for prompt caching.

  This schema describes the Elixir codebase ontology from elixir-ontologies,
  including namespaces, classes, properties, and example queries.
  """
  @spec schema_prompt() :: String.t()
  def schema_prompt do
    "ELIXIR CODEBASE ONTOLOGY REFERENCE\n" <>
    "===================================\n" <>
    "\n" <>
    "NAMESPACES:\n" <>
    "- struct: <https://w3id.org/elixir-code/structure#>\n" <>
    "- core: <https://w3id.org/elixir-code/core#>\n" <>
    "- otp: <https://w3id.org/elixir-code/otp#>\n" <>
    "- evo: <https://w3id.org/elixir-code/evolution#>\n" <>
    "\n" <>
    "KEY CLASSES:\n" <>
    "- struct:Module - Elixir modules\n" <>
    "- struct:PublicFunction - Public functions\n" <>
    "- struct:PrivateFunction - Private functions\n" <>
    "- struct:Protocol - Protocol definitions\n" <>
    "- struct:Behaviour - Behaviour definitions\n" <>
    "- struct:Struct - Struct definitions\n" <>
    "\n" <>
    "KEY PROPERTIES:\n" <>
    "- struct:moduleName - Module/function name (string)\n" <>
    "- struct:belongsTo - Function belongs to Module\n" <>
    "- struct:arity - Function arity (integer)\n" <>
    "- struct:hasDocumentation - Documentation string\n" <>
    "- struct:implementsBehaviour - Module implements Behaviour\n" <>
    "- struct:definesCallback - Behaviour defines callback\n" <>
    "- struct:implementsProtocol - Module implements Protocol\n" <>
    "- struct:callsFunction - Function calls another function\n" <>
    "- struct:usesModule - Module uses another module\n" <>
    "- struct:requiresModule - Module requires another module\n" <>
    "- struct:importsFrom - Module imports from module\n" <>
    "- struct:aliasesModule - Module aliases module\n" <>
    "- struct:hasField - Struct has a field\n" <>
    "- struct:fieldName - Field name\n" <>
    "- core:inSourceFile - Entity defined in source file\n" <>
    "\n" <>
    "EXAMPLE QUERIES:\n" <>
    "\n" <>
    "Find all modules:\n" <>
    "SELECT ?module ?name WHERE ?module a struct:Module . ?module struct:moduleName ?name .\n" <>
    "\n" <>
    "Find functions in a module:\n" <>
    "SELECT ?function ?name ?arity WHERE\n" <>
    "  ?module struct:moduleName \"MyApp.User\" .\n" <>
    "  ?function struct:belongsTo ?module .\n" <>
    "  ?function struct:functionName ?name .\n" <>
    "  ?function struct:arity ?arity .\n" <>
    "\n" <>
    "Find behaviour implementations:\n" <>
    "SELECT ?impl ?impl_name WHERE\n" <>
    "  ?behaviour struct:moduleName \"GenServer\" .\n" <>
    "  ?impl struct:implementsBehaviour ?behaviour .\n" <>
    "  ?impl struct:moduleName ?impl_name .\n" <>
    "\n" <>
    "Find protocol implementations:\n" <>
    "SELECT ?impl ?impl_name WHERE\n" <>
    "  ?protocol struct:moduleName \"Enumerable\" .\n" <>
    "  ?impl struct:implementsProtocol ?protocol .\n" <>
    "  ?impl struct:moduleName ?impl_name .\n" <>
    "\n" <>
    "Get module dependencies:\n" <>
    "SELECT ?dep_name WHERE\n" <>
    "  ?module struct:moduleName \"MyApp.User\" .\n" <>
    "  ?module struct:usesModule ?dep .\n" <>
    "  ?dep struct:moduleName ?dep_name .\n" <>
    "\n" <>
    "Search for modules by name pattern:\n" <>
    "SELECT ?name WHERE\n" <>
    "  ?module a struct:Module .\n" <>
    "  ?module struct:moduleName ?name .\n" <>
    "  FILTER(CONTAINS(LCASE(STR(?name)), \"user\"))\n" <>
    "\n" <>
    "QUERY TIPS:\n" <>
    "- Always use LIMIT to prevent large result sets\n" <>
    "- Use OPTIONAL for optional properties\n" <>
    "- Use FILTER with CONTAINS for pattern matching\n" <>
    "- Use LCASE for case-insensitive searches\n"
  end

  @doc """
  Returns a concise version of the ontology schema.

  This is a shorter version suitable for brief references.
  """
  @spec concise_schema() :: String.t()
  def concise_schema do
    "ELIXIR ONTOLOGY - Quick Reference\n" <>
    "=================================\n" <>
    "\n" <>
    "Classes: Module, PublicFunction, PrivateFunction, Protocol, Behaviour, Struct\n" <>
    "\n" <>
    "Properties:\n" <>
    "- moduleName, belongsTo, arity, hasDocumentation\n" <>
    "- implementsBehaviour, implementsProtocol, callsFunction\n" <>
    "- usesModule, requiresModule, importsFrom, aliasesModule\n" <>
    "- hasField, fieldName, inSourceFile\n" <>
    "\n" <>
    "Namespaces: struct:, core:, otp:, evo:\n"
  end

  @doc """
  Returns SPARQL query templates for common patterns.

  These templates can be used as a starting point for constructing queries.
  """
  @spec query_templates() :: String.t()
  def query_templates do
    "SPARQL QUERY TEMPLATES\n" <>
    "======================\n" <>
    "\n" <>
    "Find all modules:\n" <>
    "SELECT ?m ?n WHERE ?m a struct:Module . ?m struct:moduleName ?n .\n" <>
    "\n" <>
    "Find module by name:\n" <>
    "SELECT ?m WHERE ?m a struct:Module ; struct:moduleName \"ModuleName\" .\n" <>
    "\n" <>
    "List functions in module:\n" <>
    "SELECT ?f ?n ?a WHERE\n" <>
    "  ?m struct:moduleName \"ModuleName\" .\n" <>
    "  ?f struct:belongsTo ?m ; struct:functionName ?n ; struct:arity ?a .\n" <>
    "\n" <>
    "Find behaviour implementations:\n" <>
    "SELECT ?i WHERE\n" <>
    "  ?b struct:moduleName \"BehaviourName\" .\n" <>
    "  ?i struct:implementsBehaviour ?b .\n" <>
    "\n" <>
    "Module dependencies:\n" <>
    "SELECT ?d WHERE\n" <>
    "  ?m struct:moduleName \"ModuleName\" ; struct:usesModule ?d .\n" <>
    "  ?d struct:moduleName ?dn .\n" <>
    "\n" <>
    "Search by pattern:\n" <>
    "SELECT ?n WHERE\n" <>
    "  ?m a struct:Module ; struct:moduleName ?n .\n" <>
    "  FILTER(CONTAINS(LCASE(STR(?n)), \"pattern\"))\n"
  end
end
