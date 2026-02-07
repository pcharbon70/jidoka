# Phase 8.4: Phoenix Channels Client - Strategic Implementation Plan

**Plan Version**: 1.1
**Created**: 2026-02-07
**Updated**: 2026-02-07 (User decisions recorded)
**Status**: Ready for Breakdown Phase
**Research Document**: `notes/phase-8.4-phoenix-channels-client/research.md`

---

## Executive Summary

This plan details the strategic implementation of a Phoenix Channels client for the Jidoka agentic system using the **Slipstream v1.2.0** library. The implementation follows the existing MCP client architecture pattern, integrating with the Jidoka signal system for real-time bidirectional communication with remote Phoenix Framework applications.

**Key Change from Original Feature Document**: The research phase identified that **Slipstream** (not the `phoenix` library) is the recommended choice for Phoenix Channels client implementation in Elixir.

---

## 1. Impact Analysis Summary

### 1.1 Codebase Changes Required

**New Modules** (4 files, ~1,000 lines):
- `lib/jidoka/protocol/phoenix/client.ex` - Main GenServer using Slipstream
- `lib/jidoka/protocol/phoenix/connection_supervisor.ex` - DynamicSupervisor
- `lib/jidoka/protocol/phoenix/message_router.ex` - Signal routing logic
- `lib/jidoka/signals/phoenix.ex` - Phoenix-specific signal types

**New Tests** (3 files, ~650 lines):
- `test/jidoka/protocol/phoenix/client_test.exs`
- `test/jidoka/protocol/phoenix/connection_supervisor_test.exs`
- `test/jidoka/protocol/phoenix/message_router_test.exs`

**Modified Files** (5 files):
- `mix.exs` - Add `{:slipstream, "~> 1.2"}` dependency
- `lib/jidoka/application.ex` - Add Phoenix ConnectionSupervisor to supervision tree
- `config/config.exs` - Add Phoenix connections configuration example
- `config/dev.exs` - Add dev environment configuration
- `config/runtime.exs` - Add runtime configuration for secrets

### 1.2 Existing Patterns to Follow

| Pattern | Source | Application |
|---------|--------|-------------|
| GenServer client lifecycle | `lib/jidoka/protocol/mcp/client.ex:44-125` | Use same status lifecycle pattern |
| DynamicSupervisor management | `lib/jidoka/protocol/mcp/connection_supervisor.ex:56-134` | Copy pattern for Phoenix |
| Signal creation with options | `lib/jidoka/signals.ex:94-104` | Create Phoenix signal module |
| PubSub topic conventions | `lib/jidoka/pubsub.ex:10-17` | Use `jido.protocol.phoenix.*` topics |
| Configuration access | `lib/jidoka/config.ex:91-93` | Add Phoenix config accessors |

### 1.3 Architectural Integration Points

**Supervision Tree Integration** (`lib/jidoka/application.ex`):
```elixir
# Add as sibling to MCP.ConnectionSupervisor
{Jidoka.Protocol.Phoenix.ConnectionSupervisor, []}
```

**Signal System Integration**:
- Phoenix messages → MessageRouter → Jido.Signal → PubSub broadcast
- Topic pattern: `jido.protocol.phoenix.<connection_name>.<channel>`

**Configuration Integration**:
- Application config: `config :jidoka, :phoenix_connections`
- Runtime secrets via environment variables

---

## 2. Feature Specification

### 2.1 User Stories

**US-1: External Service Integration**
> As a system developer, I want Jidoka to connect to remote Phoenix applications so that agents can interact with external Phoenix-based services.

**Acceptance Criteria**:
- Client can connect to `ws://` and `wss://` endpoints
- Connection supports custom headers and params
- Multiple named connections can coexist
- Connection status is queryable

**US-2: Real-Time Message Reception**
> As an agent developer, I want to receive Phoenix Channel messages as Jidoka signals so that agents can react to real-time events from Phoenix applications.

**Acceptance Criteria**:
- Incoming Phoenix messages convert to Jidoka signals
- Signals include metadata: connection name, topic, event
- Signals broadcast to correct PubSub topics
- Agents can subscribe to connection-specific topics

**US-3: Channel Management**
> As a system developer, I want to dynamically join and leave Phoenix channels so that agents can control their channel subscriptions.

**Acceptance Criteria**:
- API to join channels with params
- API to leave channels
- API to push events to joined channels
- Channels track join state

**US-4: Automatic Reconnection**
> As a system operator, I want the client to automatically reconnect on network failure so that temporary issues don't require manual intervention.

**Acceptance Criteria**:
- Exponential backoff reconnection
- Configurable max retry limit
- Auto-rejoin previously joined channels
- Reconnection status signals

### 2.2 API Contracts

#### Client API

```elixir
# Start a connection
Jidoka.Protocol.Phoenix.Client.start_link(opts)
# opts: [
#   name: :connection_name (required, atom)
#   uri: "ws://localhost:4000/socket/websocket" (required)
#   headers: [{"X-API-Key", "key"}]
#   params: %{token: "auth"}
#   auto_join_channels: [{"room:lobby", %{}}, ...]
# ]

# Channel operations
Jidoka.Protocol.Phoenix.Client.join_channel(pid, topic, params \\ %{})
# => {:ok, ref} | {:error, reason}

Jidoka.Protocol.Phoenix.Client.leave_channel(pid, topic)
# => :ok | {:error, reason}

Jidoka.Protocol.Phoenix.Client.push_event(pid, topic, event, payload)
# => {:ok, ref} | {:error, reason}

# Status queries
Jidoka.Protocol.Phoenix.Client.status(pid)
# => :connecting | :connected | :disconnecting | :disconnected

Jidoka.Protocol.Phoenix.Client.list_channels(pid)
# => [topic1, topic2, ...]
```

#### Supervisor API

```elixir
# Dynamic connection management
Jidoka.Protocol.Phoenix.ConnectionSupervisor.start_connection(opts)
# => {:ok, pid} | {:error, reason}

Jidoka.Protocol.Phoenix.ConnectionSupervisor.stop_connection(name)
# => :ok | {:error, :not_found}

Jidoka.Protocol.Phoenix.ConnectionSupervisor.list_connections()
# => [{name1, pid1}, {name2, pid2}, ...]

Jidoka.Protocol.Phoenix.ConnectionSupervisor.connection_status(name)
# => status | {:error, :not_found}

Jidoka.Protocol.Phoenix.ConnectionSupervisor.start_configured_connections()
# => :ok
```

#### Message Router API

```elixir
# Signal conversion (internal, used by Client callbacks)
Jidoka.Protocol.Phoenix.MessageRouter.route_message(
  connection_name,
  topic,
  event,
  payload,
  ref \\ nil
)
# => :ok | {:error, reason}
```

#### Signal Types

```elixir
# Phoenix connection lifecycle signals
Jidoka.Signals.Phoenix.connection_connected(connection_name, metadata)
Jidoka.Signals.Phoenix.connection_disconnected(connection_name, reason)
Jidoka.Signals.Phoenix.channel_joined(connection_name, topic, response)
Jidoka.Signals.Phoenix.channel_left(connection_name, topic)

# Message signals
Jidoka.Signals.Phoenix.message(connection_name, topic, event, payload)
```

### 2.3 Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Remote Phoenix Server                       │
└────────────────────────────────────┬────────────────────────────────┘
                                     │ WebSocket
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Jidoka.Protocol.Phoenix.Client (Slipstream)            │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Slipstream Callbacks                                         │  │
│  │  handle_connect/1    → Auto-join configured channels         │  │
│  │  handle_join/3       → Track joined channel                  │  │
│  │  handle_message/4    → Route to MessageRouter                │  │
│  │  handle_disconnect/2 → Trigger reconnection                   │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────┬────────────────────────────────┘
                                     │ route_message()
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Jidoka.Protocol.Phoenix.MessageRouter                  │
│  • Convert Phoenix message → Jido.Signal                            │
│  • Add metadata (connection_name, topic, event)                     │
│  • Broadcast to PubSub topics                                       │
└────────────────────────────────────┬────────────────────────────────┘
                                     │ broadcast_signal()
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Phoenix PubSub                                │
│  Topics:                                                            │
│  • "jido.protocol.phoenix.<connection_name>"                        │
│  • "jido.protocol.phoenix.<connection_name>.<channel>"              │
└────────────────────────────────────┬────────────────────────────────┘
                                     │ subscribe()
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Agent Processes                              │
│  • Receive signals via handle_info                                 │
│  • React to Phoenix events                                         │
│  • Push responses via Client.push_event/4                          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Technical Design

### 3.1 State Management Design

**Client State Struct**:

```elixir
defmodule Jidoka.Protocol.Phoenix.Client do
  use Slipstream, restart: :temporary

  defstruct [
    # Connection identity
    connection_name: nil,        # Atom name for registration

    # Slipstream socket (managed by use Slipstream)
    # Access via socket.assigns in callbacks

    # Channel tracking
    joined_channels: %{},        # %{topic => %{params: ..., joined_at: ..., ref: ...}}

    # Pending operations
    pending_pushes: %{},         # %{ref => {from, topic, event, payload}}

    # Connection state
    status: :disconnected,       # :disconnected | :connecting | :connected | :disconnecting

    # Reconnection tracking
    reconnect_attempts: 0,
    max_reconnect_attempts: 10,

    # Configuration (keep for reconnection)
    uri: nil,
    headers: [],
    params: %{},
    auto_join_channels: []
  ]

  @type status :: :disconnected | :connecting | :connected | :disconnecting
end
```

**Status Lifecycle**:
```
:disconnected (init)
    ↓ (Slipstream.connect/1)
:connecting
    ↓ (handle_connect/1)
:connected
    ↓ (close/1)
:disconnecting
    ↓ (terminate/2)
:disconnected
```

### 3.2 Channel State Tracking

Channels are tracked in `socket.assigns` (Slipstream pattern) and replicated in our state struct:

```elixir
# In handle_join/3
def handle_join(topic, _response, socket) do
  channels = Map.put(socket.assigns.channels || %{}, topic, %{
    params: %{},
    joined_at: DateTime.utc_now(),
    ref: nil
  })

  new_socket = Slipstream.assign(socket, :channels, channels)
  {:ok, new_socket}
end
```

### 3.3 Reconnection Strategy

**Slipstream Built-in Reconnection**:

```elixir
# In init/1
config = [
  uri: uri,
  reconnect_after_msec: [100, 500, 1_000, 2_000, 5_000, 10_000, 30_000],
  rejoin_after_msec: [100, 500, 1_000, 2_000, 5_000, 10_000]
]
```

**Custom Reconnection Logic** (in handle_disconnect/2):

```elixir
def handle_disconnect(reason, socket) do
  Logger.warning("Phoenix connection disconnected: #{inspect(reason)}")

  if socket.assigns.reconnect_attempts < socket.assigns.max_reconnect_attempts do
    # Slipstream will auto-reconnect with backoff
    # We just track attempts
    new_attempts = socket.assigns.reconnect_attempts + 1
    new_socket = Slipstream.assign(socket, :reconnect_attempts, new_attempts)

    # Attempt reconnect
    case Slipstream.reconnect(new_socket) do
      {:ok, socket} ->
        {:ok, socket}
      {:error, _reason} ->
        # Stop and let supervisor handle restart
        {:stop, :reconnect_failed, socket}
    end
  else
    # Max retries reached
    Logger.error("Max reconnection attempts reached")
    {:stop, :max_retries_reached, socket}
  end
end
```

### 3.4 Signal Type Design

**Phoenix Signal Module** (`lib/jidoka/signals/phoenix.ex`):

```elixir
defmodule Jidoka.Signals.Phoenix do
  @moduledoc """
  Signal types for Phoenix Channels client events.
  """

  use Jido.Signal

  @doc "Connection established signal"
  def connection_connected(connection_name, metadata \\ %{}) do
    new(%{
      type: "phoenix.connection.connected",
      source: "/jidoka/phoenix/#{connection_name}",
      data: %{connection_name: connection_name, timestamp: DateTime.utc_now()},
      metadata: metadata
    })
  end

  @doc "Connection lost signal"
  def connection_disconnected(connection_name, reason) do
    new(%{
      type: "phoenix.connection.disconnected",
      source: "/jidoka/phoenix/#{connection_name}",
      data: %{connection_name: connection_name, reason: reason}
    })
  end

  @doc "Channel joined signal"
  def channel_joined(connection_name, topic, response) do
    new(%{
      type: "phoenix.channel.joined",
      source: "/jidoka/phoenix/#{connection_name}",
      data: %{connection_name: connection_name, topic: topic, response: response}
    })
  end

  @doc "Incoming message signal"
  def message(connection_name, topic, event, payload) do
    new(%{
      type: "phoenix.#{sanitize_topic(topic)}.#{event}",
      source: "/jidoka/phoenix/#{connection_name}",
      data: %{payload: payload},
      metadata: %{
        connection_name: connection_name,
        phoenix_topic: topic,
        phoenix_event: event
      }
    })
  end

  defp sanitize_topic(topic) do
    topic |> String.replace(":", "_") |> String.replace("/", "_")
  end
end
```

### 3.5 Message Router Design

**Message Router** (`lib/jidoka/protocol/phoenix/message_router.ex`):

```elixir
defmodule Jidoka.Protocol.Phoenix.MessageRouter do
  @moduledoc """
  Routes incoming Phoenix messages to Jidoka signals.

  Phoenix messages are converted to signals and broadcast via PubSub
  for agent consumption.
  """

  alias Jido.Signal
  alias Jidoka.PubSub
  alias Jidoka.Signals.Phoenix

  @doc """
  Route a Phoenix message to the signal system.
  """
  def route_message(connection_name, topic, event, payload, _ref \\ nil) do
    # Build signal type from topic and event
    signal_type = build_signal_type(connection_name, topic, event)

    # Create signal
    case Phoenix.message(connection_name, topic, event, payload) do
      {:ok, signal} ->
        # Broadcast to connection-specific topic
        connection_topic = "jido.protocol.phoenix.#{connection_name}"
        PubSub.broadcast(connection_topic, signal)

        # Broadcast to channel-specific topic (for granular subscriptions)
        channel_topic = "jido.protocol.phoenix.#{connection_name}.#{sanitize_topic(topic)}"
        PubSub.broadcast(channel_topic, signal)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Route a connection lifecycle event.
  """
  def route_connection_event(connection_name, event_type, data \\ %{}) do
    signal_type = "phoenix.connection.#{event_type}"

    case Signal.new(%{
      type: signal_type,
      source: "/jidoka/phoenix/#{connection_name}",
      data: Map.put(data, :connection_name, connection_name)
    }) do
      {:ok, signal} ->
        PubSub.broadcast("jido.protocol.phoenix.#{connection_name}", signal)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_signal_type(connection_name, topic, event) do
    "phoenix.#{connection_name}.#{sanitize_topic(topic)}.#{event}"
  end

  defp sanitize_topic(topic) do
    topic |> String.replace(":", "_") |> String.replace("/", "_")
  end
end
```

### 3.6 Configuration Schema

**Application Configuration**:

```elixir
# config/config.exs
config :jidoka, :phoenix_connections,
  # Example connection
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
    auto_join_channels: [
      {"room:lobby", %{}},
      {"user:123", %{user_id: "123"}}
    ],
    reconnect: true,
    max_retries: 10,
    reconnect_after_msec: [100, 500, 1_000, 2_000, 5_000, 10_000, 30_000],
    rejoin_after_msec: [100, 500, 1_000, 2_000, 5_000, 10_000]
  ]
```

**Environment Variables** (production):

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :jidoka, :phoenix_connections,
    backend_service: [
      name: :phoenix_backend,
      uri: System.get_env("PHOENIX_BACKEND_URL") || "wss://example.com/socket/websocket",
      headers: [{"X-API-Key", System.get_env("PHOENIX_API_KEY") || ""}],
      params: %{token: System.get_env("PHOENIX_AUTH_TOKEN") || ""},
      reconnect: true
    ]
end
```

---

## 4. Implementation Strategy

### 4.1 Primary Approach

**Follow MCP Client Pattern**:

The implementation will closely mirror the existing `Jidoka.Protocol.MCP.Client` structure, adapting it for Slipstream's callback-based architecture.

**Key Differences from MCP**:
- **No separate transport layer** - Slipstream handles WebSocket internally
- **No request manager** - Slipstream tracks push/reply correlations
- **Simpler reconnection** - Slipstream has built-in reconnection logic
- **Async callback style** - Not using `await_*` functions in production

### 4.2 Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Library** | Slipstream v1.2.0 | Purpose-built for Phoenix Channels client |
| **GenServer pattern** | `use Slipstream` directly | Cleaner integration, less boilerplate |
| **State storage** | Both socket.assigns + state struct | Follow Slipstream pattern for state |
| **Message routing** | Separate module, not GenServer | Pure function transformation |
| **Supervision** | Parallel to MCP.ConnectionSupervisor | Matches Phase 8.3 pattern |
| **Signal types** | Pre-defined + dynamic | Common events pre-defined, custom events dynamic |
| **Reconnection** | Slipstream built-in + custom tracking | Balance of simplicity and control |

### 4.3 Module Organization

```
lib/jidoka/protocol/phoenix/
├── client.ex                    # Main GenServer using Slipstream
├── connection_supervisor.ex     # DynamicSupervisor (copy MCP pattern)
└── message_router.ex           # Signal routing (pure functions)

lib/jidoka/signals/
└── phoenix.ex                   # Phoenix-specific signal types
```

### 4.4 Slipstream Integration Pattern

**Using `use Slipstream` directly** (not wrapping):

```elixir
defmodule Jidoka.Protocol.Phoenix.Client do
  use Slipstream, restart: :temporary

  # NOT: use GenServer (Slipstream is already a GenServer)

  # Slipstream callbacks
  @impl true
  def init(args) do
    # Build configuration
    # Return {:ok, connect!(config)}
  end

  @impl true
  def handle_connect(socket) do
    # Auto-join channels
    # Emit connection signal
    {:ok, socket}
  end

  @impl true
  def handle_join(topic, response, socket) do
    # Track channel
    # Emit joined signal
    {:ok, socket}
  end

  @impl true
  def handle_message(topic, event, payload, socket) do
    # Route to MessageRouter
    {:ok, socket}
  end

  @impl true
  def handle_disconnect(reason, socket) do
    # Handle reconnection
    # Emit disconnected signal
    {:ok, socket} or {:stop, reason, socket}
  end
end
```

---

## 5. Implementation Phases

### Phase 1: Foundation and Infrastructure

**Objectives**:
- Set up project dependencies
- Create module structure
- Implement supervisor
- Add configuration schema

**Tasks**:
1. Add `{:slipstream, "~> 1.2"}` to mix.exs
2. Create `lib/jidoka/protocol/phoenix/` directory
3. Create `client.ex` with basic structure
4. Create `connection_supervisor.ex` (copy MCP pattern)
5. Add configuration to config files
6. Add ConnectionSupervisor to Application supervisor

**Success Criteria**:
- `mix deps.get` succeeds
- `mix compile` succeeds
- ConnectionSupervisor starts in Application

**Dependencies**: None (foundational phase)

**Estimated Complexity**: Low

---

### Phase 2: Core Client Implementation

**Objectives**:
- Implement Slipstream integration
- Handle connection lifecycle
- Implement channel operations

**Tasks**:
1. Implement `init/1` with Slipstream configuration
2. Implement `handle_connect/1` with auto-join logic
3. Implement `handle_join/3` with channel tracking
4. Implement `handle_disconnect/2` with reconnection
5. Implement `join_channel/3` API
6. Implement `leave_channel/2` API
7. Implement `push_event/4` API
8. Implement status query functions

**Success Criteria**:
- Client can connect to a Phoenix server
- Client can join channels
- Client can push events
- Status lifecycle works correctly

**Dependencies**: Phase 1 must be complete

**Estimated Complexity**: Medium

---

### Phase 3: Signal Integration

**Objectives**:
- Create Phoenix signal types
- Implement message router
- Connect to PubSub

**Tasks**:
1. Create `lib/jidoka/signals/phoenix.ex`
2. Implement signal type constructors
3. Create `message_router.ex`
4. Implement `route_message/5`
5. Implement `route_connection_event/3`
6. Wire handle_message/4 to MessageRouter
7. Wire lifecycle events to signals

**Success Criteria**:
- Phoenix messages convert to signals
- Signals broadcast to correct topics
- Agents can subscribe to topics

**Dependencies**: Phase 2 must be complete

**Estimated Complexity**: Medium

---

### Phase 4: Testing and Documentation

**Objectives**:
- Write comprehensive tests
- Add documentation
- Verify all success criteria

**Tasks**:
1. Write `client_test.exs` with Slipstream.SocketTest
2. Write `connection_supervisor_test.exs`
3. Write `message_router_test.exs`
4. Add moduledoc examples
5. Add usage examples
6. Document configuration options
7. Run full test suite
8. Verify 80%+ test coverage

**Success Criteria**:
- All tests pass
- Coverage ≥ 80%
- Documentation complete
- All feature success criteria met

**Dependencies**: Phase 3 must be complete

**Estimated Complexity**: Medium

---

### Phase 5: Integration and Validation

**Objectives**:
- Integration testing
- Performance validation
- Security review

**Tasks**:
1. End-to-end testing with real Phoenix server
2. Load testing for message throughput
3. Security audit (credentials, wss:// enforcement)
4. Documentation review
5. Feature plan checklist verification

**Success Criteria**:
- E2E tests pass
- Performance acceptable
- Security issues resolved
- All tasks in feature plan marked complete

**Dependencies**: Phase 4 must be complete

**Estimated Complexity**: Low

---

## 6. Quality and Testing Strategy

### 6.1 Testing Approach

**Unit Tests** (ExUnit):
- Test individual functions in isolation
- Mock Slipstream where needed
- Focus on logic, not WebSocket behavior

**Integration Tests** (Slipstream.SocketTest):
- Test client lifecycle with emulated server
- Test channel operations
- Test message flow

**End-to-End Tests**:
- Real Phoenix server (test endpoint)
- Full message round-trip
- Reconnection scenarios

### 6.2 Test Coverage Goals

| Module | Target Coverage |
|--------|-----------------|
| Client | ≥ 85% |
| ConnectionSupervisor | ≥ 80% |
| MessageRouter | ≥ 90% |
| Signals.Phoenix | ≥ 80% |

### 6.3 Essential Test Cases

**Connection Lifecycle**:
- ✓ Successful connection
- ✓ Connection failure handling
- ✓ Disconnection
- ✓ Reconnection with backoff
- ✓ Max retry enforcement

**Channel Operations**:
- ✓ Successful join with params
- ✓ Join error handling
- ✓ Leave channel
- ✓ Push event (with/without ack)
- ✓ Push error handling

**Message Routing**:
- ✓ Phoenix message → Signal conversion
- ✓ Signal broadcast to correct topic
- ✓ Metadata preservation
- ✓ Multiple connections isolation

**Supervisor**:
- ✓ Dynamic start/stop
- ✓ Configuration-based startup
- ✓ Connection status queries
- ✓ Child termination

### 6.4 Testing Tools

- **ExUnit** - Standard Elixir test framework
- **Slipstream.SocketTest** - Phoenix client testing
- No additional mocking libraries needed

---

## 7. Risk Assessment and Mitigation

### 7.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Slipstream API changes | Low | Medium | Pin to v1.2.x, track releases |
| Phoenix protocol mismatch | Low | Low | Slipstream handles V2 by default |
| Signal naming conflicts | Low | Low | Use `phoenix.` prefix |
| Memory leak from signals | Low | Medium | Monitor PubSub subscription cleanup |

### 7.2 Integration Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Supervisor tree conflict | Low | Low | Parallel to MCP, not under ProtocolSupervisor |
| PubSub topic collision | Low | Low | Connection name in topic |
| Configuration conflicts | Low | Low | Use distinct config key |

### 7.3 Operational Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Credentials in config | Medium | High | Use runtime.exs + env vars |
| WebSocket (ws://) in prod | Medium | High | Validate wss:// in prod config |
| Reconnection spam | Low | Medium | Exponential backoff + max retries |

### 7.4 Security Considerations

**Credentials Management**:
- Use environment variables for secrets
- Never commit credentials to repo
- Use `runtime.exs` for production config

**WebSocket Security**:
- Require `wss://` in production
- Validate TLS configuration
- Support custom `mint_opts` for TLS

**API Key Handling**:
- Headers for API keys
- Params for auth tokens
- Document secret rotation

---

## 8. Agent Consultations Summary

### 8.1 elixir-expert Consultation

**Date**: 2026-02-07

**Key Recommendations**:
1. Use async callback style, not `await_*` functions in production
2. Track joined channels in `socket.assigns`
3. Use `restart: :temporary` in `use Slipstream`
4. Pre-define common signal types, allow dynamic creation
5. Use environment variables for secrets management

**Code Patterns Provided**:
- Full GenServer implementation using `use Slipstream`
- Signal integration pattern with metadata
- Configuration examples for dev/prod
- Testing patterns with Slipstream.SocketTest

### 8.2 architecture-agent Consultation

**Date**: 2026-02-07

**Key Recommendations**:
1. Follow MCP client structure exactly for consistency
2. Use same status lifecycle: :disconnected → :connecting → :connected → :disconnecting
3. Create MessageRouter module for signal conversion (not separate GenServer)
4. Use atom names for connection registration
5. Add to Application supervisor as sibling to MCP (not under ProtocolSupervisor)

**File Structure Confirmed**:
```
lib/jidoka/protocol/phoenix/
├── client.ex                    # Main GenServer (450-500 lines)
├── connection_supervisor.ex     # DynamicSupervisor (140 lines)
└── message_router.ex           # Signal routing (150-200 lines)
```

### 8.3 research-agent Consultation

**Date**: 2026-02-07

**Key Findings**:
1. **Slipstream v1.2.0** is the recommended Phoenix Channels client library
2. Phoenix.Socket.Client does not exist as a separate module
3. Phoenix Channels Protocol V2 uses list-based message format
4. Slipstream has built-in reconnection with configurable backoff

**Documentation Sources**:
- [Slipstream Documentation](https://hexdocs.pm/slipstream/Slipstream.html)
- [Slipstream.Configuration](https://hexdocs.pm/slipstream/Slipstream.Configuration.html)
- [Phoenix Channels Guide](https://hexdocs.pm/phoenix/channels.html)

---

## 9. Success Criteria

### 9.1 Feature Success Criteria (from original feature plan)

1. ✅ Phoenix client can connect to a remote Phoenix server
2. ✅ Client can join channels successfully
3. ✅ Client can push events to channels
4. ✅ Incoming messages are routed to agents via signals
5. ✅ Reconnection works on disconnect with backoff
6. ✅ Connections are supervised via ConnectionSupervisor
7. ✅ All tests pass (80%+ coverage)

### 9.2 Additional Success Criteria

8. ✅ Configuration-based connection startup works
9. ✅ Multiple named connections can coexist
10. ✅ Signal types follow Jidoka conventions
11. ✅ PubSub topics follow naming conventions
12. ✅ Documentation includes usage examples
13. ✅ Security best practices followed (env vars, wss://)

### 9.3 Definition of Done

- All implementation phases complete
- All tests passing with ≥80% coverage
- Documentation complete (moduledocs, examples)
- Security review complete
- Performance acceptable
- Original feature plan tasks marked complete
- Feature branch ready for review

---

## 10. User Decisions Recorded

### 10.1 Architectural Decisions (User Approved)

| Decision | User Choice | Implementation Note |
|----------|-------------|---------------------|
| **Q1: Channel Auto-Join** | Support both | Implement `auto_join_channels` config option AND explicit `join_channel/3` API |
| **Q2: Signal Type Naming** | Include connection name | Format: `phoenix.<connection_name>.<sanitized_topic>.<event>` |
| **Q3: Multiple Connections** | Allow multiple | Support multiple named connections to same server with different auth/params |

### 10.2 All Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Library | Slipstream v1.2.0 | Research confirmed best choice |
| Architecture | Follow MCP pattern | Consistency across codebase |
| Supervision | Parallel to MCP.ConnectionSupervisor | Matches Phase 8.3 |
| Signal routing | Separate module, inline calls | Simpler than separate GenServer |
| Reconnection | Slipstream built-in + tracking | Balance of simplicity/control |
| Auto-join channels | Both config + API | User approved Q1 |
| Signal naming | Include connection name | User approved Q2 |
| Multiple connections | Allowed | User approved Q3 |

---

## 11. Next Steps

### 11.1 Proceed to Breakdown Phase

This strategic plan provides sufficient detail for the breakdown phase where:

1. Each implementation phase will be broken into numbered checklists
2. Each task will have specific acceptance criteria
3. Dependencies between tasks will be explicitly mapped
4. Code structure will be defined at function level

### 11.2 Pre-Breakdown Checklist

- ✅ Research phase complete with comprehensive documentation
- ✅ Expert consultations completed and incorporated
- ✅ Architecture decisions documented with rationale
- ✅ Implementation phases defined with objectives
- ✅ Quality and testing strategy established
- ✅ Risks identified with mitigation strategies
- ✅ Success criteria clearly defined
- ✅ Open questions documented with recommendations

**Ready for `/breakdown` command**

---

## 12. Sources

### Research Documents
- `notes/phase-8.4-phoenix-channels-client/research.md` - Comprehensive research findings

### External Documentation
- [Slipstream v1.2.0 Documentation](https://hexdocs.pm/slipstream/Slipstream.html)
- [Slipstream.Configuration](https://hexdocs.pm/slipstream/Slipstream.Configuration.html)
- [Slipstream.SocketTest](https://hexdocs.pm/slipstream/Slipstream.SocketTest.html)
- [Phoenix Channels Guide](https://hexdocs.pm/phoenix/channels.html)

### Internal Codebase Patterns
- `lib/jidoka/protocol/mcp/client.ex` - GenServer client pattern (472 lines)
- `lib/jidoka/protocol/mcp/connection_supervisor.ex` - Supervisor pattern
- `lib/jidoka/signals.ex` - Signal creation pattern
- `lib/jidoka/pubsub.ex` - PubSub topic conventions

---

**Plan Status**: ✅ Complete

**Next Phase**: `/breakdown` - Detailed task decomposition
