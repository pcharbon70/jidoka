defmodule JidoCoderLib.SignalsTest do
  use ExUnit.Case, async: true

  alias JidoCoderLib.Signals
  alias JidoCoderLib.PubSub
  alias JidoCoderLib.Signals.{FileChanged, AnalysisComplete, BroadcastEvent, ChatRequest}

  describe "file_changed/3" do
    test "creates a valid file changed signal" do
      {:ok, signal} = Signals.file_changed("/path/to/file.ex", :updated)

      assert signal.type == "jido_coder.file.changed"
      assert signal.data.path == "/path/to/file.ex"
      assert signal.data.action == :updated
      assert signal.source == "/jido_coder/filesystem"
    end

    test "includes optional session_id" do
      {:ok, signal} =
        Signals.file_changed("/path/to/file.ex", :updated, session_id: "session-123")

      assert signal.data.session_id == "session-123"
    end

    test "includes optional metadata" do
      {:ok, signal} =
        Signals.file_changed(
          "/path/to/file.ex",
          :created,
          metadata: %{size: 1024, encoding: "utf-8"}
        )

      assert signal.data.metadata.size == 1024
      assert signal.data.metadata.encoding == "utf-8"
    end

    test "accepts all valid actions" do
      {:ok, signal1} = Signals.file_changed("/test.ex", :created)
      {:ok, signal2} = Signals.file_changed("/test.ex", :updated)
      {:ok, signal3} = Signals.file_changed("/test.ex", :deleted)

      assert signal1.data.action == :created
      assert signal2.data.action == :updated
      assert signal3.data.action == :deleted
    end

    test "accepts empty string path (semantic validation is app-level)" do
      # Jido Signal validates types, not semantic validity
      {:ok, signal} = Signals.file_changed("", :updated, dispatch: false)
      assert signal.data.path == ""
    end

    test "can override default source" do
      {:ok, signal} =
        Signals.file_changed("/test.ex", :updated, source: "/custom/source")

      assert signal.source == "/custom/source"
    end
  end

  describe "analysis_complete/3" do
    test "creates a valid analysis signal" do
      results = %{errors: [], warnings: ["unused var"]}

      {:ok, signal} = Signals.analysis_complete("credo", results)

      assert signal.type == "jido_coder.analysis.complete"
      assert signal.data.analysis_type == "credo"
      assert signal.data.results == results
      assert signal.source == "/jido_coder/analyzer"
    end

    test "includes optional duration_ms" do
      {:ok, signal} = Signals.analysis_complete("type_check", %{}, duration_ms: 150)

      assert signal.data.duration_ms == 150
    end

    test "includes optional session_id" do
      {:ok, signal} =
        Signals.analysis_complete("dialyzer", %{}, session_id: "session-456")

      assert signal.data.session_id == "session-456"
    end

    test "accepts complex result structures" do
      results = %{
        issues: [
          %{
            category: :warning,
            message: "Pattern match not exhaustive",
            line: 42
          }
        ],
        summary: %{total: 1, warnings: 1, errors: 0}
      }

      {:ok, signal} = Signals.analysis_complete("compiler", results)

      assert signal.data.results.summary.total == 1
    end

    test "accepts empty analysis_type (semantic validation is app-level)" do
      # Jido Signal validates types, not semantic validity
      {:ok, signal} = Signals.analysis_complete("", %{}, dispatch: false)
      assert signal.data.analysis_type == ""
    end
  end

  describe "broadcast_event/3" do
    test "creates a valid broadcast event signal" do
      {:ok, signal} = Signals.broadcast_event("llm_stream_chunk", %{content: "Hello"})

      assert signal.type == "jido_coder.client.broadcast"
      assert signal.data.event_type == "llm_stream_chunk"
      assert signal.data.payload == %{content: "Hello"}
      assert signal.source == "/jido_coder/coordinator"
    end

    test "includes optional session_id for targeted broadcasts" do
      {:ok, signal} =
        Signals.broadcast_event(
          "agent_status",
          %{status: :ready},
          session_id: "session-789"
        )

      assert signal.data.session_id == "session-789"
    end

    test "accepts complex payload structures" do
      payload = %{
        agent_name: "code_analyzer",
        status: :processing,
        progress: 0.65,
        metadata: %{files_processed: 13, total_files: 20}
      }

      {:ok, signal} = Signals.broadcast_event("agent_update", payload)

      assert signal.data.payload.progress == 0.65
      assert signal.data.payload.metadata.files_processed == 13
    end

    test "accepts empty event_type (semantic validation is app-level)" do
      # Jido Signal validates types, not semantic validity
      {:ok, signal} = Signals.broadcast_event("", %{}, dispatch: false)
      assert signal.data.event_type == ""
    end
  end

  describe "chat_request/2" do
    test "creates a valid chat request signal" do
      {:ok, signal} = Signals.chat_request("Help me debug this function")

      assert signal.type == "jido_coder.chat.request"
      assert signal.data.message == "Help me debug this function"
      assert signal.data.session_id == ""
      assert signal.source == "/jido_coder/client"
    end

    test "includes optional session_id" do
      {:ok, signal} = Signals.chat_request("Explain this code", session_id: "session-abc")

      assert signal.data.session_id == "session-abc"
    end

    test "includes optional user_id" do
      {:ok, signal} =
        Signals.chat_request("What does this do?", user_id: "user-xyz")

      assert signal.data.user_id == "user-xyz"
    end

    test "includes optional context" do
      {:ok, signal} =
        Signals.chat_request(
          "Refactor this",
          context: %{language: "elixir", file: "lib/app.ex"}
        )

      assert signal.data.context.language == "elixir"
      assert signal.data.context.file == "lib/app.ex"
    end

    test "accepts complex context structures" do
      context = %{
        language: "phoenix",
        framework_version: "1.7.0",
        selected_code: "def index() end",
        cursor_position: %{line: 5, column: 12}
      }

      {:ok, signal} = Signals.chat_request("Add error handling", context: context)

      assert signal.data.context.cursor_position.line == 5
    end

    test "accepts empty message (semantic validation is app-level)" do
      # Jido Signal validates types, not semantic validity
      {:ok, signal} = Signals.chat_request("", dispatch: false)
      assert signal.data.message == ""
    end
  end

  describe "individual signal modules" do
    test "FileChanged validates required fields" do
      assert {:ok, _signal} = FileChanged.new(%{path: "/test.ex", action: :updated})
      assert {:error, _reason} = FileChanged.new(%{path: "/test.ex"})
    end

    test "AnalysisComplete validates required fields" do
      assert {:ok, _signal} =
               AnalysisComplete.new(%{analysis_type: "test", results: %{}})

      assert {:error, _reason} = AnalysisComplete.new(%{analysis_type: "test"})
    end

    test "BroadcastEvent validates required fields" do
      assert {:ok, _signal} =
               BroadcastEvent.new(%{event_type: "test", payload: %{}})

      assert {:error, _reason} = BroadcastEvent.new(%{event_type: "test"})
    end

    test "ChatRequest validates required fields" do
      assert {:ok, _signal} = ChatRequest.new(%{message: "hello"})
      assert {:error, _reason} = ChatRequest.new(%{})
    end

    test "signals use default sources correctly" do
      {:ok, file_signal} = FileChanged.new(%{path: "/test", action: :updated})
      {:ok, analysis_signal} = AnalysisComplete.new(%{analysis_type: "test", results: %{}})
      {:ok, broadcast_signal} = BroadcastEvent.new(%{event_type: "test", payload: %{}})
      {:ok, chat_signal} = ChatRequest.new(%{message: "hello"})

      assert file_signal.source == "/jido_coder/filesystem"
      assert analysis_signal.source == "/jido_coder/analyzer"
      assert broadcast_signal.source == "/jido_coder/coordinator"
      assert chat_signal.source == "/jido_coder/client"
    end

    test "can override default sources" do
      {:ok, signal} =
        FileChanged.new(%{path: "/test.ex", action: :updated}, source: "/custom")

      assert signal.source == "/custom"
    end
  end

  describe "CloudEvents compliance" do
    test "all signals include required CloudEvents fields" do
      {:ok, file_signal} = Signals.file_changed("/test.ex", :updated, dispatch: false)
      {:ok, analysis_signal} = Signals.analysis_complete("test", %{}, dispatch: false)
      {:ok, broadcast_signal} = Signals.broadcast_event("test", %{}, dispatch: false)
      {:ok, chat_signal} = Signals.chat_request("test", dispatch: false)

      # Check specversion
      assert file_signal.specversion == "1.0.2"
      assert analysis_signal.specversion == "1.0.2"
      assert broadcast_signal.specversion == "1.0.2"
      assert chat_signal.specversion == "1.0.2"

      # Check id (UUID)
      assert is_binary(file_signal.id)
      assert String.length(file_signal.id) == 36

      # Check type
      assert is_binary(file_signal.type)
      assert is_binary(analysis_signal.type)
      assert is_binary(broadcast_signal.type)
      assert is_binary(chat_signal.type)

      # Check source
      assert is_binary(file_signal.source)
      assert String.starts_with?(file_signal.source, "/")
    end

    test "signals include auto-generated timestamps" do
      {:ok, signal} = Signals.file_changed("/test.ex", :updated, dispatch: false)

      assert is_binary(signal.time)
      # ISO 8601 format should be longer than 20 characters
      assert String.length(signal.time) > 20
    end
  end

  describe "PubSub dispatch integration" do
    setup do
      # Application is already started via test_helper.exs
      # Subscribe to signal topics
      PubSub.subscribe("jido.signal.jido_coder.file.changed")
      PubSub.subscribe("jido.signal.jido_coder.analysis.complete")
      PubSub.subscribe("jido.signal.jido_coder.client.broadcast")
      PubSub.subscribe("jido.signal.jido_coder.chat.request")

      :ok
    end

    test "file_changed signal broadcasts by default" do
      {:ok, signal} = Signals.file_changed("/test.ex", :updated)

      assert_receive({_sender, ^signal}, 100)
    after
      PubSub.unsubscribe("jido.signal.jido_coder.file.changed")
    end

    test "analysis_complete signal broadcasts by default" do
      results = %{score: 95}
      {:ok, signal} = Signals.analysis_complete("quality", results)

      assert_receive({_sender, ^signal}, 100)
    after
      PubSub.unsubscribe("jido.signal.jido_coder.analysis.complete")
    end

    test "broadcast_event signal broadcasts by default" do
      {:ok, signal} = Signals.broadcast_event("test_event", %{data: "value"})

      assert_receive({_sender, ^signal}, 100)
    after
      PubSub.unsubscribe("jido.signal.jido_coder.client.broadcast")
    end

    test "chat_request signal broadcasts by default" do
      {:ok, signal} = Signals.chat_request("Hello, AI!")

      assert_receive({_sender, ^signal}, 100)
    after
      PubSub.unsubscribe("jido.signal.jido_coder.chat.request")
    end

    test "signals can be created without dispatching" do
      {:ok, signal} = Signals.file_changed("/test.ex", :updated, dispatch: false)

      refute_receive({_sender, ^signal}, 50)
    after
      PubSub.unsubscribe("jido.signal.jido_coder.file.changed")
    end
  end

  describe "client event broadcasting" do
    setup do
      # Application is already started via test_helper.exs
      PubSub.subscribe(PubSub.client_events_topic())

      on_exit(fn ->
        PubSub.unsubscribe(PubSub.client_events_topic())
      end)

      :ok
    end

    test "client-facing signals broadcast to client events topic" do
      {:ok, signal} = Signals.broadcast_event("llm_stream", %{content: "test"})

      # Client-facing signals should also broadcast to client events
      assert_receive({_sender, {:signal, ^signal}}, 100)
    end

    test "chat_request signals broadcast to client events topic" do
      {:ok, signal} = Signals.chat_request("test message")

      assert_receive({_sender, {:signal, ^signal}}, 100)
    end

    test "non-client-facing signals do not broadcast to client events" do
      Signals.file_changed("/test.ex", :updated)

      # File changed signals are not client-facing
      refute_receive({_sender, {:signal, %{type: "jido_coder.file.changed"}}}, 50)
    end
  end
end
