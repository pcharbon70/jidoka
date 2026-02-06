defmodule Jidoka.ClientEventsTest do
  use ExUnit.Case, async: true

  alias Jidoka.ClientEvents

  describe "event_types/0" do
    test "returns all defined event types" do
      types = ClientEvents.event_types()

      assert :llm_stream_chunk in types
      assert :llm_response in types
      assert :agent_status in types
      assert :analysis_complete in types
      assert :issue_found in types
      assert :tool_call in types
      assert :tool_result in types
      assert :context_updated in types
    end
  end

  describe "schema/1" do
    test "returns schema for llm_stream_chunk" do
      schema = ClientEvents.schema(:llm_stream_chunk)

      assert schema.required == [:content, :session_id]
      assert :chunk_index in schema.optional
      assert :is_final in schema.optional
    end

    test "returns schema for llm_response" do
      schema = ClientEvents.schema(:llm_response)

      assert schema.required == [:content, :session_id]
      assert :model in schema.optional
    end

    test "returns schema for agent_status" do
      schema = ClientEvents.schema(:agent_status)

      assert schema.required == [:agent_name, :status]
      assert :message in schema.optional
    end

    test "returns schema for analysis_complete" do
      schema = ClientEvents.schema(:analysis_complete)

      assert schema.required == [:session_id, :files_analyzed, :issues_found]
      assert :duration_ms in schema.optional
    end

    test "returns schema for issue_found" do
      schema = ClientEvents.schema(:issue_found)

      assert schema.required == [:session_id, :severity, :message]
      assert :file in schema.optional
    end

    test "returns schema for tool_call" do
      schema = ClientEvents.schema(:tool_call)

      assert schema.required == [:session_id, :tool_name, :tool_id, :parameters]
    end

    test "returns schema for tool_result" do
      schema = ClientEvents.schema(:tool_result)

      assert schema.required == [:session_id, :tool_id, :tool_name, :status]
      assert :result in schema.optional
    end

    test "returns schema for context_updated" do
      schema = ClientEvents.schema(:context_updated)

      assert schema.required == [:session_id]
      assert :project_path in schema.optional
    end

    test "returns nil for unknown event type" do
      assert ClientEvents.schema(:unknown_type) == nil
    end
  end

  describe "new/2" do
    test "creates valid llm_stream_chunk event" do
      assert {:ok, event} =
               ClientEvents.new(:llm_stream_chunk, %{
                 content: "Hello",
                 session_id: "session-123"
               })

      assert event.type == :llm_stream_chunk
      assert event.payload.content == "Hello"
      assert event.payload.session_id == "session-123"
      assert Map.has_key?(event.payload, :timestamp)
    end

    test "creates valid llm_response event" do
      assert {:ok, event} =
               ClientEvents.new(:llm_response, %{
                 content: "Full response",
                 session_id: "session-123",
                 model: "gpt-4"
               })

      assert event.type == :llm_response
      assert event.payload.content == "Full response"
      assert event.payload.model == "gpt-4"
    end

    test "creates valid agent_status event" do
      assert {:ok, event} =
               ClientEvents.new(:agent_status, %{
                 agent_name: "coordinator",
                 status: :ready
               })

      assert event.type == :agent_status
      assert event.payload.agent_name == "coordinator"
      assert event.payload.status == :ready
    end

    test "creates valid analysis_complete event" do
      assert {:ok, event} =
               ClientEvents.new(:analysis_complete, %{
                 session_id: "session-123",
                 files_analyzed: 10,
                 issues_found: 2
               })

      assert event.type == :analysis_complete
      assert event.payload.files_analyzed == 10
      assert event.payload.issues_found == 2
    end

    test "creates valid issue_found event" do
      assert {:ok, event} =
               ClientEvents.new(:issue_found, %{
                 session_id: "session-123",
                 severity: :error,
                 message: "Syntax error"
               })

      assert event.type == :issue_found
      assert event.payload.severity == :error
      assert event.payload.message == "Syntax error"
    end

    test "creates valid tool_call event" do
      assert {:ok, event} =
               ClientEvents.new(:tool_call, %{
                 session_id: "session-123",
                 tool_name: "read_file",
                 tool_id: "call-1",
                 parameters: %{path: "test.exs"}
               })

      assert event.type == :tool_call
      assert event.payload.tool_name == "read_file"
    end

    test "creates valid tool_result event" do
      assert {:ok, event} =
               ClientEvents.new(:tool_result, %{
                 session_id: "session-123",
                 tool_id: "call-1",
                 tool_name: "read_file",
                 status: :success,
                 result: %{content: "data"}
               })

      assert event.type == :tool_result
      assert event.payload.status == :success
    end

    test "creates valid context_updated event" do
      assert {:ok, event} =
               ClientEvents.new(:context_updated, %{
                 session_id: "session-123",
                 project_path: "/path/to/project"
               })

      assert event.type == :context_updated
      assert event.payload.project_path == "/path/to/project"
    end

    test "returns error for unknown event type" do
      assert {:error, {:unknown_event_type, :unknown}} =
               ClientEvents.new(:unknown, %{})
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_required_fields, missing}} =
               ClientEvents.new(:llm_stream_chunk, %{content: "Hello"})

      assert :session_id in missing
    end

    test "adds timestamp automatically" do
      assert {:ok, event} =
               ClientEvents.new(:agent_status, %{
                 agent_name: "coordinator",
                 status: :ready
               })

      assert Map.has_key?(event.payload, :timestamp)
      assert String.starts_with?(event.payload.timestamp, "20")
    end

    test "preserves existing timestamp" do
      custom_ts = "2024-01-01T00:00:00Z"

      assert {:ok, event} =
               ClientEvents.new(:agent_status, %{
                 agent_name: "coordinator",
                 status: :ready,
                 timestamp: custom_ts
               })

      assert event.payload.timestamp == custom_ts
    end
  end

  describe "new!/2" do
    test "creates event or raises" do
      event =
        ClientEvents.new!(:llm_stream_chunk, %{
          content: "Hello",
          session_id: "session-123"
        })

      assert event.type == :llm_stream_chunk
    end

    test "raises for invalid event" do
      assert_raise ArgumentError, fn ->
        ClientEvents.new!(:llm_stream_chunk, %{content: "Hello"})
      end
    end
  end

  describe "to_directive/1" do
    test "converts event to broadcast directive" do
      {:ok, event} =
        ClientEvents.new(:agent_status, %{
          agent_name: "coordinator",
          status: :ready
        })

      directive = ClientEvents.to_directive(event)

      assert directive.__struct__ == Jido.Agent.Directive.Emit
    end

    test "uses event type string for broadcast" do
      {:ok, event} =
        ClientEvents.new(:llm_stream_chunk, %{
          content: "Hello",
          session_id: "session-123"
        })

      directive = ClientEvents.to_directive(event)

      assert directive.signal.type == "jido_coder.client.broadcast"
      assert directive.signal.data.event_type == "llm_stream_chunk"
    end
  end

  describe "to_directive/2" do
    test "converts event to session-specific directive" do
      {:ok, event} =
        ClientEvents.new(:llm_stream_chunk, %{
          content: "Hello",
          session_id: "session-123"
        })

      directive = ClientEvents.to_directive(event, "session-456")

      assert directive.__struct__ == Jido.Agent.Directive.Emit
      # Should use session from parameter, not from payload
    end
  end

  describe "llm_stream_chunk/3" do
    test "creates llm_stream_chunk event" do
      assert {:ok, event} = ClientEvents.llm_stream_chunk("Hello", "session-123")

      assert event.type == :llm_stream_chunk
      assert event.payload.content == "Hello"
    end

    test "accepts optional fields" do
      assert {:ok, event} =
               ClientEvents.llm_stream_chunk(
                 "Hello",
                 "session-123",
                 chunk_index: 1,
                 is_final: true
               )

      assert event.payload.chunk_index == 1
      assert event.payload.is_final == true
    end
  end

  describe "llm_response/3" do
    test "creates llm_response event" do
      assert {:ok, event} = ClientEvents.llm_response("Full response", "session-123")

      assert event.type == :llm_response
      assert event.payload.content == "Full response"
    end

    test "accepts optional fields" do
      assert {:ok, event} =
               ClientEvents.llm_response(
                 "Full response",
                 "session-123",
                 model: "gpt-4",
                 tokens_used: 100
               )

      assert event.payload.model == "gpt-4"
      assert event.payload.tokens_used == 100
    end
  end

  describe "agent_status/3" do
    test "creates agent_status event" do
      assert {:ok, event} = ClientEvents.agent_status("coordinator", :ready)

      assert event.type == :agent_status
      assert event.payload.agent_name == "coordinator"
      assert event.payload.status == :ready
    end

    test "accepts optional message" do
      assert {:ok, event} =
               ClientEvents.agent_status(
                 "coordinator",
                 :busy,
                 message: "Processing..."
               )

      assert event.payload.message == "Processing..."
    end
  end

  describe "analysis_complete/4" do
    test "creates analysis_complete event" do
      assert {:ok, event} = ClientEvents.analysis_complete("session-123", 10, 2)

      assert event.type == :analysis_complete
      assert event.payload.files_analyzed == 10
      assert event.payload.issues_found == 2
    end

    test "accepts optional fields" do
      assert {:ok, event} =
               ClientEvents.analysis_complete(
                 "session-123",
                 10,
                 2,
                 duration_ms: 5000,
                 results: %{summary: "Done"}
               )

      assert event.payload.duration_ms == 5000
      assert event.payload.results == %{summary: "Done"}
    end
  end

  describe "issue_found/4" do
    test "creates issue_found event" do
      assert {:ok, event} =
               ClientEvents.issue_found(
                 "session-123",
                 :error,
                 "Syntax error"
               )

      assert event.type == :issue_found
      assert event.payload.severity == :error
      assert event.payload.message == "Syntax error"
    end

    test "accepts optional fields" do
      assert {:ok, event} =
               ClientEvents.issue_found(
                 "session-123",
                 :warning,
                 "Unused variable",
                 file: "test.exs",
                 line: 10,
                 suggestion: "Remove it"
               )

      assert event.payload.file == "test.exs"
      assert event.payload.line == 10
      assert event.payload.suggestion == "Remove it"
    end
  end

  describe "tool_call/5" do
    test "creates tool_call event" do
      assert {:ok, event} =
               ClientEvents.tool_call(
                 "session-123",
                 "read_file",
                 "call-1",
                 %{path: "test.exs"}
               )

      assert event.type == :tool_call
      assert event.payload.tool_name == "read_file"
      assert event.payload.tool_id == "call-1"
    end
  end

  describe "tool_result/5" do
    test "creates tool_result event with success" do
      assert {:ok, event} =
               ClientEvents.tool_result(
                 "session-123",
                 "call-1",
                 "read_file",
                 :success,
                 result: %{content: "data"}
               )

      assert event.type == :tool_result
      assert event.payload.status == :success
      assert event.payload.result == %{content: "data"}
    end

    test "creates tool_result event with error" do
      assert {:ok, event} =
               ClientEvents.tool_result(
                 "session-123",
                 "call-1",
                 "read_file",
                 :error,
                 error: "File not found"
               )

      assert event.type == :tool_result
      assert event.payload.status == :error
      assert event.payload.error == "File not found"
    end
  end

  describe "context_updated/2" do
    test "creates context_updated event" do
      assert {:ok, event} = ClientEvents.context_updated("session-123")

      assert event.type == :context_updated
      assert event.payload.session_id == "session-123"
    end

    test "accepts optional fields" do
      assert {:ok, event} =
               ClientEvents.context_updated(
                 "session-123",
                 project_path: "/path/to/project",
                 files_changed: ["test.exs", "lib/app.ex"]
               )

      assert event.payload.project_path == "/path/to/project"
      assert event.payload.files_changed == ["test.exs", "lib/app.ex"]
    end
  end
end
