defmodule Jidoka.ClientEvents do
  @moduledoc """
  Standardized client event types and helpers for jidoka.

  This module defines the standard event types that are broadcast to connected
  clients via Phoenix PubSub. Each event type has a defined schema for its
  payload, ensuring consistency across all agents.

  ## Event Types

  ### LLM Events
  * `:llm_stream_chunk` - Streaming LLM response chunk
  * `:llm_response` - Final LLM response

  ### Agent Status Events
  * `:agent_status` - Agent status changes

  ### Analysis Events
  * `:analysis_complete` - Code analysis results

  ### Issue Events
  * `:issue_found` - Issue detected during analysis

  ### Tool Events
  * `:tool_call` - Tool being called
  * `:tool_result` - Tool execution result

  ### Context Events
  * `:context_updated` - Context/project changes

  ## Usage

  Create an event with validation:

      event = ClientEvents.new(:llm_stream_chunk, %{
        content: "Hello",
        session_id: "session-123"
      })

  Convert to a broadcast directive:

      directive = ClientEvents.to_directive(event)

  For session-specific events:

      directive = ClientEvents.to_directive(event, "session-123")

  ## Event Schemas

  Each event type has a schema defining required and optional fields:

  ### llm_stream_chunk

  * `:content` (required) - The text content chunk
  * `:session_id` (required) - The session ID
  * `:chunk_index` (optional) - Index of this chunk
  * `:is_final` (optional) - Whether this is the final chunk

  ### llm_response

  * `:content` (required) - The complete response text
  * `:session_id` (required) - The session ID
  * `:model` (optional) - The model used
  * `:tokens_used` (optional) - Total tokens used

  ### agent_status

  * `:agent_name` (required) - The agent name
  * `:status` (required) - The status (e.g., :ready, :busy, :error)
  * `:message` (optional) - Status message
  * `:timestamp` (optional) - Status timestamp (auto-added if not provided)

  ### analysis_complete

  * `:session_id` (required) - The session ID
  * `:files_analyzed` (required) - Number of files analyzed
  * `:issues_found` (required) - Number of issues found
  * `:duration_ms` (optional) - Analysis duration in milliseconds
  * `:results` (optional) - Detailed analysis results

  ### issue_found

  * `:session_id` (required) - The session ID
  * `:severity` (required) - Issue severity (:error, :warning, :info)
  * :`message` (required) - Issue message
  * `:file` (optional) - File path where issue was found
  * `:line` (optional) - Line number
  * `:column` (optional) - Column number
  * `:suggestion` (optional) - Suggested fix

  ### tool_call

  * `:session_id` (required) - The session ID
  * `:tool_name` (required) - Name of the tool being called
  * `:tool_id` (required) - Unique ID for this tool call
  * `:parameters` (required) - Tool parameters
  * `:timestamp` (optional) - Call timestamp (auto-added)

  ### tool_result

  * `:session_id` (required) - The session ID
  * `:tool_id` (required) - ID of the corresponding tool call
  * `:tool_name` (required) - Name of the tool
  * `:status` (required) - Result status (:success, :error)
  * `:result` (optional) - Tool result data
  * `:error` (optional) - Error message if status is :error

  ### context_updated

  * `:session_id` (required) - The session ID
  * `:project_path` (optional) - New project path
  * `:files_changed` (optional) - List of changed files
  * `:timestamp` (optional) - Update timestamp (auto-added)

  """

  alias Jidoka.Agent.Directives

  @type event_type :: atom()
  @type event :: %{type: event_type(), payload: map()}
  @type directive :: term()

  # ============================================================================
  # Event Type Definitions
  # ============================================================================

  @event_types [
    :llm_stream_chunk,
    :llm_response,
    :agent_status,
    :analysis_complete,
    :issue_found,
    :tool_call,
    :tool_result,
    :context_updated
  ]

  @doc """
  Returns the list of all defined event types.
  """
  @spec event_types() :: [event_type()]
  def event_types, do: @event_types

  # ============================================================================
  # Event Schemas
  # ============================================================================

  @doc """
  Returns the schema for a given event type.

  ## Examples

      iex> schema = ClientEvents.schema(:llm_stream_chunk)
      iex> schema.required
      [:content, :session_id]

  """
  @spec schema(event_type()) :: map() | nil
  def schema(:llm_stream_chunk) do
    %{
      required: [:content, :session_id],
      optional: [:chunk_index, :is_final],
      types: %{
        content: :string,
        session_id: :string,
        chunk_index: :integer,
        is_final: :boolean
      }
    }
  end

  def schema(:llm_response) do
    %{
      required: [:content, :session_id],
      optional: [:model, :tokens_used],
      types: %{
        content: :string,
        session_id: :string,
        model: :string,
        tokens_used: :integer
      }
    }
  end

  def schema(:agent_status) do
    %{
      required: [:agent_name, :status],
      optional: [:message],
      types: %{
        agent_name: :string,
        status: :atom,
        message: :string
      }
    }
  end

  def schema(:analysis_complete) do
    %{
      required: [:session_id, :files_analyzed, :issues_found],
      optional: [:duration_ms, :results],
      types: %{
        session_id: :string,
        files_analyzed: :integer,
        issues_found: :integer,
        duration_ms: :integer,
        results: :map
      }
    }
  end

  def schema(:issue_found) do
    %{
      required: [:session_id, :severity, :message],
      optional: [:file, :line, :column, :suggestion],
      types: %{
        session_id: :string,
        severity: :atom,
        message: :string,
        file: :string,
        line: :integer,
        column: :integer,
        suggestion: :string
      }
    }
  end

  def schema(:tool_call) do
    %{
      required: [:session_id, :tool_name, :tool_id, :parameters],
      optional: [],
      types: %{
        session_id: :string,
        tool_name: :string,
        tool_id: :string,
        parameters: :map
      }
    }
  end

  def schema(:tool_result) do
    %{
      required: [:session_id, :tool_id, :tool_name, :status],
      optional: [:result, :error],
      types: %{
        session_id: :string,
        tool_id: :string,
        tool_name: :string,
        status: :atom,
        result: :any,
        error: :string
      }
    }
  end

  def schema(:context_updated) do
    %{
      required: [:session_id],
      optional: [:project_path, :files_changed],
      types: %{
        session_id: :string,
        project_path: :string,
        files_changed: {:list, :string}
      }
    }
  end

  def schema(_), do: nil

  # ============================================================================
  # Event Creation
  # ============================================================================

  @doc """
  Creates a new event with the given type and payload.

  Validates the payload against the event type's schema and adds
  a timestamp if not already present.

  ## Parameters

  * `type` - The event type (atom)
  * `payload` - The event payload data

  ## Returns

  * `{:ok, event}` - If the event is valid
  * `{:error, reason}` - If validation fails

  ## Examples

      iex> {:ok, event} = ClientEvents.new(:llm_stream_chunk, %{
      ...>   content: "Hello",
      ...>   session_id: "session-123"
      ...> })
      iex> event.type
      :llm_stream_chunk

      iex> {:error, _} = ClientEvents.new(:llm_stream_chunk, %{
      ...>   content: "Hello"
      ...> })
      {:error, {:missing_required_fields, [:session_id]}}

  """
  @spec new(event_type(), map()) :: {:ok, event()} | {:error, term()}
  def new(type, payload) when is_atom(type) and is_map(payload) do
    with {:ok, schema} <- validate_type_exists(type),
         {:ok, validated_payload} <- validate_payload(type, payload, schema) do
      event = %{
        type: type,
        payload: add_timestamp(validated_payload)
      }

      {:ok, event}
    end
  end

  @doc """
  Creates a new event, raising on error.

  Like `new/2` but raises an exception if validation fails.

  ## Examples

      event = ClientEvents.new!(:llm_stream_chunk, %{
        content: "Hello",
        session_id: "session-123"
      })

  """
  @spec new!(event_type(), map()) :: event()
  def new!(type, payload) when is_atom(type) and is_map(payload) do
    case new(type, payload) do
      {:ok, event} -> event
      {:error, reason} -> raise ArgumentError, "invalid event: #{inspect(reason)}"
    end
  end

  # ============================================================================
  # Directive Conversion
  # ============================================================================

  @doc """
  Converts an event to a broadcast directive for global client events.

  The event is broadcast to the `jido.client.events` topic.

  ## Examples

      {:ok, event} = ClientEvents.new(:agent_status, %{
        agent_name: "coordinator",
        status: :ready
      })
      directive = ClientEvents.to_directive(event)

  """
  @spec to_directive(event()) :: directive()
  def to_directive(%{type: type, payload: payload}) do
    event_type = Atom.to_string(type)
    Directives.client_broadcast(event_type, payload)
  end

  @doc """
  Converts an event to a session-specific broadcast directive.

  The event is broadcast to `jido.client.session.<session_id>` topic.

  ## Parameters

  * `event` - The event to broadcast
  * `session_id` - The session ID (overrides payload session_id if present)

  ## Examples

      {:ok, event} = ClientEvents.new(:llm_stream_chunk, %{
        content: "Hello",
        session_id: "session-123"
      })
      directive = ClientEvents.to_directive(event, "session-123")

  """
  @spec to_directive(event(), String.t()) :: directive()
  def to_directive(%{type: type, payload: payload}, session_id) when is_binary(session_id) do
    event_type = Atom.to_string(type)
    Directives.session_broadcast(session_id, event_type, payload)
  end

  # ============================================================================
  # Convenience Event Creators
  # ============================================================================

  @doc """
  Creates an LLM stream chunk event.

  ## Examples

      ClientEvents.llm_stream_chunk("Hello", "session-123")
      |> ClientEvents.to_directive("session-123")

  """
  @spec llm_stream_chunk(String.t(), String.t(), Keyword.t()) :: {:ok, event()} | {:error, term()}
  def llm_stream_chunk(content, session_id, opts \\ []) do
    payload =
      %{
        content: content,
        session_id: session_id
      }
      |> maybe_put(:chunk_index, Keyword.get(opts, :chunk_index))
      |> maybe_put(:is_final, Keyword.get(opts, :is_final))

    new(:llm_stream_chunk, payload)
  end

  @doc """
  Creates an LLM response event.

  ## Examples

      ClientEvents.llm_response("Complete response", "session-123", model: "gpt-4")
      |> ClientEvents.to_directive("session-123")

  """
  @spec llm_response(String.t(), String.t(), Keyword.t()) :: {:ok, event()} | {:error, term()}
  def llm_response(content, session_id, opts \\ []) do
    payload =
      %{
        content: content,
        session_id: session_id
      }
      |> maybe_put(:model, Keyword.get(opts, :model))
      |> maybe_put(:tokens_used, Keyword.get(opts, :tokens_used))

    new(:llm_response, payload)
  end

  @doc """
  Creates an agent status event.

  ## Examples

      ClientEvents.agent_status("coordinator", :ready)
      |> ClientEvents.to_directive()

  """
  @spec agent_status(String.t(), atom(), Keyword.t()) :: {:ok, event()} | {:error, term()}
  def agent_status(agent_name, status, opts \\ []) do
    payload =
      %{
        agent_name: agent_name,
        status: status
      }
      |> maybe_put(:message, Keyword.get(opts, :message))

    new(:agent_status, payload)
  end

  @doc """
  Creates an analysis complete event.

  ## Examples

      ClientEvents.analysis_complete("session-123", 5, 2)
      |> ClientEvents.to_directive("session-123")

  """
  @spec analysis_complete(String.t(), integer(), integer(), Keyword.t()) ::
          {:ok, event()} | {:error, term()}
  def analysis_complete(session_id, files_analyzed, issues_found, opts \\ []) do
    payload =
      %{
        session_id: session_id,
        files_analyzed: files_analyzed,
        issues_found: issues_found
      }
      |> maybe_put(:duration_ms, Keyword.get(opts, :duration_ms))
      |> maybe_put(:results, Keyword.get(opts, :results))

    new(:analysis_complete, payload)
  end

  @doc """
  Creates an issue found event.

  ## Examples

      ClientEvents.issue_found("session-123", :error, "Syntax error")
      |> ClientEvents.to_directive("session-123")

  """
  @spec issue_found(String.t(), atom(), String.t(), Keyword.t()) ::
          {:ok, event()} | {:error, term()}
  def issue_found(session_id, severity, message, opts \\ []) do
    payload =
      %{
        session_id: session_id,
        severity: severity,
        message: message
      }
      |> maybe_put(:file, Keyword.get(opts, :file))
      |> maybe_put(:line, Keyword.get(opts, :line))
      |> maybe_put(:column, Keyword.get(opts, :column))
      |> maybe_put(:suggestion, Keyword.get(opts, :suggestion))

    new(:issue_found, payload)
  end

  @doc """
  Creates a tool call event.

  ## Examples

      ClientEvents.tool_call("session-123", "read_file", "call-123", %{path: "test.exs"})
      |> ClientEvents.to_directive("session-123")

  """
  @spec tool_call(String.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, event()} | {:error, term()}
  def tool_call(session_id, tool_name, tool_id, parameters, _opts \\ []) do
    payload = %{
      session_id: session_id,
      tool_name: tool_name,
      tool_id: tool_id,
      parameters: parameters
    }

    new(:tool_call, payload)
  end

  @doc """
  Creates a tool result event.

  ## Examples

      ClientEvents.tool_result("session-123", "call-123", "read_file", :success, %{content: "data"})
      |> ClientEvents.to_directive("session-123")

  """
  @spec tool_result(String.t(), String.t(), String.t(), atom(), Keyword.t()) ::
          {:ok, event()} | {:error, term()}
  def tool_result(session_id, tool_id, tool_name, status, opts \\ []) do
    payload =
      %{
        session_id: session_id,
        tool_id: tool_id,
        tool_name: tool_name,
        status: status
      }
      |> maybe_put(:result, Keyword.get(opts, :result))
      |> maybe_put(:error, Keyword.get(opts, :error))

    new(:tool_result, payload)
  end

  @doc """
  Creates a context updated event.

  ## Examples

      ClientEvents.context_updated("session-123", project_path: "/path/to/project")
      |> ClientEvents.to_directive("session-123")

  """
  @spec context_updated(String.t(), Keyword.t()) :: {:ok, event()} | {:error, term()}
  def context_updated(session_id, opts \\ []) do
    payload =
      %{
        session_id: session_id
      }
      |> maybe_put(:project_path, Keyword.get(opts, :project_path))
      |> maybe_put(:files_changed, Keyword.get(opts, :files_changed))

    new(:context_updated, payload)
  end

  # ============================================================================
  # Validation Functions (Private)
  # ============================================================================

  defp validate_type_exists(type) do
    if type in @event_types do
      {:ok, schema(type)}
    else
      {:error, {:unknown_event_type, type}}
    end
  end

  defp validate_payload(_type, payload, schema) do
    # Check required fields
    missing =
      Enum.filter(schema.required, fn field ->
        not Map.has_key?(payload, field)
      end)

    if Enum.empty?(missing) do
      # Validate field types
      validate_field_types(payload, schema)
    else
      {:error, {:missing_required_fields, missing}}
    end
  end

  defp validate_field_types(payload, schema) do
    all_fields = Map.keys(payload)

    invalid_types =
      Enum.filter(all_fields, fn field ->
        case Map.get(schema.types, field) do
          nil -> false
          expected_type -> not validate_type(Map.get(payload, field), expected_type)
        end
      end)

    if Enum.empty?(invalid_types) do
      {:ok, payload}
    else
      {:error, {:invalid_types, invalid_types}}
    end
  end

  defp validate_type(value, :string), do: is_binary(value)
  defp validate_type(value, :atom), do: is_atom(value)
  defp validate_type(value, :integer), do: is_integer(value)
  defp validate_type(value, :boolean), do: is_boolean(value)
  defp validate_type(value, :map), do: is_map(value)
  defp validate_type(_value, :any), do: true

  defp validate_type(value, {:list, inner_type}) do
    is_list(value) and Enum.all?(value, fn v -> validate_type(v, inner_type) end)
  end

  defp add_timestamp(payload) do
    if Map.has_key?(payload, :timestamp) do
      payload
    else
      Map.put(payload, :timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
    end
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
