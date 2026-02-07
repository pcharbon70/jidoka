# Phase 8.4: Phoenix Channels Client

## Problem Statement

The Jidoka system needs to connect to remote Phoenix Framework applications as a client, enabling bidirectional real-time communication over WebSockets using Phoenix Channels protocol. This is essential for:

1. **External Service Integration**: Connecting to Phoenix-based services that expose Channels
2. **Cross-Node Communication**: Enabling Jidoka instances to communicate across different nodes
3. **Real-Time Updates**: Subscribing to remote channels for live data feeds
4. **Agent Communication**: Facilitating agent-to-agent communication through Phoenix Channels

## Solution Overview

We will implement a Phoenix Channels client that:

1. Uses the `phoenix` library's `Phoenix.Socket.Client` for WebSocket connections
2. Implements reconnection logic with exponential backoff
3. Supports channel joining, event pushing, and message handling
4. Integrates with the existing Jidoka signal system for incoming messages
5. Provides supervision through the existing ProtocolSupervisor

### Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| **Use phoenix library** | Leverages official Phoenix client implementation |
| **GenServer-based Connection** | Matches existing MCP client pattern for consistency |
| **Signal-based routing** | Incoming messages convert to Jidoka signals for agent handling |
| **DynamicSupervisor integration** | Allows dynamic connection lifecycle management |
| **Exponential backoff reconnection** | Handles transient network failures gracefully |

### Dependencies

This implementation requires adding the `phoenix` package to dependencies.

**Note**: `phoenix_pubsub` is already a dependency for internal PubSub. The full `phoenix` package includes the Channels client functionality.

## Technical Details

### Files to Create

| File | Purpose |
|------|---------|
| `lib/jidoka/protocol/phoenix/connection.ex` | Main Phoenix Channels client GenServer |
| `lib/jidoka/protocol/phoenix/message_handler.ex` | Message routing to signals |
| `lib/jidoka/protocol/phoenix/reconnect_manager.ex` | Reconnection logic with backoff |
| `lib/jidoka/protocol/phoenix/connection_supervisor.ex` | Dynamic supervisor for connections |
| `lib/jidoka/protocol/phoenix.ex` | Main API module |
| `test/jidoka/protocol/phoenix/connection_test.exs` | Connection tests |
| `test/jidoka/protocol/phoenix/reconnect_manager_test.exs` | Reconnection tests |

### Files to Modify

| File | Changes |
|------|---------|
| `mix.exs` | Add `:phoenix` dependency |
| `lib/jidoka/application.ex` | Add Phoenix ConnectionSupervisor to supervision tree |
| `config/config.exs` | Add Phoenix connections configuration |

## Success Criteria

1. ✅ Phoenix client can connect to a remote Phoenix server
2. ✅ Client can join channels successfully
3. ✅ Client can push events to channels
4. ✅ Incoming messages are routed to agents via signals
5. ✅ Reconnection works on disconnect with backoff
6. ✅ Connections are supervised via ProtocolSupervisor
7. ✅ All tests pass (80%+ coverage)

## Implementation Plan

### Task 8.4.1: Create Jidoka.Protocol.Phoenix.Connection Module ⏳
**Status**: Pending
**File**: `lib/jidoka/protocol/phoenix/connection.ex`

- [ ] 8.4.1.1 Define Connection struct with socket, channels, and status fields
- [ ] 8.4.1.2 Implement `start_link/1` for connection initialization
- [ ] 8.4.1.3 Implement Phoenix.Socket.Client integration
- [ ] 8.4.1.4 Handle connection lifecycle (connecting, connected, disconnected)
- [ ] 8.4.1.5 Add graceful shutdown handling

### Task 8.4.2: Implement Channel Joining ⏳
**Status**: Pending
**File**: `lib/jidoka/protocol/phoenix/connection.ex`

- [ ] 8.4.2.1 Implement `join_channel/3` API function
- [ ] 8.4.2.2 Handle Phoenix channel join handshake
- [ ] 8.4.2.3 Track joined channels in state
- [ ] 8.4.2.4 Handle join replies (success/error)
- [ ] 8.4.2.5 Support channel parameters

### Task 8.4.3: Implement Event Pushing ⏳
**Status**: Pending
**File**: `lib/jidoka/protocol/phoenix/connection.ex`

- [ ] 8.4.3.1 Implement `push_event/3` API function
- [ ] 8.4.3.2 Serialize event payloads to Phoenix format
- [ ] 8.4.3.3 Handle push acknowledgments
- [ ] 8.4.3.4 Validate channel is joined before push
- [ ] 8.4.3.5 Handle push errors

### Task 8.4.4: Handle Incoming Messages ⏳
**Status**: Pending
**File**: `lib/jidoka/protocol/phoenix/message_handler.ex`

- [ ] 8.4.4.1 Create MessageHandler module for routing
- [ ] 8.4.4.2 Convert Phoenix messages to Jidoka signals
- [ ] 8.4.4.3 Route signals to Coordinator for agent handling
- [ ] 8.4.4.4 Handle different message types (broadcast, direct, reply)
- [ ] 8.4.4.5 Add message filtering support

### Task 8.4.5: Implement Reconnection Logic ⏳
**Status**: Pending
**File**: `lib/jidoka/protocol/phoenix/reconnect_manager.ex`

- [ ] 8.4.5.1 Create ReconnectManager GenServer
- [ ] 8.4.5.2 Implement exponential backoff strategy
- [ ] 8.4.5.3 Add max retry limit configuration
- [ ] 8.4.5.4 Handle reconnection success/failure
- [ ] 8.4.5.5 Notify on reconnection status changes

### Task 8.4.6: Create Connection Supervisor ⏳
**Status**: Pending
**File**: `lib/jidoka/protocol/phoenix/connection_supervisor.ex`

- [ ] 8.4.6.1 Create DynamicSupervisor for Phoenix connections
- [ ] 8.4.6.2 Implement `start_connection/1` for dynamic connection start
- [ ] 8.4.6.3 Implement `stop_connection/1` for graceful shutdown
- [ ] 8.4.6.4 Implement `list_connections/0` for connection discovery
- [ ] 8.4.6.5 Implement `connection_status/1` for health checks

### Task 8.4.7: Create Main API Module ⏳
**Status**: Pending
**File**: `lib/jidoka/protocol/phoenix.ex`

- [ ] 8.4.7.1 Create main API module
- [ ] 8.4.7.2 Add convenience functions for common operations
- [ ] 8.4.7.3 Add configuration helpers
- [ ] 8.4.7.4 Add connection management helpers

### Task 8.4.8: Add Dependency and Configuration ⏳
**Status**: Pending
**Files**: `mix.exs`, `config/config.exs`, `lib/jidoka/application.ex`

- [ ] 8.4.8.1 Add `:phoenix` to mix.exs dependencies
- [ ] 8.4.8.2 Add Phoenix connection configuration schema
- [ ] 8.4.8.3 Add Phoenix ConnectionSupervisor to Application
- [ ] 8.4.8.4 Add configuration examples to config.exs

### Task 8.4.9: Write Tests ⏳
**Status**: Pending
**Files**: Test files in `test/jidoka/protocol/phoenix/`

- [ ] 8.4.9.1 Test connection lifecycle (connect, disconnect, reconnect)
- [ ] 8.4.9.2 Test channel joining (success, error, params)
- [ ] 8.4.9.3 Test event pushing (ack, no-ack, error)
- [ ] 8.4.9.4 Test message routing to signals
- [ ] 8.4.9.5 Test reconnection backoff behavior
- [ ] 8.4.9.6 Test supervisor management
- [ ] 8.4.9.7 Test API module functions

### Task 8.4.10: Documentation and Examples ⏳
**Status**: Pending

- [ ] 8.4.10.1 Add moduledoc examples to all modules
- [ ] 8.4.10.2 Add usage examples to Connection module
- [ ] 8.4.10.3 Document configuration options
- [ ] 8.4.10.4 Add reconnection behavior documentation

## Agent Consultations Performed

### elixir-expert
**Status**: Not yet consulted
**Purpose**: Phoenix Channels client implementation patterns and best practices

### research-agent
**Status**: Not yet consulted
**Purpose**: Phoenix Channels protocol documentation and client library usage

### architecture-agent
**Status**: Not yet consulted
**Purpose**: Integration with existing ProtocolSupervisor and signal system

## Notes and Considerations

### Phoenix Socket Client API

The Phoenix framework provides `Phoenix.Socket.Client` for building WebSocket clients:
- Connects to `ws://` or `wss://` endpoints
- Handles channel joining via `Phoenix.Socket.Channel`
- Supports pushes and message reception
- Built-in reconnection capabilities

### Message Flow

```
┌─────────────────┐         ┌──────────────────┐
│ Jidoka Agent    │         │ Remote Phoenix   │
│                 │         │ Server           │
└────────┬────────┘         └────────┬─────────┘
         │                           │
         │ 1. join_channel(topic)    │
         │──────────────────────────>│
         │                           │
         │ 2. {:ok, join_reply}      │
         │<──────────────────────────│
         │                           │
         │ 3. push_event(event)      │
         │──────────────────────────>│
         │                           │
         │ 4. {:ok, ref}             │
         │<──────────────────────────│
         │                           │
         │ 5. incoming_message       │
         │<──────────────────────────│
         │                           │
         │ 6. Route to agent         │
         │    (via signal)           │
```

### Reconnection Strategy

- Initial backoff: 1 second
- Maximum backoff: 30 seconds
- Max retries: 10 (configurable)
- Exponential multiplier: 1.5
- Jitter: ±25% random

### Configuration Example

```elixir
config :jidoka, :phoenix_connections,
  my_remote_service: [
    url: "ws://localhost:4000/socket",
    headers: [{"X-API-Key", "secret"}],
    params: %{token: "auth_token"},
    channels: [
      "room:lobby",
      "user:123"
    ],
    reconnect: true,
    max_retries: 10
  ]
```

## Current Status

**What Works**: Nothing implemented yet for Phoenix Channels client.

**What's Next**: Implement Task 8.4.1 - Create the Connection module with Phoenix.Socket.Client integration.

**How to Run**: Once implemented, connections can be started via:
```elixir
Jidoka.Protocol.Phoenix.Connection.start_link(
  name: :my_connection,
  url: "ws://localhost:4000/socket/websocket"
)
```

## Updated Log

- **2026-02-07**: Created initial feature planning document. Ready to begin implementation.
