# Phase 8: Client API & Protocols

This phase implements the complete Client API and protocol integrations (MCP, Phoenix Channels, A2A). The Client API provides a well-defined interface for any client type to interact with the core, while the protocol layer enables integration with external tools and services.

---

## 8.1 Client API Module

- [ ] **Task 8.1** Implement the complete Client API

Create a comprehensive API module for clients to interact with the system.

- [ ] 8.1.1 Expand `JidoCoderLib.Client` with full API surface
- [ ] 8.1.2 Implement `send_message/3` for sending messages to sessions
- [ ] 8.1.3 Implement `analyze_code/3` for code analysis requests
- [ ] 8.1.4 Implement `get_context/2` for context retrieval
- [ ] 8.1.5 Implement `list_tools/0` for tool discovery
- [ ] 8.1.6 Implement `get_tool_schema/2` for tool details
- [ ] 8.1.7 Implement `subscribe_to_events/1` for event subscriptions
- [ ] 8.1.8 Implement `unsubscribe_from_events/1` for cleanup

**Unit Tests for Section 8.1:**
- Test send_message routes to correct session
- Test analyze_code triggers analysis
- Test get_context returns session context
- Test list_tools returns available tools
- Test get_tool_schema returns tool details
- Test subscribe_to_events receives events
- Test unsubscribe stops event delivery

---

## 8.2 Event API Definition

- [ ] **Task 8.2** Define and document all client events

Establish the complete event protocol for clients.

- [ ] 8.2.1 Document `{:llm_stream_chunk, ...}` event format
- [ ] 8.2.2 Document `{:llm_response, ...}` event format
- [ ] 8.2.3 Document `{:agent_status, ...}` event format
- [ ] 8.2.4 Document `{:analysis_complete, ...}` event format
- [ ] 8.2.5 Document `{:issue_found, ...}` event format
- [ ] 8.2.6 Document `{:tool_call, ...}` and `{:tool_result, ...}` events
- [ ] 8.2.7 Document `{:context_updated, ...}` event format
- [ ] 8.2.8 Document `{:session_created, ...}` and `{:session_terminated, ...}` events
- [ ] 8.2.9 Create event format validation

**Unit Tests for Section 8.2:**
- Test each event format is documented
- Test event format validation works
- Test events include all required fields
- Test events conform to documented schema

---

## 8.3 MCP Client Integration

- [ ] **Task 8.3** Implement MCP (Model Context Protocol) client

Create an MCP client for integrating with external MCP servers.

- [ ] 8.3.1 Create `JidoCoderLib.Protocol.MCP.Client` module
- [ ] 8.3.2 Implement `connect/2` for server connections
- [ ] 8.3.3 Implement `list_tools/1` for discovering server tools
- [ ] 8.3.4 Implement `call_tool/3` for executing tools
- [ ] 8.3.5 Create `MCP.Supervisor` for connection management
- [ ] 8.3.6 Configure MCP servers from config
- [ ] 8.3.7 Add connection retry logic
- [ ] 8.3.8 Map MCP tools to Jido Actions

**Unit Tests for Section 8.3:**
- Test MCP client connects to server
- Test list_tools retrieves available tools
- Test call_tool executes tools correctly
- Test supervisor manages connections
- Test retry logic works on failure
- Test MCP tools map to Jido Actions

---

## 8.4 Phoenix Channels Client

- [ ] **Task 8.4** Implement Phoenix Channels client

Create a client for connecting to remote Phoenix Channels.

- [ ] 8.4.1 Create `JidoCoderLib.Protocol.Phoenix.Connection` module
- [ ] 8.4.2 Implement `start_link/1` for connection initialization
- [ ] 8.4.3 Implement `join_channel/3` for joining channels
- [ ] 8.4.4 Implement `push_event/3` for sending events
- [ ] 8.4.5 Handle incoming messages and route to agents
- [ ] 8.4.6 Add reconnection logic
- [ ] 8.4.7 Add to ProtocolSupervisor

**Unit Tests for Section 8.4:**
- Test Phoenix client connects successfully
- Test join_channel joins channels
- Test push_event sends events
- Test incoming messages are routed correctly
- Test reconnection works on disconnect

---

## 8.5 A2A Gateway

- [ ] **Task 8.5** Implement Agent-to-Agent (A2A) gateway

Create a gateway for cross-framework agent communication.

- [ ] 8.5.1 Create `JidoCoderLib.Protocol.A2A.Gateway` module
- [ ] 8.5.2 Implement `discover_agent/2` for agent discovery
- [ ] 8.5.3 Implement `send_message/3` for agent communication
- [ ] 8.5.4 Implement JSON-RPC 2.0 request handling
- [ ] 8.5.5 Handle incoming A2A messages
- [ ] 8.5.6 Add agent card publication
- [ ] 8.5.7 Add to ProtocolSupervisor

**Unit Tests for Section 8.5:**
- Test discover_agent retrieves agent cards
- Test send_message delivers messages
- Test JSON-RPC requests are formatted correctly
- Test incoming A2A messages are handled
- Test agent card is published

---

## 8.6 Protocol Supervisor

- [ ] **Task 8.6** Create ProtocolSupervisor for protocol management

Supervise all protocol connections and handle their lifecycle.

- [ ] 8.6.1 Create `JidoCoderLib.ProtocolSupervisor` module
- [ ] 8.6.2 Configure `:one_for_one` strategy
- [ ] 8.6.3 Add MCP client children dynamically
- [ ] 8.6.4 Add Phoenix connection children dynamically
- [ ] 8.6.5 Add A2A gateway child
- [ ] 8.6.6 Add to Application supervision tree
- [ ] 8.6.7 Implement protocol health checks

**Unit Tests for Section 8.6:**
- Test ProtocolSupervisor starts children
- Test one_for_one strategy works
- Test children can be added dynamically
- Test health checks report status
- Test supervisor stops cleanly

---

## 8.7 Tool Definitions

- [ ] **Task 8.7** Implement core tools as Jido Actions

Define the standard tools that the LLM can invoke.

- [ ] 8.7.1 Create `JidoCoderLib.Tools.ReadFile` action
- [ ] 8.7.2 Create `JidoCoderLib.Tools.SearchCode` action
- [ ] 8.7.3 Create `JidoCoderLib.Tools.AnalyzeFunction` action
- [ ] 8.7.4 Create `JidoCoderLib.Tools.ListFiles` action
- [ ] 8.7.5 Create `JidoCoderLib.Tools.GetDefinition` action
- [ ] 8.7.6 Create `JidoCoderLib.Tools.Registry` for tool discovery
- [ ] 8.7.7 Implement tool schema generation for LLM

**Unit Tests for Section 8.7:**
- Test ReadFile reads file contents
- Test SearchCode finds matching code
- Test AnalyzeFunction analyzes functions
- Test ListFiles lists directory contents
- Test GetDefinition finds definitions
- Test Registry returns available tools
- Test tool schema generates correct format

---

## 8.8 LLM Agent with Tool Calling

- [ ] **Task 8.8** Complete LLMOrchestrator with tool calling

Finalize the LLM agent with full tool calling support.

- [ ] 8.8.1 Implement tool selection and calling logic
- [ ] 8.8.2 Handle tool results and feed back to LLM
- [ ] 8.8.3 Support multi-step tool calling
- [ ] 8.8.4 Add streaming response support
- [ ] 8.8.5 Integrate with conversation logging
- [ ] 8.8.6 Add error handling for tool failures

**Unit Tests for Section 8.8:**
- Test LLM can select tools
- Test tools are executed with correct parameters
- Test tool results are fed back to LLM
- Test multi-step calling works
- Test streaming delivers chunks
- Test errors are handled gracefully

---

## 8.9 Phase 8 Integration Tests ✅

Comprehensive integration tests verifying the complete system.

- [ ] 8.9.1 Test full client API workflow
- [ ] 8.9.2 Test event delivery to clients
- [ ] 8.9.3 Test MCP tool integration
- [ ] 8.9.4 Test Phoenix Channels communication
- [ ] 8.9.5 Test A2A agent communication
- [ ] 8.9.6 Test tool calling end-to-end
- [ ] 8.9.7 Test complete conversation flow
- [ ] 8.9.8 Test system fault tolerance

**Expected Test Coverage:**
- Client API tests: 30 tests
- Event API tests: 15 tests
- MCP Integration tests: 20 tests
- Phoenix Channels tests: 15 tests
- A2A Gateway tests: 15 tests
- Tool Definitions tests: 25 tests
- LLM Agent tests: 30 tests

**Total: 150 integration tests**

---

## Success Criteria

1. **Client API**: Complete API for all client operations
2. **Event Protocol**: All events documented and validated
3. **MCP Support**: External MCP servers can be integrated
4. **Phoenix Channels**: Remote channel communication works
5. **A2A Gateway**: Cross-framework agent communication works
6. **Tool Calling**: LLM can invoke tools correctly
7. **Streaming**: LLM responses stream to clients
8. **Test Coverage**: All API and protocol modules have 80%+ test coverage

---

## Critical Files

**New Files:**
- `lib/jido_coder_lib/client.ex` - Complete client API
- `lib/jido_coder_lib/client_events.ex` - Event documentation
- `lib/jido_coder_lib/protocol/mcp/client.ex` - MCP client
- `lib/jido_coder_lib/protocol/mcp/supervisor.ex` - MCP supervisor
- `lib/jido_coder_lib/protocol/phoenix/connection.ex` - Phoenix client
- `lib/jido_coder_lib/protocol/a2a/gateway.ex` - A2A gateway
- `lib/jido_coder_lib/protocol_supervisor.ex` - Protocol supervisor
- `lib/jido_coder_lib/tools/read_file.ex` - ReadFile action
- `lib/jido_coder_lib/tools/search_code.ex` - SearchCode action
- `lib/jido_coder_lib/tools/analyze_function.ex` - AnalyzeFunction action
- `lib/jido_coder_lib/tools/list_files.ex` - ListFiles action
- `lib/jido_coder_lib/tools/get_definition.ex` - GetDefinition action
- `lib/jido_coder_lib/tools/registry.ex` - Tool registry
- `test/jido_coder_lib/client_test.exs`
- `test/jido_coder_lib/protocol/mcp_test.exs`
- `test/jido_coder_lib/protocol/phoenix_test.exs`
- `test/jido_coder_lib/protocol/a2a_test.exs`
- `test/jido_coder_lib/tools_test.exs`
- `test/jido_coder_lib/integration/phase8_test.exs`

**Modified Files:**
- `lib/jido_coder_lib/application.ex` - Add ProtocolSupervisor
- `lib/jido_coder_lib/agents/llm_orchestrator.ex` - Complete tool calling
- `lib/jido_coder_lib/agents/coordinator.ex` - Route protocol events
- `config/config.exs` - Add protocol configuration

**Dependencies:**
- All previous phases (1-7)

---

## Dependencies

**Depends on:**
- Phase 1: Core Foundation (supervision, configuration)
- Phase 2: Agent Layer Base (agent abstractions, Coordinator)
- Phase 3: Multi-Session Architecture (session management)
- Phase 4: Two-Tier Memory System (memory for tools)
- Phase 5: Knowledge Graph Layer (semantic understanding)
- Phase 6: Codebase Semantic Model (code-aware tools)
- Phase 7: Conversation History (logging tool usage)

**Final Phase** - Completes the foundation implementation
