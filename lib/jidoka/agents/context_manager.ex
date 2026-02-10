defmodule Jidoka.Agents.ContextManager do
  @moduledoc """
  Session-isolated context management agent with STM integration.

  Each session has its own ContextManager that manages:
  - Conversation history via STM ConversationBuffer (messages with role, content, timestamps)
  - Working context via STM WorkingContext (semantic scratchpad)
  - Active files list (files currently in context)
  - File index (metadata about tracked files)
  - Optional LTM integration for context enrichment

  ## Architecture

  The ContextManager is a GenServer that:
  - Starts with a session_id for isolation
  - Registers in AgentRegistry with "context_manager:" <> session_id key
  - Maintains session-isolated state with STM integration
  - Publishes events to session-specific PubSub topics
  - Provides build_context/3 for LLM context assembly
  - Supports optional LTM retrieval for context enrichment

  ## State

  ```elixir
  %{
    session_id: "session-123",
    stm: %ShortTerm{
      conversation_buffer: %ConversationBuffer{...},
      working_context: %WorkingContext{...},
      pending_memories: %PendingMemories{...}
    },
    active_files: [
      %{path: "/path/to/file.ex", added_at: ~U[2025-01-24 10:00:00Z]}
    ],
    file_index: %{
      "/path/to/file.ex" => %{
        language: :elixir,
        line_count: 42,
        last_accessed: ~U[2025-01-24 10:00:00Z]
      }
    },
    max_history: 100,
    max_files: 50,
    stm_enabled: true
  }
  ```

  ## PubSub Events

  The ContextManager broadcasts events to the session topic (via PubSub.session_topic/1):
  - `{:conversation_added, %{session_id: ..., role: ..., content: ...}}`
  - `{:conversation_cleared, %{session_id: ...}}`
  - `{:file_added, %{session_id: ..., file_path: ...}}`
  - `{:file_removed, %{session_id: ..., file_path: ...}}`
  - `{:context_updated, %{session_id: ...}}`
  - `{:working_context_updated, %{session_id: ..., key: ...}}`

  ## Memory Integration

  When STM is enabled, the ContextManager:
  - Stores conversation messages in ConversationBuffer with token budgeting
  - Manages working context in WorkingContext for semantic key-value storage
  - Provides LTM enrichment via Retrieval module

  ## Examples

  Starting a ContextManager (typically done by SessionSupervisor):

      {:ok, pid} = ContextManager.start_link(session_id: "session-123")
      {:ok, pid} = ContextManager.start_link(session_id: "session-123", stm_enabled: false)

  Adding a conversation message:

      :ok = ContextManager.add_message("session-123", :user, "Hello, world!")

  Managing working context:

      :ok = ContextManager.put_working_context("session-123", "current_file", "/path/to/file.ex")
      {:ok, "/path/to/file.ex"} = ContextManager.get_working_context("session-123", "current_file")

  Adding a file to context:

      :ok = ContextManager.add_file("session-123", "/path/to/file.ex")

  Building LLM context with LTM enrichment:

      {:ok, context} = ContextManager.build_context("session-123", [:conversation, :files],
        ltm_enrichment: true,
        ltm_keywords: ["file", "elixir"]
      )

  """

  use GenServer
  require Logger

  alias Jidoka.{PubSub, AgentRegistry, Memory}
  alias Memory.ShortTerm

  @registry_key_prefix "context_manager:"

  # Default limits
  @default_max_history 100
  @default_max_files 50
  @default_max_tokens 4000
  @default_max_context_items 50
  @default_stm_enabled true

  # Client API

  @doc """
  Starts a ContextManager for the given session_id.

  ## Options

  * `:session_id` - Required. Unique session identifier
  * `:max_history` - Maximum conversation history size (default: 100)
  * `:max_files` - Maximum active files (default: 50)
  * `:stm_enabled` - Enable STM integration (default: true)
  * `:max_tokens` - Token budget for conversation (default: 4000)
  * `:max_context_items` - Max working context items (default: 50)

  ## Returns

  * `{:ok, pid}` - ContextManager started successfully
  * `{:error, reason}` - Failed to start

  ## Examples

      {:ok, pid} = ContextManager.start_link(session_id: "session-123")
      {:ok, pid} = ContextManager.start_link(session_id: "session-123", max_history: 200)
      {:ok, pid} = ContextManager.start_link(session_id: "session-123", stm_enabled: false)

  """
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    max_history = Keyword.get(opts, :max_history, @default_max_history)
    max_files = Keyword.get(opts, :max_files, @default_max_files)
    stm_enabled = Keyword.get(opts, :stm_enabled, @default_stm_enabled)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    max_context_items = Keyword.get(opts, :max_context_items, @default_max_context_items)

    GenServer.start_link(
      __MODULE__,
      %{
        session_id: session_id,
        max_history: max_history,
        max_files: max_files,
        stm_enabled: stm_enabled,
        max_tokens: max_tokens,
        max_context_items: max_context_items
      }
    )
  end

  @doc """
  Adds a message to the conversation history.

  ## Parameters

  * `session_id` - The session ID
  * `role` - Message role (:user, :assistant, :system)
  * `content` - Message content (string)

  ## Returns

  * `:ok` - Message added
  * `{:error, reason}` - Failed to add

  ## Examples

      :ok = ContextManager.add_message("session-123", :user, "Hello")
      :ok = ContextManager.add_message("session-123", :assistant, "Hi there!")

  """
  def add_message(session_id, role, content)
      when is_binary(session_id) and is_atom(role) and is_binary(content) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:add_message, role, content})

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Gets the conversation history for a session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, history}` - List of conversation messages
  * `{:error, reason}` - Failed to retrieve

  ## Examples

      {:ok, history} = ContextManager.get_conversation_history("session-123")

  """
  def get_conversation_history(session_id) when is_binary(session_id) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_conversation_history)

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Clears the conversation history for a session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `:ok` - History cleared
  * `{:error, reason}` - Failed to clear

  ## Examples

      :ok = ContextManager.clear_conversation("session-123")

  """
  def clear_conversation(session_id) when is_binary(session_id) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, :clear_conversation)

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Adds a file to the active files list.

  ## Parameters

  * `session_id` - The session ID
  * `file_path` - Path to the file

  ## Returns

  * `:ok` - File added
  * `{:error, reason}` - Failed to add

  ## Examples

      :ok = ContextManager.add_file("session-123", "/path/to/file.ex")

  """
  def add_file(session_id, file_path) when is_binary(session_id) and is_binary(file_path) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:add_file, file_path})

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Removes a file from the active files list.

  ## Parameters

  * `session_id` - The session ID
  * `file_path` - Path to the file

  ## Returns

  * `:ok` - File removed
  * `{:error, reason}` - Failed to remove

  ## Examples

      :ok = ContextManager.remove_file("session-123", "/path/to/file.ex")

  """
  def remove_file(session_id, file_path) when is_binary(session_id) and is_binary(file_path) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:remove_file, file_path})

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Gets the active files list for a session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, files}` - List of active file entries
  * `{:error, reason}` - Failed to retrieve

  ## Examples

      {:ok, files} = ContextManager.get_active_files("session-123")

  """
  def get_active_files(session_id) when is_binary(session_id) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_active_files)

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Updates the file index with metadata.

  ## Parameters

  * `session_id` - The session ID
  * `file_path` - Path to the file
  * `metadata` - Metadata map (language, line_count, etc.)

  ## Returns

  * `:ok` - File index updated
  * `{:error, reason}` - Failed to update

  ## Examples

      :ok = ContextManager.update_file_index("session-123", "/path/to/file.ex", %{
        language: :elixir,
        line_count: 42
      })

  """
  def update_file_index(session_id, file_path, metadata)
      when is_binary(session_id) and is_binary(file_path) and is_map(metadata) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:update_file_index, file_path, metadata})

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Gets the file index for a session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, index}` - File index map
  * `{:error, reason}` - Failed to retrieve

  ## Examples

      {:ok, index} = ContextManager.get_file_index("session-123")

  """
  def get_file_index(session_id) when is_binary(session_id) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_file_index)

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Builds LLM context for a session.

  ## Parameters

  * `session_id` - The session ID
  * `include` - List of context types to include (:conversation, :files, :file_index, :working_context, :codebase)
  * `opts` - Additional options
    * `:max_messages` - Maximum messages to include (default: max_history)
    * `:max_files` - Maximum files to include (default: max_files)
    * `:dependency_depth` - Codebase dependency depth (default: 1)
    * `:max_modules` - Maximum modules from codebase (default: 20)
    * `:engine_name` - Knowledge engine name (default: :knowledge_engine)

  ## Returns

  * `{:ok, context}` - Context map for LLM consumption
  * `{:error, reason}` - Failed to build context

  ## Context Structure

  ```elixir
  %{
    session_id: "session-123",
    conversation: [
      %{role: :user, content: "Hello", timestamp: ...}
    ],
    files: [
      %{path: "/path/to/file.ex", added_at: ...}
    ],
    file_index: %{
      "/path/to/file.ex" => %{language: :elixir, line_count: 42}
    },
    codebase: %{
      modules: [
        %{
          name: "MyApp.User",
          file: "lib/my_app/user.ex",
          public_functions: ["get_user/1", "update_user/2"],
          dependencies: ["MyApp.Repo", "Ecto.Schema"]
        }
      ],
      project_structure: %{
        total_modules: 42,
        indexed_files: 15
      }
    },
    metadata: %{
      conversation_count: 10,
      active_file_count: 3,
      timestamp: ~U[2025-01-24 10:00:00Z]
    }
  }
  ```

  ## Examples

      # Basic context
      {:ok, context} = ContextManager.build_context("session-123", [:conversation, :files], [])

      # Full context including codebase
      {:ok, full_context} = ContextManager.build_context("session-123",
        [:conversation, :files, :file_index, :codebase],
        dependency_depth: 1,
        max_modules: 20
      )

  """
  def build_context(session_id, include, opts \\ [])
      when is_binary(session_id) and is_list(include) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:build_context, include, opts})

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Puts a value in the working context.

  ## Parameters

  * `session_id` - The session ID
  * `key` - Context key (string)
  * `value` - Context value (any term)

  ## Returns

  * `:ok` - Value stored
  * `{:error, reason}` - Failed to store

  ## Examples

      :ok = ContextManager.put_working_context("session-123", "current_file", "/path/to/file.ex")
      :ok = ContextManager.put_working_context("session-123", "language", :elixir)

  """
  def put_working_context(session_id, key, value) when is_binary(session_id) and is_binary(key) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:put_working_context, key, value})

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Gets a value from the working context.

  ## Parameters

  * `session_id` - The session ID
  * `key` - Context key (string)

  ## Returns

  * `{:ok, value}` - Value found
  * `{:error, reason}` - Key not found or error

  ## Examples

      {:ok, file} = ContextManager.get_working_context("session-123", "current_file")

  """
  def get_working_context(session_id, key) when is_binary(session_id) and is_binary(key) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:get_working_context, key})

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Gets all working context keys.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, keys}` - List of context keys
  * `{:error, reason}` - Failed to retrieve

  ## Examples

      {:ok, keys} = ContextManager.working_context_keys("session-123")

  """
  def working_context_keys(session_id) when is_binary(session_id) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, :working_context_keys)

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Deletes a value from the working context.

  ## Parameters

  * `session_id` - The session ID
  * `key` - Context key to delete

  ## Returns

  * `:ok` - Key deleted
  * `{:error, reason}` - Failed to delete

  ## Examples

      :ok = ContextManager.delete_working_context("session-123", "current_file")

  """
  def delete_working_context(session_id, key) when is_binary(session_id) and is_binary(key) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:delete_working_context, key})

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Gets the STM state for the session.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, stm}` - STM struct
  * `{:error, reason}` - STM not available or error

  ## Examples

      {:ok, stm} = ContextManager.get_stm("session-123")

  """
  def get_stm(session_id) when is_binary(session_id) do
    case find_context_manager(session_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_stm)

      {:error, :not_found} ->
        {:error, :context_manager_not_found}
    end
  end

  @doc """
  Finds a ContextManager by session_id.

  ## Parameters

  * `session_id` - The session ID

  ## Returns

  * `{:ok, pid}` - ContextManager found
  * `{:error, :not_found}` - ContextManager not found

  ## Examples

      {:ok, pid} = ContextManager.find_context_manager("session-123")

  """
  def find_context_manager(session_id) when is_binary(session_id) do
    key = registry_key(session_id)

    case Registry.lookup(AgentRegistry, key) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns the registry key for a given session_id.

  """
  def registry_key(session_id) when is_binary(session_id) do
    @registry_key_prefix <> session_id
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_id = Map.fetch!(opts, :session_id)
    max_history = Map.get(opts, :max_history, @default_max_history)
    max_files = Map.get(opts, :max_files, @default_max_files)
    stm_enabled = Map.get(opts, :stm_enabled, @default_stm_enabled)
    max_tokens = Map.get(opts, :max_tokens, @default_max_tokens)
    max_context_items = Map.get(opts, :max_context_items, @default_max_context_items)

    # Register in AgentRegistry
    key = registry_key(session_id)

    # Check if already registered before attempting to register
    case Registry.lookup(AgentRegistry, key) do
      [{_pid, _}] ->
        # Already registered, ignore this process start
        :ignore

      [] ->
        # Not registered, proceed with registration
        case Registry.register(AgentRegistry, key, %{}) do
          {:ok, _} ->
            # Initialize STM if enabled
            stm =
              if stm_enabled do
                ShortTerm.new(session_id,
                  max_messages: max_history,
                  max_tokens: max_tokens,
                  max_context_items: max_context_items
                )
              else
                nil
              end

            state = %{
              session_id: session_id,
              conversation_history: [],
              active_files: [],
              file_index: %{},
              max_history: max_history,
              max_files: max_files,
              stm_enabled: stm_enabled,
              stm: stm,
              max_tokens: max_tokens,
              max_context_items: max_context_items
            }

            Logger.info("ContextManager started for session: #{session_id} (STM: #{stm_enabled})")
            {:ok, state}

          {:error, {:already_registered, _pid}} ->
            :ignore
        end
    end
  end

  @impl true
  def handle_call({:add_message, role, content}, _from, state) do
    message = %{
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }

    # Add to STM if enabled, otherwise use legacy conversation_history
    {updated_state, _evicted} =
      if state.stm_enabled and state.stm do
        case ShortTerm.add_message(state.stm, message) do
          {:ok, stm} ->
            {%{state | stm: stm}, []}

          {:ok, stm, evicted} ->
            {%{state | stm: stm}, evicted}
        end
      else
        # Legacy behavior: use conversation_history list
        updated_history =
          state.conversation_history
          |> Kernel.then(fn history -> history ++ [message] end)
          |> enforce_max_history(state.max_history)

        {%{state | conversation_history: updated_history}, []}
      end

    # Broadcast event
    broadcast_context_event(
      state.session_id,
      {:conversation_added,
       %{
         session_id: state.session_id,
         role: role,
         content: content,
         timestamp: message.timestamp
       }}
    )

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call(:get_conversation_history, _from, state) do
    # Return from STM if enabled, otherwise use legacy conversation_history
    history =
      if state.stm_enabled and state.stm do
        ShortTerm.all_messages(state.stm)
      else
        state.conversation_history
      end

    {:reply, {:ok, history}, state}
  end

  @impl true
  def handle_call(:clear_conversation, _from, state) do
    # Clear STM if enabled, otherwise use legacy conversation_history
    updated_state =
      if state.stm_enabled and state.stm do
        cleared_stm = %{
          state.stm
          | conversation_buffer: state.stm.conversation_buffer.__struct__.new()
        }

        %{state | stm: cleared_stm}
      else
        %{state | conversation_history: []}
      end

    # Broadcast event
    broadcast_context_event(
      state.session_id,
      {:conversation_cleared,
       %{
         session_id: state.session_id
       }}
    )

    {:reply, :ok, updated_state}
  end

  # Working context handlers

  @impl true
  def handle_call({:put_working_context, key, value}, _from, state) do
    if state.stm_enabled and state.stm do
      case ShortTerm.put_context(state.stm, key, value) do
        {:ok, stm} ->
          updated_state = %{state | stm: stm}

          # Broadcast event
          broadcast_context_event(
            state.session_id,
            {:working_context_updated,
             %{
               session_id: state.session_id,
               key: key
             }}
          )

          {:reply, :ok, updated_state}

        {:error, _} = error ->
          {:reply, error, state}
      end
    else
      # STM not enabled, return error
      {:reply, {:error, :stm_not_enabled}, state}
    end
  end

  @impl true
  def handle_call({:get_working_context, key}, _from, state) do
    if state.stm_enabled and state.stm do
      result = ShortTerm.get_context(state.stm, key)
      {:reply, result, state}
    else
      {:reply, {:error, :stm_not_enabled}, state}
    end
  end

  @impl true
  def handle_call(:working_context_keys, _from, state) do
    if state.stm_enabled and state.stm do
      keys = ShortTerm.context_keys(state.stm)
      {:reply, {:ok, keys}, state}
    else
      {:reply, {:error, :stm_not_enabled}, state}
    end
  end

  @impl true
  def handle_call({:delete_working_context, key}, _from, state) do
    if state.stm_enabled and state.stm do
      case ShortTerm.delete_context(state.stm, key) do
        {:ok, stm} ->
          updated_state = %{state | stm: stm}
          {:reply, :ok, updated_state}

        {:error, _} = error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :stm_not_enabled}, state}
    end
  end

  @impl true
  def handle_call(:get_stm, _from, state) do
    if state.stm_enabled and state.stm do
      {:reply, {:ok, state.stm}, state}
    else
      {:reply, {:error, :stm_not_enabled}, state}
    end
  end

  @impl true
  def handle_call({:add_file, file_path}, _from, state) do
    # Check if file already exists
    exists? = Enum.any?(state.active_files, fn f -> f.path == file_path end)

    updated_files =
      if exists? do
        state.active_files
      else
        # Enforce max files limit
        state.active_files
        |> Kernel.then(fn files ->
          files ++ [%{path: file_path, added_at: DateTime.utc_now()}]
        end)
        |> enforce_max_files(state.max_files)
      end

    updated_state = %{state | active_files: updated_files}

    # Broadcast event if actually added
    if not exists? do
      broadcast_context_event(
        state.session_id,
        {:file_added,
         %{
           session_id: state.session_id,
           file_path: file_path
         }}
      )
    end

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:remove_file, file_path}, _from, state) do
    updated_files = Enum.reject(state.active_files, fn f -> f.path == file_path end)

    # Remove from file index as well
    updated_index = Map.delete(state.file_index, file_path)

    updated_state = %{state | active_files: updated_files, file_index: updated_index}

    # Broadcast event if file was removed
    was_removed = length(updated_files) < length(state.active_files)

    if was_removed do
      broadcast_context_event(
        state.session_id,
        {:file_removed,
         %{
           session_id: state.session_id,
           file_path: file_path
         }}
      )
    end

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call(:get_active_files, _from, state) do
    {:reply, {:ok, state.active_files}, state}
  end

  @impl true
  def handle_call({:update_file_index, file_path, metadata}, _from, state) do
    # Merge with existing metadata and add last_accessed timestamp
    existing_metadata = Map.get(state.file_index, file_path, %{})

    updated_metadata =
      existing_metadata |> Map.merge(metadata) |> Map.put(:last_accessed, DateTime.utc_now())

    updated_index = Map.put(state.file_index, file_path, updated_metadata)
    updated_state = %{state | file_index: updated_index}

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call(:get_file_index, _from, state) do
    {:reply, {:ok, state.file_index}, state}
  end

  @impl true
  def handle_call({:build_context, include, opts}, _from, state) do
    max_messages = Keyword.get(opts, :max_messages, state.max_history)
    max_files_to_include = Keyword.get(opts, :max_files, state.max_files)

    # Get conversation count based on STM or legacy
    conversation_count =
      if state.stm_enabled and state.stm do
        ShortTerm.message_count(state.stm)
      else
        length(state.conversation_history)
      end

    context = %{
      session_id: state.session_id,
      metadata: %{
        conversation_count: conversation_count,
        active_file_count: length(state.active_files),
        timestamp: DateTime.utc_now()
      }
    }

    # Add conversation history if requested
    context =
      if :conversation in include do
        conversation =
          if state.stm_enabled and state.stm do
            # Get messages from STM (returns most recent first, reverse for chronological)
            state.stm
            |> ShortTerm.recent_messages(max_messages)
            |> Enum.reverse()
          else
            # Legacy behavior
            state.conversation_history
            |> Enum.take(-max_messages)
          end

        Map.put(context, :conversation, conversation)
      else
        context
      end

    # Add working context if requested (STM only)
    context =
      if :working_context in include do
        working_context =
          if state.stm_enabled and state.stm do
            # Get all working context as a map
            state.stm.working_context.data
          else
            %{}
          end

        Map.put(context, :working_context, working_context)
      else
        context
      end

    # Add active files if requested
    context =
      if :files in include do
        files = Enum.take(state.active_files, -max_files_to_include)
        Map.put(context, :files, files)
      else
        context
      end

    # Add file index if requested
    context =
      if :file_index in include do
        Map.put(context, :file_index, state.file_index)
      else
        context
      end

    # Add codebase context if requested
    context =
      if :codebase in include do
        codebase_context = build_codebase_context(state.active_files, opts)
        Map.put(context, :codebase, codebase_context)
      else
        context
      end

    {:reply, {:ok, context}, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Helpers

  defp enforce_max_history(history, max) do
    if length(history) > max do
      Enum.drop(history, length(history) - max)
    else
      history
    end
  end

  defp enforce_max_files(files, max) do
    if length(files) > max do
      Enum.drop(files, length(files) - max)
    else
      files
    end
  end

  defp broadcast_context_event(session_id, event) do
    topic = PubSub.session_topic(session_id)
    PubSub.broadcast(topic, event)
  end

  # Build codebase context from active files
  defp build_codebase_context(active_files, opts) do
    alias Jidoka.Agents.CodebaseContext

    # Extract file paths from active files
    file_paths =
      Enum.map(active_files, fn
        %{path: path} -> path
        path when is_binary(path) -> path
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    # Get codebase enrichment options
    codebase_opts = [
      dependency_depth: Keyword.get(opts, :dependency_depth, 1),
      max_modules: Keyword.get(opts, :max_modules, 20),
      engine_name: Keyword.get(opts, :engine_name, :knowledge_engine)
    ]

    # Enrich with codebase context
    case CodebaseContext.enrich(file_paths, codebase_opts) do
      {:ok, codebase_data} ->
        codebase_data

      {:error, _reason} ->
        # Return empty codebase context on error
        %{
          modules: [],
          project_structure: %{total_modules: 0, indexed_files: 0},
          metadata: %{
            note: "Codebase context unavailable"
          }
        }
    end
  end
end
