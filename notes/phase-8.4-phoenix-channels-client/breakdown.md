# Phase 8.4: Phoenix Channels Client - Task Breakdown

**Breakdown Version**: 1.0
**Created**: 2026-02-07
**Status**: Ready for Execution
**Plan Document**: `notes/phase-8.4-phoenix-channels-client/plan.md`

---

## How to Use This Breakdown

This breakdown contains numbered checklists for each implementation phase. Tasks should be completed in order within each phase. Dependencies between tasks are explicitly marked.

**Instructions**:
1. Start with Step 1, complete all tasks in order
2. Mark each task complete as you finish it
3. Do not proceed to next step until current step is complete
4. Run `mix test` after each step to ensure nothing is broken

---

## Step 1: Foundation and Infrastructure

**Objective**: Set up project dependencies, create module structure, implement supervisor, add configuration schema.

**Estimated Time**: 1-2 hours
**Dependencies**: None (foundational step)

### 1.1 Add Slipstream Dependency

- [ ] 1.1.1 Open `mix.exs`
- [ ] 1.1.2 Add `{:slipstream, "~> 1.2"}` to the `deps()` function
- [ ] 1.1.3 Run `mix deps.get` to fetch the dependency
- [ ] 1.1.4 Run `mix compile` to verify no conflicts
- [ ] 1.1.5 Verify Slipstream is available in IEx: `iex -S mix` then `Slipstream.__info__(:module)`

**Acceptance Criteria**:
- `mix deps.get` succeeds without errors
- `mix compile` succeeds
- Slipstream module is accessible

---

### 1.2 Create Module Directory Structure

- [ ] 1.2.1 Create `lib/jidoka/protocol/phoenix/` directory
- [ ] 1.2.2 Create `test/jidoka/protocol/phoenix/` directory

**Acceptance Criteria**:
- Directories exist
- `ls -la lib/jidoka/protocol/phoenix/` shows empty directory

---

### 1.3 Create Client Module Skeleton

**File**: `lib/jidoka/protocol/phoenix/client.ex`

- [ ] 1.3.1 Create file with module definition: `defmodule Jidoka.Protocol.Phoenix.Client do`
- [ ] 1.3.2 Add `use Slipstream, restart: :temporary`
- [ ] 1.3.3 Add `require Logger`
- [ ] 1.3.4 Define state struct with fields:
  - `connection_name` (atom)
  - `joined_channels` (map)
  - `pending_pushes` (map)
  - `status` (atom)
  - `reconnect_attempts` (integer)
  - `max_reconnect_attempts` (integer)
  - `uri` (string)
  - `headers` (list)
  - `params` (map)
  - `auto_join_channels` (list)
- [ ] 1.3.5 Add `@type status :: :disconnected | :connecting | :connected | :disconnecting`
- [ ] 1.3.6 Add `@moduledoc` with basic description

**Acceptance Criteria**:
- File compiles with `mix compile`
- Module definition is valid

**Code Template**:
```elixir
defmodule Jidoka.Protocol.Phoenix.Client do
  @moduledoc """
  Phoenix Channels client using Slipstream for WebSocket connections.

  Follows the same pattern as Jidoka.Protocol.MCP.Client for consistency.
  """

  use Slipstream, restart: :temporary
  require Logger

  defstruct [
    :connection_name,
    :joined_channels,
    :pending_pushes,
    :status,
    :reconnect_attempts,
    :max_reconnect_attempts,
    :uri,
    :headers,
    :params,
    :auto_join_channels
  ]

  @type status :: :disconnected | :connecting | :connected | :disconnecting
end
```

---

### 1.4 Create ConnectionSupervisor (Copy MCP Pattern)

**File**: `lib/jidoka/protocol/phoenix/connection_supervisor.ex`

- [ ] 1.4.1 Create file with `use DynamicSupervisor` and `require Logger`
- [ ] 1.4.2 Define `start_link/1` function with `DynamicSupervisor.start_link`
- [ ] 1.4.3 Implement `init/1` returning `DynamicSupervisor.init(strategy: :one_for_one)`
- [ ] 1.4.4 Implement `start_connection/1`:
  - Extract `name` and `uri` from opts
  - Build child_spec with `restart: :transient`
  - Call `DynamicSupervisor.start_child`
  - Log success/error
- [ ] 1.4.5 Implement `stop_connection/1`:
  - Find PID with `Process.whereis/1`
  - Call `DynamicSupervisor.terminate_child` or return `{:error, :not_found}`
- [ ] 1.4.6 Implement `list_connections/0`:
  - Call `DynamicSupervisor.which_children`
  - Return list of `{id, pid}` tuples
- [ ] 1.4.7 Implement `connection_status/1`:
  - Find PID or return `{:error, :not_found}`
  - Call `GenServer.call(pid, :status)`
- [ ] 1.4.8 Implement `start_configured_connections/0`:
  - Get `Application.get_env(:jidoka, :phoenix_connections)`
  - Enumerate and call `start_connection/1` for each

**Acceptance Criteria**:
- Module compiles
- All public functions are defined
- Matches MCP.ConnectionSupervisor pattern

**Reference**: `lib/jidoka/protocol/mcp/connection_supervisor.ex:56-134`

---

### 1.5 Add Configuration

- [ ] 1.5.1 Open `config/config.exs`
- [ ] 1.5.2 Add example Phoenix connections configuration:
  ```elixir
  config :jidoka, :phoenix_connections,
    backend_service: [
      name: :phoenix_backend,
      uri: "ws://localhost:4000/socket/websocket",
      headers: [{"X-API-Key", "your-api-key"}],
      params: %{token: "auth-token"},
      auto_join_channels: [{"room:lobby", %{}}],
      reconnect: true,
      max_retries: 10
    ]
  ```

- [ ] 1.5.3 Open `config/dev.exs`
- [ ] 1.5.4 Add dev environment configuration for local testing
- [ ] 1.5.5 Open `config/runtime.exs`
- [ ] 1.5.6 Add production configuration with `System.get_env/1` for secrets:
  - `PHOENIX_BACKEND_URL`
  - `PHOENIX_API_KEY`
  - `PHOENIX_AUTH_TOKEN`

**Acceptance Criteria**:
- Config files are valid Elixir syntax
- `mix compile` succeeds

---

### 1.6 Add to Application Supervisor Tree

**File**: `lib/jidoka/application.ex`

- [ ] 1.6.1 Open `lib/jidoka/application.ex`
- [ ] 1.6.2 Locate the children list (after MCP.ConnectionSupervisor)
- [ ] 1.6.3 Add `{Jidoka.Protocol.Phoenix.ConnectionSupervisor, []}` to children
- [ ] 1.6.4 Run `mix compile` to verify
- [ ] 1.6.5 Run `mix test` to ensure no regressions

**Acceptance Criteria**:
- Application compiles
- All existing tests still pass
- ConnectionSupervisor starts on application boot

---

### Step 1 Completion Checklist

- [ ] All tasks in Phase 1 are complete
- [ ] `mix compile` succeeds
- [ ] `mix test` succeeds (existing tests)
- [ ] Slipstream dependency is available
- [ ] ConnectionSupervisor starts with application

---

## Step 2: Core Client Implementation

**Objective**: Implement Slipstream integration, handle connection lifecycle, implement channel operations.

**Estimated Time**: 3-4 hours
**Dependencies**: Step 1 must be complete

### 2.1 Implement Client Initialization

**File**: `lib/jidoka/protocol/phoenix/client.ex`

- [ ] 2.1.1 Implement `start_link/1` function:
  - Accept `opts` keyword list
  - Extract required: `name`, `uri`
  - Extract optional: `headers`, `params`, `auto_join_channels`, `max_retries`
  - Call `Slipstream.start_link(__MODULE__, opts, name: name)`
- [ ] 2.1.2 Implement `init/1` callback:
  - Extract configuration from args
  - Build Slipstream config list with:
    - `uri:` from args
    - `headers:` from args (or `[]`)
    - `params:` from args (or `%{}`)
    - `reconnect_after_msec:` default `[100, 500, 1_000, 2_000, 5_000, 10_000, 30_000]`
    - `rejoin_after_msec:` default `[100, 500, 1_000, 2_000, 5_000, 10_000]`
  - Initialize state struct with defaults
  - Call `connect!/1` to establish connection
  - Return `{:ok, socket}`

**Acceptance Criteria**:
- `Client.start_link(name: :test, uri: "ws://localhost:4000/socket")` returns `{:ok, pid}`
- State struct is properly initialized

---

### 2.2 Implement Connection Lifecycle Callbacks

- [ ] 2.2.1 Implement `handle_connect/1`:
  - Log "Connected to Phoenix server: #{uri}"
  - Update socket.assigns with status: `:connected`
  - Iterate `auto_join_channels` from state
  - For each channel, call `Slipstream.join/3`
  - Emit connection signal via MessageRouter
  - Return `{:ok, socket}`
- [ ] 2.2.2 Implement `handle_disconnect/2`:
  - Log warning with disconnect reason
  - Increment `reconnect_attempts` in socket.assigns
  - Check if `reconnect_attempts < max_reconnect_attempts`
  - If yes: call `Slipstream.reconnect/1`, return `{:ok, socket}`
  - If no: emit disconnect signal, return `{:stop, :max_retries_reached, socket}`

**Acceptance Criteria**:
- Connection transitions from :connecting to :connected
- Auto-join channels are attempted on connect
- Reconnection is attempted on disconnect

---

### 2.3 Implement Channel Join Callback

- [ ] 2.3.1 Implement `handle_join/3`:
  - Extract topic and response
  - Log "Joined channel: #{topic}"
  - Update `socket.assigns.channels` map with topic → channel state
  - Channel state includes: `%{params: ..., joined_at: DateTime.utc_now(), ref: nil}`
  - Emit channel_joined signal via MessageRouter
  - Return `{:ok, socket}`

**Acceptance Criteria**:
- Joined channels are tracked in socket.assigns
- Signal is emitted on successful join

---

### 2.4 Implement Channel Leave Tracking

- [ ] 2.4.1 Add `handle_topic_close/3` callback:
  - Log "Channel closed: #{topic}"
  - Remove topic from `socket.assigns.channels`
  - Return `{:ok, socket}`

**Acceptance Criteria**:
- Left channels are removed from tracking

---

### 2.5 Implement Public Channel Join API

- [ ] 2.5.1 Implement `join_channel/3`:
  - `def join_channel(client, topic, params \\ %{})`
  - Use `GenServer.call(client, {:join_channel, topic, params})`
- [ ] 2.5.2 Implement `handle_call({:join_channel, topic, params})`:
  - Check if status is `:connected`
  - Call `Slipstream.join(socket, topic, params)`
  - Return `{:reply, {:ok, ref}, socket}` or `{:reply, {:error, reason}, socket}`

**Acceptance Criteria**:
- External callers can join channels dynamically
- Error returned if not connected

---

### 2.6 Implement Public Channel Leave API

- [ ] 2.6.1 Implement `leave_channel/2`:
  - `def leave_channel(client, topic)`
  - Use `GenServer.call(client, {:leave_channel, topic})`
- [ ] 2.6.2 Implement `handle_call({:leave_channel, topic})`:
  - Call `Slipstream.leave(socket, topic)`
  - Update channels map (remove topic)
  - Return `{:reply, :ok, socket}` or `{:reply, {:error, reason}, socket}`

**Acceptance Criteria**:
- External callers can leave channels
- Channel is removed from tracking

---

### 2.7 Implement Event Push API

- [ ] 2.7.1 Implement `push_event/4`:
  - `def push_event(client, topic, event, payload)`
  - Use `GenServer.call(client, {:push_event, topic, event, payload})`
- [ ] 2.7.2 Implement `handle_call({:push_event, topic, event, payload})`:
  - Verify topic is in `socket.assigns.channels`
  - Call `Slipstream.push(socket, topic, event, payload)`
  - Return `{:reply, {:ok, ref}, socket}` or `{:reply, {:error, reason}, socket}`

**Acceptance Criteria**:
- External callers can push events to joined channels
- Error returned if channel not joined

---

### 2.8 Implement Handle Reply Callback

- [ ] 2.8.1 Implement `handle_reply/3`:
  - Log "Received reply: #{inspect(reply)}"
  - Find and remove from `pending_pushes` if ref matches
  - No action needed (GenServer.reply already called by Slipstream)
  - Return `{:ok, socket}`

**Acceptance Criteria**:
- Replies to pushes are received
- Pending pushes are cleaned up

---

### 2.9 Implement Status Query Functions

- [ ] 2.9.1 Implement `status/1`:
  - `def status(client)`
  - Use `GenServer.call(client, :status)`
- [ ] 2.9.2 Implement `handle_call(:status)`:
  - Return current status from socket.assigns
  - `{:reply, status, socket}`
- [ ] 2.9.3 Implement `list_channels/1`:
  - `def list_channels(client)`
  - Use `GenServer.call(client, :list_channels)`
- [ ] 2.9.4 Implement `handle_call(:list_channels)`:
  - Return `Map.keys(socket.assigns.channels || %{})`

**Acceptance Criteria**:
- External callers can query connection status
- External callers can list joined channels

---

### Step 2 Completion Checklist

- [ ] All tasks in Step 2 are complete
- [ ] Client module compiles with `mix compile`
- [ ] All callback functions are implemented
- [ ] Public API functions are defined
- [ ] `mix test` runs (tests may fail until Step 4)

---

## Step 3: Signal Integration

**Objective**: Create Phoenix signal types, implement message router, connect to PubSub.

**Estimated Time**: 2-3 hours
**Dependencies**: Step 2 must be complete

### 3.1 Create Phoenix Signal Module

**File**: `lib/jidoka/signals/phoenix.ex`

- [ ] 3.1.1 Create file with `defmodule Jidoka.Signals.Phoenix`
- [ ] 3.1.2 Add `use Jido.Signal`
- [ ] 3.1.3 Implement `connection_connected/2`:
  - `def connection_connected(connection_name, metadata \\ %{})`
  - Create signal with type `"phoenix.connection.connected"`
  - Source: `"/jidoka/phoenix/#{connection_name}"`
  - Data: `%{connection_name: connection_name, timestamp: DateTime.utc_now()}`
- [ ] 3.1.4 Implement `connection_disconnected/2`:
  - `def connection_disconnected(connection_name, reason)`
  - Create signal with type `"phoenix.connection.disconnected"`
  - Data includes connection_name and reason
- [ ] 3.1.5 Implement `channel_joined/3`:
  - `def channel_joined(connection_name, topic, response)`
  - Create signal with type `"phoenix.channel.joined"`
- [ ] 3.1.6 Implement `channel_left/2`:
  - `def channel_left(connection_name, topic)`
  - Create signal with type `"phoenix.channel.left"`
- [ ] 3.1.7 Implement `message/4`:
  - `def message(connection_name, topic, event, payload)`
  - Create signal with type `"phoenix.#{connection_name}.#{sanitize_topic(topic)}.#{event}"`
  - Source: `"/jidoka/phoenix/#{connection_name}"`
  - Data: `%{payload: payload}`
  - Metadata: `%{connection_name: connection_name, phoenix_topic: topic, phoenix_event: event}`
- [ ] 3.1.8 Add `sanitize_topic/1` helper:
  - Replace `:` with `_`
  - Replace `/` with `_`

**Acceptance Criteria**:
- Module compiles
- All signal constructors return `{:ok, signal}` or `{:error, reason}`

---

### 3.2 Create Message Router Module

**File**: `lib/jidoka/protocol/phoenix/message_router.ex`

- [ ] 3.2.1 Create file with `defmodule Jidoka.Protocol.Phoenix.MessageRouter`
- [ ] 3.2.2 Add alias for `Jido.Signal`
- [ ] 3.2.3 Add alias for `Jidoka.PubSub`
- [ ] 3.2.4 Add alias for `Jidoka.Signals.Phoenix`
- [ ] 3.2.5 Implement `route_message/5`:
  - `def route_message(connection_name, topic, event, payload, ref \\ nil)`
  - Call `Phoenix.message/4` to create signal
  - On success: broadcast to `"jido.protocol.phoenix.#{connection_name}"`
  - On success: broadcast to `"jido.protocol.phoenix.#{connection_name}.#{sanitize_topic(topic)}"`
  - Return `:ok` or `{:error, reason}`
- [ ] 3.2.6 Implement `route_connection_event/3`:
  - `def route_connection_event(connection_name, event_type, data \\ %{})`
  - Build signal type: `"phoenix.connection.#{event_type}"`
  - Create signal with `Signal.new/1`
  - Broadcast to connection topic
  - Return `:ok` or `{:error, reason}`
- [ ] 3.2.7 Add `sanitize_topic/1` private helper

**Acceptance Criteria**:
- Module compiles
- Functions return expected tuples
- PubSub broadcasts are called

---

### 3.3 Wire Message Router to Client

**File**: `lib/jidoka/protocol/phoenix/client.ex`

- [ ] 3.3.1 Add alias for `Jidoka.Protocol.Phoenix.MessageRouter`
- [ ] 3.3.2 In `handle_connect/1`, call `MessageRouter.route_connection_event(connection_name, "connected")`
- [ ] 3.3.3 In `handle_disconnect/2`, call `MessageRouter.route_connection_event(connection_name, "disconnected", %{reason: reason})`
- [ ] 3.3.4 In `handle_join/3`, call `MessageRouter.route_connection_event(connection_name, "channel_joined", %{topic: topic, response: response})`
- [ ] 3.3.5 Implement `handle_message/4`:
  - Extract topic, event, payload
  - Call `MessageRouter.route_message(connection_name, topic, event, payload)`
  - Return `{:ok, socket}`

**Acceptance Criteria**:
- All connection lifecycle events emit signals
- Incoming Phoenix messages are routed to signal system

---

### Step 3 Completion Checklist

- [ ] All tasks in Step 3 are complete
- [ ] `mix compile` succeeds
- [ ] Signal types are defined
- [ ] Message router is functional
- [ ] Client callbacks route to message router

---

## Step 4: Testing and Documentation

**Objective**: Write comprehensive tests, add documentation, verify all success criteria.

**Estimated Time**: 3-4 hours
**Dependencies**: Step 3 must be complete

### 4.1 Create Client Tests

**File**: `test/jidoka/protocol/phoenix/client_test.exs`

- [ ] 4.1.1 Create file with `defmodule Jidoka.Protocol.Phoenix.ClientTest`
- [ ] 4.1.2 Add `use ExUnit.Case, async: false`
- [ ] 4.1.3 Add `use Slipstream.SocketTest`
- [ ] 4.1.4 Test "connection lifecycle":
  - Test client connects successfully
  - Test client handles disconnect
  - Test client reconnects with backoff
- [ ] 4.1.5 Test "channel operations":
  - Test join channel with params
  - Test join channel error handling
  - Test leave channel
  - Test push event
  - Test push to non-joined channel returns error
- [ ] 4.1.6 Test "status queries":
  - Test status/1 returns current status
  - Test list_channels/1 returns joined channels

**Acceptance Criteria**:
- All tests pass with `mix test test/jidoka/protocol/phoenix/client_test.exs`
- Coverage ≥ 85% for Client module

---

### 4.2 Create ConnectionSupervisor Tests

**File**: `test/jidoka/protocol/phoenix/connection_supervisor_test.exs`

- [ ] 4.2.1 Create file with `defmodule Jidoka.Protocol.Phoenix.ConnectionSupervisorTest`
- [ ] 4.2.2 Add `use ExUnit.Case`
- [ ] 4.2.3 Test "dynamic connection management":
  - Test start_connection/1 starts a child
  - Test start_connection/1 returns error on duplicate name
  - Test stop_connection/1 stops child
  - Test stop_connection/1 returns error for unknown connection
- [ ] 4.2.4 Test "connection listing":
  - Test list_connections/0 returns all connections
  - Test connection_status/1 returns status
- [ ] 4.2.5 Test "configuration-based startup":
  - Test start_configured_connections/0 starts all configured

**Acceptance Criteria**:
- All tests pass
- Coverage ≥ 80% for ConnectionSupervisor module

---

### 4.3 Create MessageRouter Tests

**File**: `test/jidoka/protocol/phoenix/message_router_test.exs`

- [ ] 4.3.1 Create file with `defmodule Jidoka.Protocol.Phoenix.MessageRouterTest`
- [ ] 4.3.2 Add `use ExUnit.Case`
- [ ] 4.3.3 Setup mock PubSub for testing
- [ ] 4.3.4 Test "route_message/5":
  - Test creates correct signal type
  - Test broadcasts to connection topic
  - Test broadcasts to channel topic
  - Test handles connection name sanitization
- [ ] 4.3.5 Test "route_connection_event/3":
  - Test creates connection event signals
  - Test broadcasts to connection topic
- [ ] 4.3.6 Test "sanitize_topic/1":
  - Test replaces : with _
  - Test replaces / with _

**Acceptance Criteria**:
- All tests pass
- Coverage ≥ 90% for MessageRouter module

---

### 4.4 Create Phoenix Signal Tests

**File**: `test/jidoka/signals/phoenix_test.exs`

- [ ] 4.4.1 Create file with `defmodule Jidoka.Signals.PhoenixTest`
- [ ] 4.4.2 Add `use ExUnit.Case`
- [ ] 4.4.3 Test "connection_connected/2":
  - Test returns {:ok, signal}
  - Test signal has correct type and source
- [ ] 4.4.4 Test "connection_disconnected/2":
  - Test returns {:ok, signal}
  - Test signal includes reason
- [ ] 4.4.5 Test "channel_joined/3":
  - Test returns {:ok, signal}
- [ ] 4.4.6 Test "message/4":
  - Test returns {:ok, signal}
  - Test signal type includes connection name
  - Test signal includes metadata

**Acceptance Criteria**:
- All tests pass
- Coverage ≥ 80% for Phoenix signals module

---

### 4.5 Add Module Documentation

- [ ] 4.5.1 Add comprehensive `@moduledoc` to Client with:
  - Module description
  - Usage example
  - Configuration options
- [ ] 4.5.2 Add `@moduledoc` to ConnectionSupervisor with:
  - Description
  - API examples
- [ ] 4.5.3 Add `@moduledoc` to MessageRouter with:
  - Description
  - Message flow diagram
- [ ] 4.5.4 Add `@moduledoc` to Phoenix signals with:
  - Description of each signal type
  - Examples

**Acceptance Criteria**:
- All modules have documentation
- `mix docs` generates documentation successfully

---

### 4.6 Verify Success Criteria

- [ ] 4.6.1 Verify "Phoenix client can connect to a remote Phoenix server"
- [ ] 4.6.2 Verify "Client can join channels successfully"
- [ ] 4.6.3 Verify "Client can push events to channels"
- [ ] 4.6.4 Verify "Incoming messages are routed to agents via signals"
- [ ] 4.6.5 Verify "Reconnection works on disconnect with backoff"
- [ ] 4.6.6 Verify "Connections are supervised via ConnectionSupervisor"
- [ ] 4.6.7 Verify "All tests pass (80%+ coverage)"

**Acceptance Criteria**:
- All 7 feature success criteria are met
- Run `mix test --cover` and verify coverage ≥ 80%

---

### Step 4 Completion Checklist

- [ ] All tasks in Step 4 are complete
- [ ] All tests pass
- [ ] Coverage ≥ 80%
- [ ] Documentation is complete
- [ ] All success criteria verified

---

## Step 5: Integration and Validation

**Objective**: Integration testing, performance validation, security review.

**Estimated Time**: 2-3 hours
**Dependencies**: Step 4 must be complete

### 5.1 End-to-End Integration Test

- [ ] 5.1.1 Create a test Phoenix server endpoint (optional)
- [ ] 5.1.2 Test full connection lifecycle
- [ ] 5.1.3 Test message round-trip (push → receive)
- [ ] 5.1.4 Test multi-channel scenario
- [ ] 5.1.5 Test reconnection scenario

**Acceptance Criteria**:
- E2E scenarios work correctly

---

### 5.2 Security Review

- [ ] 5.2.1 Verify credentials use environment variables (not hardcoded)
- [ ] 5.2.2 Verify wss:// is documented for production
- [ ] 5.2.3 Verify no secrets in config files (only in runtime.exs)
- [ ] 5.2.4 Review error messages for information leakage

**Acceptance Criteria**:
- No security concerns identified
- Security best practices documented

---

### 5.3 Update Original Feature Plan

**File**: `notes/features/phase-8.4-phoenix-channels-client.md`

- [ ] 5.3.1 Update "Dependencies" section to note Slipstream instead of phoenix
- [ ] 5.3.2 Mark all tasks as completed
- [ ] 5.3.3 Update "Current Status" section
- [ ] 5.3.4 Add completion date to "Updated Log"

**Acceptance Criteria**:
- Feature plan is up to date
- All tasks marked complete

---

### 5.4 Create Summary

**File**: `notes/summaries/phase-8.4-phoenix-channels-client.md`

- [ ] 5.4.1 Create summary document
- [ ] 5.4.2 Document what was implemented
- [ ] 5.4.3 Document key decisions
- [ ] 5.4.4 Document any deviations from plan
- [ ] 5.4.5 Document next steps (future enhancements)

**Acceptance Criteria**:
- Summary document exists
- All key points documented

---

### Step 5 Completion Checklist

- [ ] All tasks in Step 5 are complete
- [ ] E2E tests pass
- [ ] Security review complete
- [ ] Feature plan updated
- [ ] Summary document created

---

## Overall Completion Checklist

Before considering this feature complete:

- [ ] Step 1: Foundation complete
- [ ] Step 2: Core Client complete
- [ ] Step 3: Signal Integration complete
- [ ] Step 4: Testing complete
- [ ] Step 5: Integration complete
- [ ] All 7 feature success criteria met
- [ ] Test coverage ≥ 80%
- [ ] Documentation complete
- [ ] Feature branch ready for review

---

## Task Execution Tips

1. **Compile often**: Run `mix compile` after each significant change
2. **Test as you go**: Don't wait until the end of a phase to run tests
3. **Check dependencies**: Ensure each phase is fully complete before starting the next
4. **Ask for help**: If stuck on a Slipstream API, refer to [hexdocs.pm/slipstream](https://hexdocs.pm/slipstream/Slipstream.html)
5. **Follow patterns**: Refer to `lib/jidoka/protocol/mcp/client.ex` for implementation patterns

---

**Breakdown Status**: ✅ Complete

**Next Step**: Begin Phase 1 implementation
