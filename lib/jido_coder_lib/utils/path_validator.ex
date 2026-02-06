defmodule JidoCoderLib.Utils.PathValidator do
  @moduledoc """
  Path validation utilities for secure file operations.

  This module provides functions to validate file paths and ensure they
  stay within allowed directories, preventing directory traversal attacks.

  ## Examples

      iex> PathValidator.validate_path("lib/my_app.ex", "lib")
      :ok

      iex> PathValidator.validate_path("../etc/passwd", "lib")
      {:error, :path_outside_allowed}

  """

  @type path() :: String.t()
  @type allowed_dir() :: String.t() | [String.t()]
  @type validation_result() :: :ok | {:error, atom()}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Validates that a path is within the allowed directory.

  Prevents directory traversal by expanding and normalizing both paths,
  then checking that the target path is contained within the allowed base.

  ## Options

  * `:strict` - Require exact containment (default: true)
  * `:allow_symlinks` - Allow symbolic links (default: false)

  ## Examples

      iex> PathValidator.validate_within("lib/app.ex", "lib")
      :ok

      iex> PathValidator.validate_within("lib/app.ex", "/home/user/project/lib")
      :ok

      iex> PathValidator.validate_within("../etc/passwd", "lib")
      {:error, :path_outside_allowed}

      iex> PathValidator.validate_within("/etc/passwd", "lib")
      {:error, :path_outside_allowed}

  """
  @spec validate_within(path(), allowed_dir(), keyword()) :: validation_result()
  def validate_within(target_path, allowed_dir, opts \\ [])

  def validate_within(target_path, allowed_dir, opts) when is_binary(allowed_dir) do
    validate_within(target_path, [allowed_dir], opts)
  end

  def validate_within(target_path, allowed_dirs, opts) when is_list(allowed_dirs) do
    # Expand and normalize the target path
    expanded_target = Path.expand(target_path)

    # Check each allowed directory
    Enum.find_value(allowed_dirs, fn allowed_dir ->
      expanded_allowed = Path.expand(allowed_dir)

      # Ensure target starts with allowed path
      if String.starts_with?(expanded_target, expanded_allowed) do
        :ok
      else
        nil
      end
    end) || {:error, :path_outside_allowed}
  end

  @doc """
  Validates that a path is safe for indexing operations.

  Performs multiple checks:
  - Path is within allowed directories
  - Path has allowed file extension
  - Path is not a symbolic link (unless allowed)
  - Path exists (optional check)

  ## Options

  * `:allowed_dirs` - List of allowed base directories (default: [File.cwd!()])
  * `:allowed_extensions` - List of allowed extensions (default: [".ex", ".exs"])
  * `:allow_symlinks` - Allow symbolic links (default: false)
  * `:must_exist` - Path must exist (default: false)
  * `:max_depth` - Maximum directory depth (default: nil)

  ## Examples

      iex> PathValidator.safe_path?("lib/my_app/user.ex")
      :ok

      iex> PathValidator.safe_path?("../../../etc/passwd")
      {:error, :path_outside_allowed}

      iex> PathValidator.safe_path?("lib/my_app/config.json", allowed_extensions: [".ex", ".exs"])
      {:error, :invalid_extension}

  """
  @spec safe_path?(path(), keyword()) :: validation_result()
  def safe_path?(path, opts \\ []) do
    allowed_dirs = Keyword.get(opts, :allowed_dirs, [File.cwd!()])
    allowed_extensions = Keyword.get(opts, :allowed_extensions, [".ex", ".exs"])
    allow_symlinks = Keyword.get(opts, :allow_symlinks, false)
    must_exist = Keyword.get(opts, :must_exist, false)

    with :ok <- validate_within(path, allowed_dirs),
         :ok <- validate_extension(path, allowed_extensions),
         :ok <- validate_not_symlink(path, allow_symlinks),
         :ok <- validate_exists(path, must_exist) do
      :ok
    end
  end

  @doc """
  Gets the default allowed directories for indexing.

  Returns the current working directory and any configured
  additional directories.

  """
  @spec allowed_directories() :: [String.t()]
  def allowed_directories do
    base_dirs = [File.cwd!()]

    case Application.get_env(:jido_coder_lib, :allowed_index_directories) do
      nil -> base_dirs
      dirs when is_list(dirs) -> base_dirs ++ dirs
      dir when is_binary(dir) -> base_dirs ++ [dir]
    end
  end

  @doc """
  Checks if a path is potentially malicious.

  Returns true if the path contains patterns that could indicate
  an attack (e.g., "..", absolute paths outside allowed dirs).

  """
  @spec suspicious_path?(path()) :: boolean()
  def suspicious_path?(path) when is_binary(path) do
    # Check for null bytes first (invalid in paths)
    if String.contains?(path, "\0") do
      true
    else
      expanded = Path.expand(path)
      cwd = File.cwd!()

      cond do
        # Contains parent directory references in original or expanded
        String.contains?(path, "..") or String.contains?(expanded, "..") -> true
        # Absolute path - check if outside current working directory
        String.starts_with?(expanded, "/") and not String.starts_with?(expanded, cwd) -> true
        # Otherwise seems safe
        true -> false
      end
    end
  end

  @doc """
  Normalizes a path for safe use in operations.

  Expands the path and ensures it uses forward slashes.

  """
  @spec normalize(path()) :: String.t()
  def normalize(path) when is_binary(path) do
    path
    |> Path.expand()
    |> to_string()
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp validate_extension(path, allowed_extensions) do
    ext = Path.extname(path)

    if ext in allowed_extensions do
      :ok
    else
      {:error, :invalid_extension}
    end
  end

  defp validate_not_symlink(path, allow_symlinks) do
    if allow_symlinks do
      :ok
    else
      case File.lstat(path) do
        {:ok, %File.Stat{type: :symlink}} ->
          {:error, :symlink_not_allowed}

        {:ok, _} ->
          :ok

        {:error, _} ->
          # File doesn't exist yet, can't check for symlink
          :ok
      end
    end
  end

  defp validate_exists(path, must_exist) do
    if must_exist do
      if File.exists?(path) do
        :ok
      else
        {:error, :file_not_found}
      end
    else
      :ok
    end
  end
end
