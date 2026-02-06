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
      {:jido_ai, path: "../jido_ai"},
      # Phoenix PubSub for message passing
      {:phoenix_pubsub, "~> 2.1"},
      # LLM integration
      {:req_llm, "~> 1.3", override: true},
      # RDF and SPARQL for knowledge graph
      {:rdf, "~> 2.0"},
      {:sparql, "~> 0.3"},
      # Elixir ontology
      {:elixir_ontologies, path: "../../elixir-ontologies"},
      # Triple store backend
      {:triple_store, path: "/home/ducky/code/triple_store", override: true}
    ]
  end
end
