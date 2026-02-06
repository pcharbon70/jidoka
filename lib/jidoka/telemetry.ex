defmodule Jidoka.Telemetry do
  @moduledoc """
  Standard telemetry event definitions for Jidoka.

  This module defines all telemetry events emitted by the application.
  Events follow the pattern `[:jidoka, :component, :action]`.

  ## Event Metadata

  Each event may include measurements and metadata:

  ### Measurements
  Numeric values that can be aggregated (durations, counts, sizes).

  ### Metadata
  Structured data that provides context (ids, types, status).

  ## Usage

  Emit events using `:telemetry.execute/3`:

      :telemetry.execute(
        Jidoka.Telemetry.session_started(),
        %{duration: System.monotonic_time(:millisecond) - start_time},
        %{session_id: "abc123", user_id: "user1"}
      )

  Attach handlers using `:telemetry.attach/4`:

      :telemetry.attach(
        "my-handler",
        Jidoka.Telemetry.session_started(),
        &MyHandler.handle_event/4,
        nil
      )

  ## Standard Events

  Session Events: session_started/0, session_stopped/0, session_error/0
  Agent Events: agent_dispatch/0, agent_complete/0, agent_error/0
  LLM Events: llm_request/0, llm_response/0, llm_error/0
  Context Events: context_cache_hit/0, context_cache_miss/0, context_cache_eviction/0
  PubSub Events: pubsub_broadcast/0, pubsub_receive/0
  Registry Events: registry_register/0, registry_unregister/0

  """

  @type event_name :: [atom(), ...]

  # Session Events
  @doc """
  Event name for session start.

  **Measurements:**
  - `:duration` - Time taken to start the session (milliseconds)

  **Metadata:**
  - `:session_id` - Unique session identifier
  - `:user_id` - User identifier (optional)
  - `:max_sessions` - Maximum concurrent sessions
  """
  @spec session_started() :: event_name()
  def session_started, do: [:jidoka, :session, :started]

  @doc """
  Event name for session stop.

  **Measurements:**
  - `:duration` - Session lifetime (milliseconds)

  **Metadata:**
  - `:session_id` - Unique session identifier
  - `:reason` - Reason for stopping (:normal, :shutdown, :timeout)
  """
  @spec session_stopped() :: event_name()
  def session_stopped, do: [:jidoka, :session, :stopped]

  @doc """
  Event name for session error.

  **Measurements:**
  - `:duration` - Time until error (milliseconds)

  **Metadata:**
  - `:session_id` - Unique session identifier
  - `:error_type` - Type of error
  - `:error_message` - Error message
  """
  @spec session_error() :: event_name()
  def session_error, do: [:jidoka, :session, :error]

  # Agent Events
  @doc """
  Event name for agent action dispatch.

  **Measurements:**
  - `:duration` - Dispatch time (milliseconds)

  **Metadata:**
  - `:agent_id` - Agent identifier
  - `:action_name` - Name of the action
  - `:session_id` - Associated session (optional)
  """
  @spec agent_dispatch() :: event_name()
  def agent_dispatch, do: [:jidoka, :agent, :dispatch]

  @doc """
  Event name for agent action completion.

  **Measurements:**
  - `:duration` - Action execution time (milliseconds)

  **Metadata:**
  - `:agent_id` - Agent identifier
  - `:action_name` - Name of the action
  - `:status` - Completion status (:ok, :error)
  - `:session_id` - Associated session (optional)
  """
  @spec agent_complete() :: event_name()
  def agent_complete, do: [:jidoka, :agent, :complete]

  @doc """
  Event name for agent action error.

  **Measurements:**
  - `:duration` - Time until error (milliseconds)

  **Metadata:**
  - `:agent_id` - Agent identifier
  - `:action_name` - Name of the action
  - `:error_type` - Type of error
  - `:session_id` - Associated session (optional)
  """
  @spec agent_error() :: event_name()
  def agent_error, do: [:jidoka, :agent, :error]

  # LLM Events
  @doc """
  Event name for LLM request.

  **Measurements:**
  - `:tokens_sent` - Number of tokens in the request
  - `:request_size` - Size of request in bytes

  **Metadata:**
  - `:provider` - LLM provider (:openai, :anthropic, :ollama)
  - `:model` - Model name
  - `:request_id` - Unique request identifier
  - `:session_id` - Associated session (optional)
  """
  @spec llm_request() :: event_name()
  def llm_request, do: [:jidoka, :llm, :request]

  @doc """
  Event name for LLM response.

  **Measurements:**
  - `:duration` - Request duration (milliseconds)
  - `:tokens_received` - Number of tokens in response
  - `:response_size` - Size of response in bytes

  **Metadata:**
  - `:provider` - LLM provider
  - `:model` - Model name
  - `:request_id` - Unique request identifier
  - `:status` - Response status (:success, :error)
  - `:session_id` - Associated session (optional)
  """
  @spec llm_response() :: event_name()
  def llm_response, do: [:jidoka, :llm, :response]

  @doc """
  Event name for LLM error.

  **Measurements:**
  - `:duration` - Time until error (milliseconds)

  **Metadata:**
  - `:provider` - LLM provider
  - `:model` - Model name
  - `:request_id` - Unique request identifier
  - `:error_type` - Type of error
  - `:error_message` - Error message
  - `:session_id` - Associated session (optional)
  """
  @spec llm_error() :: event_name()
  def llm_error, do: [:jidoka, :llm, :error]

  # Context Events
  @doc """
  Event name for context cache hit.

  **Measurements:**
  - `:size` - Size of cached value (bytes)

  **Metadata:**
  - `:cache_table` - Name of the ETS table
  - `:key` - Cache key (partial)
  - `:session_id` - Associated session (optional)
  """
  @spec context_cache_hit() :: event_name()
  def context_cache_hit, do: [:jidoka, :context, :cache_hit]

  @doc """
  Event name for context cache miss.

  **Measurements:**
  - `:none` - No measurements

  **Metadata:**
  - `:cache_table` - Name of the ETS table
  - `:key` - Cache key (partial)
  - `:session_id` - Associated session (optional)
  """
  @spec context_cache_miss() :: event_name()
  def context_cache_miss, do: [:jidoka, :context, :cache_miss]

  @doc """
  Event name for context cache eviction.

  **Measurements:**
  - `:size` - Size of evicted value (bytes)
  - `:ttl` - Remaining TTL (milliseconds)

  **Metadata:**
  - `:cache_table` - Name of the ETS table
  - `:key` - Cache key (partial)
  - `:reason` - Reason for eviction
  """
  @spec context_cache_eviction() :: event_name()
  def context_cache_eviction, do: [:jidoka, :context, :cache_eviction]

  # PubSub Events
  @doc """
  Event name for PubSub broadcast.

  **Measurements:**
  - `:size` - Message size in bytes

  **Metadata:**
  - `:topic` - Topic name
  - `:message_type` - Type of message
  - `:subscriber_count` - Number of subscribers
  """
  @spec pubsub_broadcast() :: event_name()
  def pubsub_broadcast, do: [:jidoka, :pubsub, :broadcast]

  @doc """
  Event name for PubSub message receive.

  **Measurements:**
  - `:size` - Message size in bytes

  **Metadata:**
  - `:topic` - Topic name
  - `:message_type` - Type of message
  - `:subscriber_pid` - Subscriber process ID
  """
  @spec pubsub_receive() :: event_name()
  def pubsub_receive, do: [:jidoka, :pubsub, :receive]

  # Registry Events
  @doc """
  Event name for registry registration.

  **Measurements:**
  - `:none` - No measurements

  **Metadata:**
  - `:registry_name` - Name of the registry
  - `:key` - Registration key (partial)
  - `:pid` - Process ID
  """
  @spec registry_register() :: event_name()
  def registry_register, do: [:jidoka, :registry, :register]

  @doc """
  Event name for registry unregistration.

  **Measurements:**
  - `:none` - No measurements

  **Metadata:**
  - `:registry_name` - Name of the registry
  - `:key` - Registration key (partial)
  - `:pid` - Process ID
  """
  @spec registry_unregister() :: event_name()
  def registry_unregister, do: [:jidoka, :registry, :unregister]

  @doc """
  Wrapper for executing a function and emitting a telemetry event.

  ## Parameters

  - `event_name_fn` - Function that returns the event name tuple
  - `metadata` - Static metadata to include (merged with dynamic metadata)
  - `fun` - Function to execute

  ## Returns

  The result of the function.

  ## Example

      start_time = System.monotonic_time()

      result =
        execute_with_telemetry(
          &Telemetry.llm_request/0,
          %{model: "gpt-4", provider: :openai},
          fn -> LLM.chat_completion(prompt) end
        )

  """
  @spec execute_with_telemetry(fun(), map(), fun()) :: any()
  def execute_with_telemetry(event_name_fn, static_metadata, fun)
      when is_function(event_name_fn, 0) do
    start_time = System.monotonic_time()

    try do
      result = fun.()

      measurements = %{
        duration: System.monotonic_time() - start_time
      }

      :telemetry.execute(event_name_fn.(), measurements, static_metadata)

      result
    rescue
      error ->
        measurements = %{
          duration: System.monotonic_time() - start_time
        }

        metadata = Map.put(static_metadata, :error, Exception.message(error))

        # Emit error event if there's a corresponding one
        :telemetry.execute(event_name_fn.(), measurements, metadata)

        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Wrapper for executing a function and emitting start/complete telemetry events.

  ## Parameters

  - `start_event_fn` - Function that returns the start event name tuple
  - `complete_event_fn` - Function that returns the complete event name tuple
  - `metadata` - Static metadata to include
  - `fun` - Function to execute

  ## Returns

  The result of the function.

  ## Example

      execute_with_start_complete(
        &Telemetry.agent_dispatch/0,
        &Telemetry.agent_complete/0,
        %{agent_id: "agent1", action_name: "chat"},
        fn -> Agent.execute(action) end
      )

  """
  @spec execute_with_start_complete(fun(), fun(), map(), fun()) :: any()
  def execute_with_start_complete(start_event_fn, complete_event_fn, static_metadata, fun)
      when is_function(start_event_fn, 0) and is_function(complete_event_fn, 0) do
    start_time = System.monotonic_time()

    :telemetry.execute(start_event_fn.(), %{system_time: start_time}, static_metadata)

    try do
      result = fun.()

      measurements = %{
        duration: System.monotonic_time() - start_time
      }

      metadata = Map.put(static_metadata, :status, :ok)

      :telemetry.execute(complete_event_fn.(), measurements, metadata)

      result
    rescue
      error in [Exit, RuntimeError] ->
        measurements = %{
          duration: System.monotonic_time() - start_time
        }

        metadata =
          static_metadata
          |> Map.put(:status, :error)
          |> Map.put(:error_type, error.__struct__)
          |> Map.put(:error_message, Exception.message(error))

        :telemetry.execute(complete_event_fn.(), measurements, metadata)

        reraise error, __STACKTRACE__
    end
  end
end
