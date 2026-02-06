defmodule Jidoka.Utils.PathValidatorTest do
  use ExUnit.Case, async: true

  alias Jidoka.Utils.PathValidator

  describe "validate_within/3" do
    test "accepts path within allowed directory" do
      assert PathValidator.validate_within("lib/test.ex", "lib") == :ok
      assert PathValidator.validate_within("lib/my_app/test.ex", "lib") == :ok
    end

    test "accepts path with ../ that resolves within allowed directory" do
      # When we're in the project root, ../project would be outside
      # But lib/subdir/../file.ex is within lib
      lib_path = Path.join([File.cwd!(), "lib"])
      test_path = Path.join([lib_path, "subdir", "..", "file.ex"])

      result = PathValidator.validate_within(test_path, lib_path)
      assert result == :ok
    end

    test "rejects path outside allowed directory" do
      assert PathValidator.validate_within("../etc/passwd", "lib") ==
               {:error, :path_outside_allowed}

      assert PathValidator.validate_within("/etc/passwd", "lib") ==
               {:error, :path_outside_allowed}
    end

    test "accepts path within any of multiple allowed directories" do
      assert PathValidator.validate_within("lib/test.ex", ["lib", "test"]) == :ok
      assert PathValidator.validate_within("test/test.exs", ["lib", "test"]) == :ok
    end

    test "rejects path outside all allowed directories" do
      assert PathValidator.validate_within("/etc/passwd", ["lib", "test"]) ==
               {:error, :path_outside_allowed}
    end
  end

  describe "safe_path?/2" do
    test "accepts valid .ex file within default directory" do
      assert PathValidator.safe_path?("lib/my_app/user.ex") == :ok
    end

    test "accepts valid .exs file within default directory" do
      assert PathValidator.safe_path?("test/my_app_test.exs") == :ok
    end

    test "rejects file with invalid extension" do
      assert PathValidator.safe_path?("lib/my_app/config.json") ==
               {:error, :invalid_extension}

      assert PathValidator.safe_path?("lib/my_app/readme.md") ==
               {:error, :invalid_extension}
    end

    test "rejects path outside allowed directory" do
      assert PathValidator.safe_path?("../../../etc/passwd") ==
               {:error, :path_outside_allowed}
    end

    test "accepts path within custom allowed directories" do
      result = PathValidator.safe_path?("/custom/path/test.ex",
        allowed_dirs: ["/custom/path"]
      )
      assert result == :ok
    end

    test "accepts custom allowed extensions" do
      result = PathValidator.safe_path?("lib/my_app/config.json",
        allowed_extensions: [".json"]
      )
      assert result == :ok
    end
  end

  describe "suspicious_path?/1" do
    test "identifies paths with parent directory references" do
      assert PathValidator.suspicious_path?("../../../etc/passwd") == true
      assert PathValidator.suspicious_path?("../test.ex") == true
    end

    test "identifies absolute paths outside current directory" do
      # This test depends on the current working directory
      cwd = File.cwd!()

      # Paths outside current directory are suspicious
      assert PathValidator.suspicious_path?("/etc/passwd") == true
      assert PathValidator.suspicious_path?("/tmp/test.ex") == true

      # Current directory and subdirectories are not suspicious
      assert PathValidator.suspicious_path?("lib/test.ex") == false
      assert PathValidator.suspicious_path?(Path.join([cwd, "lib", "test.ex"])) == false
    end

    test "identifies paths with null bytes" do
      # Null bytes in path names are problematic
      path_with_null = "lib/test" <> <<0>> <> "file.ex"
      assert PathValidator.suspicious_path?(path_with_null) == true
    end

    test "normal paths are not suspicious" do
      assert PathValidator.suspicious_path?("lib/my_app/user.ex") == false
      assert PathValidator.suspicious_path?("test/support/test.exs") == false
    end
  end

  describe "normalize/1" do
    test "expands relative paths" do
      result = PathValidator.normalize("lib/test.ex")
      assert String.starts_with?(result, "/")
    end

    test "handles absolute paths" do
      result = PathValidator.normalize("/absolute/path/test.ex")
      assert result == "/absolute/path/test.ex"
    end

    test "handles parent directory references" do
      # Normalizing with .. should resolve the path
      cwd = File.cwd!()
      lib_path = Path.join([cwd, "lib"])
      result = PathValidator.normalize(Path.join([lib_path, "..", "lib", "test.ex"]))

      assert result == Path.join([cwd, "lib", "test.ex"])
    end
  end

  describe "allowed_directories/0" do
    test "returns current directory by default" do
      dirs = PathValidator.allowed_directories()

      assert is_list(dirs)
      assert File.cwd!() in dirs
    end
  end
end
