defmodule Jidoka.Session.State do
  @moduledoc """
  Struct and functions for managing session state.

  This module defines the data structures that hold session-specific
  state and configuration, including validation, state transitions,
  and serialization.

  ## Session Status

  Sessions can be in one of the following states:

  | Status | Description |
  |--------|-------------|
  | `:initializing` | Session is being created, SessionSupervisor starting |
  | `:active` | Session is ready and processing |
  | `:idle` | Session is active but no current activity |
  | `:terminating` | Session is being shut down |
  | `:terminated` | Session has been shut down |

  ## State Transitions

  Valid state transitions:

  ```
  :initializing → :active
  :initializing → :terminated  (startup failure)
  :active → :idle
  :idle → :active
  :active → :terminating
  :idle → :terminating
  :terminating → :terminated
  ```

  ## Examples

  Creating a new session state:

      {:ok, state} = Session.State.new("session-123", %{
        llm_config: %{model: "gpt-4"},
        metadata: %{project: "my-project"}
      })

      state.session_id
      #=> "session-123"

      state.status
      #=> :initializing

  Transitioning state:

      {:ok, updated_state} = Session.State.transition(state, :active)

  Serializing state:

      map = Session.State.serialize(state)
      {:ok, restored} = Session.State.deserialize(map)

  """

  defstruct [
    :session_id,
    :status,
    :config,
    :llm_config,
    :metadata,
    :created_at,
    :updated_at,
    :active_tasks,
    :conversation_count,
    :error
  ]

  # Session status values
  @status [:initializing, :active, :idle, :terminating, :terminated]

  # Valid state transitions
  @valid_transitions %{
    initializing: [:active, :terminated],
    active: [:idle, :terminating],
    idle: [:active, :terminating],
    terminating: [:terminated],
    # Terminal state
    terminated: []
  }

  @type t :: %__MODULE__{
          session_id: String.t(),
          status: atom(),
          config: Config.t() | nil,
          llm_config: map() | nil,
          metadata: map() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          active_tasks: [String.t()] | nil,
          conversation_count: non_neg_integer() | nil,
          error: String.t() | nil
        }

  # Config struct
  defmodule Config do
    @moduledoc """
    Session configuration options.

    ## Fields

    * `:max_conversations` - Maximum number of conversations (default: 100)
    * `:timeout_minutes` - Session timeout in minutes (default: 30)
    * `:persistence_enabled` - Whether to persist session (default: false)
    * `:features` - List of enabled features (default: [])

    ## Examples

        config = %Session.State.Config{
          max_conversations: 50,
          timeout_minutes: 60,
          persistence_enabled: true,
          features: [:code_analysis, :file_editing]
        }

    """

    defstruct max_conversations: 100,
              timeout_minutes: 30,
              persistence_enabled: false,
              features: []

    @type t :: %__MODULE__{
            max_conversations: non_neg_integer(),
            timeout_minutes: pos_integer(),
            persistence_enabled: boolean(),
            features: [atom()]
          }
  end

  # Public API

  @doc """
  Creates a new session state.

  ## Parameters

  * `session_id` - Unique session identifier
  * `opts` - Optional keyword list
    * `:config` - Session configuration struct
    * `:llm_config` - LLM configuration map
    * `:metadata` - User metadata map

  ## Returns

  * `{:ok, state}` - Valid state created
  * `{:error, reason}` - Validation failed

  ## Examples

      {:ok, state} = Session.State.new("session-123")

      {:ok, state} = Session.State.new("session-123",
        config: %Session.State.Config{max_conversations: 50},
        llm_config: %{model: "gpt-4"},
        metadata: %{project: "my-project"}
      )

  """
  def new(session_id, opts \\ []) do
    config = Keyword.get(opts, :config)
    llm_config = Keyword.get(opts, :llm_config, %{})
    metadata = Keyword.get(opts, :metadata, %{})

    now = DateTime.utc_now()

    state = %__MODULE__{
      session_id: session_id,
      status: :initializing,
      config: config || struct(Config),
      llm_config: llm_config,
      metadata: metadata,
      created_at: now,
      updated_at: now,
      active_tasks: [],
      conversation_count: 0
    }

    case validate(state) do
      :ok -> {:ok, state}
      error -> error
    end
  end

  @doc """
  Transitions a session to a new status.

  ## Parameters

  * `state` - Current session state
  * `new_status` - Target status

  ## Returns

  * `{:ok, updated_state}` - Valid transition
  * `{:error, :invalid_transition}` - Invalid transition

  ## Examples

      {:ok, state} = Session.State.new("session-123")
      {:ok, active_state} = Session.State.transition(state, :active)

      {:error, :invalid_transition} = Session.State.transition(active_state, :terminated)

  """
  def transition(%__MODULE__{status: current_status} = state, new_status)
      when is_atom(new_status) do
    if valid_transition?(current_status, new_status) do
      updated = %{state | status: new_status, updated_at: DateTime.utc_now()}
      {:ok, updated}
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Updates a session state with the given changes.

  ## Parameters

  * `state` - Current session state
  * `changes` - Map of fields to update

  ## Returns

  * `{:ok, updated_state}` - Valid update
  * `{:error, reason}` - Validation failed

  ## Examples

      {:ok, state} = Session.State.new("session-123")
      {:ok, updated} = Session.State.update(state, %{conversation_count: 5})

  """
  def update(%__MODULE__{} = state, changes) when is_map(changes) do
    updated = struct(state, changes)

    # Always update updated_at on changes
    updated = %{updated | updated_at: DateTime.utc_now()}

    case validate(updated) do
      :ok -> {:ok, updated}
      error -> error
    end
  end

  @doc """
  Validates a session state.

  ## Parameters

  * `state` - Session state to validate

  ## Returns

  * `:ok` - State is valid
  * `{:error, reason}` - State is invalid

  ## Examples

      :ok = Session.State.valid?(state)

  """
  def valid?(%__MODULE__{} = state) do
    with :ok <- validate_session_id(state),
         :ok <- validate_status(state),
         :ok <- validate_timestamps(state),
         :ok <- validate_counts(state) do
      :ok
    end
  end

  @doc """
  Serializes a session state to a map.

  ## Parameters

  * `state` - Session state to serialize

  ## Returns

  * Map representation suitable for storage/transport

  ## Examples

      map = Session.State.serialize(state)
      map.session_id
      #=> "session-123"

  """
  def serialize(%__MODULE__{} = state) do
    %{
      "session_id" => state.session_id,
      "status" => Atom.to_string(state.status),
      "config" => serialize_config(state.config),
      "llm_config" => state.llm_config,
      "metadata" => state.metadata,
      "created_at" => DateTime.to_iso8601(state.created_at),
      "updated_at" => DateTime.to_iso8601(state.updated_at),
      "active_tasks" => state.active_tasks || [],
      "conversation_count" => state.conversation_count || 0,
      "error" => state.error
    }
  end

  @doc """
  Deserializes a map to a session state.

  ## Parameters

  * `map` - Map to deserialize (from serialize/1)

  ## Returns

  * `{:ok, state}` - Successfully deserialized
  * `{:error, reason}` - Deserialization failed

  ## Examples

      {:ok, state} = Session.State.deserialize(map)

  """
  def deserialize(map) when is_map(map) do
    with {:ok, session_id} <- fetch_string(map, "session_id"),
         {:ok, status} <- fetch_status(map["status"]),
         {:ok, created_at} <- parse_datetime(map["created_at"]),
         {:ok, updated_at} <- parse_datetime(map["updated_at"]) do
      state = %__MODULE__{
        session_id: session_id,
        status: status,
        config: deserialize_config(map["config"]),
        llm_config: map["llm_config"] || %{},
        metadata: map["metadata"] || %{},
        created_at: created_at,
        updated_at: updated_at,
        active_tasks: map["active_tasks"] || [],
        conversation_count: map["conversation_count"] || 0,
        error: map["error"]
      }

      case validate(state) do
        :ok -> {:ok, state}
        error -> error
      end
    end
  end

  @doc """
  Checks if a transition between two statuses is valid.

  ## Parameters

  * `from_status` - Current status
  * `to_status` - Target status

  ## Returns

  * `true` - Transition is valid
  * `false` - Transition is invalid

  ## Examples

      true = Session.State.valid_transition?(:initializing, :active)
      false = Session.State.valid_transition?(:active, :initializing)

  """
  def valid_transition?(from_status, to_status)
      when is_atom(from_status) and is_atom(to_status) do
    case Map.get(@valid_transitions, from_status, []) do
      [] -> false
      valid -> to_status in valid
    end
  end

  # Private Helpers

  defp validate(%__MODULE__{} = state) do
    with :ok <- validate_session_id(state),
         :ok <- validate_status(state),
         :ok <- validate_timestamps(state),
         :ok <- validate_counts(state) do
      :ok
    end
  end

  defp validate_session_id(%{session_id: ""}), do: {:error, {:empty_field, "session_id"}}
  defp validate_session_id(%{session_id: id}) when is_binary(id), do: :ok
  defp validate_session_id(_), do: {:error, :invalid_session_id}

  defp validate_status(%{status: status}) when status in @status, do: :ok
  defp validate_status(_), do: {:error, :invalid_status}

  defp validate_timestamps(%{created_at: created, updated_at: updated}) do
    if is_struct(created, DateTime) and is_struct(updated, DateTime) do
      :ok
    else
      {:error, :invalid_timestamps}
    end
  end

  defp validate_timestamps(_), do: {:error, :invalid_timestamps}

  defp validate_counts(%{active_tasks: tasks, conversation_count: count}) do
    if (is_list(tasks) or is_nil(tasks)) and (is_integer(count) and count >= 0) do
      :ok
    else
      {:error, :invalid_counts}
    end
  end

  defp validate_counts(_), do: :ok

  defp serialize_config(%Config{} = config) do
    %{
      "max_conversations" => config.max_conversations,
      "timeout_minutes" => config.timeout_minutes,
      "persistence_enabled" => config.persistence_enabled,
      "features" => Enum.map(config.features, &Atom.to_string/1)
    }
  end

  defp serialize_config(_), do: %{}

  defp deserialize_config(nil), do: struct(Config)

  defp deserialize_config(map) when is_map(map),
    do: %Config{
      max_conversations: Map.get(map, "max_conversations", 100),
      timeout_minutes: Map.get(map, "timeout_minutes", 30),
      persistence_enabled: Map.get(map, "persistence_enabled", false),
      features: Map.get(map, "features", []) |> Enum.map(&String.to_existing_atom/1)
    }

  defp fetch_string(map, key) do
    case Map.get(map, key) do
      nil -> {:error, {:missing_field, key}}
      "" -> {:error, {:empty_field, key}}
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, {:invalid_field, key}}
    end
  end

  defp fetch_status(nil), do: {:error, {:missing_field, "status"}}

  defp fetch_status(status) when is_binary(status) do
    case String.to_existing_atom(status) do
      nil -> {:error, :invalid_status}
      atom when atom in @status -> {:ok, atom}
      _ -> {:error, :invalid_status}
    end
  end

  defp parse_datetime(nil), do: {:error, :missing_datetime}

  defp parse_datetime(iso8601) when is_binary(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _} -> {:ok, dt}
      {:error, _} -> {:error, :invalid_datetime_format}
    end
  end
end
