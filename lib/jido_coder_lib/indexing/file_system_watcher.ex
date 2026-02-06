defmodule JidoCoderLib.Indexing.FileSystemWatcher do
  @moduledoc """
  File system watcher for automatic code indexing.

  This GenServer monitors specified directories for changes to Elixir source
  files (`.ex` and `.exs`) and triggers reindexing via the CodeIndexer.

  ## Architecture

  The watcher uses a polling-based approach to check for file modifications:
  - Polls watched directories at a configurable interval
  - Tracks file modification times to detect changes
  - Debounces rapid changes to avoid excessive reindexing
  - Filters files by extension (`.ex`, `.exs`)

  ## State

  * `:watched_dirs` - Map of directory paths to their last poll time
  * `:file_mtimes` - Map of file paths to their last modification times
  * `:debounce_timer` - Reference to the debounce timer
  * `:pending_files` - Set of files pending reindexing
  * `:indexer_name` - Name of the CodeIndexer GenServer
  * `:poll_interval` - Interval between polls (default: 1000ms)
  * `:debounce_ms` - Debounce delay for batch processing (default: 100ms)

  ## Client API

  * `start_link/1` - Starts the file system watcher
  * `watch_directory/2` - Add a directory to watch
  * `unwatch_directory/2` - Remove a directory from watch list
  * `watched_directories/1` - List currently watched directories

  ## Examples

      # Start the watcher
      {:ok, watcher} = FileSystemWatcher.start_link()

      # Watch a directory
      :ok = FileSystemWatcher.watch_directory("lib/my_app")

      # Watch multiple directories
      :ok = FileSystemWatcher.watch_directory("test/my_app")

      # List watched directories
      {:ok, dirs} = FileSystemWatcher.watched_directories()

  """

  use GenServer
  require Logger

  @type watch_state :: %{
          watched_dirs: MapSet.t(Path.t()),
          file_mtimes: %{Path.t() => integer()},
          debounce_timer: reference() | nil,
          pending_files: MapSet.t(Path.t()),
          indexer_name: atom(),
          poll_interval: pos_integer(),
          debounce_ms: pos_integer()
        }

  # Default intervals
  @default_poll_interval 1000
  @default_debounce_ms 100

  # File extensions to watch
  @watched_extensions [".ex", ".exs"]

  # Directories to ignore by default
  @ignored_dirs [
    "_build",
    "deps",
    ".git",
    "cover",
    "doc",
    "node_modules"
  ]

  # ========================================================================
  # Client API
  # ========================================================================

  @doc """
  Starts the FileSystemWatcher GenServer.

  ## Options

  * `:name` - The name of the GenServer (default: `__MODULE__`)
  * `:indexer_name` - The name of the CodeIndexer GenServer (default: `JidoCoderLib.Indexing.CodeIndexer`)
  * `:poll_interval` - Interval between polls in milliseconds (default: 1000)
  * `:debounce_ms` - Debounce delay for batch processing in milliseconds (default: 100)

  ## Examples

      {:ok, watcher} = FileSystemWatcher.start_link()

      {:ok, watcher} = FileSystemWatcher.start_link(
        name: MyWatcher,
        poll_interval: 500
      )

  """
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])

    GenServer.start_link(
      __MODULE__,
      init_opts,
      gen_opts
    )
  end

  @doc """
  Adds a directory to the watch list.

  The watcher will monitor all `.ex` and `.exs` files in the directory
  and its subdirectories.

  ## Parameters

  * `directory` - Path to the directory to watch
  * `opts` - Keyword list of options

  ## Options

  * `:name` - The name of the watcher GenServer (default: `__MODULE__`)

  ## Examples

      :ok = FileSystemWatcher.watch_directory("lib/my_app")

  """
  @spec watch_directory(Path.t(), keyword()) :: :ok
  def watch_directory(directory, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:watch_directory, Path.expand(directory)})
  end

  @doc """
  Removes a directory from the watch list.

  ## Parameters

  * `directory` - Path to the directory to stop watching
  * `opts` - Keyword list of options

  ## Options

  * `:name` - The name of the watcher GenServer (default: `__MODULE__`)

  ## Examples

      :ok = FileSystemWatcher.unwatch_directory("lib/my_app")

  """
  @spec unwatch_directory(Path.t(), keyword()) :: :ok
  def unwatch_directory(directory, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:unwatch_directory, Path.expand(directory)})
  end

  @doc """
  Returns the list of currently watched directories.

  ## Parameters

  * `opts` - Keyword list of options

  ## Options

  * `:name` - The name of the watcher GenServer (default: `__MODULE__`)

  ## Examples

      {:ok, dirs} = FileSystemWatcher.watched_directories()

  """
  @spec watched_directories(keyword()) :: {:ok, [Path.t()]}
  def watched_directories(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, :watched_directories)
  end

  @doc """
  Returns the current watch state including file modification times.

  ## Parameters

  * `opts` - Keyword list of options

  ## Options

  * `:name` - The name of the watcher GenServer (default: `__MODULE__`)

  ## Examples

      {:ok, state} = FileSystemWatcher.get_state()

  """
  @spec get_state(keyword()) :: {:ok, map()}
  def get_state(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, :get_state)
  end

  # ========================================================================
  # Server Callbacks
  # ========================================================================

  @impl true
  def init(opts) do
    indexer_name = Keyword.get(opts, :indexer_name, JidoCoderLib.Indexing.CodeIndexer)
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
    debounce_ms = Keyword.get(opts, :debounce_ms, @default_debounce_ms)

    # Start the poll timer
    ref = schedule_poll(poll_interval)

    state = %{
      watched_dirs: MapSet.new(),
      file_mtimes: %{},
      debounce_timer: nil,
      pending_files: MapSet.new(),
      indexer_name: indexer_name,
      poll_interval: poll_interval,
      debounce_ms: debounce_ms,
      poll_timer: ref
    }

    Logger.info(
      "FileSystemWatcher started (poll_interval: #{poll_interval}ms, debounce: #{debounce_ms}ms)"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:watch_directory, directory}, _from, state) do
    if File.dir?(directory) do
      # Scan directory and populate initial mtimes
      new_mtimes = scan_directory(directory)

      new_state = %{
        state
        | watched_dirs: MapSet.put(state.watched_dirs, directory),
          file_mtimes: Map.merge(state.file_mtimes, new_mtimes)
      }

      Logger.info("Watching directory: #{directory} (#{map_size(new_mtimes)} files)")

      {:reply, :ok, new_state}
    else
      Logger.warning("Cannot watch non-existent directory: #{directory}")
      {:reply, {:error, :enoent}, state}
    end
  end

  @impl true
  def handle_call({:unwatch_directory, directory}, _from, state) do
    # Remove directory from watch list
    new_watched = MapSet.delete(state.watched_dirs, directory)

    # Remove mtimes for files in this directory
    new_mtimes =
      Enum.reject(state.file_mtimes, fn {path, _mtime} ->
        String.starts_with?(path, directory <> "/")
      end)
      |> Map.new()

    new_state = %{state | watched_dirs: new_watched, file_mtimes: new_mtimes}

    Logger.info("Stopped watching: #{directory}")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:watched_directories, _from, state) do
    {:reply, {:ok, MapSet.to_list(state.watched_dirs)}, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    summary = %{
      watched_directories: MapSet.to_list(state.watched_dirs),
      tracked_files: map_size(state.file_mtimes),
      pending_files: MapSet.to_list(state.pending_files),
      poll_interval: state.poll_interval,
      debounce_ms: state.debounce_ms
    }

    {:reply, {:ok, summary}, state}
  end

  @impl true
  def handle_info(:poll, state) do
    # Reschedule the poll
    _ref = schedule_poll(state.poll_interval)

    # Check all watched directories for changes
    {changed_files, new_mtimes} =
      Enum.map(state.watched_dirs, fn dir -> scan_directory(dir) end)
      |> Enum.reduce(
        {[], %{}},
        fn mtimes, {changed, all_mtimes} ->
          {new_changed, new_all} = find_changed(mtimes, state.file_mtimes)
          {changed ++ new_changed, Map.merge(all_mtimes, new_all)}
        end
      )

    new_state = %{state | file_mtimes: Map.merge(state.file_mtimes, new_mtimes)}

    # If there are changed files, add to pending and schedule debounce
    if Enum.empty?(changed_files) do
      {:noreply, new_state}
    else
      Logger.debug("Detected #{length(changed_files)} changed file(s)")
      handle_changed_files(changed_files, new_state)
    end
  end

  @impl true
  def handle_info(:process_pending, state) do
    # Process all pending files
    pending_list = MapSet.to_list(state.pending_files)

    new_state = %{state | pending_files: MapSet.new(), debounce_timer: nil}

    if Enum.empty?(pending_list) do
      {:noreply, new_state}
    else
      Logger.info("Reindexing #{length(pending_list)} changed file(s)")
      process_files(pending_list, new_state)
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in FileSystemWatcher: #{inspect(msg)}")
    {:noreply, state}
  end

  # ========================================================================
  # Private Helpers
  # ========================================================================

  # Schedule the next poll
  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  # Scan a directory for all .ex and .exs files
  defp scan_directory(directory) do
    scan_directory(directory, %{})
  end

  defp scan_directory(directory, acc) do
    case File.ls(directory) do
      {:ok, entries} ->
        Enum.reduce(entries, acc, fn entry, inner_acc ->
          full_path = Path.join(directory, entry)

          cond do
            # Skip ignored directories
            File.dir?(full_path) and should_ignore_dir?(entry) ->
              inner_acc

            # Recurse into subdirectories
            File.dir?(full_path) ->
              scan_directory(full_path, inner_acc)

            # Track .ex and .exs files
            should_watch_file?(full_path) ->
              case File.stat(full_path) do
                {:ok, stat} ->
                  Map.put(inner_acc, full_path, stat.mtime)

                _ ->
                  inner_acc
              end

            # Skip other files
            true ->
              inner_acc
          end
        end)

      _ ->
        acc
    end
  end

  # Check if a directory should be ignored
  defp should_ignore_dir?(name) do
    Enum.member?(@ignored_dirs, name) or String.starts_with?(name, ".")
  end

  # Check if a file should be watched based on extension
  defp should_watch_file?(path) do
    ext = Path.extname(path)
    Enum.member?(@watched_extensions, ext)
  end

  # Find files that have changed since last scan
  defp find_changed(new_mtimes, old_mtimes) do
    Enum.reduce(new_mtimes, {[], %{}}, fn {path, new_mtime}, {changed, all_mtimes} ->
      case Map.get(old_mtimes, path) do
        nil ->
          # New file
          {[path | changed], Map.put(all_mtimes, path, new_mtime)}

        old_mtime when old_mtime != new_mtime ->
          # Modified file
          {[path | changed], Map.put(all_mtimes, path, new_mtime)}

        _ ->
          # Unchanged
          {changed, Map.put(all_mtimes, path, new_mtime)}
      end
    end)
  end

  # Handle changed files - add to pending and schedule debounce
  defp handle_changed_files(changed_files, state) do
    new_pending =
      Enum.reduce(changed_files, state.pending_files, fn path, acc ->
        MapSet.put(acc, path)
      end)

    # Cancel existing timer if any
    new_state =
      if state.debounce_timer do
        Process.cancel_timer(state.debounce_timer)
        %{state | debounce_timer: nil}
      else
        state
      end

    # Schedule debounce processing
    ref = schedule_debounce(new_state.debounce_ms)

    {:noreply, %{new_state | pending_files: new_pending, debounce_timer: ref}}
  end

  # Schedule the debounce timer
  defp schedule_debounce(debounce_ms) do
    Process.send_after(self(), :process_pending, debounce_ms)
  end

  # Process changed files by triggering reindexing
  defp process_files(files, state) do
    indexer = state.indexer_name

    results =
      Enum.map(files, fn file ->
        # Call CodeIndexer.reindex_file for each changed file
        try do
          case GenServer.call(indexer, {:reindex_file, file, []}) do
            {:ok, _info} ->
              Logger.debug("Reindexed: #{file}")
              {:ok, file}

            {:error, reason} ->
              Logger.warning("Failed to reindex #{file}: #{inspect(reason)}")
              {:error, file, reason}

            :ok ->
              {:ok, file}
          end
        rescue
          error ->
            Logger.error("Error reindexing #{file}: #{inspect(error)}")
            {:error, file, error}
        end
      end)

    # Emit telemetry
    successful =
      Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    failed = length(results) - successful

    :telemetry.execute(
      [:jido_coder_lib, :file_system_watcher, :batch_complete],
      %{files_count: length(files), successful: successful, failed: failed},
      %{watcher: __MODULE__}
    )

    {:noreply, state}
  end
end
