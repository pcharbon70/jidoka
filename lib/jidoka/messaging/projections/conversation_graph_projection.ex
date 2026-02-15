defmodule Jidoka.Messaging.Projections.ConversationGraphProjection do
  @moduledoc """
  Projects canonical messaging room events into the conversation knowledge graph.

  This projection subscribes to `jido.messaging.room.message_added` events from
  `Jidoka.Messaging` and writes prompt/answer/tool entries via
  `Jidoka.Conversation.Logger`.
  """

  use GenServer

  require Logger

  alias JidoMessaging.Supervisor, as: MessagingSupervisor
  alias Jidoka.Conversation.Logger, as: ConversationLogger
  alias Jidoka.Messaging

  @subscribe_pattern "jido.messaging.room.message_added"
  @subscribe_retry_ms 200
  @max_seen_ids 10_000

  defstruct subscription_id: nil, seen_ids: MapSet.new(), seen_order: :queue.new()

  @type state :: %__MODULE__{
          subscription_id: term() | nil,
          seen_ids: MapSet.t(String.t()),
          seen_order: :queue.queue(String.t())
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    send(self(), :subscribe)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(:subscribe, state) do
    bus_name = MessagingSupervisor.signal_bus_name(Messaging)

    case Jido.Signal.Bus.subscribe(bus_name, @subscribe_pattern) do
      {:ok, subscription_id} ->
        {:noreply, %{state | subscription_id: subscription_id}}

      {:error, reason} ->
        Logger.warning(
          "[ConversationGraphProjection] Failed to subscribe to #{inspect(bus_name)}: #{inspect(reason)}"
        )

        Process.send_after(self(), :subscribe, @subscribe_retry_ms)
        {:noreply, state}
    end
  end

  def handle_info({:signal, %{type: @subscribe_pattern} = signal}, state) do
    message = get_signal_message(signal)
    next_state = maybe_project_message(message, state)
    {:noreply, next_state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp maybe_project_message(%{id: message_id} = message, state) when is_binary(message_id) do
    if MapSet.member?(state.seen_ids, message_id) do
      state
    else
      try do
        project_message(message)
      rescue
        exception ->
          Logger.warning(
            "[ConversationGraphProjection] Exception while projecting message #{message_id}: #{Exception.message(exception)}"
          )
      end

      remember_message_id(state, message_id)
    end
  end

  defp maybe_project_message(_message, state), do: state

  defp project_message(%{room_id: room_id} = message) when is_binary(room_id) do
    with {:ok, room} <- Messaging.get_room(room_id),
         {:ok, session_id} <- session_id_from_room(room),
         {:ok, conversation_iri} <- ConversationLogger.ensure_conversation(session_id),
         {:ok, turn_index} <- turn_index_for_message(session_id, message.id) do
      project_by_role(message, session_id, conversation_iri, turn_index)
    else
      {:error, :skip} ->
        :ok

      {:error, :no_turn} ->
        :ok

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[ConversationGraphProjection] Failed to project message #{inspect(message.id)}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp project_message(_message), do: :ok

  defp project_by_role(%{role: :user} = message, session_id, conversation_iri, turn_index) do
    case extract_message_text(message) do
      {:ok, prompt_text} ->
        log_result(
          ConversationLogger.log_prompt(conversation_iri, turn_index, prompt_text),
          :prompt,
          session_id,
          turn_index
        )

      {:error, :skip} ->
        :ok
    end
  end

  defp project_by_role(%{role: :assistant} = message, session_id, conversation_iri, turn_index) do
    case extract_message_text(message) do
      {:ok, answer_text} ->
        log_result(
          ConversationLogger.log_answer(conversation_iri, turn_index, answer_text),
          :answer,
          session_id,
          turn_index
        )

      {:error, :skip} ->
        :ok
    end
  end

  defp project_by_role(%{role: :tool} = message, session_id, conversation_iri, turn_index) do
    metadata = Map.get(message, :metadata, %{})

    case metadata_get(metadata, :event_type) do
      value when value in [:tool_call, "tool_call"] ->
        tool_name = metadata_get(metadata, :tool_name)
        parameters = metadata_get(metadata, :parameters)
        tool_index = metadata_get(metadata, :tool_index)

        if is_binary(tool_name) and is_map(parameters) and is_integer(tool_index) do
          log_result(
            ConversationLogger.log_tool_invocation(
              conversation_iri,
              turn_index,
              tool_index,
              tool_name,
              parameters
            ),
            :tool_invocation,
            session_id,
            turn_index
          )
        else
          :ok
        end

      value when value in [:tool_result, "tool_result"] ->
        result_data = metadata_get(metadata, :result_data)
        tool_index = metadata_get(metadata, :tool_index)

        if is_integer(tool_index) and is_map(result_data) do
          log_result(
            ConversationLogger.log_tool_result(
              conversation_iri,
              turn_index,
              tool_index,
              result_data
            ),
            :tool_result,
            session_id,
            turn_index
          )
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp project_by_role(_message, _session_id, _conversation_iri, _turn_index), do: :ok

  defp session_id_from_room(room) do
    metadata = Map.get(room, :metadata, %{})

    case metadata_get(metadata, :session_id) do
      session_id when is_binary(session_id) and session_id != "" -> {:ok, session_id}
      _ -> {:error, :skip}
    end
  end

  defp turn_index_for_message(session_id, message_id) do
    with {:ok, messages} <- Messaging.list_session_messages(session_id, limit: 5_000) do
      {user_count, found?} =
        Enum.reduce_while(messages, {0, false}, fn message, {count, _} ->
          next_count =
            if Map.get(message, :role) == :user do
              count + 1
            else
              count
            end

          if Map.get(message, :id) == message_id do
            {:halt, {next_count, true}}
          else
            {:cont, {next_count, false}}
          end
        end)

      cond do
        found? and user_count > 0 ->
          {:ok, user_count - 1}

        true ->
          {:error, :no_turn}
      end
    end
  end

  defp extract_message_text(message) do
    text =
      message
      |> Map.get(:content, [])
      |> Enum.map(&content_block_to_text/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
      |> String.trim()

    if text == "" do
      {:error, :skip}
    else
      {:ok, text}
    end
  end

  defp content_block_to_text(%{type: :text, text: text}) when is_binary(text), do: text
  defp content_block_to_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp content_block_to_text(block) when is_map(block), do: inspect(block)
  defp content_block_to_text(_), do: ""

  defp metadata_get(metadata, key) when is_map(metadata) do
    case Map.fetch(metadata, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(metadata, to_string(key))
    end
  end

  defp log_result({:ok, _}, _entry_type, _session_id, _turn_index), do: :ok

  defp log_result({:error, reason}, entry_type, session_id, turn_index) do
    Logger.warning(
      "[ConversationGraphProjection] Failed #{entry_type} projection for session #{session_id}, turn #{turn_index}: #{inspect(reason)}"
    )

    :ok
  end

  defp get_signal_message(signal) do
    data = Map.get(signal, :data, %{})
    Map.get(data, :message) || Map.get(data, "message")
  end

  defp remember_message_id(state, message_id) do
    seen_ids = MapSet.put(state.seen_ids, message_id)
    seen_order = :queue.in(message_id, state.seen_order)
    trim_seen_ids(%{state | seen_ids: seen_ids, seen_order: seen_order})
  end

  defp trim_seen_ids(%{seen_ids: seen_ids, seen_order: seen_order} = state) do
    if MapSet.size(seen_ids) <= @max_seen_ids do
      state
    else
      case :queue.out(seen_order) do
        {{:value, oldest_id}, next_queue} ->
          next_seen_ids = MapSet.delete(seen_ids, oldest_id)
          trim_seen_ids(%{state | seen_ids: next_seen_ids, seen_order: next_queue})

        {:empty, _queue} ->
          state
      end
    end
  end
end
