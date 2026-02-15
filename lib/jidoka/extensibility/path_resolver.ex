defmodule Jidoka.Extensibility.PathResolver do
  @moduledoc """
  Resolves predetermined extensibility paths for global and project tiers.

  Default layout:

  - Global root: `~/.jido_code`
  - Project root: `<project_root>/.jido_code`
  """

  @default_global_root "~/.jido_code"
  @default_local_dir ".jido_code"

  @type tier :: :global | :local

  @type tier_path_map :: %{
          root: String.t(),
          settings: String.t(),
          memory: String.t(),
          commands: String.t(),
          agents: String.t(),
          skills: String.t(),
          plugins: String.t(),
          hooks: String.t()
        }

  @type all_tier_paths :: %{global: tier_path_map(), local: tier_path_map()}

  @doc """
  Returns the resolved global extensibility root.

  ## Options

  * `:global_root` - Override the global root path
  """
  @spec global_root(keyword()) :: String.t()
  def global_root(opts \\ []) when is_list(opts) do
    opts
    |> Keyword.get(:global_root, config_global_root())
    |> expand_home()
    |> Path.expand()
  end

  @doc """
  Returns the resolved local extensibility root for a project.

  ## Options

  * `:local_dir` - Override the project-local directory
  """
  @spec local_root(String.t(), keyword()) :: String.t()
  def local_root(project_root \\ File.cwd!(), opts \\ [])
      when is_binary(project_root) and is_list(opts) do
    local_dir =
      opts
      |> Keyword.get(:local_dir, config_local_dir())
      |> expand_home()

    if Path.type(local_dir) == :absolute do
      Path.expand(local_dir)
    else
      Path.expand(local_dir, Path.expand(project_root))
    end
  end

  @doc """
  Returns all predetermined paths for both global and local tiers.
  """
  @spec tier_paths(String.t(), keyword()) :: all_tier_paths()
  def tier_paths(project_root \\ File.cwd!(), opts \\ [])
      when is_binary(project_root) and is_list(opts) do
    global = global_root(opts)
    local = local_root(project_root, opts)

    %{
      global: build_tier_paths(global),
      local: build_tier_paths(local)
    }
  end

  @doc """
  Returns all predetermined paths for a single tier.
  """
  @spec paths_for_tier(tier(), String.t(), keyword()) :: tier_path_map()
  def paths_for_tier(tier, project_root \\ File.cwd!(), opts \\ [])
      when tier in [:global, :local] and is_binary(project_root) and is_list(opts) do
    paths = tier_paths(project_root, opts)
    Map.fetch!(paths, tier)
  end

  @doc """
  Returns the resolved settings.json path for a tier.
  """
  @spec settings_path(tier(), String.t(), keyword()) :: String.t()
  def settings_path(tier, project_root \\ File.cwd!(), opts \\ [])
      when tier in [:global, :local] do
    paths_for_tier(tier, project_root, opts).settings
  end

  defp build_tier_paths(root) do
    %{
      root: root,
      settings: Path.join(root, "settings.json"),
      memory: Path.join(root, "JIDO.md"),
      commands: Path.join(root, "commands"),
      agents: Path.join(root, "agents"),
      skills: Path.join(root, "skills"),
      plugins: Path.join(root, "plugins"),
      hooks: Path.join(root, "hooks")
    }
  end

  defp config_global_root do
    Application.get_env(:jidoka, :extensibility, [])
    |> Keyword.get(:global_root, @default_global_root)
  end

  defp config_local_dir do
    Application.get_env(:jidoka, :extensibility, [])
    |> Keyword.get(:local_dir, @default_local_dir)
  end

  defp expand_home(path) when is_binary(path) do
    if String.starts_with?(path, "~") do
      Path.expand(path)
    else
      path
    end
  end
end
