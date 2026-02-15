defmodule Jidoka.Extensibility.SettingsLoaderTest do
  use ExUnit.Case, async: false

  alias Jidoka.Extensibility.SettingsLoader

  setup do
    unique = System.unique_integer([:positive, :monotonic])
    base_dir = Path.join(System.tmp_dir!(), "jidoka_ext_loader_#{unique}")
    project_root = Path.join(base_dir, "project")
    global_root = Path.join(base_dir, "global")
    local_root = Path.join(project_root, ".jido_code")

    File.mkdir_p!(project_root)
    File.mkdir_p!(global_root)
    File.mkdir_p!(local_root)

    on_exit(fn ->
      File.rm_rf!(base_dir)
    end)

    {:ok,
     project_root: project_root,
     global_root: global_root,
     local_root: local_root,
     global_settings: Path.join(global_root, "settings.json"),
     local_settings: Path.join(local_root, "settings.json")}
  end

  describe "load/2" do
    test "merges global and local settings with local precedence", ctx do
      File.write!(
        ctx.global_settings,
        Jason.encode!(%{
          "version" => "2.0.0",
          "channels" => %{
            "default" => %{
              "socket" => "ws://localhost:4000/socket",
              "topic" => "jido:global"
            }
          },
          "plugins" => %{
            "enabled" => ["global-tooling"]
          }
        })
      )

      File.write!(
        ctx.local_settings,
        Jason.encode!(%{
          "channels" => %{
            "default" => %{
              "topic" => "jido:project"
            }
          },
          "plugins" => %{
            "enabled" => ["local-tooling"],
            "disabled" => ["legacy-tooling"]
          }
        })
      )

      assert {:ok, settings} =
               SettingsLoader.load(ctx.project_root,
                 global_root: ctx.global_root,
                 local_dir: ".jido_code"
               )

      assert settings.version == "2.0.0"
      assert settings.global_settings_path == ctx.global_settings
      assert settings.local_settings_path == ctx.local_settings
      assert settings.channels["default"]["socket"] == "ws://localhost:4000/socket"
      assert settings.channels["default"]["topic"] == "jido:project"
      assert settings.plugins["enabled"] == ["local-tooling"]
      assert settings.plugins["disabled"] == ["legacy-tooling"]
    end

    test "returns defaults when settings files are missing", ctx do
      assert {:ok, settings} =
               SettingsLoader.load(ctx.project_root,
                 global_root: ctx.global_root,
                 local_dir: ".jido_code"
               )

      assert settings.raw == %{}
      assert settings.channels == %{}
      assert settings.permissions == %{}
      assert settings.hooks == %{}
      assert settings.agents == %{}
      assert settings.plugins == %{}
      assert settings.global_settings_path == nil
      assert settings.local_settings_path == nil
    end

    test "returns an error when settings json is invalid", ctx do
      File.write!(ctx.local_settings, "{\"invalid\":")

      assert {:error, {:invalid_json, path, _reason}} =
               SettingsLoader.load(ctx.project_root,
                 global_root: ctx.global_root,
                 local_dir: ".jido_code"
               )

      assert path == ctx.local_settings
    end

    test "returns an error when settings json root is not an object", ctx do
      File.write!(ctx.global_settings, Jason.encode!(["not", "a", "map"]))

      assert {:error, {:invalid_json, path, :expected_object}} =
               SettingsLoader.load(ctx.project_root,
                 global_root: ctx.global_root,
                 local_dir: ".jido_code"
               )

      assert path == ctx.global_settings
    end
  end

  describe "load_raw/2" do
    test "returns merged raw settings map", ctx do
      File.write!(ctx.global_settings, Jason.encode!(%{"plugins" => %{"enabled" => ["global"]}}))
      File.write!(ctx.local_settings, Jason.encode!(%{"plugins" => %{"enabled" => ["local"]}}))

      assert {:ok, raw} =
               SettingsLoader.load_raw(ctx.project_root,
                 global_root: ctx.global_root,
                 local_dir: ".jido_code"
               )

      assert raw["plugins"]["enabled"] == ["local"]
    end
  end
end
