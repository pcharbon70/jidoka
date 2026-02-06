defmodule JidoCoderLib.Memory.Ontology do
  @moduledoc """
  Convert between memory items and RDF triples using the Jido Memory Core ontology.

  This module handles serialization of memory maps to RDF for storage in the
  knowledge graph, and deserialization back to memory maps.

  ## Jido Memory Core Ontology

  Based on the Jido Memory Core (jmem) ontology:
  - Namespace: https://w3id.org/jido/memory/core#
  - Defines classes: Fact, Claim, DerivedFact, PlanStepFact, UserPreference, etc.
  - Defines properties: statementText, confidence, salience, createdAt, etc.

  ## Memory Type Mapping

  Memory type atoms map to Jido ontology classes:

  | Type Atom | Ontology Class |
  |-----------|----------------|
  | :fact | jmem:Fact |
  | :claim | jmem:Claim |
  | :derived_fact | jmem:DerivedFact |
  | :analysis | jmem:Claim |
  | :conversation | jmem:Claim |
  | :file_context | jmem:DocumentSource |
  | :decision | jmem:PlanStepFact |
  | :assumption | jmem:Claim |
  | :user_preference | jmem:UserPreference |
  | :constraint | jmem:ConstraintFact |
  | :tool_result | jmem:ToolResultFact |

  ## Examples

      iex> memory = %{
      ...>   id: "mem_1",
      ...>   session_id: "session_123",
      ...>   type: :fact,
      ...>   data: %{key: "value"},
      ...>   importance: 0.8,
      ...>   created_at: DateTime.utc_now(),
      ...>   updated_at: DateTime.utc_now()
      ...> }
      iex> {:ok, description} = Ontology.to_rdf(memory)
      iex> description.subject
      ~I<https://jido.ai/memory/mem_1>

  """

  alias RDF.{Description, IRI}

  # Jido Memory Core namespace
  @jmem_ns "https://w3id.org/jido/memory/core#"
  # Memory individual namespace
  @memory_ns "https://jido.ai/memory/"
  # Session context namespace
  @session_ns "https://jido.ai/sessions/"

  # RDF namespaces
  @rdf_ns RDF.NS.RDF

  @typedoc "Memory item map structure"
  @type memory :: %{
          id: String.t(),
          session_id: String.t(),
          type: atom(),
          data: map(),
          importance: float(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @typedoc "Memory type atoms"
  @type memory_type ::
          :fact
          | :claim
          | :derived_fact
          | :analysis
          | :conversation
          | :file_context
          | :decision
          | :assumption
          | :user_preference
          | :constraint
          | :tool_result

  # Memory type to ontology class mapping
  @type_to_class %{
    fact: "Fact",
    claim: "Claim",
    derived_fact: "DerivedFact",
    analysis: "Claim",
    conversation: "Claim",
    file_context: "DocumentSource",
    decision: "PlanStepFact",
    assumption: "Claim",
    user_preference: "UserPreference",
    constraint: "ConstraintFact",
    tool_result: "ToolResultFact"
  }

  # Reverse mapping (class suffix to type atom)
  @class_to_type %{
    "Fact" => :fact,
    "Claim" => :claim,
    "DerivedFact" => :derived_fact,
    "DocumentSource" => :file_context,
    "PlanStepFact" => :decision,
    "UserPreference" => :user_preference,
    "ConstraintFact" => :constraint,
    "ToolResultFact" => :tool_result
  }

  @doc """
  Convert a memory map to an RDF Description using Jido Memory Core ontology.

  ## Options

  * `:context_graph` - Optional RDF.Graph to add the description to

  ## Examples

      iex> memory = %{
      ...>   id: "mem_1",
      ...>   session_id: "session_123",
      ...>   type: :fact,
      ...>   data: %{key: "value"},
      ...>   importance: 0.8,
      ...>   created_at: DateTime.utc_now(),
      ...>   updated_at: DateTime.utc_now()
      ...> }
      iex> {:ok, desc} = Ontology.to_rdf(memory)
      iex> is_struct(desc, RDF.Description)
      true

  """
  @spec to_rdf(memory(), keyword()) :: {:ok, Description.t()} | {:error, term()}
  def to_rdf(memory, _opts \\ []) do
    try do
      uri = memory_uri(memory.id)
      class_uri = class_uri_for_type(memory.type)
      session_context_uri = session_context_uri(memory.session_id)

      description =
        Description.new(uri,
          init: [
            {@rdf_ns.type(), class_uri},
            {statement_text(), serialize_data(memory.data)},
            {salience(), literal(memory.importance)},
            {created_at(), literal_datetime(memory.created_at)},
            {updated_at(), literal_datetime(memory.updated_at)},
            {in_context(), session_context_uri},
            {session_id(), literal(memory.session_id)}
          ]
        )

      {:ok, description}
    rescue
      e -> {:error, {:conversion_error, Exception.message(e)}}
    end
  end

  @doc """
  Convert an RDF Description back to a memory map.

  ## Examples

      iex> memory = %{
      ...>   id: "mem_1",
      ...>   session_id: "session_123",
      ...>   type: :fact,
      ...>   data: %{key: "value"},
      ...>   importance: 0.8,
      ...>   created_at: DateTime.utc_now(),
      ...>   updated_at: DateTime.utc_now()
      ...> }
      iex> {:ok, desc} = Ontology.to_rdf(memory)
      iex> {:ok, restored} = Ontology.from_rdf(desc)
      iex> restored.id
      "mem_1"

  """
  @spec from_rdf(Description.t() | IRI.t()) :: {:ok, memory()} | {:error, term()}
  def from_rdf(%Description{} = description) do
    try do
      # Extract ID from subject URI
      id = id_from_uri(description.subject)

      # Get type from rdf:type
      type = extract_type(description)

      # Get session_id from jmem:sessionId
      session_id = extract_session_id(description)

      # Get statement text and deserialize
      data = extract_data(description)

      # Get salience (importance)
      importance = extract_literal(description, salience(), 0.5)

      # Get timestamps
      created_at = extract_datetime(description, created_at())
      updated_at = extract_datetime(description, updated_at())

      memory = %{
        id: id,
        session_id: session_id,
        type: type,
        data: data,
        importance: importance,
        created_at: created_at,
        updated_at: updated_at
      }

      {:ok, memory}
    rescue
      e -> {:error, {:parse_error, Exception.message(e)}}
    end
  end

  def from_rdf(%IRI{} = iri) do
    {:error, {:not_implemented, "Use RDF.Graph to look up descriptions by IRI"}}
  end

  @doc """
  Get the URI for a memory individual by ID.

  ## Examples

      iex> Ontology.memory_uri("mem_1")
      ~I<https://jido.ai/memory/mem_1>

  """
  @spec memory_uri(String.t()) :: IRI.t()
  def memory_uri(id), do: IRI.new("#{@memory_ns}#{id}")

  @doc """
  Extract memory ID from a URI.

  ## Examples

      iex> Ontology.id_from_uri(~I<https://jido.ai/memory/mem_1>)
      "mem_1"

  """
  @spec id_from_uri(IRI.t()) :: String.t() | nil
  def id_from_uri(%IRI{} = iri) do
    value = IRI.to_string(iri)

    if String.starts_with?(value, @memory_ns) do
      String.replace_prefix(value, @memory_ns, "")
    else
      nil
    end
  end

  @doc """
  Get the URI for a SessionContext by session_id.

  ## Examples

      iex> Ontology.session_context_uri("session_123")
      ~I<https://jido.ai/sessions/session_123#context>

  """
  @spec session_context_uri(String.t()) :: IRI.t()
  def session_context_uri(session_id) do
    IRI.new("#{@session_ns}#{session_id}#context")
  end

  @doc """
  Extract session_id from a SessionContext URI.

  ## Examples

      iex> Ontology.session_id_from_uri(~I<https://jido.ai/sessions/session_123#context>)
      "session_123"

  """
  @spec session_id_from_uri(IRI.t()) :: String.t() | nil
  def session_id_from_uri(%IRI{} = iri) do
    value = IRI.to_string(iri)

    if String.starts_with?(value, @session_ns) do
      value
      |> String.replace_prefix(@session_ns, "")
      |> String.replace_suffix("#context", "")
    else
      nil
    end
  end

  @doc """
  Get the ontology class URI for a memory type atom.

  ## Examples

      iex> Ontology.class_uri_for_type(:fact)
      ~I<https://w3id.org/jido/memory/core#Fact>

  """
  @spec class_uri_for_type(memory_type()) :: IRI.t()
  def class_uri_for_type(type) when is_atom(type) do
    class_name = Map.get(@type_to_class, type, "Fact")
    IRI.new("#{@jmem_ns}#{class_name}")
  end

  @doc """
  Get the memory type atom for an ontology class URI.

  ## Examples

      iex> Ontology.type_for_class_uri(~I<https://w3id.org/jido/memory/core#Fact>)
      :fact

  """
  @spec type_for_class_uri(IRI.t()) :: memory_type()
  def type_for_class_uri(%IRI{} = iri) do
    value = IRI.to_string(iri)

    # Extract class name from URI
    class_name =
      if String.contains?(value, "#") do
        value |> String.split("#") |> List.last()
      else
        value |> String.split("/") |> List.last()
      end

    Map.get(@class_to_type, class_name, :fact)
  end

  @doc """
  List all defined memory type atoms.

  ## Examples

      iex> types = Ontology.memory_types()
      iex> :fact in types
      true

  """
  @spec memory_types() :: [memory_type()]
  def memory_types do
    Map.keys(@type_to_class)
  end

  # Private Helpers

  defp statement_text, do: IRI.new("#{@jmem_ns}statementText")
  defp salience, do: IRI.new("#{@jmem_ns}salience")
  defp created_at, do: IRI.new("#{@jmem_ns}createdAt")
  defp updated_at, do: IRI.new("#{@jmem_ns}updatedAt")
  defp in_context, do: IRI.new("#{@jmem_ns}inContext")
  defp session_id, do: IRI.new("#{@jmem_ns}sessionId")

  defp serialize_data(data) when is_map(data) do
    case Jason.encode(data) do
      {:ok, json} -> literal(json)
      _ -> literal("#{inspect(data)}")
    end
  end

  defp serialize_data(data), do: literal("#{inspect(data)}")

  defp literal(value), do: RDF.Literal.new(value)

  defp literal_datetime(%DateTime{} = dt) do
    RDF.Literal.new(DateTime.to_iso8601(dt), datatype: RDF.NS.XSD.dateTime())
  end

  defp extract_type(description) do
    case Description.first(description, @rdf_ns.type()) do
      nil -> :fact
      class_uri when is_struct(class_uri, IRI) -> type_for_class_uri(class_uri)
      _ -> :fact
    end
  end

  defp extract_session_id(description) do
    case extract_literal(description, session_id()) do
      nil -> ""
      session_id when is_binary(session_id) -> session_id
    end
  end

  defp extract_data(description) do
    case Description.first(description, statement_text()) do
      nil ->
        %{}

      literal ->
        value = RDF.Literal.value(literal)

        # Try to parse as JSON
        case Jason.decode(value) do
          {:ok, map} when is_map(map) -> map
          _ -> %{text: value}
        end
    end
  end

  defp extract_literal(description, predicate, default \\ nil) do
    case Description.first(description, predicate) do
      nil -> default
      literal -> RDF.Literal.value(literal)
    end
  end

  defp extract_datetime(description, predicate) do
    case Description.first(description, predicate) do
      nil ->
        DateTime.utc_now()

      literal ->
        value = RDF.Literal.value(literal)

        case value do
          %DateTime{} = dt ->
            dt

          string when is_binary(string) ->
            case DateTime.from_iso8601(string) do
              {:ok, dt, _} -> dt
              _ -> DateTime.utc_now()
            end

          _ ->
            DateTime.utc_now()
        end
    end
  end
end
