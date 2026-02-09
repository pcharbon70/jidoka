# Jidoka Architecture Guide

## Table of Contents
- [Introduction](#introduction)
- [Architectural Principles](#architectural-principles)
- [System Layers](#system-layers)
- [Component Overview](#component-overview)
- [Design Patterns](#design-patterns)
- [Communication Flow](#communication-flow)
- [Supervision Tree](#supervision-tree)
- [Deployment Patterns](#deployment-patterns)

## Introduction

This guide provides a comprehensive deep-dive into the Jidoka system architecture. It covers the design principles, component relationships, communication patterns, and structural decisions that make Jidoka a robust, scalable agentic coding assistant core.

## Architectural Principles

### 1. Headless Design

Jidoka is designed as a **headless core** - it has no built-in user interface. All UI is provided by pluggable clients that connect via the Client API.

**Benefits:**
- Core functionality remains stable regardless of UI changes
- Multiple clients can connect simultaneously
- UI can be developed independently of core logic
- Easy to test and validate core functionality

### 2. Process Isolation

Each agent and service runs as an independent BEAM process:

```mermaid
graph TB
    subgraph "Supervision Tree"
        APP[Jidoka.Application]
        SUP[DynamicSupervisor]

        APP --> SUP
        SUP --> A1[Agent 1 ~25KB]
        SUP --> A2[Agent 2 ~25KB]
        SUP --> A3[Agent 3 ~25KB]
        SUP --> A4[Agent N ~25KB]
    end

    style A1 fill:#90EE90
    style A2 fill:#90EE90
    style A3 fill:#90EE90
    style A4 fill:#90EE90
```

**Benefits:**
- Fault containment - failures don't cascade
- Independent scaling
- Hot code upgrades per process
- Predictable resource usage

### 3. Signal-Based Communication

All inter-process communication uses **signals** (CloudEvents-compliant messages) via Phoenix PubSub:

```mermaid
sequenceDiagram
    participant A as Agent A
    participant P as Phoenix PubSub
    participant B as Agent B
    participant C as Client

    A->>P: Publish signal(type: "code.analyzed")
    P->>B: Deliver signal
    P->>C: Deliver signal (if subscribed)
    B->>P: Publish signal(type: "analysis.result")
    P->>C: Deliver result
```

### 4. Semantic Memory

Knowledge is stored as RDF triples with SPARQL query capabilities, enabling:
- Semantic relationships between concepts
- Complex queries across knowledge domains
- Inference and reasoning capabilities

### 5. Client-Agnostic API

All clients communicate through the same well-defined PubSub event API:
- No client-specific logic in core
- Uniform event structure
- Easy client development

## System Layers

Jidoka is organized into four distinct layers:

```mermaid
graph TB
    subgraph "Layer 4: Client Layer"
        direction LR
        TUI["Terminal UI"]
        WEB["Web Interface"]
        API["REST/GraphQL API"]
        CUSTOM["Custom Clients"]
    end

    subgraph "Layer 3: Agent Layer"
        direction TB
        COORD["Coordinator Agent"]
        SESSION["Session Manager"]
        ANALYZER["Code Analyzer"]
        DETECTOR["Issue Detector"]
        LLM["LLM Orchestrator"]
        CONTEXT["Context Manager"]
    end

    subgraph "Layer 2: Protocol Layer"
        direction LR
        MCP["MCP Client"]
        PHX["Phoenix Channels"]
        A2A["A2A Gateway"]
        WATCH["File Watcher"]
    end

    subgraph "Layer 1: Knowledge Layer"
        TRIPLE["Triple Store"]
        SPARQL["SPARQL Engine"]
        INDEX["Code Index"]
    end

    TUI -->|"client.events<br/>PubSub"| COORD
    WEB -->|"client.events<br/>PubSub"| COORD
    API -->|"client.events<br/>PubSub"| COORD
    CUSTOM -->|"client.events<br/>PubSub"| COORD

    COORD --> SESSION
    COORD --> ANALYZER
    COORD --> DETECTOR
    COORD --> LLM
    COORD --> CONTEXT

    LLM --> MCP
    COORD --> PHX
    ANALYZER --> WATCH
    LLM --> A2A

    CONTEXT --> SPARQL
    ANALYZER --> INDEX
    INDEX --> TRIPLE
```

### Layer 1: Knowledge Layer

The foundation of the system - handles all persistent storage and semantic understanding.

**Components:**
- **Triple Store** - RDF triple storage (SPARQL endpoint)
- **SPARQL Engine** - Query engine for semantic data
- **Code Index** - Indexed representation of code structure

**Responsibilities:**
- Persistent knowledge storage
- Semantic querying
- Code relationship understanding

### Layer 2: Protocol Layer

Handles all external integrations and communication protocols.

**Components:**
- **MCP Client** - Model Context Protocol for tool integration
- **Phoenix Channels** - Real-time bidirectional communication
- **A2A Gateway** - Agent-to-Agent cross-framework communication
- **File Watcher** - File system change detection

**Responsibilities:**
- External tool integration
- Real-time communication
- File system monitoring
- Cross-framework messaging

### Layer 3: Agent Layer

The intelligence core - contains all agent logic and orchestration.

**Components:**
- **Coordinator Agent** - Central hub for inter-agent communication
- **Session Manager** - Multi-session isolation and management
- **Code Analyzer** - Codebase structure and pattern analysis
- **Issue Detector** - Code issue identification
- **LLM Orchestrator** - LLM interaction and tool calling
- **Context Manager** - Memory and context handling

**Responsibilities:**
- Task execution
- Agent coordination
- Context management
- LLM interaction

### Layer 4: Client Layer

Pluggable UI layer - all clients are optional.

**Client Types:**
- **Terminal UI** - Command-line interface
- **Web Interface** - Browser-based UI
- **API** - REST/GraphQL for integrations
- **Custom** - Any client implementation

## Component Overview

### Core Application

**Module:** `Jidoka.Application`

The root of the supervision tree. Starts and supervises all core services.

```mermaid
graph TB
    APP[Jidoka.Application]

    APP --> REG[Registry]
    APP --> PUBSUB[Phoenix.PubSub]
    APP --> TRIPLE_STORE[TripleStore Supervisor]
    APP --> AGENT_SUP[Agent Supervisor]
    APP --> PROTOCOL_SUP[Protocol Supervisor]

    AGENT_SUP --> COORD[Coordinator]
    AGENT_SUP --> SESSION[Session Manager]
    AGENT_SUP --> ANALYZER[Code Analyzer]
    AGENT_SUP --> LLM[LLM Orchestrator]

    PROTOCOL_SUP --> MCP[MCP Client]
    PROTOCOL_SUP --> PHX[Phoenix Channels]
    PROTOCOL_SUP --> A2A[A2A Gateway]
```

### Coordinator Agent

**Module:** `Jidoka.Agents.Coordinator`

The central hub that:
- Routes signals between agents
- Broadcasts events to clients
- Manages agent lifecycle
- Handles session orchestration

**Signal Flow:**
```mermaid
graph LR
    CLIENT[Client] -->|request| COORD
    COORD -->|dispatch| AGENT1[Agent 1]
    COORD -->|dispatch| AGENT2[Agent 2]
    AGENT1 -->|result| COORD
    AGENT2 -->|result| COORD
    COORD -->|broadcast| CLIENT
```

### Session Manager

**Module:** `Jidoka.Agents.SessionManager`

Manages isolated work sessions:
- Creates session supervisors
- Tracks active sessions
- Handles session lifecycle
- Isolates session state

**Session Structure:**
```mermaid
graph TB
    SM[Session Manager]

    SM --> S1[Session 1 Supervisor]
    SM --> S2[Session 2 Supervisor]
    SM --> SN[Session N Supervisor]

    S1 --> S1A[Session Agents]
    S2 --> S2A[Session Agents]
    SN --> SNA[Session Agents]

    S1A --> S1CTX[Session Context]
    S2A --> S2CTX[Session Context]
    SNA --> SNCTX[Session Context]
```

### Code Analyzer

**Module:** `Jidoka.Agents.CodeAnalyzer`

Analyzes codebases for:
- Structure and organization
- Dependency relationships
- Code patterns
- Metrics and complexity

### LLM Orchestrator

**Module:** `Jidoka.Agents.LLMOrchestrator`

Manages LLM interactions:
- Prompt construction
- Tool calling
- Response streaming
- Context management

### Context Manager

**Module:** `Jidoka.Agents.ContextManager`

Handles the two-tier memory system:
- Short-term memory (conversation buffers)
- Long-term memory (triple store)
- Memory promotion
- Context retrieval

## Design Patterns

### Supervisor Pattern

Every component has a supervisor with appropriate restart strategies:

```elixir
# Example from the codebase
defmodule Jidoka.Agents.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Jidoka.Agents.Coordinator, []},
      {Jidoka.Agents.SessionManager, []},
      {Jidoka.Agents.CodeAnalyzer, []},
      {Jidoka.Agents.LLMOrchestrator, []},
      {Jidoka.Agents.ContextManager, []}
    ]

    # one_for_one - if one child crashes, only that child is restarted
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### GenServer Pattern

All agents implement the GenServer behavior:

```elixir
defmodule Jidoka.Agents.ExampleAgent do
  use GenServer
  require Jidoka.Signals

  @impl true
  def init(_init_arg) do
    # Subscribe to relevant signals
    Phoenix.PubSub.subscribe(Jidoka.PubSub, "signals")
    {:ok, %{}}
  end

  @impl true
  def handle_info(%Jidoka.Signal{} = signal, state) do
    # Process signal
    {:noreply, state}
  end
end
```

### Signal-Subscription Pattern

Agents subscribe to specific signal types:

```elixir
# Subscribe to specific signal types
defp subscribe_to_signals do
  Phoenix.PubSub.subscribe(Jidoka.PubSub, "signals")
end

# Filter signals in handle_info
@impl true
def handle_info(%Jidoka.Signal{type: "code.analyzed"} = signal, state) do
  handle_code_analyzed(signal)
  {:noreply, state}
end

@impl true
def handle_info(%Jidoka.Signal{}, state) do
  # Ignore unhandled signals
  {:noreply, state}
end
```

### Registry Pattern

Process registration for discovery and messaging:

```elixir
# Register process
Registry.register(Jidoka.Registry, {:agent, :coordinator}, pid)

# Lookup process
case Registry.lookup(Jidoka.Registry, {:agent, :coordinator}) do
  [{pid, _}] -> GenServer.call(pid, :status)
  [] -> {:error, :not_found}
end
```

## Communication Flow

### Request Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant Coord as Coordinator
    participant CA as Code Analyzer
    participant LLM as LLM Orchestrator
    participant KG as Knowledge Graph

    C->>Coord: Signal(user_request)
    Coord->>CA: Dispatch analysis task
    CA->>KG: Query codebase structure
    KG-->>CA: Code structure data
    CA-->>Coord: Signal(analysis_complete)
    Coord->>LLM: Generate response with context
    LLM-->>Coord: Signal(llm_response)
    Coord-->>C: Broadcast response
```

### Event Broadcasting

```mermaid
sequenceDiagram
    participant A as Agent
    participant PS as Phoenix PubSub
    participant C1 as Client 1
    participant C2 as Client 2
    participant C3 as Client 3

    A->>PS: Publish signal to "client.events"
    PS->>C1: Deliver event
    PS->>C2: Deliver event
    PS->>C3: Deliver event
```

## Supervision Tree

The complete supervision tree of a running Jidoka system:

```mermaid
graph TB
    APP["Jidoka.Application"]

    subgraph "Core Services"
        APP --> REG["Registry"]
        APP --> PUB["Phoenix.PubSub"]
        APP --> FIN["Finch (HTTP)"]
    end

    subgraph "Knowledge Layer"
        APP --> TS_SUP["TripleStore.Supervisor"]
        TS_SUP --> TS["TripleStore"]
        TS_SUP --> SPARQL["SPARQL.Endpoint"]
    end

    subgraph "Agent Layer"
        APP --> AG_SUP["Agent.Supervisor"]
        AG_SUP --> COORD["Coordinator"]
        AG_SUP --> SESS["SessionManager"]
        AG_SUP --> ANAL["CodeAnalyzer"]
        AG_SUP --> DET["IssueDetector"]
        AG_SUP --> LLM["LLMOrchestrator"]
        AG_SUP --> CTX["ContextManager"]
    end

    subgraph "Session Agents"
        SESS --> S1_SUP["Session.1.Supervisor"]
        SESS --> S2_SUP["Session.2.Supervisor"]

        S1_SUP --> S1_AGENTS["Session 1 Agents"]
        S2_SUP --> S2_AGENTS["Session 2 Agents"]
    end

    subgraph "Protocol Layer"
        APP --> PROT_SUP["Protocol.Supervisor"]
        PROT_SUP --> MCP["MCP.Client"]
        PROT_SUP --> PHX["Phoenix.Channels"]
        PROT_SUP --> A2A["A2A.Gateway"]
        PROT_SUP --> FW["FileWatcher"]
    end
```

## Deployment Patterns

### Single Node Deployment

For development and small deployments:

```mermaid
graph TB
    NODE["Single BEAM Node"]

    subgraph "Jidoka Instance"
        NODE --> AGENTS["All Agents"]
        NODE --> PROTOCOLS["All Protocols"]
        NODE --> KNOWLEDGE["Local Triple Store"]
    end
```

### Distributed Deployment

For production and scaling:

```mermaid
graph TB
    LB["Load Balancer"]

    subgraph "Node 1"
        N1_AG["Agent Instances"]
        N1_PR["Protocol Instances"]
    end

    subgraph "Node 2"
        N2_AG["Agent Instances"]
        N2_PR["Protocol Instances"]
    end

    subgraph "Shared Services"
        TS["Distributed Triple Store"]
        DB["PostgreSQL"]
    end

    LB --> N1_AG
    LB --> N2_AG

    N1_AG --> TS
    N2_AG --> TS

    N1_AG --> DB
    N2_AG --> DB
```

### Horizontal Scaling

Agents can be scaled independently:

```mermaid
graph LR
    subgraph "Scaled Agents"
        CA1[Code Analyzer 1]
        CA2[Code Analyzer 2]
        CA3[Code Analyzer N]
    end

    subgraph "Single Instance"
        COORD[Coordinator]
        LLM[LLM Orchestrator]
    end

    COORD --> CA1
    COORD --> CA2
    COORD --> CA3

    CA1 --> COORD
    CA2 --> COORD
    CA3 --> COORD
```

## See Also

- **[Agent Layer](agent-layer.md)** - Deep dive into agent implementation
- **[Protocol Layer](protocol-layer.md)** - Protocol integration details
- **[Signals](signals.md)** - Signal-based communication system
- **[Memory System](memory-system.md)** - Knowledge graph architecture
