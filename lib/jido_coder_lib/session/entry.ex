defmodule JidoCoderLib.Session.Entry do
  @moduledoc """
  Struct representing an entry in the SessionManager's ETS table.

  Each session in the SessionManager is stored as a SessionEntry in the ETS table.
  This struct provides type safety and documentation for the session entry structure.

  ## Fields

  * `:state` - The Session.State struct for this session
  * `:pid` - The SessionSupervisor PID (or nil if terminated)
  * `:monitor_ref` - The process monitor reference (or nil if not monitoring)
  * `:last_activity` - Timestamp of last activity (for timeout tracking)

  ## Examples

      entry = %Session.Entry{
        state: session_state,
        pid: supervisor_pid,
        monitor_ref: monitor_ref,
        last_activity: DateTime.utc_now()
      }

  Checking if a session entry is active:

      Session.Entry.active?(entry)
      #=> true

  Creating a new entry:

      {:ok, entry} = Session.Entry.new(session_id, supervisor_pid, monitor_ref)

  """

  alias JidoCoderLib.Session.State

  defstruct [:state, :pid, :monitor_ref, :last_activity]

  @type t :: %__MODULE__{
          state: State.t() | nil,
          pid: pid() | nil,
          monitor_ref: reference() | nil,
          last_activity: DateTime.t() | nil
        }

  @doc """
  Creates a new session entry.

  ## Parameters

  * `session_state` - The Session.State struct for the session
  * `supervisor_pid` - The SessionSupervisor PID
  * `monitor_ref` - The process monitor reference
  * `opts` - Optional keyword list
    * `:last_activity` - Custom last activity timestamp (default: DateTime.utc_now())

  ## Returns

  * `{:ok, entry}` - Valid entry created
  * `{:error, reason}` - Validation failed

  ## Examples

      {:ok, entry} = Session.Entry.new(session_state, supervisor_pid, monitor_ref)

  """
  def new(session_state, supervisor_pid, monitor_ref, opts \\ []) do
    last_activity = Keyword.get(opts, :last_activity, DateTime.utc_now())

    entry = %__MODULE__{
      state: session_state,
      pid: supervisor_pid,
      monitor_ref: monitor_ref,
      last_activity: last_activity
    }

    case validate(entry) do
      :ok -> {:ok, entry}
      error -> error
    end
  end

  @doc """
  Creates a terminated entry (for sessions that have been terminated).

  ## Parameters

  * `session_state` - The terminated Session.State struct

  ## Returns

  A Session.Entry with nil pid and monitor_ref

  ## Examples

      entry = Session.Entry.terminated(terminated_state)

  """
  def terminated(session_state) do
    %__MODULE__{
      state: session_state,
      pid: nil,
      monitor_ref: nil,
      last_activity: DateTime.utc_now()
    }
  end

  @doc """
  Checks if a session entry is active (has a live PID and is not terminated).

  ## Examples

      Session.Entry.active?(entry)
      #=> true

  """
  def active?(%__MODULE__{pid: nil}), do: false
  def active?(%__MODULE__{pid: pid}) when is_pid(pid), do: Process.alive?(pid)
  def active?(%__MODULE__{}), do: false

  @doc """
  Checks if a session entry is terminated.

  ## Examples

      Session.Entry.terminated?(entry)
      #=> true

  """
  def terminated?(%__MODULE__{state: nil}), do: true
  def terminated?(%__MODULE__{state: %State{status: :terminated}}), do: true
  def terminated?(%__MODULE__{}), do: false

  @doc """
  Updates the last activity timestamp to the current time.

  ## Examples

      updated_entry = Session.Entry.touch_activity(entry)

  """
  def touch_activity(%__MODULE__{} = entry) do
    %{entry | last_activity: DateTime.utc_now()}
  end

  @doc """
  Converts a Session.Entry to a map for ETS storage.

  This is useful when you need to store the entry in ETS as a map
  rather than a struct.

  ## Examples

      map = Session.Entry.to_map(entry)

  """
  def to_map(%__MODULE__{} = entry) do
    Map.from_struct(entry)
  end

  @doc """
  Creates a Session.Entry from a map (typically from ETS lookup).

  ## Examples

      entry = Session.Entry.from_map(map_from_ets)

  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      state: Map.get(map, :state),
      pid: Map.get(map, :pid),
      monitor_ref: Map.get(map, :monitor_ref),
      last_activity: Map.get(map, :last_activity)
    }
  end

  # Private Helpers

  defp validate(%__MODULE__{} = entry) do
    with :ok <- validate_state(entry),
         :ok <- validate_monitor_ref(entry) do
      :ok
    end
  end

  defp validate_state(%__MODULE__{state: nil}), do: :ok
  defp validate_state(%__MODULE__{state: %State{}}), do: :ok
  defp validate_state(_), do: {:error, :invalid_state}

  defp validate_monitor_ref(%__MODULE__{monitor_ref: nil}), do: :ok
  defp validate_monitor_ref(%__MODULE__{monitor_ref: ref}) when is_reference(ref), do: :ok
  defp validate_monitor_ref(_), do: {:error, :invalid_monitor_ref}
end
