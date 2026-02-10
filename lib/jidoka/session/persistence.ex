defmodule Jidoka.Session.Persistence do
  @moduledoc """
  Session persistence to disk.

  This module handles saving and loading session state to/from disk as JSON files.
  Sessions are persisted in a configured directory with filenames based on session IDs.

  ## File Format

  Sessions are stored as JSON files with the following structure:

  ```json
  {
    "session_id": "session_abc123",
    "state": {
      "session_id": "session_abc123",
      "status": "active",
      ...
    },
    "saved_at": "2025-01-24T10:00:00Z"
  }
  ```

  ## Configuration

  The persistence directory can be configured via Application config:

      config :jidoka, :persistence_dir, "/path/to/sessions"

  Default: `./priv/sessions`

  ## Examples

  Saving a session:

      {:ok, session_entry} = SessionManager.get_session_entry(session_id)
      :ok = Session.Persistence.save(session_id, session_entry)

  Loading a session:

      {:ok, session_state} = Session.Persistence.load(session_id)

  Listing saved sessions:

      sessions = Session.Persistence.list_saved()

  Deleting a saved session:

      :ok = Session.Persistence.delete(session_id)

  """

  require Logger

  @default_persistence_dir "./priv/sessions"

  @doc """
  Saves a session to disk.

  ## Parameters

  * `session_id` - The session ID
  * `session_entry` - Map or Session.Entry with session state

  ## Returns

  * `:ok` - Session saved successfully
  * `{:error, reason}` - Save failed

  """
  def save(session_id, session_entry) when is_binary(session_id) and is_map(session_entry) do
    persistence_dir = get_persistence_dir()
    File.mkdir_p!(persistence_dir)

    session_state =
      case session_entry do
        %{state: %_{} = state} -> state
        %_{} = state -> state
      end

    data = %{
      session_id: session_id,
      state: Jidoka.Session.State.serialize(session_state),
      saved_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    file_path = Path.join(persistence_dir, "#{session_id}.json")

    case File.write(file_path, Jason.encode!(data, pretty: true)) do
      :ok ->
        Logger.debug("Saved session: #{session_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to save session #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Loads a session from disk.

  ## Parameters

  * `session_id` - The session ID to load

  ## Returns

  * `{:ok, session_state}` - Session loaded successfully
  * `{:error, :not_found}` - Session file doesn't exist
  * `{:error, reason}` - Load failed

  """
  def load(session_id) when is_binary(session_id) do
    file_path = Path.join(get_persistence_dir(), "#{session_id}.json")

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"state" => state_map}} ->
            case Jidoka.Session.State.deserialize(state_map) do
              {:ok, _session_state} = result ->
                Logger.debug("Loaded session: #{session_id}")
                result

              error ->
                error
            end

          {:ok, _} ->
            {:error, :invalid_format}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all saved sessions.

  ## Returns

  List of session IDs that have been saved to disk

  """
  def list_saved do
    persistence_dir = get_persistence_dir()

    case File.ls(persistence_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(&String.replace_trailing(&1, ".json", ""))
        |> Enum.sort()

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Deletes a saved session from disk.

  ## Parameters

  * `session_id` - The session ID to delete

  ## Returns

  * `:ok` - Session deleted successfully
  * `{:error, :not_found}` - Session file doesn't exist
  * `{:error, reason}` - Delete failed

  """
  def delete(session_id) when is_binary(session_id) do
    file_path = Path.join(get_persistence_dir(), "#{session_id}.json")

    case File.rm(file_path) do
      :ok ->
        Logger.debug("Deleted saved session: #{session_id}")
        :ok

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a session has been saved.

  ## Parameters

  * `session_id` - The session ID to check

  ## Returns

  * `true` - Session file exists
  * `false` - Session file doesn't exist

  """
  def saved?(session_id) when is_binary(session_id) do
    file_path = Path.join(get_persistence_dir(), "#{session_id}.json")
    File.exists?(file_path)
  end

  # Private Helpers

  defp get_persistence_dir do
    Application.get_env(:jidoka, :persistence_dir, @default_persistence_dir)
  end
end
