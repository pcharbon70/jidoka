defmodule Jidoka.Extensibility.Precedence do
  @moduledoc """
  Precedence and merge helpers for extensibility configuration.

  Global configuration is treated as the base layer and project configuration
  is applied on top.
  """

  @doc """
  Merges global and local settings maps, with local values taking precedence.

  Nested maps are recursively merged. Non-map values (including lists) are
  replaced by the local value.
  """
  @spec merge_tiers(map(), map()) :: map()
  def merge_tiers(global_settings, local_settings)
      when is_map(global_settings) and is_map(local_settings) do
    deep_merge(global_settings, local_settings)
  end

  @doc """
  Recursively merges two values.

  Map values are recursively merged. Any non-map value from `override` replaces
  the corresponding value from `base`.
  """
  @spec deep_merge(term(), term()) :: term()
  def deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, left, right ->
      deep_merge(left, right)
    end)
  end

  def deep_merge(_base, override), do: override
end
