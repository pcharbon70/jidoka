defmodule JidoCoderLib.Signals do
  @moduledoc """
  Convenience functions for creating and dispatching JidoCoderLib signals.

  This module provides a unified interface for signal creation and dispatch,
  integrating with Phoenix PubSub for signal routing.

  All signals follow the CloudEvents v1.0.2 specification and are built
  on top of Jido's Signal system.

  ## Signal Types

  - `file_changed/3` - File system events
  - `analysis_complete/3` - Analysis results
  - `broadcast_event/3` - Client broadcast events
  - `chat_request/2` - User chat requests
  - `indexing_status/2` - Code indexing status updates

  ## Options

  All signal constructors accept the following options:

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override the default source
  - `:subject` - Set a custom subject for the signal

  ## Examples

  Create and dispatch a signal (default behavior):

      {:ok, signal} = JidoCoderLib.Signals.file_changed("/path/to/file.ex", :updated)

  Create a signal without dispatching:

      {:ok, signal} = JidoCoderLib.Signals.file_changed(
        "/path/to/file.ex",
        :updated,
        dispatch: false
      )

  Create with custom source:

      {:ok, signal} = JidoCoderLib.Signals.analysis_complete(
        "custom_type",
        %{result: :ok},
        source: "/custom/source"
      )

  """

  alias JidoCoderLib.PubSub

  alias JidoCoderLib.Signals.{
    FileChanged,
    AnalysisComplete,
    BroadcastEvent,
    ChatRequest,
    IndexingStatus
  }

  @type signal :: Jido.Signal.t()
  @type signal_result :: {:ok, signal()} | {:error, term()}

  @doc """
  Creates and optionally dispatches a file changed signal.

  ## Parameters

  - `path` - Absolute path to the changed file
  - `action` - Type of change: `:created`, `:updated`, or `:deleted`
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/filesystem`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Session tracking ID
  - `:metadata` - Additional metadata about the file change

  ## Examples

      {:ok, signal} = Signals.file_changed("/path/to/file.ex", :updated)

      {:ok, signal} = Signals.file_changed(
        "/path/to/file.ex",
        :created,
        session_id: "session-123",
        metadata: %{size: 1024}
      )

  """
  @spec file_changed(String.t(), atom(), Keyword.t()) :: signal_result()
  def file_changed(path, action, opts \\ []) when is_binary(path) and is_atom(action) do
    data =
      %{
        path: path,
        action: action,
        metadata: Keyword.get(opts, :metadata, %{})
      }
      |> maybe_put_session_id(opts)

    create_and_dispatch(FileChanged, data, opts)
  end

  @doc """
  Creates and optionally dispatches an analysis complete signal.

  ## Parameters

  - `analysis_type` - Type of analysis performed (e.g., "credo", "dialyzer")
  - `results` - Analysis results map
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/analyzer`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Associated session ID
  - `:duration_ms` - Analysis duration in milliseconds

  ## Examples

      {:ok, signal} = Signals.analysis_complete("credo", %{errors: [], warnings: ["unused var"]})

      {:ok, signal} = Signals.analysis_complete(
        "dialyzer",
        %{warnings: 5},
        session_id: "session-123",
        duration_ms: 150
      )

  """
  @spec analysis_complete(String.t(), map(), Keyword.t()) :: signal_result()
  def analysis_complete(analysis_type, results, opts \\ []) when is_binary(analysis_type) do
    data =
      %{
        analysis_type: analysis_type,
        results: results
      }
      |> maybe_put_session_id(opts)
      |> maybe_put_duration_ms(opts)

    create_and_dispatch(AnalysisComplete, data, opts)
  end

  @doc """
  Creates and optionally dispatches a client broadcast event signal.

  ## Parameters

  - `event_type` - Type of client event (e.g., "llm_stream_chunk", "agent_status")
  - `payload` - Event payload map
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/coordinator`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Target session ID for targeted broadcasts

  ## Examples

      {:ok, signal} = Signals.broadcast_event("llm_stream_chunk", %{content: "Hello"})

      {:ok, signal} = Signals.broadcast_event(
        "agent_status",
        %{status: :ready},
        session_id: "session-123"
      )

  """
  @spec broadcast_event(String.t(), map(), Keyword.t()) :: signal_result()
  def broadcast_event(event_type, payload, opts \\ []) when is_binary(event_type) do
    data =
      %{
        event_type: event_type,
        payload: payload
      }
      |> maybe_put_session_id(opts)

    create_and_dispatch(BroadcastEvent, data, opts)
  end

  @doc """
  Creates and optionally dispatches an indexing status signal.

  ## Parameters

  - `file_path` - Path to the file being indexed
  - `status` - Current indexing status (required)
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/indexing`)
  - `:subject` - Custom subject for the signal
  - `:project_root` - Root directory of the project
  - `:triple_count` - Number of triples generated
  - `:error_message` - Error message (for failed operations)
  - `:duration_ms` - Duration in milliseconds

  ## Examples

      {:ok, signal} = Signals.indexing_status("lib/my_app.ex", :in_progress)

      {:ok, signal} = Signals.indexing_status(
        "lib/my_app.ex",
        :completed,
        triple_count: 42,
        duration_ms: 150
      )

      {:ok, signal} = Signals.indexing_status(
        "lib/invalid.ex",
        :failed,
        error_message: "Syntax error at line 10",
        duration_ms: 50
      )

  """
  @spec indexing_status(String.t(), atom(), Keyword.t()) :: signal_result()
  def indexing_status(file_path, status, opts \\ [])
      when is_binary(file_path) and is_atom(status) do
    data =
      %{
        file_path: file_path,
        status: status
      }
      |> maybe_put_project_root(opts)
      |> maybe_put_triple_count(opts)
      |> maybe_put_error_message(opts)
      |> maybe_put_duration_ms(opts)

    create_and_dispatch(IndexingStatus, data, opts)
  end

  @doc """
  Creates and optionally dispatches a chat request signal.

  ## Parameters

  - `message` - User message content
  - `opts` - Keyword list of options

  ## Options

  - `:dispatch` - Whether to broadcast to PubSub (default: `true`)
  - `:source` - Override default source (`/jido_coder/client`)
  - `:subject` - Custom subject for the signal
  - `:session_id` - Associated session ID (defaults to empty string)
  - `:user_id` - User identifier
  - `:context` - Additional conversation context map

  ## Examples

      {:ok, signal} = Signals.chat_request("Help me debug this function")

      {:ok, signal} = Signals.chat_request(
        "Explain this code",
        session_id: "session-123",
        user_id: "user-456",
        context: %{language: "elixir"}
      )

  """
  @spec chat_request(String.t(), Keyword.t()) :: signal_result()
  def chat_request(message, opts \\ []) when is_binary(message) do
    data =
      %{
        message: message,
        session_id: Keyword.get(opts, :session_id, ""),
        context: Keyword.get(opts, :context, %{})
      }
      |> maybe_put_user_id(opts)

    create_and_dispatch(ChatRequest, data, opts)
  end

  # Private helper for consistent signal creation and dispatch

  defp create_and_dispatch(signal_module, data, opts) do
    # Build signal options
    signal_opts =
      []
      |> maybe_put_source(opts)
      |> maybe_put_subject(opts)

    # Create the signal
    case signal_module.new(data, signal_opts) do
      {:ok, signal} = result ->
        # Dispatch if requested (default: true)
        if Keyword.get(opts, :dispatch, true) do
          dispatch_signal(signal)
        end

        result

      {:error, _reason} = error ->
        error
    end
  end

  defp dispatch_signal(signal) do
    # Broadcast to signal-type-specific topic
    PubSub.broadcast_signal(signal.type, signal)

    # For client-facing signals, also broadcast to client events
    if client_facing_signal?(signal.type) do
      PubSub.broadcast_client_event({:signal, signal})
    end

    :ok
  end

  defp client_facing_signal?("jido_coder.client." <> _), do: true
  defp client_facing_signal?("jido_coder.chat." <> _), do: true
  defp client_facing_signal?(_), do: false

  defp maybe_put_source(signal_opts, opts) do
    case Keyword.get(opts, :source) do
      nil -> signal_opts
      source -> Keyword.put(signal_opts, :source, source)
    end
  end

  defp maybe_put_subject(signal_opts, opts) do
    case Keyword.get(opts, :subject) do
      nil -> signal_opts
      subject -> Keyword.put(signal_opts, :subject, subject)
    end
  end

  # Data field helpers for optional fields

  defp maybe_put_session_id(data, opts) do
    case Keyword.get(opts, :session_id) do
      nil -> data
      session_id -> Map.put(data, :session_id, session_id)
    end
  end

  defp maybe_put_duration_ms(data, opts) do
    case Keyword.get(opts, :duration_ms) do
      nil -> data
      duration_ms -> Map.put(data, :duration_ms, duration_ms)
    end
  end

  defp maybe_put_user_id(data, opts) do
    case Keyword.get(opts, :user_id) do
      nil -> data
      user_id -> Map.put(data, :user_id, user_id)
    end
  end

  defp maybe_put_project_root(data, opts) do
    case Keyword.get(opts, :project_root) do
      nil -> data
      project_root -> Map.put(data, :project_root, project_root)
    end
  end

  defp maybe_put_triple_count(data, opts) do
    case Keyword.get(opts, :triple_count) do
      nil -> data
      triple_count -> Map.put(data, :triple_count, triple_count)
    end
  end

  defp maybe_put_error_message(data, opts) do
    case Keyword.get(opts, :error_message) do
      nil -> data
      error_message -> Map.put(data, :error_message, error_message)
    end
  end
end
