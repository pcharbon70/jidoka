defmodule Jidoka.Tools.ListFiles do
  @moduledoc """
  Jido Action for listing files in directories.

  This tool allows the LLM to explore the directory structure
  of the codebase, with support for glob patterns and recursive listing.

  ## Parameters

  * `:path` - Directory path to list (optional, default: ".")
  * `:pattern` - Glob pattern for filtering files (optional, default: "*")
  * `:recursive` - Include subdirectories (optional, default: false)
  * `:include_hidden` - Include hidden files (optional, default: false)

  ## Examples

      {:ok, files} = ListFiles.run(
        %{path: "lib/jidoka", pattern: "*.ex", recursive: true},
        %{}
      )

      {:ok, files} = ListFiles.run(
        %{path: ".", pattern: "*.md", recursive: false},
        %{}
      )

  ## Security

  All paths are validated to stay within the project root.
  """

  use Jido.Action,
    name: "list_files",
    description: "List files in a directory with optional glob pattern filtering",
    category: "filesystem",
    tags: ["list", "files", "directory"],
    vsn: "1.0.0",
    schema: [
      path: [
        type: :string,
        required: false,
        default: ".",
        doc: "Directory path to list"
      ],
      pattern: [
        type: :string,
        required: false,
        default: "*",
        doc: "Glob pattern for filtering files"
      ],
      recursive: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Include subdirectories recursively"
      ],
      include_hidden: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Include hidden files (starting with .)"
      ]
    ]

  alias Jidoka.Utils.PathValidator

  @impl true
  def run(params, _context) do
    path = params[:path] || "."
    pattern = params[:pattern] || "*"
    recursive = params[:recursive] || false
    include_hidden = params[:include_hidden] || false

    project_root = File.cwd!()
    full_path = Path.expand(path, project_root)

    with :ok <- validate_directory(full_path, project_root) do
      wildcard_pattern = build_wildcard_pattern(full_path, pattern, recursive)

      files =
        Path.wildcard(wildcard_pattern)
        |> Enum.filter(&valid_file?(&1, include_hidden))
        |> Enum.map(fn file_path ->
          relative_path = Path.relative_to(file_path, project_root)

          stat = File.stat!(file_path)

          %{
            path: relative_path,
            name: Path.basename(file_path),
            type: file_type(stat),
            size: stat.size
          }
        end)
        |> Enum.sort_by(& &1.path)

      metadata = %{
        path: path,
        pattern: pattern,
        recursive: recursive,
        count: length(files),
        directories: count_directories(files),
        files: count_files(files)
      }

      {:ok, %{files: files, metadata: metadata}, []}
    else
      {:error, :path_outside_allowed} = error ->
        error

      {:error, :not_a_directory} = error ->
        error

      {:error, reason} ->
        {:error, "Failed to list files: #{inspect(reason)}"}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp validate_directory(path, project_root) do
    case PathValidator.validate_within(path, project_root) do
      :ok ->
        if File.dir?(path) do
          :ok
        else
          {:error, :not_a_directory}
        end

      error ->
        error
    end
  end

  defp build_wildcard_pattern(base_path, pattern, recursive) do
    if recursive do
      # Recursive: include all subdirectories
      Path.join([base_path, "**", pattern])
    else
      # Non-recursive: only immediate directory
      Path.join(base_path, pattern)
    end
  end

  defp valid_file?(file_path, include_hidden) do
    basename = Path.basename(file_path)

    # Check if hidden
    if not include_hidden and String.starts_with?(basename, ".") do
      false
    else
      # Regular file or directory
      File.exists?(file_path)
    end
  end

  defp file_type(%File.Stat{type: :directory}), do: :directory
  defp file_type(%File.Stat{type: :regular}), do: :file
  defp file_type(_), do: :other

  defp count_directories(files) do
    Enum.count(files, &(&1.type == :directory))
  end

  defp count_files(files) do
    Enum.count(files, &(&1.type == :file))
  end
end
