defmodule Jidoka.Messaging do
  @moduledoc """
  JidoMessaging runtime for Jidoka.

  This module is the new canonical conversation store scaffold for the project.
  It runs independently from the legacy session/tracker pipeline and provides a
  session-to-room mapping API to support migration.
  """

  use JidoMessaging,
    adapter: JidoMessaging.Adapters.ETS

  require Logger

  alias JidoMessaging.RoomServer
  alias JidoMessaging.Content.Text
  alias Jidoka.PubSub

  @session_channel :jidoka_session
  @session_instance_id "jidoka-core"

  @doc """
  Gets or creates a messaging room for a session identifier.
  """
  @spec ensure_room_for_session(String.t(), map()) ::
          {:ok, JidoMessaging.Room.t()} | {:error, term()}
  def ensure_room_for_session(session_id, attrs \\ %{})
      when is_binary(session_id) and is_map(attrs) do
    room_attrs =
      attrs
      |> Map.put_new(:type, :direct)
      |> Map.put_new(:name, "Session #{session_id}")
      |> Map.update(
        :metadata,
        %{session_id: session_id},
        &Map.put_new(&1, :session_id, session_id)
      )

    get_or_create_room_by_external_binding(
      @session_channel,
      @session_instance_id,
      session_id,
      room_attrs
    )
  end

  @doc """
  Returns a room id for a session if the mapping exists.
  """
  @spec session_room_id(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def session_room_id(session_id) when is_binary(session_id) do
    case get_room_by_external_binding(@session_channel, @session_instance_id, session_id) do
      {:ok, room} -> {:ok, room.id}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Saves a role/content message to the session room.
  """
  @spec append_session_message(
          String.t(),
          :user | :assistant | :system | :tool,
          String.t(),
          keyword()
        ) ::
          {:ok, JidoMessaging.Message.t()} | {:error, term()}
  def append_session_message(session_id, role, content, opts \\ [])
      when is_binary(session_id) and role in [:user, :assistant, :system, :tool] and
             is_binary(content) and is_list(opts) do
    with {:ok, room} <- ensure_room_for_session(session_id) do
      sender_id =
        case Keyword.get(opts, :sender_id) do
          id when is_binary(id) and id != "" -> id
          _ -> default_sender_id(role, session_id)
        end

      metadata =
        case Keyword.get(opts, :metadata, %{}) do
          value when is_map(value) -> value
          _ -> %{}
        end

      with {:ok, message} <-
             save_message(%{
               room_id: room.id,
               sender_id: sender_id,
               role: role,
               content: [%Text{text: content}],
               metadata: metadata
             }) do
        publish_room_message(room, message)
        publish_conversation_event(session_id, role, content, message)
        {:ok, message}
      end
    end
  end

  @doc """
  Lists messages for a session room.
  """
  @spec list_session_messages(String.t(), keyword()) ::
          {:ok, [JidoMessaging.Message.t()]} | {:error, term()}
  def list_session_messages(session_id, opts \\ [])
      when is_binary(session_id) and is_list(opts) do
    with {:ok, room} <- ensure_room_for_session(session_id) do
      list_messages(room.id, opts)
    end
  end

  @doc """
  Deletes all persisted messages for a session room.
  """
  @spec clear_session_messages(String.t(), keyword()) :: :ok | {:error, term()}
  def clear_session_messages(session_id, opts \\ [])
      when is_binary(session_id) and is_list(opts) do
    batch_size =
      case Keyword.get(opts, :batch_size, 200) do
        size when is_integer(size) and size > 0 -> size
        _ -> 200
      end

    do_clear_session_messages(session_id, batch_size)
  end

  defp default_sender_id(:user, session_id), do: "user:#{session_id}"
  defp default_sender_id(:assistant, _session_id), do: "assistant:jidoka"
  defp default_sender_id(:system, _session_id), do: "system:jidoka"
  defp default_sender_id(:tool, _session_id), do: "tool:jidoka"

  defp publish_room_message(room, message) do
    case get_or_start_room_server(room) do
      {:ok, room_pid} ->
        case RoomServer.add_message(room_pid, message) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "[Jidoka.Messaging] Failed to publish room message #{message.id}: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.warning(
          "[Jidoka.Messaging] Failed to start room server for #{room.id}: #{inspect(reason)}"
        )
    end
  end

  defp do_clear_session_messages(session_id, batch_size) do
    case list_session_messages(session_id, limit: batch_size) do
      {:ok, []} ->
        :ok

      {:ok, messages} ->
        case Enum.reduce_while(messages, :ok, fn message, _acc ->
               case delete_message(message.id) do
                 :ok -> {:cont, :ok}
                 {:error, _reason} = error -> {:halt, error}
               end
             end) do
          :ok -> do_clear_session_messages(session_id, batch_size)
          {:error, _reason} = error -> error
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp publish_conversation_event(session_id, role, content, message) do
    case Process.whereis(PubSub.pubsub_name()) do
      pid when is_pid(pid) ->
        PubSub.broadcast_session(
          session_id,
          {:conversation_added,
           %{
             session_id: session_id,
             role: role,
             content: content,
             timestamp: message.inserted_at || DateTime.utc_now()
           }}
        )

      nil ->
        :ok
    end
  end
end
