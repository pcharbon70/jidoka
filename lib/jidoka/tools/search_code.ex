defmodule Jidoka.Tools.SearchCode do
  @moduledoc """
  Jido Action for searching code patterns across the codebase.

  This tool allows the LLM to search for text patterns in source files,
  similar to grep. Supports file pattern filtering and case-insensitive search.

  ## Parameters

  * `:pattern` - Search pattern (required, supports regex)
  * `:file_pattern` - Glob pattern for files to search (optional, default: "*.ex")
  * `:case_sensitive` - Whether search is case-sensitive (optional, default: false)
  * `:max_results` - Maximum number of results (optional, default: 50)

  ## Examples

      {:ok, results} = SearchCode.run(
        %{pattern: "defmodule", file_pattern: "*.ex"},
        %{}
      )

      {:ok, results} = SearchCode.run(
        %{pattern: "TODO:", file_pattern: "*.ex", case_sensitive: false},
        %{}
      )

  ## Security

  Search operations are restricted to the project root directory.
  """

  use Jido.Action,
    name: "search_code",
    description: "Search for text patterns in source files",
    category: "search",
    tags: ["search", "grep", "codebase"],
    vsn: "1.0.0",
    schema: [
      pattern: [
        type: :string,
        required: true,
        doc: "Search pattern (supports regex)"
      ],
      file_pattern: [
        type: :string,
        required: false,
        default: "*.ex",
        doc: "Glob pattern for files to search"
      ],
      case_sensitive: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Whether search is case-sensitive"
      ],
      max_results: [
        type: :integer,
        required: false,
        default: 50,
        doc: "Maximum number of results to return"
      ]
    ]

  @impl true
  def run(params, _context) do
    pattern = params[:pattern]
    file_pattern = params[:file_pattern] || "*.ex"
    case_sensitive = params[:case_sensitive] || false
    max_results = params[:max_results] || 50

    project_root = File.cwd!()

    with :ok <- validate_pattern(pattern),
         {:ok, regex} <- compile_regex(pattern, case_sensitive),
         {:ok, files} <- find_matching_files(project_root, file_pattern) do
      results = search_files(files, regex, max_results)

      metadata = %{
        pattern: pattern,
        file_pattern: file_pattern,
        case_sensitive: case_sensitive,
        files_searched: length(files),
        matches_found: length(results),
        truncated: length(results) >= max_results
      }

      {:ok, %{results: results, metadata: metadata}, []}
    else
      {:error, :invalid_pattern} = error ->
        error

      {:error, :invalid_regex} = error ->
        error

      {:error, reason} ->
        {:error, "Search failed: #{inspect(reason)}"}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp validate_pattern(pattern) when is_binary(pattern) do
    if String.trim(pattern) == "" do
      {:error, :invalid_pattern}
    else
      :ok
    end
  end

  defp validate_pattern(_), do: {:error, :invalid_pattern}

  defp compile_regex(pattern, case_sensitive) do
    opts = if case_sensitive, do: [], else: [:caseless]

    try do
      {:ok, Regex.compile!(pattern, opts)}
    rescue
      _ -> {:error, :invalid_regex}
    end
  end

  defp find_matching_files(project_root, file_pattern) do
    # Convert glob pattern to regex
    regex_pattern = glob_to_regex(file_pattern)

    # Walk directory and find matching files
    files =
      Path.wildcard(Path.join([project_root, "**", "*"]))
      |> Enum.filter(fn path ->
        File.regular?(path) and
          String.starts_with?(Path.expand(path), project_root) and
          Regex.match?(regex_pattern, Path.basename(path))
      end)

    {:ok, files}
  end

  defp glob_to_regex(glob) do
    # Simple glob to regex conversion
    regex =
      glob
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")
      |> String.replace("?", ".")

    Regex.compile!("^#{regex}$", [:caseless])
  end

  defp search_files(files, regex, max_results) do
    project_root = File.cwd!()

    files
    |> Enum.reduce({[], 0}, fn file, {acc, count} ->
      if count >= max_results do
        {acc, count}
      else
        case search_single_file(file, regex, project_root) do
          [] -> {acc, count}
          matches -> {acc ++ matches, count + length(matches)}
        end
      end
    end)
    |> elem(0)
    |> Enum.take(max_results)
  end

  defp search_single_file(file_path, regex, project_root) do
    case File.read(file_path) do
      {:ok, content} ->
        relative_path = Path.relative_to(file_path, project_root)

        content
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _index} -> Regex.match?(regex, line) end)
        |> Enum.map(fn {line, index} ->
          %{
            file_path: relative_path,
            line_number: index,
            line_content: String.trim(line)
          }
        end)

      {:error, _} ->
        []
    end
  end
end
