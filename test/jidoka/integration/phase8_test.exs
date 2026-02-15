defmodule Jidoka.Integration.Phase8Test do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration tests for Phase 8: Client API & Protocols.

  These tests verify that all Phase 8 components work together correctly:
  - Client API workflow
  - Event delivery
  - MCP integration
  - Phoenix Channels communication
  - A2A Gateway communication
  - Tool calling
  - Complete conversation flows
  - System fault tolerance

  Tests use async: false due to shared state and event ordering requirements.
  """

  alias Jidoka.{Client, ClientEvents, Messaging, PubSub}
  alias Jidoka.Agents.{SessionManager, ContextManager, LLMOrchestrator}
  alias Jidoka.Tools.Registry
  alias Jido.Signal

  # ============================================================================
  # Setup and Teardown
  # ============================================================================

  setup do
    # Ensure we start with a clean state
    session_id = "integration-test-#{System.unique_integer([:positive, :monotonic])}"

    # Subscribe to client events for this test
    PubSub.subscribe_client_events()

    on_exit(fn ->
      # Clean up any created sessions
      Client.terminate_session(session_id)
      # Flush any remaining messages
      flush_messages()
    end)

    %{session_id: session_id}
  end

  # ============================================================================
  # Client API Workflow Tests
  # ============================================================================

  describe "Client API Workflow" do
    test "client can create and manage sessions", %{session_id: session_id} do
      # Create a session
      assert {:ok, created_id} = Client.create_session(metadata: %{test: "integration"})
      assert is_binary(created_id)

      # List sessions should include the new session
      sessions = Client.list_sessions()
      assert length(sessions) > 0

      # Get session info
      assert {:ok, info} = Client.get_session_info(created_id)
      assert info.session_id == created_id
      assert info.status in [:active, :idle]

      # Terminate session
      assert :ok = Client.terminate_session(created_id)

      # Session should no longer be in list
      :timer.sleep(100)
      assert {:error, :not_found} = Client.get_session_info(created_id)
    end

    test "client can send messages and receive history", %{session_id: session_id} do
      # Create session
      {:ok, session_id} = Client.create_session()

      # Subscribe to session events
      :ok = Client.subscribe_to_session(session_id)

      # Send a message
      assert :ok = Client.send_message(session_id, :user, "Hello, world!")

      # Should receive conversation_added event (wrapped in {from, message})
      assert_receive {_from,
                      {:conversation_added,
                       %{session_id: ^session_id, role: :user, content: "Hello, world!"}}},
                     500

      # Clean up
      Client.terminate_session(session_id)
    end

    test "client can list tools", _context do
      tools = Registry.list_tools()
      assert is_list(tools)
      assert length(tools) >= 5

      # Check that core tools are present
      tool_names = Enum.map(tools, & &1.name)
      assert "read_file" in tool_names
      assert "list_files" in tool_names
      assert "search_code" in tool_names
      assert "query_codebase" in tool_names
      assert "get_definition" in tool_names
    end

    test "client can find specific tool", _context do
      assert {:ok, tool} = Registry.find_tool("read_file")
      assert tool.name == "read_file"
      assert tool.category == "filesystem"
      assert is_binary(tool.description)
      assert is_list(tool.schema)

      # Non-existent tool
      assert {:error, :not_found} = Registry.find_tool("nonexistent_tool")
    end

    test "client can filter tools by category", _context do
      filesystem_tools = Registry.list_tools(category: "filesystem")
      assert length(filesystem_tools) >= 2

      tool_names = Enum.map(filesystem_tools, & &1.name)
      assert "read_file" in tool_names
      assert "list_files" in tool_names
    end

    test "client can get tool categories", _context do
      categories = Registry.categories()
      assert is_list(categories)
      assert "filesystem" in categories
      assert "search" in categories
      assert "analysis" in categories
    end

    test "client can check tool existence", _context do
      assert Registry.tool_exists?("read_file")
      refute Registry.tool_exists?("fake_tool")
    end
  end

  # ============================================================================
  # Event Delivery Tests
  # ============================================================================

  describe "Event Delivery" do
    test "llm_stream_chunk events are delivered", %{session_id: session_id} do
      # Create session and subscribe
      {:ok, session_id} = Client.create_session()
      :ok = Client.subscribe_to_session(session_id)

      # Create and broadcast an llm_stream_chunk event
      {:ok, event} = ClientEvents.llm_stream_chunk("Hello, world!", session_id)
      directive = ClientEvents.to_directive(event, session_id)

      # Dispatch the event
      Jidoka.PubSub.broadcast(
        Jidoka.PubSub.session_topic(session_id),
        {:llm_stream_chunk, event.payload}
      )

      # Should receive the event (wrapped in {from, message} tuple)
      assert_receive {_from, {:llm_stream_chunk, payload}}, 500
      assert payload.content == "Hello, world!"
      assert payload.session_id == session_id

      Client.terminate_session(session_id)
    end

    test "llm_response events are delivered", %{session_id: session_id} do
      {:ok, session_id} = Client.create_session()
      :ok = Client.subscribe_to_session(session_id)

      # Create and broadcast llm_response event
      {:ok, event} =
        ClientEvents.llm_response("Complete response", session_id,
          model: "gpt-4",
          tokens_used: 100
        )

      topic = Jidoka.PubSub.session_topic(session_id)
      Jidoka.PubSub.broadcast(topic, {:llm_response, event.payload})

      assert_receive {_from, {:llm_response, payload}}, 500
      assert payload.content == "Complete response"
      assert payload.model == "gpt-4"
      assert payload.tokens_used == 100

      Client.terminate_session(session_id)
    end

    test "agent_status events are delivered", _context do
      # Create agent status event
      {:ok, event} = ClientEvents.agent_status("coordinator", :ready, message: "Ready for work")

      # Broadcast to client events topic
      Jidoka.PubSub.broadcast_client_event({:agent_status, event.payload})

      assert_receive {_from, {:agent_status, payload}}, 500
      assert payload.agent_name == "coordinator"
      assert payload.status == :ready
      assert payload.message == "Ready for work"
    end

    test "tool_call and tool_result events are delivered", %{session_id: session_id} do
      {:ok, session_id} = Client.create_session()
      :ok = Client.subscribe_to_session(session_id)

      # Tool call event
      {:ok, call_event} =
        ClientEvents.tool_call(session_id, "read_file", "tool-123", %{file_path: "test.ex"})

      topic = Jidoka.PubSub.session_topic(session_id)
      Jidoka.PubSub.broadcast(topic, {:tool_call, call_event.payload})

      assert_receive {_from, {:tool_call, call_payload}}, 500
      assert call_payload.tool_name == "read_file"
      assert call_payload.tool_id == "tool-123"

      # Tool result event
      {:ok, result_event} =
        ClientEvents.tool_result(session_id, "tool-123", "read_file", :success,
          result: %{content: "file content"}
        )

      Jidoka.PubSub.broadcast(topic, {:tool_result, result_event.payload})

      assert_receive {_from, {:tool_result, result_payload}}, 500
      assert result_payload.tool_id == "tool-123"
      assert result_payload.status == :success

      Client.terminate_session(session_id)
    end

    test "session_created and session_terminated events are delivered", _context do
      # Already subscribed in setup

      # Create a session
      {:ok, session_id} = Client.create_session(metadata: %{test: "lifecycle"})

      # Should receive session_created event (wrapped)
      assert_receive {_from, {:session_created, payload}}, 500
      assert payload.session_id == session_id

      # Terminate the session
      :ok = Client.terminate_session(session_id)

      # Should receive session_terminated event (wrapped)
      assert_receive {_from, {:session_terminated, payload}}, 500
      assert payload.session_id == session_id
    end
  end

  # ============================================================================
  # Tool Calling Tests
  # ============================================================================

  describe "Tool Calling" do
    test "tools have valid schemas", _context do
      tools = Registry.list_tools()

      Enum.each(tools, fn tool ->
        assert is_binary(tool.name), "Tool name must be a string"
        assert is_atom(tool.module), "Tool module must be an atom"
        assert is_binary(tool.description), "Tool description must be a string"
        assert is_list(tool.schema), "Tool schema must be a list"
      end)
    end

    test "tool schema has required fields", _context do
      # Check tool module directly for schema
      # Jido.Action generates a schema/0 function
      schema = Jidoka.Tools.ReadFile.schema()

      # Check schema has file_path parameter (schema is a keyword list)
      schema_keys = Keyword.keys(schema)
      assert :file_path in schema_keys

      # Check that file_path is required
      file_path_spec = Keyword.get(schema, :file_path)
      assert is_list(file_path_spec)
      assert Keyword.get(file_path_spec, :required) == true
    end

    test "tools can be converted to OpenAI format", _context do
      {:ok, tool} = Registry.find_tool("read_file")

      schema = Jidoka.Tools.Schema.to_openai_schema(tool.module)

      assert is_map(schema)
      assert schema.name == "read_file"
      assert is_binary(schema.description)
      assert is_map(schema.parameters)
    end

    test "all tools generate valid OpenAI schemas", _context do
      tools = Registry.list_tools()

      Enum.each(tools, fn tool ->
        schema = Jidoka.Tools.Schema.to_openai_schema(tool.module)

        # Verify schema structure
        assert is_map(schema), "Schema for #{tool.name} should be a map"
        assert is_binary(schema.name), "Schema name for #{tool.name} should be a string"

        assert is_binary(schema.description),
               "Schema description for #{tool.name} should be a string"

        assert is_map(schema.parameters), "Schema parameters for #{tool.name} should be a map"

        # Verify parameters structure
        assert is_map(schema.parameters.properties),
               "Schema properties for #{tool.name} should be a map"
      end)
    end
  end

  # ============================================================================
  # LLM Orchestrator Tests
  # ============================================================================

  describe "LLM Orchestrator" do
    test "LLMOrchestrator agent starts and registers", _context do
      # Check if the agent is registered
      pid = Jido.whereis(Jidoka.Jido, "llm_orchestrator-main")
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "LLMOrchestrator has signal routes", _context do
      routes = LLMOrchestrator.signal_routes()
      assert is_list(routes)
      assert length(routes) > 0
    end

    test "LLMOrchestrator can handle tool history", _context do
      session_id = "history-test-#{System.unique_integer()}"

      # Initially should be empty or not found
      result = LLMOrchestrator.get_tool_history(session_id)
      assert {:ok, history} = result
      assert is_list(history)

      # Clear should succeed
      assert :ok = LLMOrchestrator.clear_tool_history(session_id)
    end
  end

  # ============================================================================
  # Session Manager Tests
  # ============================================================================

  describe "Session Manager" do
    test "sessions can be created and listed", _context do
      {:ok, session_id} = SessionManager.create_session(metadata: %{test: "integration"})

      sessions = SessionManager.list_sessions()
      assert length(sessions) > 0

      found = Enum.find(sessions, fn s -> s.session_id == session_id end)
      assert found != nil

      # Cleanup
      SessionManager.terminate_session(session_id)
    end

    test "session info can be retrieved", _context do
      {:ok, session_id} = SessionManager.create_session(metadata: %{project: "test-project"})

      {:ok, info} = SessionManager.get_session_info(session_id)
      assert info.session_id == session_id
      assert info.status in [:active, :idle]
      assert info.metadata.project == "test-project"

      SessionManager.terminate_session(session_id)
    end

    test "session can be terminated", _context do
      {:ok, session_id} = SessionManager.create_session()

      assert :ok = SessionManager.terminate_session(session_id)

      # Session should have terminated status
      {:ok, info} = SessionManager.get_session_info(session_id)
      assert info.status == :terminated
    end
  end

  # ============================================================================
  # Context Manager Tests
  # ============================================================================

  describe "Context Manager" do
    test "messages can be added to session", _context do
      {:ok, session_id} = Client.create_session()

      assert :ok = ContextManager.add_message(session_id, :user, "Hello")
      assert :ok = ContextManager.add_message(session_id, :assistant, "Hi there!")

      {:ok, messages} = ContextManager.get_conversation_history(session_id)
      assert length(messages) == 2
      assert Enum.at(messages, 0).role == :user
      assert Enum.at(messages, 1).role == :assistant

      Client.terminate_session(session_id)
    end

    test "conversation can be cleared", _context do
      {:ok, session_id} = Client.create_session()

      :ok = ContextManager.add_message(session_id, :user, "Test message")
      {:ok, messages} = ContextManager.get_conversation_history(session_id)
      assert length(messages) == 1

      :ok = ContextManager.clear_conversation(session_id)
      {:ok, messages} = ContextManager.get_conversation_history(session_id)
      assert length(messages) == 0

      Client.terminate_session(session_id)
    end
  end

  # ============================================================================
  # Signal Routing Tests
  # ============================================================================

  describe "Signal Routing" do
    test "signals can be created and dispatched", _context do
      {:ok, session_id} = Client.create_session()
      :ok = Client.subscribe_to_session(session_id)

      # Create a test signal
      signal =
        Signal.new!(
          "jido.session.message",
          %{
            session_id: session_id,
            role: :user,
            content: "Test message"
          },
          %{source: "/integration-test"}
        )

      # Verify signal structure
      assert signal.type == "jido.session.message"
      assert signal.data.session_id == session_id

      # Dispatch via PubSub to session topic
      result =
        Jido.Signal.Dispatch.dispatch(
          signal,
          {:pubsub,
           [target: Jidoka.PubSub.pubsub_name(), topic: PubSub.session_topic(session_id)]}
        )

      assert :ok = result

      Client.terminate_session(session_id)
    end

    test "signals have correct structure", _context do
      signal =
        Signal.new!(
          "test.signal",
          %{test_data: "value"},
          %{source: "/test"}
        )

      assert signal.type == "test.signal"
      assert is_map(signal.data)
      assert signal.data.test_data == "value"
    end
  end

  # ============================================================================
  # PubSub Tests
  # ============================================================================

  describe "PubSub Integration" do
    test "pubsub is running", _context do
      assert Process.whereis(Phoenix.PubSub) != nil
    end

    test "client can subscribe to session topics", %{session_id: session_id} do
      {:ok, session_id} = Client.create_session()
      topic = PubSub.session_topic(session_id)

      # Subscribe
      :ok = PubSub.subscribe(self(), topic)

      # Broadcast
      PubSub.broadcast(topic, {:test_event, %{data: "test"}})

      # Should receive (events come wrapped in {from, message})
      assert_receive {_from, {:test_event, %{data: "test"}}}, 500

      Client.terminate_session(session_id)
    end

    test "multiple subscribers receive events", _context do
      {:ok, session_id} = Client.create_session()
      topic = PubSub.session_topic(session_id)

      parent = self()

      # Spawn multiple subscribers
      subscribers =
        Enum.map(1..3, fn i ->
          spawn(fn ->
            PubSub.subscribe(self(), topic)
            send(parent, {:ready, i})

            receive do
              {_from, {:test_event, _}} -> send(parent, {:received, i})
            end
          end)
        end)

      # Wait for all to be ready
      Enum.each(1..3, fn i -> assert_receive {:ready, ^i}, 500 end)

      # Broadcast
      PubSub.broadcast(topic, {:test_event, %{data: "test"}})

      # All should receive
      Enum.each(1..3, fn i -> assert_receive {:received, ^i}, 500 end)

      # Clean up
      Enum.each(subscribers, fn pid -> Process.exit(pid, :kill) end)
      Client.terminate_session(session_id)
    end
  end

  # ============================================================================
  # Complete Conversation Flow Tests
  # ============================================================================

  describe "Complete Conversation Flow" do
    test "full conversation workflow", %{session_id: session_id} do
      # Create session
      {:ok, session_id} = Client.create_session(metadata: %{test: "full_flow"})

      # Subscribe to events
      :ok = Client.subscribe_to_session(session_id)

      # Send user message
      :ok = Client.send_message(session_id, :user, "What files are in lib/jidoka?")

      # Verify message was added (event is wrapped in {from, message})
      assert_receive {_from,
                      {:conversation_added,
                       %{role: :user, content: "What files are in lib/jidoka?"}}},
                     500

      # Check conversation history
      {:ok, messages} = Messaging.list_session_messages(session_id)
      assert length(messages) >= 1

      # Get session info
      {:ok, info} = Client.get_session_info(session_id)
      assert info.session_id == session_id

      # Terminate
      :ok = Client.terminate_session(session_id)

      # Should receive terminated event (wrapped)
      assert_receive {_from, {:session_terminated, %{session_id: ^session_id}}}, 500
    end

    test "conversation with tool inquiry", %{session_id: session_id} do
      {:ok, session_id} = Client.create_session()

      # Send message asking about tools
      :ok = Client.send_message(session_id, :user, "What tools are available?")

      {:ok, messages} = Messaging.list_session_messages(session_id)
      assert length(messages) == 1

      # Verify tools exist
      tools = Registry.list_tools()
      assert length(tools) >= 5

      Client.terminate_session(session_id)
    end
  end

  # ============================================================================
  # Fault Tolerance Tests
  # ============================================================================

  describe "Fault Tolerance" do
    test "system recovers from non-existent session access", _context do
      fake_session_id = "fake-session-#{System.unique_integer()}"

      # Should not crash
      assert {:error, :not_found} = Client.get_session_info(fake_session_id)
      assert {:error, _} = Client.send_message(fake_session_id, :user, "test")
    end

    test "system handles duplicate session termination", _context do
      {:ok, session_id} = Client.create_session()

      # First termination
      assert :ok = Client.terminate_session(session_id)

      # Second termination should handle gracefully
      # May return :ok, {:error, :not_found}, or {:error, :invalid_transition}
      result = Client.terminate_session(session_id)
      assert result in [:ok, {:error, :not_found}, {:error, :invalid_transition}]
    end

    test "system handles invalid event creation", _context do
      # Missing required fields
      assert {:error, {:missing_required_fields, _}} =
               ClientEvents.new(:llm_stream_chunk, %{content: "test"})

      # Unknown event type
      assert {:error, {:unknown_event_type, :fake_event}} =
               ClientEvents.new(:fake_event, %{test: "data"})
    end

    test "pubsub handles unsubscribed topics", _context do
      # Broadcast to a topic with no subscribers should not crash
      topic = "fake-topic-#{System.unique_integer()}"
      PubSub.broadcast(topic, {:test, :data})

      # Should still be running
      assert Process.whereis(Phoenix.PubSub) != nil
    end
  end

  # ============================================================================
  # Integration Tests for Protocol Components
  # ============================================================================

  describe "Protocol Components" do
    test "protocol supervisor is running", _context do
      assert Process.whereis(Jidoka.ProtocolSupervisor) != nil
    end

    test "MCP module is available", _context do
      # Check that the MCP module exists
      assert Code.ensure_loaded?(Jidoka.Protocol.MCP)
      # The MCP module has RequestManager
      assert Code.ensure_loaded?(Jidoka.Protocol.MCP.RequestManager)
    end

    test "Phoenix protocol module is available", _context do
      # Check that the Phoenix protocol client module exists
      assert Code.ensure_loaded?(Jidoka.Protocol.Phoenix.Client)
      # The client module has start_link/1 function
      assert function_exported?(Jidoka.Protocol.Phoenix.Client, :start_link, 1)
    end

    test "A2A protocol module is available", _context do
      # Check that the A2A gateway module exists
      assert Code.ensure_loaded?(Jidoka.Protocol.A2A.Gateway)
      # The gateway module has __struct__ function
      assert function_exported?(Jidoka.Protocol.A2A.Gateway, :__struct__, 0)
    end
  end

  # ============================================================================
  # End-to-End Tool Execution Tests
  # ============================================================================

  describe "End-to-End Tool Execution" do
    test "ListFiles tool can be executed", _context do
      {:ok, tool} = Registry.find_tool("list_files")

      # Execute via Jido.Exec
      import Jido.Exec

      {:ok, result, []} = run(tool.module, %{path: "lib/jidoka/tools"})
      assert is_map(result)
      assert Map.has_key?(result, :files) or Map.has_key?(result, :result)
    end

    test "ReadFile tool can be executed", _context do
      {:ok, tool} = Registry.find_tool("read_file")

      import Jido.Exec

      # Use a file that exists
      {:ok, result, []} =
        run(tool.module, %{
          file_path: "lib/jidoka/tools/registry.ex",
          offset: 1,
          limit: 10
        })

      assert is_map(result)
    end

    test "SearchCode tool can be executed", _context do
      {:ok, tool} = Registry.find_tool("search_code")

      import Jido.Exec

      {:ok, result, []} =
        run(tool.module, %{
          pattern: "defmodule",
          path: "lib/jidoka/tools",
          max_results: 5
        })

      assert is_map(result)
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end
end
