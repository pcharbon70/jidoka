defmodule Jidoka.Extensibility.PathResolverTest do
  use ExUnit.Case, async: false

  alias Jidoka.Extensibility.PathResolver

  setup do
    original_extensibility = Application.get_env(:jidoka, :extensibility)

    on_exit(fn ->
      if is_nil(original_extensibility) do
        Application.delete_env(:jidoka, :extensibility)
      else
        Application.put_env(:jidoka, :extensibility, original_extensibility)
      end
    end)

    :ok
  end

  describe "global_root/1" do
    test "expands default global root" do
      Application.put_env(:jidoka, :extensibility, [])

      assert PathResolver.global_root() == Path.expand("~/.jido_code")
    end

    test "uses configured global root from app config" do
      Application.put_env(:jidoka, :extensibility, global_root: "~/custom_jido_code")

      assert PathResolver.global_root() == Path.expand("~/custom_jido_code")
    end

    test "allows global root override via options" do
      assert PathResolver.global_root(global_root: "/tmp/ext-global") == "/tmp/ext-global"
    end
  end

  describe "local_root/2" do
    test "resolves relative local dir against project root" do
      project_root = "/tmp/jidoka_project"

      assert PathResolver.local_root(project_root, local_dir: ".jido_code") ==
               "/tmp/jidoka_project/.jido_code"
    end

    test "uses absolute local dir when configured" do
      assert PathResolver.local_root("/tmp/project", local_dir: "/tmp/custom-local") ==
               "/tmp/custom-local"
    end
  end

  describe "tier_paths/2" do
    test "returns all predetermined global and local paths" do
      paths =
        PathResolver.tier_paths("/tmp/project-root",
          global_root: "/tmp/global-jido",
          local_dir: ".jido_code"
        )

      assert paths.global.root == "/tmp/global-jido"
      assert paths.global.settings == "/tmp/global-jido/settings.json"
      assert paths.global.memory == "/tmp/global-jido/JIDO.md"
      assert paths.global.commands == "/tmp/global-jido/commands"
      assert paths.global.agents == "/tmp/global-jido/agents"
      assert paths.global.skills == "/tmp/global-jido/skills"
      assert paths.global.plugins == "/tmp/global-jido/plugins"
      assert paths.global.hooks == "/tmp/global-jido/hooks"

      assert paths.local.root == "/tmp/project-root/.jido_code"
      assert paths.local.settings == "/tmp/project-root/.jido_code/settings.json"
      assert paths.local.memory == "/tmp/project-root/.jido_code/JIDO.md"
      assert paths.local.commands == "/tmp/project-root/.jido_code/commands"
      assert paths.local.agents == "/tmp/project-root/.jido_code/agents"
      assert paths.local.skills == "/tmp/project-root/.jido_code/skills"
      assert paths.local.plugins == "/tmp/project-root/.jido_code/plugins"
      assert paths.local.hooks == "/tmp/project-root/.jido_code/hooks"
    end
  end
end
