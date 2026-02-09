defmodule Jidoka.Protocol.MCP.Capabilities do
  @moduledoc """
  Module for querying MCP server capabilities.

  After initialization, MCP servers report their capabilities which
  indicate what features they support. This module provides functions
  to check and query those capabilities.

  ## Server Capabilities

  * `:tools` - Server supports tools
  *:resources` - Server supports resources (data sources)
  * `:prompts` - Server supports prompts (templates)
  * `:logging` - Server supports logging configuration
  * `:roots` - Server supports filesystem roots

  ## Example

      # Check if server supports tools
      if Capabilities.supports_tools?(client) do
        # Discover and use tools
      end

      # Check if server supports resource subscriptions
      if Capabilities.supports_resource_subscriptions?(client) do
        # Subscribe to resource updates
      end

      # Can also pass capabilities map directly
      caps = %{"tools" => %{}}
      if Capabilities.supports_tools?(caps) do
        # Tools are supported
      end
  """

  alias Jidoka.Protocol.MCP.Client

  @type capabilities :: %{
          optional(:tools) => map(),
          optional(:resources) => map(),
          optional(:prompts) => map(),
          optional(:logging) => map(),
          optional(:roots) => map()
        }

  @type capability_path :: [atom()]

  ## Query Functions

  @doc """
  Get the full capabilities map from the client or return the map if passed directly.
  """
  def get(caps) when is_map(caps), do: caps
  def get(client \\ Client), do: Client.capabilities(client)

  @doc """
  Check if the server has a specific capability using a path.

  Can accept either a client process or a capabilities map directly.

  ## Examples

      # Check if tools are supported (with client)
      supports?(client, [:tools])

      # Check if tools are supported (with capabilities map)
      supports?(%{"tools" => %{}}, [:tools])

      # Check if resource subscriptions are supported
      supports?(client, [:resources, :subscribe])

      # Check if prompts support list changed notifications
      supports?(client, [:prompts, :listChanged])

  """
  def supports?(caps, path) when is_map(caps) and is_list(path) do
    # Convert atom keys to string keys for JSON-RPC format
    string_path = Enum.map(path, &to_string/1)

    # Check if the key path exists, then check its value
    if key_path_exists?(caps, string_path) do
      case get_in(caps, string_path) do
        # false means explicitly disabled
        false -> false
        # nil or any other value means capability exists
        _value -> true
      end
    else
      # Key path doesn't exist
      false
    end
  end

  def supports?(nil, _path), do: false
  def supports?(client, path) when is_list(path) do
    case get(client) do
      nil -> false
      caps -> supports?(caps, path)
    end
  end

  ## Tools Capability

  @doc """
  Check if the server supports tools.
  """
  def supports_tools?(client \\ Client) do
    supports?(client, [:tools])
  end

  @doc """
  Check if the server supports the `tools/list_changed` notification.
  """
  def supports_tools_list_changed?(client \\ Client) do
    supports?(client, [:tools, :listChanged])
  end

  ## Resources Capability

  @doc """
  Check if the server supports resources.
  """
  def supports_resources?(client \\ Client) do
    supports?(client, [:resources])
  end

  @doc """
  Check if the server supports resource subscriptions.
  """
  def supports_resource_subscriptions?(client \\ Client) do
    supports?(client, [:resources, :subscribe])
  end

  @doc """
  Check if the server supports the `resources/list_changed` notification.
  """
  def supports_resources_list_changed?(client \\ Client) do
    supports?(client, [:resources, :listChanged])
  end

  ## Prompts Capability

  @doc """
  Check if the server supports prompts.
  """
  def supports_prompts?(client \\ Client) do
    supports?(client, [:prompts])
  end

  @doc """
  Check if the server supports the `prompts/list_changed` notification.
  """
  def supports_prompts_list_changed?(client \\ Client) do
    supports?(client, [:prompts, :listChanged])
  end

  ## Logging Capability

  @doc """
  Check if the server supports logging configuration.
  """
  def supports_logging?(client \\ Client) do
    supports?(client, [:logging])
  end

  ## Roots Capability

  @doc """
  Check if the server supports filesystem roots.
  """
  def supports_roots?(client \\ Client) do
    supports?(client, [:roots])
  end

  @doc """
  Check if the server supports the `roots/list_changed` notification.
  """
  def supports_roots_list_changed?(client \\ Client) do
    supports?(client, [:roots, :listChanged])
  end

  ## Utility Functions

  @doc """
  Get a summary of supported capabilities as a list of atoms.

  Useful for debugging or displaying server capabilities.
  """
  def summary(client \\ Client) do
    caps = get(client)

    []
    |> maybe_add_capability(caps, :tools, :supports_tools)
    |> maybe_add_capability(caps, :resources, :supports_resources)
    |> maybe_add_capability(caps, :prompts, :supports_prompts)
    |> maybe_add_capability(caps, :logging, :supports_logging)
    |> maybe_add_capability(caps, :roots, :supports_roots)
  end

  @doc """
  Format capabilities as a human-readable string.
  """
  def format(client \\ Client) do
    supported = summary(client)

    if supported == [] do
      "No capabilities reported"
    else
      supported
      |> Enum.map(fn cap -> "- #{cap}" end)
      |> Enum.join("\n")
    end
  end

  ## Private Functions

  defp key_path_exists?(map, [key]) when is_map(map) do
    Map.has_key?(map, key)
  end

  defp key_path_exists?(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      nil -> false
      nested -> is_map(nested) and key_path_exists?(nested, rest)
    end
  end

  defp key_path_exists?(_map, _path), do: false

  defp maybe_add_capability(list, caps, key, name) do
    # Check for both atom and string key
    has_key = Map.has_key?(caps, key) or Map.has_key?(caps, to_string(key))

    if has_key do
      [name | list]
    else
      list
    end
  end
end
