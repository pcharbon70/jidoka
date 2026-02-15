defmodule Jidoka.MixProject do
  use Mix.Project

  def project do
    [
      app: :jidoka,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jidoka.Application, []}
    ]
  end

  defp description do
    """
    A headless, client-agnostic agentic coding assistant core built on Elixir and the BEAM VM.

    Provides multi-session workspaces, two-tier memory systems, semantic knowledge graphs,
    and pluggable protocol integrations (MCP, Phoenix Channels, A2A) for building
    intelligent coding assistants.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/agentjido/jidoka"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Jido framework for agents
      {:jido, "~> 2.0.0-rc.1", override: true},
      # AI/LLM integration
      {:jido_ai, git: "https://github.com/agentjido/jido_ai.git", override: true},
      # Messaging abstractions
      {:jido_messaging, git: "https://github.com/agentjido/jido_messaging.git"},
      # Phoenix PubSub for message passing
      {:phoenix_pubsub, "~> 2.1"},
      # Phoenix Channels client
      {:slipstream, "~> 1.2"},
      # LLM integration
      {:req_llm, "~> 1.3", override: true},
      # RDF and SPARQL for knowledge graph
      {:rdf, "~> 2.0"},
      {:sparql, "~> 0.3"},
      # Elixir ontology
      {:elixir_ontologies, path: "../../semantic/elixir-ontologies"},
      # Triple store backend
      {:triple_store, path: "../../semantic/triple_store", override: true},
      # JSON encoding for tool schemas
      {:jason, "~> 1.4"},
      # Ensure Plug macros are available for transitive deps (e.g. telegex hook server)
      {:plug, "~> 1.19"},
      # JSON Schema validation for MCP tool arguments
      {:ex_json_schema, "~> 0.11"}
    ]
  end
end
