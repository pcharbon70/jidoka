defmodule Jidoka.Tools.ReadFile do
  @moduledoc """
  Jido Action for reading file contents with optional line range support.

  This tool allows the LLM to read file contents from the codebase,
  with support for reading specific line ranges to manage token limits.

  ## Parameters

  * `:file_path` - Relative path to the file (required)
  * `:offset` - Starting line number (optional, default: 1)
  * `:limit` - Maximum number of lines to read (optional, default: all)

  ## Examples

      {:ok, content, metadata} = ReadFile.run(
        %{file_path: "lib/jidoka/client.ex"},
        %{}
      )

      {:ok, excerpt, metadata} = ReadFile.run(
        %{file_path: "lib/jidoka/client.ex", offset: 100, limit: 50},
        %{}
      )

  ## Security

  All file paths are validated through `PathValidator` to prevent
  directory traversal attacks. Only files within the project root
  can be accessed.
  """

  use Jido.Action,
    name: "read_file",
    description: "Read contents of a file from the codebase",
    category: "filesystem",
    tags: ["read", "file", "codebase"],
    vsn: "1.0.0",
    schema: [
      file_path: [
        type: :string,
        required: true,
        doc: "Relative path to the file to read"
      ],
      offset: [
        type: :integer,
        required: false,
        default: 1,
        doc: "Starting line number (1-indexed)"
      ],
      limit: [
        type: :integer,
        required: false,
        default: nil,
        doc: "Maximum number of lines to read (nil for all)"
      ]
    ]

  alias Jidoka.Utils.PathValidator

  @impl true
  def run(params, _context) do
    file_path = params[:file_path]
    offset = params[:offset] || 1
    limit = params[:limit]

    # Get project root for validation
    project_root = File.cwd!()

    # Expand and validate the path
    expanded_path = Path.expand(file_path, project_root)

    with :ok <- validate_path(expanded_path, project_root),
         {:ok, content} <- read_file_content(expanded_path, offset, limit) do
      # Get file metadata
      stat = File.stat!(expanded_path)

      metadata = %{
        file_path: file_path,
        absolute_path: expanded_path,
        size: stat.size,
        line_count: count_lines(content),
        offset: offset,
        truncated: is_truncated?(content, limit)
      }

      {:ok, %{content: content, metadata: metadata}, []}
    else
      {:error, :path_outside_allowed} = error ->
        error

      {:error, :file_not_found} = error ->
        error

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp validate_path(path, project_root) do
    case PathValidator.validate_within(path, project_root) do
      :ok ->
        # Check if file exists
        if File.exists?(path) and File.regular?(path) do
          :ok
        else
          {:error, :file_not_found}
        end

      error ->
        error
    end
  end

  defp read_file_content(path, offset, limit) do
    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")

        # Apply offset (convert 1-indexed to 0-indexed)
        start_index = max(0, offset - 1)

        # Apply limit
        end_index =
          if limit do
            min(length(lines), start_index + limit)
          else
            length(lines)
          end

        if start_index >= length(lines) do
          {:ok, ""}
        else
          selected_lines = Enum.slice(lines, start_index, end_index - start_index)
          {:ok, Enum.join(selected_lines, "\n")}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end

  defp is_truncated?(_content, limit) do
    # If limit is set, the content might be truncated
    # (we'd need original file size to know for sure)
    limit != nil
  end
end
