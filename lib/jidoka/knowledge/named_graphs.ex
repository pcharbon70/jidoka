defmodule Jidoka.Knowledge.NamedGraphs do
  @moduledoc """
  High-level API for managing named graphs in the knowledge graph.

  This module provides convenience functions for working with standard named graphs
  without requiring explicit engine references. It acts as a wrapper around the
  Knowledge.Engine, using the default engine name (`:knowledge_engine`).

  ## Standard Named Graphs

  The system defines four standard named graphs:

  | Name | IRI | Purpose |
  |------|-----|---------|
  | `:long_term_context` | `https://jido.ai/graphs/long-term-context` | Persistent memories |
  | `:elixir_codebase` | `https://jido.ai/graphs/elixir-codebase` | Code model |
  | `:conversation_history` | `https://jido.ai/graphs/conversation-history` | Conversations |
  | `:system_knowledge` | `https://jido.ai/graphs/system-knowledge` | Ontologies |

  ## Examples

  List all standard graphs:

      NamedGraphs.list()
      #=> [:long_term_context, :elixir_codebase, :conversation_history, :system_knowledge]

  Get graph information:

      {:ok, info} = NamedGraphs.get_info(:long_term_context)
      info.purpose #=> "Persistent memories from work sessions"

  Check if a graph exists:

      NamedGraphs.exists?(:long_term_context)
      #=> true

  Create a graph:

      :ok = NamedGraphs.create(:long_term_context)

  Create all standard graphs:

      :ok = NamedGraphs.create_all()

  Get the IRI for a graph:

      {:ok, iri} = NamedGraphs.iri(:long_term_context)
      RDF.IRI.to_string(iri) #=> "https://jido.ai/graphs/long-term-context"

  Drop a graph:

      :ok = NamedGraphs.drop(:long_term_context)

  """

  alias Jidoka.Knowledge.Engine
  alias RDF.IRI

  # Default engine name (can be configured via Application config)
  @default_engine :knowledge_engine

  # ========================================================================
  # Graph Registry
  # ========================================================================

  @graph_info %{
    long_term_context: %{
      name: :long_term_context,
      iri_string: "https://jido.ai/graphs/long-term-context",
      purpose: "Persistent memories from work sessions",
      description:
        "Stores promoted memories from STM including facts, decisions, and lessons learned from work sessions"
    },
    elixir_codebase: %{
      name: :elixir_codebase,
      iri_string: "https://jido.ai/graphs/elixir-codebase",
      purpose: "Semantic model of Elixir codebase",
      description:
        "Stores code structure, module relationships, function signatures, and semantic information extracted from Elixir source code"
    },
    conversation_history: %{
      name: :conversation_history,
      iri_string: "https://jido.ai/graphs/conversation-history",
      purpose: "Conversation history and context",
      description:
        "Stores conversation messages, context state, and metadata for chat interactions and multi-turn dialogues"
    },
    system_knowledge: %{
      name: :system_knowledge,
      iri_string: "https://jido.ai/graphs/system-knowledge",
      purpose: "System ontologies and taxonomies",
      description:
        "Stores the Jido ontology defining memory types (Fact, Decision, LessonLearned) and other system knowledge"
    }
  }

  @standard_graphs Map.keys(@graph_info)

  # ========================================================================
  # Public API - Registry Access
  # ========================================================================

  @doc """
  Returns a list of all standard named graph names.

  ## Examples

      NamedGraphs.list()
      #=> [:long_term_context, :elixir_codebase, :conversation_history, :system_knowledge]

  """
  @spec list() :: [atom()]
  def list, do: @standard_graphs

  @doc """
  Gets metadata for a standard named graph.

  ## Parameters

  - `graph_name` - Atom name of the standard graph

  ## Returns

  - `{:ok, info_map}` - Graph metadata with keys:
    - `:name` - Graph atom name
    - `:iri_string` - Full IRI as string
    - `:purpose` - Brief purpose description
    - `:description` - Detailed description
  - `{:error, :unknown_graph}` - Graph is not a standard graph

  ## Examples

      {:ok, info} = NamedGraphs.get_info(:long_term_context)
      info.purpose #=> "Persistent memories from work sessions"

      {:error, :unknown_graph} = NamedGraphs.get_info(:unknown_graph)

  """
  @spec get_info(atom()) :: {:ok, map()} | {:error, :unknown_graph}
  def get_info(graph_name) when graph_name in @standard_graphs do
    {:ok, @graph_info[graph_name]}
  end

  def get_info(_graph_name), do: {:error, :unknown_graph}

  @doc """
  Checks if a graph is a standard named graph.

  Note: This checks if the graph is defined in the standard registry,
  not whether it exists in the triple store. Use `exists?/1` to check
  if the graph exists in the store.

  ## Parameters

  - `graph_name` - Graph name to check

  ## Returns

  - `true` - Graph is a standard named graph
  - `false` - Graph is not a standard named graph

  ## Examples

      NamedGraphs.standard_graph?(:long_term_context)
      #=> true

      NamedGraphs.standard_graph?(:custom_graph)
      #=> false

  """
  @spec standard_graph?(atom()) :: boolean()
  def standard_graph?(graph_name) when graph_name in @standard_graphs, do: true
  def standard_graph?(_graph_name), do: false

  # ========================================================================
  # Public API - Graph Operations
  # ========================================================================

  @doc """
  Checks if a named graph exists in the triple store.

  ## Parameters

  - `graph_name` - Standard graph atom name

  ## Returns

  - `true` - Graph exists in the store
  - `false` - Graph does not exist

  ## Examples

      NamedGraphs.exists?(:long_term_context)
      #=> true

      NamedGraphs.exists?(:unknown_graph)
      #=> false

  """
  @spec exists?(atom()) :: boolean()
  def exists?(graph_name) when graph_name in @standard_graphs do
    Engine.graph_exists?(engine_name(), graph_name)
  end

  def exists?(_graph_name), do: false

  @doc """
  Creates a standard named graph in the triple store.

  ## Parameters

  - `graph_name` - Standard graph atom name

  ## Returns

  - `:ok` - Graph created successfully
  - `{:error, reason}` - Failed to create

  ## Examples

      :ok = NamedGraphs.create(:long_term_context)

      {:error, reason} = NamedGraphs.create(:unknown_graph)

  """
  @spec create(atom()) :: :ok | {:error, term()}
  def create(graph_name) when graph_name in @standard_graphs do
    Engine.create_graph(engine_name(), graph_name)
  end

  def create(_graph_name), do: {:error, :unknown_graph}

  @doc """
  Creates all standard named graphs in the triple store.

  ## Returns

  - `:ok` - All graphs created successfully (some may have already existed)
  - `{error, reason}` - Failed to create one or more graphs

  ## Examples

      :ok = NamedGraphs.create_all()

  """
  @spec create_all() :: :ok | {:error, term()}
  def create_all do
    # Create each graph, collecting any errors
    results =
      Enum.map(@standard_graphs, fn graph_name ->
        create(graph_name)
      end)

    # Return :ok if all succeeded, otherwise return first error
    Enum.find(results, fn
      {:error, _} -> true
      _ -> false
    end) || :ok
  end

  @doc """
  Drops a standard named graph from the triple store.

  **Warning:** This will permanently delete all triples in the graph.

  ## Parameters

  - `graph_name` - Standard graph atom name

  ## Returns

  - `:ok` - Graph dropped successfully
  - `{:error, reason}` - Failed to drop

  ## Examples

      :ok = NamedGraphs.drop(:long_term_context)

  """
  @spec drop(atom()) :: :ok | {:error, term()}
  def drop(graph_name) when graph_name in @standard_graphs do
    Engine.drop_graph(engine_name(), graph_name)
  end

  def drop(_graph_name), do: {:error, :unknown_graph}

  # ========================================================================
  # Public API - IRI Conversion
  # ========================================================================

  @doc """
  Gets the IRI for a standard named graph.

  ## Parameters

  - `graph_name` - Standard graph atom name

  ## Returns

  - `{:ok, iri}` - RDF.IRI struct for the graph
  - `{:error, :unknown_graph}` - Graph is not a standard graph

  ## Examples

      {:ok, iri} = NamedGraphs.iri(:long_term_context)
      RDF.IRI.to_string(iri) #=> "https://jido.ai/graphs/long-term-context"

  """
  @spec iri(atom()) :: {:ok, IRI.t()} | {:error, :unknown_graph}
  def iri(graph_name) when graph_name in @standard_graphs do
    iri_string = @graph_info[graph_name].iri_string
    {:ok, IRI.new(iri_string)}
  end

  def iri(_graph_name), do: {:error, :unknown_graph}

  @doc """
  Gets the IRI string for a standard named graph.

  ## Parameters

  - `graph_name` - Standard graph atom name

  ## Returns

  - `{:ok, iri_string}` - IRI as a string
  - `{:error, :unknown_graph}` - Graph is not a standard graph

  ## Examples

      {:ok, iri_string} = NamedGraphs.iri_string(:long_term_context)
      iri_string #=> "https://jido.ai/graphs/long-term-context"

  """
  @spec iri_string(atom()) :: {:ok, String.t()} | {:error, :unknown_graph}
  def iri_string(graph_name) when graph_name in @standard_graphs do
    {:ok, @graph_info[graph_name].iri_string}
  end

  def iri_string(_graph_name), do: {:error, :unknown_graph}

  # ========================================================================
  # Private Helpers
  # ========================================================================

  defp engine_name do
    Application.get_env(:jidoka, :knowledge_engine_name, @default_engine)
  end
end
