defmodule Jidoka.Extensibility.Settings do
  @moduledoc """
  Normalized extensibility settings loaded from global and project settings.json files.

  The raw merged payload is retained in `:raw` while common top-level sections
  are exposed as convenience fields.
  """

  @enforce_keys [:raw]
  defstruct version: nil,
            channels: %{},
            permissions: %{},
            hooks: %{},
            agents: %{},
            plugins: %{},
            raw: %{},
            global_settings_path: nil,
            local_settings_path: nil

  @type t :: %__MODULE__{
          version: String.t() | nil,
          channels: map(),
          permissions: map(),
          hooks: map(),
          agents: map(),
          plugins: map(),
          raw: map(),
          global_settings_path: String.t() | nil,
          local_settings_path: String.t() | nil
        }

  @doc """
  Builds a normalized settings struct from a merged settings map.

  ## Options

  * `:global_settings_path` - Absolute path to loaded global settings file
  * `:local_settings_path` - Absolute path to loaded project settings file
  """
  @spec from_map(map(), keyword()) :: t()
  def from_map(settings_map, opts \\ []) when is_map(settings_map) and is_list(opts) do
    %__MODULE__{
      version: fetch_value(settings_map, "version", :version),
      channels: ensure_map(fetch_value(settings_map, "channels", :channels)),
      permissions: ensure_map(fetch_value(settings_map, "permissions", :permissions)),
      hooks: ensure_map(fetch_value(settings_map, "hooks", :hooks)),
      agents: ensure_map(fetch_value(settings_map, "agents", :agents)),
      plugins: ensure_map(fetch_value(settings_map, "plugins", :plugins)),
      raw: settings_map,
      global_settings_path: Keyword.get(opts, :global_settings_path),
      local_settings_path: Keyword.get(opts, :local_settings_path)
    }
  end

  defp fetch_value(map, string_key, atom_key) do
    cond do
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}
end
