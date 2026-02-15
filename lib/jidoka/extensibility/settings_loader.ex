defmodule Jidoka.Extensibility.SettingsLoader do
  @moduledoc """
  Loads and merges extensibility settings from predetermined locations.

  Load order:
  1. Global settings (`~/.jido_code/settings.json`)
  2. Project settings (`<project>/.jido_code/settings.json`)

  Project settings override global settings.
  """

  alias Jidoka.Extensibility.{PathResolver, Precedence, Settings}

  @type error_reason ::
          {:read_error, String.t(), File.posix()}
          | {:invalid_json, String.t(), term()}

  @doc """
  Loads and merges global and project settings into a normalized settings struct.

  Missing files are treated as empty settings.
  """
  @spec load(String.t(), keyword()) :: {:ok, Settings.t()} | {:error, error_reason()}
  def load(project_root \\ File.cwd!(), opts \\ [])
      when is_binary(project_root) and is_list(opts) do
    paths = PathResolver.tier_paths(project_root, opts)
    global_settings_path = paths.global.settings
    local_settings_path = paths.local.settings

    with {:ok, global_payload} <- read_settings_file(global_settings_path),
         {:ok, local_payload} <- read_settings_file(local_settings_path) do
      merged = Precedence.merge_tiers(global_payload, local_payload)

      settings =
        Settings.from_map(merged,
          global_settings_path: maybe_existing_path(global_settings_path),
          local_settings_path: maybe_existing_path(local_settings_path)
        )

      {:ok, settings}
    end
  end

  @doc """
  Loads and merges settings and returns only the merged raw map.
  """
  @spec load_raw(String.t(), keyword()) :: {:ok, map()} | {:error, error_reason()}
  def load_raw(project_root \\ File.cwd!(), opts \\ [])
      when is_binary(project_root) and is_list(opts) do
    case load(project_root, opts) do
      {:ok, %Settings{raw: raw}} -> {:ok, raw}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_settings_file(path) when is_binary(path) do
    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, map} when is_map(map) -> {:ok, map}
            {:ok, _other} -> {:error, {:invalid_json, path, :expected_object}}
            {:error, reason} -> {:error, {:invalid_json, path, reason}}
          end

        {:error, reason} ->
          {:error, {:read_error, path, reason}}
      end
    else
      {:ok, %{}}
    end
  end

  defp maybe_existing_path(path) do
    if File.exists?(path), do: path, else: nil
  end
end
