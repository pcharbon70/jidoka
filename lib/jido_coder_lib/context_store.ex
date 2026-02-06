defmodule JidoCoderLib.ContextStore do
  @moduledoc """
  GenServer that owns and manages ETS tables for high-performance shared state.

  This GenServer creates and owns three ETS tables:
  1. `:file_content` - Cached file contents
  2. `:file_metadata` - File metadata tracking
  3. `:analysis_cache` - Analysis result cache

  ETS tables provide O(1) access time and support concurrent reads without locks.

  ## Session Scoping (Phase 3.5)

  All cache operations support session-scoped data using composite keys.
  Each session can have its own isolated cache for the same file.

  * **Optional session_id:** If not provided, uses `:global` for shared cache
  * **Composite keys:** `{session_id, file_path}` for file operations
  * **Session isolation:** Data from one session doesn't affect another

  ## Table Definitions

  ### :file_content
  Caches file contents to avoid repeated disk reads.

  * **Type**: set
  * **Key**: `{session_id, file_path}` tuple
  * **Value**: `{content, mtime, size}` tuple
  * **Concurrency**: read_concurrency: true

  ### :file_metadata
  Stores metadata about files (language, line count, etc.).

  * **Type**: set
  * **Key**: `{session_id, file_path}` tuple
  * **Value**: metadata map
  * **Concurrency**: read_concurrency: true

  ### :analysis_cache
  Caches analysis results to avoid redundant computation.

  * **Type**: set
  * **Key**: `{session_id, file_path, analysis_type}` tuple
  * **Value**: `{result, timestamp}` tuple
  * **Concurrency**: read_concurrency: true, write_concurrency: true

  ## Examples

  Cache a file (global scope):

      JidoCoderLib.ContextStore.cache_file("/path/to/file.ex", "content", %{language: :elixir})

  Cache a file for a specific session:

      JidoCoderLib.ContextStore.cache_file("session-123", "/path/to/file.ex", "content", %{language: :elixir})

  Retrieve cached file:

      {:ok, {content, _mtime, _size}} = JidoCoderLib.ContextStore.get_file("session-123", "/path/to/file.ex")

  Cache analysis result:

      JidoCoderLib.ContextStore.cache_analysis("session-123", "/path/to/file.ex", :syntax_tree, ast)

  Retrieve cached analysis:

      {:ok, ast} = JidoCoderLib.ContextStore.get_analysis("session-123", "/path/to/file.ex", :syntax_tree)

  Invalidate file cache for a session:

      JidoCoderLib.ContextStore.invalidate_file("session-123", "/path/to/file.ex")

  Clear all cache for a session:

      JidoCoderLib.ContextStore.clear_session_cache("session-123")

  """

  use GenServer
  @table_names [:file_content, :file_metadata, :analysis_cache]
  @global_session :global

  # Client API

  @doc """
  Starts the ContextStore GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Caches a file's content and metadata.

  ## Parameters

  * `session_id_or_path` - Either a session_id (String/atom) or file path (for backward compatibility)
  * `path_or_content` - Either file path (when session_id provided) or content (for backward compatibility)
  * `content_or_metadata` - Either content (when session_id provided) or metadata (for backward compatibility)
  * `metadata` - Metadata map (optional, defaults to %{})

  ## Supports Multiple Arity

  For session-scoped caching:
      cache_file(session_id, path, content, metadata \\ %{})

  For global caching (backward compatible):
      cache_file(path, content, metadata \\ %{})

  ## Returns

  * `:ok` - Successfully cached

  ## Blocking I/O Notice

  This function performs file I/O operations on the caller's process,
  not in the GenServer. This prevents blocking the GenServer and allows
  concurrent file operations.

  ## Examples

  # Global cache (backward compatible)
  JidoCoderLib.ContextStore.cache_file("/path/to/file.ex", "content")

  # Session-scoped cache
  JidoCoderLib.ContextStore.cache_file("session-123", "/path/to/file.ex", "content")

  # With metadata
  JidoCoderLib.ContextStore.cache_file("session-123", "/path/to/file.ex", "content", %{language: :elixir})

  """
  # 2-arity version: path, content (backward compatible, no metadata)
  @spec cache_file(String.t(), String.t()) :: :ok
  def cache_file(file_path, content) when is_binary(file_path) and is_binary(content) do
    cache_file(@global_session, file_path, content, %{})
  end

  # 3-arity version: path, content, metadata (backward compatible)
  @spec cache_file(String.t(), String.t(), map()) :: :ok
  def cache_file(file_path, content, metadata)
      when is_binary(file_path) and is_binary(content) and is_map(metadata) do
    cache_file(@global_session, file_path, content, metadata)
  end

  # 3-arity version: session_id, path, content (for session-scoped with default metadata)
  @spec cache_file(String.t() | atom(), String.t(), String.t()) :: :ok
  def cache_file(session_id, file_path, content)
      when is_binary(file_path) and is_binary(content) do
    cache_file(session_id, file_path, content, %{})
  end

  # 4-arity version: session_id, path, content, metadata
  @spec cache_file(String.t() | atom(), String.t(), String.t(), map()) :: :ok
  def cache_file(session_id, file_path, content, metadata)
      when is_binary(file_path) and is_binary(content) and is_map(metadata) do
    # Perform file I/O on the caller's process, not in GenServer
    # This prevents blocking the GenServer for disk operations
    mtime = File.stat!(file_path, time: :posix).mtime
    size = byte_size(content)

    GenServer.call(
      __MODULE__,
      {:cache_file, session_id, file_path, content, mtime, size, metadata}
    )
  end

  @doc """
  Retrieves cached file content.

  ## Parameters

  * `session_id_or_path` - Either a session_id (String/atom) or file path (for backward compatibility)
  * `path_or_nil` - File path (when session_id provided) or nil (for backward compatibility)

  ## Supports Multiple Arity

  For session-scoped retrieval:
      get_file(session_id, path)

  For global retrieval (backward compatible):
      get_file(path)

  ## Returns

  * `{:ok, {content, mtime, size}}` - File was found in cache
  * `:error` - File not in cache

  ## Examples

  # Global cache (backward compatible)
  {:ok, {content, mtime, size}} = JidoCoderLib.ContextStore.get_file("/path/to/file.ex")

  # Session-scoped cache
  {:ok, {content, mtime, size}} = JidoCoderLib.ContextStore.get_file("session-123", "/path/to/file.ex")

  """
  @spec get_file(String.t()) :: {:ok, {String.t(), integer(), integer()}} | :error
  def get_file(file_path) when is_binary(file_path) do
    get_file(@global_session, file_path)
  end

  @spec get_file(String.t() | atom(), String.t()) ::
          {:ok, {String.t(), integer(), integer()}} | :error
  def get_file(session_id, file_path) when is_binary(file_path) do
    key = {session_id, file_path}

    case :ets.lookup(:file_content, key) do
      [{^key, content, mtime, size}] -> {:ok, {content, mtime, size}}
      [] -> :error
    end
  end

  @doc """
  Retrieves cached file metadata.

  ## Parameters

  * `session_id_or_path` - Either a session_id (String/atom) or file path (for backward compatibility)
  * `path_or_nil` - File path (when session_id provided) or nil (for backward compatibility)

  ## Supports Multiple Arity

  For session-scoped retrieval:
      get_metadata(session_id, path)

  For global retrieval (backward compatible):
      get_metadata(path)

  ## Returns

  * `{:ok, metadata}` - Metadata found
  * `:error` - Metadata not found

  ## Examples

      {:ok, meta} = JidoCoderLib.ContextStore.get_metadata("session-123", "/path/to/file.ex")

  """
  @spec get_metadata(String.t()) :: {:ok, map()} | :error
  def get_metadata(file_path) when is_binary(file_path) do
    get_metadata(@global_session, file_path)
  end

  @spec get_metadata(String.t() | atom(), String.t()) :: {:ok, map()} | :error
  def get_metadata(session_id, file_path) when is_binary(file_path) do
    key = {session_id, file_path}

    case :ets.lookup(:file_metadata, key) do
      [{^key, metadata}] -> {:ok, metadata}
      [] -> :error
    end
  end

  @doc """
  Caches an analysis result.

  ## Parameters

  * `session_id_or_path` - Either a session_id (String/atom) or file path (for backward compatibility)
  * `path_or_type` - Either file path (when session_id provided) or analysis type (for backward compatibility)
  * `type_or_result` - Either analysis type (when session_id provided) or result (for backward compatibility)
  * `result_or_nil` - Analysis result to cache (when session_id provided) or nil (for backward compatibility)

  ## Supports Multiple Arity

  For session-scoped caching:
      cache_analysis(session_id, path, type, result)

  For global caching (backward compatible):
      cache_analysis(path, type, result)

  ## Returns

  * `:ok` - Successfully cached

  ## Examples

      # Global cache (backward compatible)
      JidoCoderLib.ContextStore.cache_analysis("/path/to/file.ex", :syntax_tree, ast)

      # Session-scoped cache
      JidoCoderLib.ContextStore.cache_analysis("session-123", "/path/to/file.ex", :syntax_tree, ast)

  """
  @spec cache_analysis(String.t(), atom(), term()) :: :ok
  def cache_analysis(file_path, analysis_type, result) when is_binary(file_path) do
    cache_analysis(@global_session, file_path, analysis_type, result)
  end

  @spec cache_analysis(String.t() | atom(), String.t(), atom(), term()) :: :ok
  def cache_analysis(session_id, file_path, analysis_type, result) when is_binary(file_path) do
    GenServer.call(__MODULE__, {:cache_analysis, session_id, file_path, analysis_type, result})
  end

  @doc """
  Retrieves a cached analysis result.

  ## Parameters

  * `session_id_or_path` - Either a session_id (String/atom) or file path (for backward compatibility)
  * `path_or_type` - Either file path (when session_id provided) or analysis type (for backward compatibility)
  * `type_or_nil` - Analysis type (when session_id provided) or nil (for backward compatibility)

  ## Supports Multiple Arity

  For session-scoped retrieval:
      get_analysis(session_id, path, type)

  For global retrieval (backward compatible):
      get_analysis(path, type)

  ## Returns

  * `{:ok, result}` - Analysis found in cache
  * `:error` - Analysis not found

  ## Examples

      # Global cache (backward compatible)
      {:ok, ast} = JidoCoderLib.ContextStore.get_analysis("/path/to/file.ex", :syntax_tree)

      # Session-scoped cache
      {:ok, ast} = JidoCoderLib.ContextStore.get_analysis("session-123", "/path/to/file.ex", :syntax_tree)

  """
  @spec get_analysis(String.t(), atom()) :: {:ok, term()} | :error
  def get_analysis(file_path, analysis_type) when is_binary(file_path) do
    get_analysis(@global_session, file_path, analysis_type)
  end

  @spec get_analysis(String.t() | atom(), String.t(), atom()) :: {:ok, term()} | :error
  def get_analysis(session_id, file_path, analysis_type) when is_binary(file_path) do
    key = {session_id, file_path, analysis_type}

    case :ets.lookup(:analysis_cache, key) do
      [{^key, result, _timestamp}] -> {:ok, result}
      [] -> :error
    end
  end

  @doc """
  Retrieves a cached analysis result with timestamp.

  ## Parameters

  * `session_id_or_path` - Either a session_id (String/atom) or file path (for backward compatibility)
  * `path_or_type` - Either file path (when session_id provided) or analysis type (for backward compatibility)
  * `type_or_nil` - Analysis type (when session_id provided) or nil (for backward compatibility)

  ## Supports Multiple Arity

  For session-scoped retrieval:
      get_analysis_with_timestamp(session_id, path, type)

  For global retrieval (backward compatible):
      get_analysis_with_timestamp(path, type)

  ## Returns

  * `{:ok, result, timestamp}` - Analysis found in cache
  * `:error` - Analysis not found

  ## Examples

      # Global cache (backward compatible)
      {:ok, ast, timestamp} = JidoCoderLib.ContextStore.get_analysis_with_timestamp("/path/to/file.ex", :syntax_tree)

      # Session-scoped cache
      {:ok, ast, timestamp} = JidoCoderLib.ContextStore.get_analysis_with_timestamp("session-123", "/path/to/file.ex", :syntax_tree)

  """
  @spec get_analysis_with_timestamp(String.t(), atom()) :: {:ok, term(), integer()} | :error
  def get_analysis_with_timestamp(file_path, analysis_type) when is_binary(file_path) do
    get_analysis_with_timestamp(@global_session, file_path, analysis_type)
  end

  @spec get_analysis_with_timestamp(String.t() | atom(), String.t(), atom()) ::
          {:ok, term(), integer()} | :error
  def get_analysis_with_timestamp(session_id, file_path, analysis_type)
      when is_binary(file_path) do
    key = {session_id, file_path, analysis_type}

    case :ets.lookup(:analysis_cache, key) do
      [{^key, result, timestamp}] -> {:ok, result, timestamp}
      [] -> :error
    end
  end

  @doc """
  Invalidates all cached data for a file.

  Removes the file from all tables for a specific session, or from global cache if no session specified.

  ## Parameters

  * `session_id_or_path` - Either a session_id (String/atom) or file path (for backward compatibility)
  * `path_or_nil` - File path (when session_id provided) or nil (for backward compatibility)

  ## Supports Multiple Arity

  For session-scoped invalidation:
      invalidate_file(session_id, path)

  For global invalidation (backward compatible):
      invalidate_file(path)

  ## Returns

  * `:ok` - Successfully invalidated

  ## Examples

      # Global cache (backward compatible)
      JidoCoderLib.ContextStore.invalidate_file("/path/to/file.ex")

      # Session-scoped
      JidoCoderLib.ContextStore.invalidate_file("session-123", "/path/to/file.ex")

  """
  @spec invalidate_file(String.t()) :: :ok
  def invalidate_file(file_path) when is_binary(file_path) do
    invalidate_file(@global_session, file_path)
  end

  @spec invalidate_file(String.t() | atom(), String.t()) :: :ok
  def invalidate_file(session_id, file_path) when is_binary(file_path) do
    GenServer.call(__MODULE__, {:invalidate_file, session_id, file_path})
  end

  @doc """
  Clears all caches for a specific session.

  Removes all entries (file content, metadata, and analysis) for a given session.

  ## Parameters

  * `session_id` - The session ID to clear cache for

  ## Returns

  * `:ok` - Successfully cleared

  ## Examples

      JidoCoderLib.ContextStore.clear_session_cache("session-123")

  """
  @spec clear_session_cache(String.t() | atom()) :: :ok
  def clear_session_cache(session_id) do
    GenServer.call(__MODULE__, {:clear_session_cache, session_id})
  end

  @doc """
  Clears all caches.

  Removes all entries from all tables.

  ## Returns

  * `:ok` - Successfully cleared

  ## Examples

      JidoCoderLib.ContextStore.clear_all()

  """
  @spec clear_all() :: :ok
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  @doc """
  Gets cache statistics.

  Returns counts for each table.

  ## Returns

  * Map with table sizes

  ## Examples

      %{
        file_content: 10,
        file_metadata: 10,
        analysis_cache: 25
      } = JidoCoderLib.ContextStore.stats()

  """
  @spec stats() :: %{
          file_content: non_neg_integer(),
          file_metadata: non_neg_integer(),
          analysis_cache: non_neg_integer()
        }
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Returns the list of table names managed by ContextStore.

  ## Examples

      [:file_content, :file_metadata, :analysis_cache] = JidoCoderLib.ContextStore.table_names()

  """
  @spec table_names() :: [atom()]
  def table_names, do: @table_names

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables owned by this GenServer
    # When the GenServer dies, tables are automatically cleaned up
    # :protected access means only owner (this GenServer) can write,
    # all processes can read - provides O(1) reads with write control

    _ =
      :ets.new(:file_content, [
        :set,
        :protected,
        :named_table,
        read_concurrency: true
      ])

    _ =
      :ets.new(:file_metadata, [
        :set,
        :protected,
        :named_table,
        read_concurrency: true
      ])

    _ =
      :ets.new(:analysis_cache, [
        :set,
        :protected,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{}}
  end

  @impl true
  def handle_call(
        {:cache_file, session_id, file_path, content, mtime, size, metadata},
        _from,
        state
      ) do
    # Cache content with composite key (session_id, file_path)
    content_key = {session_id, file_path}
    :ets.insert(:file_content, {content_key, content, mtime, size})

    # Cache metadata with composite key
    full_metadata =
      metadata
      |> Map.new()
      |> Map.put(:mtime, mtime)
      |> Map.put(:size, size)

    metadata_key = {session_id, file_path}
    :ets.insert(:file_metadata, {metadata_key, full_metadata})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:invalidate_file, session_id, file_path}, _from, state) do
    # Remove from file_content table with composite key
    content_key = {session_id, file_path}
    :ets.delete(:file_content, content_key)

    # Remove from file_metadata table with composite key
    metadata_key = {session_id, file_path}
    :ets.delete(:file_metadata, metadata_key)

    # Remove all analysis cache entries for this session and file
    # Since the key is {session_id, file_path, analysis_type}, we iterate and delete
    :ets.tab2list(:analysis_cache)
    |> Enum.each(fn
      {{^session_id, ^file_path, _analysis_type}, _result, _timestamp} = entry ->
        :ets.delete_object(:analysis_cache, entry)

      _else ->
        :ok
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:cache_analysis, session_id, file_path, analysis_type, result}, _from, state) do
    timestamp = System.monotonic_time(:millisecond)
    analysis_key = {session_id, file_path, analysis_type}
    :ets.insert(:analysis_cache, {analysis_key, result, timestamp})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:clear_session_cache, session_id}, _from, state) do
    # Remove all entries for this session from file_content
    :ets.tab2list(:file_content)
    |> Enum.each(fn
      {{^session_id, _file_path}, _content, _mtime, _size} = entry ->
        :ets.delete_object(:file_content, entry)

      _else ->
        :ok
    end)

    # Remove all entries for this session from file_metadata
    :ets.tab2list(:file_metadata)
    |> Enum.each(fn
      {{^session_id, _file_path}, _metadata} = entry ->
        :ets.delete_object(:file_metadata, entry)

      _else ->
        :ok
    end)

    # Remove all entries for this session from analysis_cache
    :ets.tab2list(:analysis_cache)
    |> Enum.each(fn
      {{^session_id, _file_path, _analysis_type}, _result, _timestamp} = entry ->
        :ets.delete_object(:analysis_cache, entry)

      _else ->
        :ok
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:clear_all, _from, state) do
    # Clear all tables
    :ets.delete_all_objects(:file_content)
    :ets.delete_all_objects(:file_metadata)
    :ets.delete_all_objects(:analysis_cache)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      file_content: :ets.info(:file_content, :size),
      file_metadata: :ets.info(:file_metadata, :size),
      analysis_cache: :ets.info(:analysis_cache, :size)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
