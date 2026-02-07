# Phase 8.4: Phoenix Channels Client - Research Document

## Research Summary

This document contains comprehensive research findings for implementing Phoenix Channels client functionality in Jidoka using the Slipstream library.

**Research Date**: 2026-02-07
**Target Library**: Slipstream v1.2.0
**Integration Pattern**: Following existing MCP client architecture

---

## 1. Project Dependencies Discovered

### Current Dependencies (from mix.exs)

```elixir
# Current project dependencies:
{:jido, "~> 2.0.0-rc.1", override: true},
{:jido_ai, path: "../jido_ai"},
{:phoenix_pubsub, "~> 2.1"},      # Already present - used for internal PubSub
{:req_llm, "~> 1.3", override: true},
{:rdf, "~> 2.0"},
{:sparql, "~> 0.3"},
{:elixir_ontologies, path: "../../elixir-ontologies"},
{:triple_store, path: "/home/ducky/code/triple_store", override: true}
```

### Required New Dependency

**Slipstream** v1.2.0 - Phoenix Channels WebSocket client library

```elixir
{:slipstream, "~> 1.2"}
```

**Rationale**:
- Purpose-built for Phoenix Channels client connections
- GenServer-based (matches existing architecture)
- Built-in reconnection logic with exponential backoff
- Phoenix-independent (doesn't require full Phoenix framework)
- Well-maintained and actively developed

**Transitive Dependencies** (automatically pulled in):
- `:mint_websocket` - WebSocket transport
- `:jason` - JSON parser (likely already present)

---

## 2. Files Requiring Changes

### Files to Create

| File | Purpose | Lines (est.) |
|------|---------|--------------|
| `lib/jidoka/protocol/phoenix/client.ex` | Main GenServer using Slipstream | 450-500 |
| `lib/jidoka/protocol/phoenix/connection_supervisor.ex` | DynamicSupervisor for connections | 140 |
| `lib/jidoka/protocol/phoenix/message_router.ex` | Signal routing from Phoenix messages | 150-200 |
| `lib/jidoka/signals/phoenix.ex` | Phoenix-specific signal types | 80-100 |
| `test/jidoka/protocol/phoenix/client_test.exs` | Client tests | 300-400 |
| `test/jidoka/protocol/phoenix/connection_supervisor_test.exs` | Supervisor tests | 100-150 |
| `test/jidoka/protocol/phoenix/message_router_test.exs` | Router tests | 150-200 |

### Files to Modify

| File | Change Required |
|------|-----------------|
| `mix.exs` | Add `{:slipstream, "~> 1.2"}` to deps |
| `lib/jidoka/application.ex` | Add Phoenix ConnectionSupervisor to supervision tree |
| `config/config.exs` | Add Phoenix connections configuration example |
| `config/dev.exs` | Add dev environment Phoenix connections |
| `config/prod.exs` | Add prod environment Phoenix connections |
| `config/runtime.exs` | Add runtime configuration for secrets |

---

## 3. Existing Patterns Found

### 3.1 GenServer Protocol Client Pattern

**Source**: `lib/jidoka/protocol/mcp/client.ex` (472 lines)

**Key Pattern Elements**:

```elixir
# State struct definition (lines 44-55)
defstruct [
  :transport_pid,        # Process PID for communication
  :request_manager,      # Request tracking GenServer
  :server_capabilities,  # Server feature set
  :status,               # Connection status
  :pending_requests,     # Outstanding requests
  :config                # Full config for reconnection
]

# Status lifecycle (line 57)
@type status :: :initializing | :ready | :closing | :terminated

# Init pattern (lines 152-183)
def init({transport_config, name, timeout}) do
  # Connect transport
  # Start request manager
  # Send initialize request
  {:ok, %__MODULE__{status: :initializing, ...}}
end

# Handle_call pattern (lines 194-241)
def handle_call(:operation, from, state) do
  # Check status
  # Generate request_id
  # Send via request manager
  # Track in pending_requests
  {:noreply, state}
end

# Handle_info pattern (lines 305-322)
def handle_info({:mcp_message, message}, state) do
  handle_incoming_message(message, state)
end

def handle_info({:mcp_error, error}, state) do
  # Log error
  # Possibly terminate
end
```

**Apply to Phoenix**: Use same struct pattern, replace `transport_pid` with `socket_pid` for Slipstream.

### 3.2 DynamicSupervisor Pattern

**Source**: `lib/jidoka/protocol/mcp/connection_supervisor.ex`

```elixir
# Supervisor setup (line 140)
use DynamicSupervisor
def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

# Dynamic start (lines 56-77)
def start_connection(opts) do
  name = Keyword.fetch!(opts, :name)
  # Child spec with name registration
  child_spec = %{
    id: name,
    start: {Jidoka.Protocol.MCP.Client, :start_link, [opts]},
    restart: :transient
  }
  DynamicSupervisor.start_child(__MODULE__, child_spec)
end

# Dynamic stop (lines 82-97)
def stop_connection(name) do
  case Process.whereis(name) do
    nil -> {:error, :not_found}
    pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end

# Configuration integration (lines 121-134)
def start_configured_connections do
  Application.get_env(:jidoka, :mcp_connections, [])
  |> Enum.each(fn {_key, opts} -> start_connection(opts) end)
end
```

**Apply to Phoenix**: Copy pattern exactly, change module references to Phoenix.

### 3.3 Signal Creation Pattern

**Source**: `lib/jidoka/signals.ex` (lines 94-104, 307-317)

```elixir
# Signal creation with options (lines 94-104)
def new(type, data, opts \\ []) do
  signal = %__MODULE__{
    type: type,
    data: data,
    id: signal_id(),
    timestamp: DateTime.utc_now(),
    dispatched?: false
  }
  |> maybe_put_source(opts)
  |> maybe_put_subject(opts)
  |> maybe_put_dispatch(opts)

  {:ok, signal}
end

# Dispatch pattern (lines 307-317)
def dispatch(signal_type, signal) do
  # Broadcast to signal-type-specific topic
  PubSub.broadcast("jido.signal.#{signal_type}", signal)

  # Also broadcast to client events if client-facing
  if signal.client_facing? do
    PubSub.broadcast_client_event({:signal, signal})
  end

  signal = %{signal | dispatched?: true}
  {:ok, signal}
end
```

**Apply to Phoenix**: Create Phoenix signal module following same pattern.

### 3.4 PubSub Topic Naming Convention

**Source**: `lib/jidoka/pubsub.ex` (lines 10-17)

```elixir
# Topic naming conventions:
"jido.agent.<agent_name>"        # Agent events
"jido.session.<session_id>"      # Session events
"jido.client.events"             # Global client events
"jido.signal.<signal_type>"      # System signals
"jido.protocol.<protocol>"       # Protocol events
```

**Apply to Phoenix**:
```elixir
"jido.protocol.phoenix.<connection_name>"           # Connection-level
"jido.protocol.phoenix.<connection_name>.<channel>" # Channel-specific
```

### 3.5 Configuration Pattern

**Source**: `lib/jidoka/config.ex`

```elixir
# Section-based configuration access (lines 91-93)
def get_llm_config do
  Application.get_env(:jidoka, :llm, [])
  |> Keyword.get(:provider, :openai)
end

# Validation functions (lines 336-387)
defp validate_llm_config(config) do
  cond do
    Keyword.get(config, :provider) == nil ->
      {:error, :provider_required}
    Keyword.get(config, :model) == nil ->
      {:error, :model_required}
    true ->
      {:ok, config}
  end
end
```

**Apply to Phoenix**: Create config accessors for Phoenix connections.

---

## 4. Integration Points

### 4.1 Application Supervision Tree

**Current** (`lib/jidoka/application.ex`):

```elixir
children = [
  # ...
  # Protocol connections (Phase 8)
  {DynamicSupervisor, name: Jidoka.ProtocolSupervisor, strategy: :one_for_one},
  # MCP Connection Supervisor (Phase 8.3)
  {Jidoka.Protocol.MCP.ConnectionSupervisor, []}
]
```

**Add**:

```elixir
children = [
  # ...
  # Protocol connections (Phase 8)
  {DynamicSupervisor, name: Jidoka.ProtocolSupervisor, strategy: :one_for_one},
  # MCP Connection Supervisor (Phase 8.3)
  {Jidoka.Protocol.MCP.ConnectionSupervisor, []},
  # Phoenix Connection Supervisor (Phase 8.4)
  {Jidoka.Protocol.Phoenix.ConnectionSupervisor, []}
]
```

### 4.2 Signal System Integration

**Message Flow**:

```
Remote Phoenix Server
    ↓ (WebSocket message)
Slipstream.handle_message/4
    ↓
Client.handle_message/4 (callback)
    ↓
MessageRouter.route_message/5
    ↓
Jido.Signal.new/3
    ↓
PubSub.broadcast_signal/3
    ↓
Topic: "jido.protocol.phoenix.<connection_name>"
    ↓
Agent processes (subscribers)
```

### 4.3 Registry Pattern

For connection discovery (future enhancement):

```elixir
# In connection supervisor
def list_connections do
  __MODULE__
  |> DynamicSupervisor.which_children()
  |> Enum.map(fn {id, pid, _type, _modules} -> {id, pid} end)
end

def connection_status(name) when is_atom(name) do
  case Process.whereis(name) do
    nil -> {:error, :not_found}
    pid -> GenServer.call(pid, :status)
  end
end
```

---

## 5. Third-Party Integration: Slipstream Library

### 5.1 Library Overview

**Slipstream** v1.2.0 - Elixir WebSocket client for Phoenix Channels

- 📖 [Main Documentation](https://hexdocs.pm/slipstream/Slipstream.html) - Comprehensive guide
- 📖 [API Reference](https://hexdocs.pm/slipstream/api-reference.html) - Complete API docs
- 📖 [Configuration](https://hexdocs.pm/slipstream/Slipstream.Configuration.html) - All configuration options
- 📖 [Examples](https://hexdocs.pm/slipstream/examples.html) - Code examples
- 📖 [GitHub Repository](https://github.com/CuatroElixir/slipstream) - Source code

### 5.2 Key Callbacks

| Callback | Purpose | Documentation |
|----------|---------|---------------|
| `handle_connect/1` | WebSocket connection established | [docs](https://hexdocs.pm/slipstream/Slipstream.html#c:handle_connect/1) |
| `handle_join/3` | Channel join response received | [docs](https://hexdocs.pm/slipstream/Slipstream.html#c:handle_join/3) |
| `handle_message/4` | Incoming message from server | [docs](https://hexdocs.pm/slipstream/Slipstream.html#c:handle_message/4) |
| `handle_reply/3` | Reply to a push from this client | [docs](https://hexdocs.pm/slipstream/Slipstream.html#c:handle_reply/3) |
| `handle_disconnect/2` | Connection terminated | [docs](https://hexdocs.pm/slipstream/Slipstream.html#c:handle_disconnect/2) |

### 5.3 Configuration Options

| Option | Type | Default | Purpose |
|--------|------|---------|---------|
| `:uri` | string/URI | required | WebSocket endpoint (`ws://` or `wss://`) |
| `:headers` | list | `[]` | HTTP headers for connection |
| `:params` | map | `%{}` | Connection parameters |
| `:heartbeat_interval_msec` | integer | `30000` | Heartbeat interval (0 = disabled) |
| `:reconnect_after_msec` | list | `[10, 50, 100, ...]` | Reconnection backoff sequence |
| `:rejoin_after_msec` | list | `[100, 500, 1000, ...]` | Rejoin backoff sequence |
| `:json_parser` | module | `Jason` | JSON parser module |
| `:mint_opts` | keyword | `[]` | Options for Mint.HTTP (TLS config) |

**Reconnection Backoff**:

```elixir
# Default reconnection sequence:
[10, 50, 100, 150, 200, 250, 500, 1000, 2000, 5000]
# Each value is tried in order; final value repeats if exhausted

# Default rejoin sequence:
[100, 500, 1000, 2000, 5000, 10000]
```

### 5.4 Usage Pattern

**Basic Implementation**:

```elixir
defmodule MyPhoenixClient do
  use Slipstream, restart: :temporary

  def start_link(args) do
    Slipstream.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    url = Keyword.fetch!(args, :url)
    headers = Keyword.get(args, :headers, [])
    params = Keyword.get(args, :params, %{})

    config = [
      uri: url,
      headers: headers,
      params: params,
      heartbeat_interval_msec: 30_000,
      reconnect_after_msec: [100, 500, 1_000, 2_000, 5_000, 10_000]
    ]

    # Start connection
    {:ok, connect!(config)}
  end

  @impl true
  def handle_connect(socket) do
    # Auto-join channels here
    {:ok, join(socket, "room:lobby", %{})}
  end

  @impl true
  def handle_join(topic, _response, socket) do
    Logger.info("Joined #{topic}")
    {:ok, socket}
  end

  @impl true
  def handle_message(topic, event, payload, socket) do
    Logger.debug("Message: #{topic} #{event} #{inspect(payload)}")
    # Route to signal system
    {:ok, socket}
  end

  @impl true
  def handle_disconnect(_reason, socket) do
    case reconnect(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:stop, reason, socket}
    end
  end
end
```

### 5.5 Testing with Slipstream.SocketTest

📖 [Slipstream.SocketTest Documentation](https://hexdocs.pm/slipstream/Slipstream.SocketTest.html)

```elixir
defmodule MyClientTest do
  use ExUnit.Case
  use Slipstream.SocketTest

  test "connects and joins channel" do
    accept_connect(MyClient)
    assert_join "room:lobby", %{}, :ok
  end

  test "pushes and receives messages" do
    accept_connect(MyClient)
    assert_join "room:lobby", %{}, :ok

    # Assert client pushes
    assert_push "room:lobby", "new_msg", params, ref

    # Emulate server reply
    reply(MyClient, ref, {:ok, %{status: "ok"}})
  end
end
```

---

## 6. Test Impact & Patterns

### Current Testing Approach

**Test Framework**: ExUnit (standard Elixir)

**Mocking**: No explicit mocking library found in current deps

### Test Structure (following MCP pattern)

```
test/jidoka/protocol/phoenix/
├── client_test.exs              # Main client GenServer tests
├── connection_supervisor_test.exs  # Supervisor tests
└── message_router_test.exs      # Signal routing tests
```

### Essential Test Cases

1. **Connection Lifecycle**
   - Successful connection to Phoenix server
   - Connection failure handling
   - Disconnection and reconnection with backoff
   - Max retry limit enforcement

2. **Channel Operations**
   - Successful channel join with params
   - Channel join error handling
   - Event pushing with acknowledgment
   - Event pushing without acknowledgment
   - Channel leaving

3. **Message Routing**
   - Phoenix message conversion to Jido signals
   - Signal broadcast to correct PubSub topics
   - Metadata preservation (connection name, topic, event)

4. **Supervisor Management**
   - Dynamic connection start/stop
   - Configuration-based connection startup
   - Connection status queries
   - Child termination handling

---

## 7. Configuration & Environment

### Configuration Schema

```elixir
# config/config.exs
config :jidoka, :phoenix_connections,
  # Example: Production backend service
  backend_service: [
    name: :phoenix_backend,
    uri: "ws://localhost:4000/socket/websocket",
    headers: [
      {"X-API-Key", "your-api-key"}
    ],
    params: %{
      token: "auth-token",
      user_id: "123"
    ],
    # Auto-join these channels on connection
    auto_join_channels: [
      {"room:lobby", %{}},
      {"user:123", %{user_id: "123"}}
    ],
    # Reconnection configuration
    reconnect: true,
    max_retries: 10,
    reconnect_after_msec: [100, 500, 1_000, 2_000, 5_000, 10_000, 30_000],
    rejoin_after_msec: [100, 500, 1_000, 2_000, 5_000, 10_000]
  ]
```

### Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `PHOENIX_BACKEND_URL` | WebSocket endpoint URL | Yes (prod) |
| `PHOENIX_API_KEY` | API key for authentication | No |
| `PHOENIX_AUTH_TOKEN` | Auth token for params | No |

### Runtime Configuration

```elixir
# config/runtime.exs
if config_env() == :prod do
  phoenix_backend_url = System.get_env("PHOENIX_BACKEND_URL")

  config :jidoka, :phoenix_connections,
    backend_service: [
      name: :phoenix_backend,
      uri: phoenix_backend_url,
      headers: [{"X-API-Key", System.get_env("PHOENIX_API_KEY")}],
      params: %{token: System.get_env("PHOENIX_AUTH_TOKEN")},
      reconnect: true
    ]
end
```

---

## 8. Risk Assessment

### Breaking Changes

| Risk | Severity | Mitigation |
|------|----------|------------|
| Slipstream API changes | Low | Use v1.2.x, track releases |
| Phoenix protocol version mismatch | Low | Slipstream handles V2 by default |
| Signal naming conflicts | Low | Use `phoenix.` prefix for all signal types |

### Performance Implications

| Concern | Impact | Mitigation |
|---------|--------|------------|
| Message processing bottleneck | Medium | Use async signal dispatch |
| Memory growth from signal cache | Low | Signals don't cache by default |
| Reconnection spam | Low | Exponential backoff limits attempts |

### Security Considerations

| Area | Concern | Mitigation |
|------|---------|------------|
| Credentials in config | High | Use runtime.exs + env vars |
| WebSocket (ws://) in prod | High | Require wss:// in production |
| API key exposure | Medium | Use SecureCredentials pattern |

### Migration Complexity

- **No data migration required** - New feature only
- **No schema changes** - Uses existing signal system
- **Backward compatible** - Existing functionality unaffected

---

## 9. Architectural Decisions

### Decision 1: Slipstream vs Phoenix Library

**Choice**: Slipstream v1.2.0

**Rationale**:
- Purpose-built for Phoenix Channels client connections
- GenServer-based (matches existing architecture)
- Built-in reconnection logic
- Phoenix-independent (lighter dependency)
- Active maintenance and community support

**Rejected**:
- `phoenix` library - Designed for servers, not clients; heavier dependency

### Decision 2: GenServer Wrapping vs Direct Slipstream.GenServer

**Choice**: Use `use Slipstream` directly

**Rationale**:
- Cleaner integration (no wrapper layer)
- Slipstream is a GenServer wrapper itself
- Built-in reconnection and lifecycle management
- Less boilerplate code

### Decision 3: Signal Type Strategy

**Choice**: Pre-define common signal types, allow dynamic creation

**Rationale**:
- Common events (connected, disconnected, joined) are pre-defined
- Custom Phoenix events can create dynamic signal types
- Follows existing signal pattern in Jidoka

### Decision 4: Message Router Location

**Choice**: Separate module (MessageRouter), not separate GenServer

**Rationale**:
- Signal routing is pure function transformation
- No need for separate process (adds overhead)
- Simpler error handling in single process
- Follows existing MCP pattern (inline message handling)

### Decision 5: Supervisor Placement

**Choice**: Parallel to MCP.ConnectionSupervisor, not under ProtocolSupervisor

**Rationale**:
- ProtocolSupervisor is for ad-hoc agent-started connections
- MCP/Phoenix supervisors are for configured, persistent connections
- Matches Phase 8.3 MCP pattern
- Allows different supervision strategies per protocol

---

## 10. Agent Consultations Summary

### elixir-expert Consultation

**Key Recommendations**:
1. Use async callback style, not `await_*` functions in production
2. Track joined channels in `socket.assigns`
3. Use `restart: :temporary` in `use Slipstream`
4. Pre-define common signal types
5. Use environment variables for secrets

**Code Pattern Provided**:
- Full GenServer implementation using `use Slipstream`
- Signal integration pattern
- Configuration examples

### architecture-agent Consultation

**Key Recommendations**:
1. Follow MCP client structure exactly
2. Use same status lifecycle: :initializing -> :ready -> :closing -> :terminated
3. Create MessageRouter module for signal conversion
4. Use atom names for connection registration
5. Add to Application supervisor as sibling to MCP

**File Structure**:
```
lib/jidoka/protocol/phoenix/
├── client.ex                    # Main GenServer
├── connection_supervisor.ex     # DynamicSupervisor
└── message_router.ex           # Signal routing
```

---

## 11. Unclear Areas Requiring Clarification

### Questions for User

1. **Channel Auto-Join Strategy**
   - Should all configured channels be joined on connection?
   - Or should agents explicitly request channel joins?
   - **Recommendation**: Support both via `auto_join_channels` config + explicit API

2. **Signal Type Naming**
   - Should Phoenix signal types include connection name?
   - Example: `phoenix.backend_service.room_lobby.msg`
   - Or just: `phoenix.room_lobby.msg`
   - **Recommendation**: Include connection name for disambiguation

3. **Multiple Connections to Same Server**
   - Should we support multiple named connections to the same Phoenix server?
   - Or restrict to one connection per unique URI?
   - **Recommendation**: Allow multiple connections (different auth/params)

4. **Testing Server Requirement**
   - Should we set up a test Phoenix endpoint?
   - Or rely on Slipstream.SocketTest mocking?
   - **Recommendation**: Use Slipstream.SocketTest (no real server needed)

---

## 12. Success Criteria

Research phase is complete when:

- ✅ Complete file-level impact map created with specific locations
- ✅ All existing dependencies and patterns documented
- ✅ Version-specific documentation links gathered
- ✅ Third-party integration (Slipstream) fully researched
- ✅ Architecture consultations completed and documented
- ✅ Integration points and configuration changes identified
- ✅ Test impact assessment completed
- ✅ Risk assessment with mitigation strategies provided
- ✅ Clear questions flagged for user clarification
- ✅ Ready for **plan** phase with comprehensive guidance

---

## 13. Sources

### Slipstream Documentation
- [Slipstream v1.2.0 - Main Documentation](https://hexdocs.pm/slipstream/Slipstream.html)
- [Slipstream.Configuration](https://hexdocs.pm/slipstream/Slipstream.Configuration.html)
- [Slipstream.SocketTest](https://hexdocs.pm/slipstream/Slipstream.SocketTest.html)
- [API Reference](https://hexdocs.pm/slipstream/api-reference.html)
- [GitHub Repository](https://github.com/CuatroElixir/slipstream)

### Phoenix Framework Documentation
- [Writing a Channels Client](https://hexdocs.pm/phoenix/writing_a_channels_client.html)
- [Phoenix Channels Guide](https://hexdocs.pm/phoenix/channels.html)

### Community Resources
- [Elixir Forum - Slipstream Announcement](https://elixirforum.com/t/slipstream-a-slick-elixir-websocket-client-for-phoenix-channels/37456)
- [Phoenix Channels Protocol Specification](https://elixirforum.com/t/specification-of-the-protocol-used-by-phoenix-channels/4192)

### Internal Codebase
- `lib/jidoka/protocol/mcp/client.ex` - GenServer client pattern reference
- `lib/jidoka/protocol/mcp/connection_supervisor.ex` - Supervisor pattern reference
- `lib/jidoka/signals.ex` - Signal creation and dispatch patterns
- `lib/jidoka/pubsub.ex` - PubSub topic and subscription patterns

---

**Research Status**: ✅ Complete

**Next Phase**: `/plan` - Strategic implementation planning
