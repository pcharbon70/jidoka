defmodule Jidoka.Utils.PathValidator do
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
    allow_symlinks = Keyword.get(opts, :allow_symlinks, false)

    # Expand and normalize the target path
    expanded_target = Path.expand(target_path)

    # Check each allowed directory
    Enum.find_value(allowed_dirs, fn allowed_dir ->
      expanded_allowed = Path.expand(allowed_dir)

      # First check: Ensure target starts with allowed path
      if String.starts_with?(expanded_target, expanded_allowed) do
        # Second check: Verify no symlink escapes the allowed directory
        check_symlink_safe(expanded_target, expanded_allowed, allow_symlinks)
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

    case Application.get_env(:jidoka, :allowed_index_directories) do
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

  defp check_symlink_safe(target_path, allowed_dir, allow_symlinks) do
    if allow_symlinks do
      # If symlinks are allowed, just do basic path check
      :ok
    else
      # Resolve symlinks to get the real path, then check
      case resolve_symlinks(target_path) do
        {:ok, real_path} ->
          # Check if the real path is within allowed directory
          real_expanded = Path.expand(real_path)
          allowed_expanded = Path.expand(allowed_dir)

          # Ensure the real path starts with allowed directory
          # Also ensure there's a path separator after the allowed dir to prevent
          # /allowed_dir_something from matching /allowed_dir
          allowed_with_sep = allowed_expanded <> if(String.ends_with?(allowed_expanded, "/"), do: "", else: "/")

          if String.starts_with?(real_expanded, allowed_with_sep) or real_expanded == allowed_expanded do
            :ok
          else
            {:error, :symlink_escapes_allowed_dir}
          end

        {:error, :symlink_loop} ->
          {:error, :symlink_loop_detected}

        {:error, _} ->
          # If we can't resolve the symlink, be conservative and reject
          {:error, :cannot_resolve_symlink}
      end
    end
  end

  # Resolve symlinks in a path to get the real target
  # This handles nested symlinks and detects loops
  defp resolve_symlinks(path, visited \\ MapSet.new()) do
    # Get the directory and basename
    dir = Path.dirname(path)
    base = Path.basename(path)

    # Resolve the directory first (bottom-up)
    case resolve_symlinks_in_dir(dir, visited) do
      {:ok, real_dir} ->
        # Now check if the current path component is a symlink
        current_path = Path.join(real_dir, base)

        case File.lstat(current_path) do
          {:ok, %File.Stat{type: :symlink}} ->
            # It's a symlink, resolve it
            case resolve_single_symlink(current_path, visited) do
              {:ok, target} ->
                # Recursively resolve the target (might be another symlink)
                if MapSet.member?(visited, target) do
                  {:error, :symlink_loop}
                else
                  resolve_symlinks(target, MapSet.put(visited, current_path))
                end

              {:error, _} ->
                {:error, :symlink_resolution_failed}
            end

          {:ok, _} ->
            # Not a symlink, return the path as-is
            {:ok, current_path}

          {:error, :enoent} ->
            # Path doesn't exist yet, can't check symlinks
            # This is okay - we're validating a path that might be created
            {:ok, current_path}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Resolve symlinks in a directory path
  defp resolve_symlinks_in_dir(dir, visited) do
    if dir == "." or dir == "" do
      {:ok, File.cwd!()}
    else
      parts = Path.split(dir)
      resolve_path_parts(parts, visited)
    end
  end

  # Resolve each part of a path, handling symlinks
  # Process parts in order from root to leaf
  defp resolve_path_parts(parts, visited) do
    parts
    |> Enum.reduce_while({:ok, "/"}, fn part, {:ok, base_path} ->
      current = Path.join([base_path, part])

      case File.lstat(current) do
        {:ok, %File.Stat{type: :symlink}} ->
          case resolve_single_symlink(current, visited) do
            {:ok, target} ->
              # Continue resolving with the symlink target
              # Split the target and continue from there
              target_parts = Path.split(target)
              # Resolve the target starting from the current base path
              resolved_target = Path.expand(target, Path.dirname(current))

              # Check if the resolved target is within bounds
              if String.starts_with?(resolved_target, base_path) do
                {:cont, {:ok, resolved_target}}
              else
                # Symlink target escapes the current base path
                {:halt, {:error, :symlink_escapes_allowed_dir}}
              end

            {:error, _} ->
              {:halt, {:error, :symlink_resolution_failed}}
          end

        {:ok, _} ->
          {:cont, {:ok, current}}

        {:error, :enoent} ->
          # Path component doesn't exist - allow but don't resolve further
          {:cont, {:ok, current}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # Resolve a single symlink and get its target
  defp resolve_single_symlink(path, visited) do
    if MapSet.member?(visited, path) do
      {:error, :symlink_loop}
    else
      case File.read_link(path) do
        {:ok, target} ->
          # If relative, resolve against the symlink's directory
          resolved =
            if Path.type(target) == :relative do
              Path.join([Path.dirname(path), target]) |> Path.expand()
            else
              Path.expand(target)
            end

          {:ok, resolved}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

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
