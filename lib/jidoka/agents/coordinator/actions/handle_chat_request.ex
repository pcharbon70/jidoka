defmodule Jidoka.Agents.Coordinator.Actions.HandleChatRequest do
  @moduledoc """
  Action to handle user chat request signals.

  This action processes `jido_coder.chat.request` signals from users
  and routes them to the appropriate agent (typically an LLM agent).

  ## Signal Data

  * `:message` - User message content
  * `:session_id` - Associated session ID
  * `:user_id` - Optional user identifier
  * `:context` - Additional conversation context map

  ## State Updates

  Creates an active task entry for the chat request.

  ## Directives

  Broadcasts the chat request to session-specific topic for LLM processing.

  ## Conversation Persistence

  Persists incoming user prompts into `Jidoka.Messaging` as the canonical
  conversation store before routing downstream.
  """

  use Jido.Action,
    name: "handle_chat_request",
    description: "Process user chat requests and route to LLM",
    category: "coordinator",
    tags: ["chat", "llm", "routing"],
    vsn: "1.0.0",
    schema: [
      message: [
        type: :string,
        required: true,
        doc: "User message content"
      ],
      session_id: [
        type: :string,
        required: true,
        doc: "Associated session ID"
      ],
      user_id: [
        type: :string,
        required: false,
        doc: "User identifier"
      ],
      context: [
        type: :map,
        default: %{},
        doc: "Additional conversation context"
      ]
    ]

  alias Jido.Agent.{Directive, StateOp}
  alias Jido.Signal
  alias Jidoka.Messaging
  alias Jidoka.PubSub
  alias Jidoka.Signals

  alias Directive.Emit
  alias StateOp.SetState

  @impl true
  def run(params, _context) do
    # Extract signal data
    message = params[:message]
    session_id = params[:session_id]
    user_id = params[:user_id]
    context_data = params[:context]

    with {:ok, _room} <- Messaging.ensure_room_for_session(session_id),
         {:ok, _stored_message} <-
           Messaging.append_session_message(
             session_id,
             :user,
             message,
             sender_id: user_sender_id(user_id, session_id)
           ) do
      # Generate unique task ID for this chat request
      task_id = "chat_#{session_id}_#{System.unique_integer([:positive, :monotonic])}"

      # Build payload for client broadcast (chat received)
      payload = %{
        task_id: task_id,
        message: message,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      # Create chat received signal with proper BroadcastEvent structure
      received_signal =
        Signals.BroadcastEvent.new!(%{
          event_type: "chat_received",
          payload: payload,
          session_id: session_id
        })

      # State updates: track as active task
      state_updates = %{
        active_tasks: %{
          task_id => %{
            type: :chat,
            session_id: session_id,
            user_id: user_id,
            status: :processing,
            started_at: DateTime.utc_now()
          }
        }
      }

      # Build LLM request signal data
      llm_request_data = %{
        task_id: task_id,
        message: message,
        session_id: session_id,
        user_id: user_id,
        context: context_data
      }

      # Create a signal to route to LLM processor
      llm_request_signal =
        Signal.new!(
          "jido_coder.llm.request",
          llm_request_data,
          %{source: "/jido_coder/coordinator"}
        )

      # Return result with state update and emit directives
      {:ok, %{status: :routed, task_id: task_id, session_id: session_id},
       [
         # State operation: track as active task
         %SetState{attrs: state_updates},
         # Broadcast to client events that chat was received
         %Emit{
           signal: received_signal,
           dispatch:
             {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.client_events_topic()]}
         },
         # Route to session-specific topic for LLM processing
         %Emit{
           signal: llm_request_signal,
           dispatch:
             {:pubsub, [target: PubSub.pubsub_name(), topic: PubSub.session_topic(session_id)]}
         }
       ]}
    end
  end

  defp user_sender_id(user_id, session_id) when is_binary(user_id) and user_id != "" do
    "user:#{user_id}"
  end

  defp user_sender_id(_user_id, session_id) do
    "user:#{session_id}"
  end
end
