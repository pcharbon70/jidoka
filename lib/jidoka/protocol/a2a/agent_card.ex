defmodule Jidoka.Protocol.A2A.AgentCard do
  @moduledoc """
  Agent Card specification for A2A (Agent-to-Agent) communication.

  An Agent Card describes an agent's capabilities, endpoints, and metadata
  for discovery and inter-agent communication. Based on JSON-LD and follows
  Schema.org patterns.

  ## Fields

  - `:id` - Unique agent identifier (e.g., "agent:jidoka:coordinator")
  - `:name` - Human-readable agent name
  - `:type` - List of agent types (e.g., ["Coordinator", "Orchestrator"])
  - `:version` - Agent version string
  - `:capabilities` - Agent capabilities (tools, accepts, produces)
  - `:endpoints` - Communication endpoints (rpc, ws)
  - `:authentication` - Authentication configuration (optional)

  ## Examples

      iex> card = AgentCard.new(%{
      ...>   id: "agent:jidoka:coordinator",
      ...>   name: "Jidoka Coordinator",
      ...>   type: ["Coordinator"],
      ...>   version: "1.0.0"
      ...> })
      iex> card.id
      "agent:jidoka:coordinator"

  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: [String.t()],
          version: String.t(),
          capabilities: capabilities(),
          endpoints: endpoints(),
          authentication: authentication() | nil
        }

  @type capabilities :: %{
          optional(:tools) => [String.t()],
          optional(:accepts) => [String.t()],
          optional(:produces) => [String.t()]
        }

  @type endpoints :: %{
          optional(:rpc) => String.t(),
          optional(:ws) => String.t(),
          optional(:http) => String.t()
        }

  @type authentication :: %{
          type: String.t(),
          token: String.t() | nil
        }

  defstruct [
    :id,
    :name,
    :type,
    :version,
    :description,
    capabilities: %{},
    endpoints: %{},
    authentication: nil
  ]

  @doc """
  Creates a new AgentCard with validation.

  ## Options

  * `:id` - Required. Unique agent identifier
  * `:name` - Required. Human-readable name
  * `:type` - Required. List of agent types
  * `:version` - Required. Version string
  * `:capabilities` - Optional. Agent capabilities map
  * `:endpoints` - Optional. Communication endpoints map
  * `:authentication` - Optional. Authentication configuration

  ## Examples

      iex> {:ok, card} = AgentCard.new(%{
      ...>   id: "agent:jidoka:coordinator",
      ...>   name: "Jidoka Coordinator",
      ...>   type: ["Coordinator"],
      ...>   version: "1.0.0"
      ...> })
      iex> card.name
      "Jidoka Coordinator"

      iex> {:error, _} = AgentCard.new(%{
      ...>   id: "invalid-id",
      ...>   name: "Test"
      ...> })

  """
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_id(attrs[:id]),
         :ok <- validate_type(attrs[:type]) do
      card = struct(__MODULE__, normalize_attrs(attrs))
      {:ok, card}
    end
  end

  @doc """
  Creates a new AgentCard for this Jidoka instance.

  ## Options

  * `:agent_type` - Type of this agent (default: ["Jidoka"])
  * `:extra_capabilities` - Additional capabilities to include
  * `:endpoints` - Override default endpoints

  ## Examples

      iex> card = AgentCard.for_jidoka(
      ...>   agent_type: ["Coordinator"],
      ...>   endpoints: %{rpc: "http://localhost:4000/a2a/rpc"}
      ...> )
      iex> String.starts_with?(card.id, "agent:jidoka:")
      true

  """
  def for_jidoka(opts \\ []) when is_list(opts) do
    agent_type = Keyword.get(opts, :agent_type, ["Jidoka"])
    extra_capabilities = Keyword.get(opts, :extra_capabilities, %{})
    endpoints = Keyword.get(opts, :endpoints, %{})
    build_jidoka_card(agent_type, extra_capabilities, endpoints)
  end

  def for_jidoka(opts) when is_map(opts) do
    agent_type = Map.get(opts, :agent_type, ["Jidoka"])
    extra_capabilities = Map.get(opts, :extra_capabilities, %{})
    endpoints = Map.get(opts, :endpoints, %{})
    build_jidoka_card(agent_type, extra_capabilities, endpoints)
  end

  defp build_jidoka_card(agent_type, extra_capabilities, endpoints) do
    capabilities =
      %{
        tools: [],
        accepts: ["text/plain", "application/json", "application/json-rpc+json"],
        produces: ["application/json", "application/json-rpc+json"]
      }
      |> Map.merge(extra_capabilities)

    {:ok, card} = new(%{
      id: "agent:jidoka:#{get_instance_id()}",
      name: "Jidoka #{Enum.join(agent_type, " ")}",
      type: agent_type,
      version: version(),
      capabilities: capabilities,
      endpoints: endpoints,
      authentication: nil
    })

    card
  end

  @doc """
  Converts an AgentCard to JSON-LD format.

  ## Examples

      iex> card = AgentCard.for_jidoka()
      iex> json = AgentCard.to_json_ld(card)
      iex> json["@context"]
      "https://jidoka.ai/ns/a2a#"

  """
  def to_json_ld(%__MODULE__{} = card) do
    %{
      "@context" => "https://jidoka.ai/ns/a2a#",
      "@id" => card.id,
      "name" => card.name,
      "type" => card.type,
      "version" => card.version,
      "capabilities" => card.capabilities,
      "endpoints" => card.endpoints
    }
    |> maybe_put_authentication(card.authentication)
    |> maybe_put_description(card.description)
  end

  @doc """
  Parses a JSON-LD AgentCard from a map.

  ## Examples

      iex> json = %{
      ...>   "@context" => "https://jidoka.ai/ns/a2a#",
      ...>   "id" => "agent:test:123",
      ...>   "name" => "Test Agent",
      ...>   "type" => ["Test"],
      ...>   "version" => "1.0.0"
      ...> }
      iex> {:ok, card} = AgentCard.from_json_ld(json)
      iex> card.name
      "Test Agent"

  """
  def from_json_ld(json) when is_map(json) do
    attrs = %{
      id: Map.get(json, "@id") || Map.get(json, "id") || Map.get(json, :id),
      name: Map.get(json, "name") || Map.get(json, :name),
      type: Map.get(json, "type") || Map.get(json, :type),
      version: Map.get(json, "version") || Map.get(json, :version),
      description: Map.get(json, "description") || Map.get(json, :description),
      capabilities: Map.get(json, "capabilities") || Map.get(json, :capabilities) || %{},
      endpoints: Map.get(json, "endpoints") || Map.get(json, :endpoints) || %{},
      authentication: Map.get(json, "authentication") || Map.get(json, :authentication)
    }

    new(attrs)
  end

  @doc """
  Returns true if the agent card appears valid for basic usage.

  ## Examples

      iex> card = AgentCard.for_jidoka()
      iex> AgentCard.valid?(card)
      true

  """
  def valid?(%__MODULE__{} = card) do
    case validate_required(%{
      id: card.id,
      name: card.name,
      type: card.type,
      version: card.version
    }) do
      :ok -> true
      _ -> false
    end
  end

  # Private Helpers

  defp validate_required(attrs) do
    required = [:id, :name, :type, :version]
    missing = Enum.reject(required, &Map.has_key?(attrs, &1))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp validate_id(id) when is_binary(id) do
    if String.starts_with?(id, "agent:") do
      :ok
    else
      {:error, {:invalid_id, "must start with 'agent:'"}}
    end
  end

  defp validate_id(_), do: {:error, {:invalid_id, "must be a string"}}

  defp validate_type(type) when is_list(type) do
    if Enum.all?(type, &is_binary/1) do
      :ok
    else
      {:error, {:invalid_type, "must be a list of strings"}}
    end
  end

  defp validate_type(_), do: {:error, {:invalid_type, "must be a list"}}

  defp normalize_attrs(attrs) do
    %{
      id: to_string(attrs[:id] || attrs["id"]),
      name: to_string(attrs[:name] || attrs["name"]),
      type: normalize_type(attrs[:type] || attrs["type"]),
      version: to_string(attrs[:version] || attrs["version"]),
      description: attrs[:description] || attrs["description"],
      capabilities: normalize_capabilities(attrs[:capabilities] || attrs["capabilities"] || %{}),
      endpoints: normalize_endpoints(attrs[:endpoints] || attrs["endpoints"] || %{}),
      authentication: attrs[:authentication] || attrs["authentication"]
    }
  end

  defp normalize_type(type) when is_list(type), do: type
  defp normalize_type(type) when is_binary(type), do: [type]
  defp normalize_type(_), do: []

  defp normalize_capabilities(cap) when is_map(cap), do: cap
  defp normalize_capabilities(_), do: %{}

  defp normalize_endpoints(eps) when is_map(eps), do: eps
  defp normalize_endpoints(_), do: %{}

  defp maybe_put_authentication(json, nil), do: json
  defp maybe_put_authentication(json, auth), do: Map.put(json, "authentication", auth)

  defp maybe_put_description(json, nil), do: json
  defp maybe_put_description(json, description), do: Map.put(json, "description", description)

  defp get_hostname do
    case :inet.gethostname() do
      {:ok, hostname} -> to_string(hostname)
      _ -> "localhost"
    end
  end

  defp get_instance_id do
    # Use node name or generate a unique ID
    node()
    |> to_string()
    |> String.replace("@", "-")
    |> String.replace(".", "-")
  end

  defp version do
    case :application.get_key(:jidoka, :vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      _ -> "0.1.0"
    end
  end
end
